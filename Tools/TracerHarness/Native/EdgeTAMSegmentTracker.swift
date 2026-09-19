import Foundation

struct EdgeTAMLearnedConstants: Decodable, Sendable {
    let noMemoryEmbedding: [Float]
    let memoryTemporalEmbeddings: [[Float]]

    func validate() throws {
        guard noMemoryEmbedding.count == 256,
              memoryTemporalEmbeddings.count == 7,
              memoryTemporalEmbeddings.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isFinite) }),
              noMemoryEmbedding.allSatisfy(\.isFinite) else {
            throw EdgeTAMNativeError.invalidState("Unexpected learned embedding dimensions")
        }
    }
}

struct EdgeTAMFrameOutput: Sendable {
    let frameIndex: Int
    let sourceTime: Double
    let masks: EdgeTAMMaskOutput
    let spatialMemoryFrames: [Int]
    let pointerFrames: [Int]
}

/// One object, one conditioning point and one fixed crop. A new crop creates a
/// fresh tracker; its caller preserves the canonical point from the old crop.
/// Predictions are serial. Source times describe observations, never a nominal FPS.
final class EdgeTAMSegmentTracker {
    private struct StoredFrame {
        let index: Int
        let memory: EdgeTAMTensor
        let pointer: EdgeTAMTensor
    }

    private let components: any EdgeTAMComponents
    private let constants: EdgeTAMLearnedConstants
    private let frameCount: Int
    private let step: Int
    private let position: EdgeTAMTensor
    private var conditioning: StoredFrame?
    private var previous: [Int: StoredFrame] = [:]
    private var memoryPosition: EdgeTAMTensor?
    private var lastIndex: Int?
    private var lastSourceTime: Double?

    init(components: any EdgeTAMComponents, constants: EdgeTAMLearnedConstants,
         frameCount: Int, reverse: Bool) throws {
        try constants.validate()
        guard frameCount > 0 else { throw EdgeTAMNativeError.invalidState("Empty source interval") }
        self.components = components
        self.constants = constants
        self.frameCount = frameCount
        self.step = reverse ? -1 : 1
        self.position = try Self.imagePositionEncoding()
    }

    func process(imageNormalised: EdgeTAMTensor, frameIndex: Int, sourceTime: Double,
                 point: (x: Float, y: Float)? = nil) throws -> EdgeTAMFrameOutput {
        guard (0..<frameCount).contains(frameIndex), sourceTime.isFinite, sourceTime >= 0 else {
            throw EdgeTAMNativeError.invalidState("Frame index or source timestamp is invalid")
        }
        if let lastIndex, let lastSourceTime {
            guard frameIndex == lastIndex + step,
                  (sourceTime - lastSourceTime) * Double(step) > 0,
                  point == nil else {
                throw EdgeTAMNativeError.invalidState("A segment must propagate consecutive frames in its direction")
            }
        } else {
            guard let point, point.x.isFinite, point.y.isFinite,
                  (0..<1024).contains(point.x), (0..<1024).contains(point.y) else {
                throw EdgeTAMNativeError.invalidState("The first frame needs one in-image positive point")
            }
        }
        let image = try imageNormalised.requiringShape([1, 3, 1024, 1024])
        let features = try components.image(image)
        let rawLow = try features.low.requiringShape([1, 256, 64, 64])
        _ = try features.high0.requiringShape([1, 32, 256, 256])
        _ = try features.high1.requiringShape([1, 64, 128, 128])
        let fused: EdgeTAMTensor
        var memoryIndices: [Int] = []
        var pointerIndices: [Int] = []
        if point != nil {
            var values = rawLow.values
            for channel in 0..<256 {
                let embedding = constants.noMemoryEmbedding[channel]
                for pixel in 0..<4096 { values[channel * 4096 + pixel] += embedding }
            }
            fused = try EdgeTAMTensor(shape: rawLow.shape, values: values)
        } else {
            guard let conditioning, let memoryPosition else {
                throw EdgeTAMNativeError.invalidState("Conditioning memory is missing")
            }
            // The upstream order is conditioning first, then available temporal
            // slots from oldest to newest. Missing slots are skipped, not padded.
            var selected: [(position: Int, frame: StoredFrame)] = [(0, conditioning)]
            for temporalPosition in 1..<7 {
                let relative = 7 - temporalPosition
                if let frame = previous[frameIndex - step * relative] {
                    selected.append((temporalPosition, frame))
                }
            }
            var memoryValues: [Float] = []
            var positionValues: [Float] = []
            memoryValues.reserveCapacity(selected.count * 512 * 64)
            positionValues.reserveCapacity(selected.count * 512 * 64)
            for selectedFrame in selected {
                memoryIndices.append(selectedFrame.frame.index)
                memoryValues.append(contentsOf: selectedFrame.frame.memory.values)
                let temporal = constants.memoryTemporalEmbeddings[6 - selectedFrame.position]
                for index in memoryPosition.values.indices {
                    positionValues.append(memoryPosition.values[index] + temporal[index % 64])
                }
            }
            var pointers: [StoredFrame] = []
            if (frameIndex - conditioning.index) * step >= 0 { pointers.append(conditioning) }
            for relative in 1..<min(frameCount, 16) {
                let index = frameIndex - step * relative
                if !(0..<frameCount).contains(index) { break }
                if let frame = previous[index] { pointers.append(frame) }
            }
            guard !pointers.isEmpty else { throw EdgeTAMNativeError.invalidState("Pointer history is empty") }
            pointerIndices = pointers.map(\.index)
            let pointerValues = pointers.flatMap { $0.pointer.values }
            fused = try components.attention(
                current: rawLow, position: position,
                memory: EdgeTAMTensor(shape: [1, selected.count * 512, 64], values: memoryValues),
                memoryPosition: EdgeTAMTensor(shape: [1, selected.count * 512, 64], values: positionValues),
                pointers: EdgeTAMTensor(shape: [1, pointers.count * 4, 64], values: pointerValues)
            )
        }
        _ = try fused.requiringShape([1, 256, 64, 64])
        let masks = try components.masks(features: features, fused: fused, point: point)
        _ = try masks.lowMask.requiringShape([1, 1, 256, 256])
        _ = try masks.highMask.requiringShape([1, 1, 1024, 1024])
        _ = try masks.objectPointer.requiringShape([1, 256])
        _ = try masks.objectScore.requiringShape([1, 1])
        let encoded = try components.memory(features: rawLow, mask: masks.highMask,
                                            objectScore: masks.objectScore, fromPoint: point != nil)
        _ = try encoded.features.requiringShape([1, 512, 64])
        _ = try encoded.position.requiringShape([1, 512, 64])
        if memoryPosition == nil { memoryPosition = encoded.position }
        // SAM2VideoPredictor stores spatial features as bfloat16 between frames.
        // Keep the rounded values in float32 storage for Core ML's next input.
        let stored = StoredFrame(
            index: frameIndex,
            memory: try EdgeTAMTensor(shape: [1, 512, 64], values: encoded.features.values.map(Self.bfloat16Roundtrip)),
            pointer: masks.objectPointer
        )
        if point != nil { conditioning = stored } else { previous[frameIndex] = stored }
        // Only the most recent fifteen non-conditioning frames can be queried.
        previous = previous.filter { (frameIndex - $0.key) * step < 16 }
        lastIndex = frameIndex
        lastSourceTime = sourceTime
        return EdgeTAMFrameOutput(frameIndex: frameIndex, sourceTime: sourceTime, masks: masks,
                                  spatialMemoryFrames: memoryIndices, pointerFrames: pointerIndices)
    }

    static func bfloat16Roundtrip(_ value: Float) -> Float {
        let bits = value.bitPattern
        let rounded = bits &+ 0x7fff &+ ((bits >> 16) & 1)
        return Float(bitPattern: rounded & 0xffff0000)
    }

    static func imagePositionEncoding() throws -> EdgeTAMTensor {
        let size = 64
        let halfChannels = 128
        var values = [Float](repeating: 0, count: 256 * size * size)
        let scale = Float(2 * Double.pi)
        for channel in 0..<halfChannels {
            let exponent = Float(2 * (channel / 2)) / Float(halfChannels)
            let divisor = powf(10000, exponent)
            for coordinate in 0..<size {
                let normalised = Float(coordinate + 1) / (Float(size) + Float(1e-6)) * scale
                let angle = normalised / divisor
                let value = channel.isMultiple(of: 2) ? sinf(angle) : cosf(angle)
                for other in 0..<size {
                    values[channel * 4096 + coordinate * size + other] = value
                    values[(channel + halfChannels) * 4096 + other * size + coordinate] = value
                }
            }
        }
        return try EdgeTAMTensor(shape: [1, 256, 64, 64], values: values)
    }
}
