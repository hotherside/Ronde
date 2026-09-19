import Foundation

/// Contiguous row-major float32 tensor shared by the native diagnostic stages.
/// It owns its storage, so a model output cannot be invalidated by a later prediction.
struct EdgeTAMTensor: Sendable {
    let shape: [Int]
    var values: [Float]

    init(shape: [Int], values: [Float]) throws {
        guard !shape.isEmpty, shape.allSatisfy({ $0 > 0 }) else {
            throw EdgeTAMNativeError.invalidTensor("Non-positive or empty shape")
        }
        var count = 1
        for dimension in shape {
            let product = count.multipliedReportingOverflow(by: dimension)
            guard !product.overflow else { throw EdgeTAMNativeError.invalidTensor("Shape overflow") }
            count = product.partialValue
        }
        guard count == values.count, values.allSatisfy(\.isFinite) else {
            throw EdgeTAMNativeError.invalidTensor("Storage size or finite-value check failed")
        }
        self.shape = shape
        self.values = values
    }

    func requiringShape(_ expected: [Int]) throws -> EdgeTAMTensor {
        guard shape == expected else {
            throw EdgeTAMNativeError.invalidTensor("Expected \(expected), received \(shape)")
        }
        return self
    }
}

enum EdgeTAMNativeError: Error, CustomStringConvertible {
    case invalidTensor(String)
    case invalidState(String)
    case model(String)

    var description: String {
        switch self {
        case let .invalidTensor(message), let .invalidState(message), let .model(message): message
        }
    }
}

struct EdgeTAMImageFeatures: Sendable {
    let low: EdgeTAMTensor
    let high0: EdgeTAMTensor
    let high1: EdgeTAMTensor
}

struct EdgeTAMMaskOutput: Sendable {
    let lowMask: EdgeTAMTensor
    let highMask: EdgeTAMTensor
    let ious: EdgeTAMTensor
    let objectPointer: EdgeTAMTensor
    let objectScore: EdgeTAMTensor
}

struct EdgeTAMMemoryOutput: Sendable {
    let features: EdgeTAMTensor
    let position: EdgeTAMTensor
}

/// Synchronous interface, confined to the serial native tracker. The model
/// implementation and state machine never execute concurrent predictions.
protocol EdgeTAMComponents: AnyObject {
    func image(_ normalised: EdgeTAMTensor) throws -> EdgeTAMImageFeatures
    func attention(current: EdgeTAMTensor, position: EdgeTAMTensor,
                   memory: EdgeTAMTensor, memoryPosition: EdgeTAMTensor,
                   pointers: EdgeTAMTensor) throws -> EdgeTAMTensor
    func masks(features: EdgeTAMImageFeatures, fused: EdgeTAMTensor,
               point: (x: Float, y: Float)?) throws -> EdgeTAMMaskOutput
    func memory(features: EdgeTAMTensor, mask: EdgeTAMTensor,
                objectScore: EdgeTAMTensor, fromPoint: Bool) throws -> EdgeTAMMemoryOutput
}
