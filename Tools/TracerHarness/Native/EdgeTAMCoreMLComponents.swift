import CoreML
import Foundation

/// Native synchronous component execution. This object is deliberately not
/// Sendable; its owner is the serial tracker. The lock also prevents overlapping
/// predictions if a diagnostic caller accidentally uses multiple threads.
final class EdgeTAMCoreMLComponents: EdgeTAMComponents {
    struct PackageURLs: Sendable {
        let image: URL
        let attention: URL
        let point: URL
        let noPoint: URL
        let memory: URL

        init(image: URL, attention: URL, point: URL, noPoint: URL, memory: URL) {
            self.image = image
            self.attention = attention
            self.point = point
            self.noPoint = noPoint
            self.memory = memory
        }

        init(_ urls: [String: URL]) throws {
            let required: Set<String> = ["image", "attention", "point", "noPoint", "memory"]
            guard Set(urls.keys) == required else {
                throw EdgeTAMNativeError.model("Expected exactly image, attention, point, noPoint and memory package URLs")
            }
            self.init(image: urls["image"]!, attention: urls["attention"]!, point: urls["point"]!,
                      noPoint: urls["noPoint"]!, memory: urls["memory"]!)
        }
    }

    /// Actual compiled locations, useful for a diagnostic manifest. Compilation
    /// returns an external temporary directory; it never writes beside source.
    let compiledModelURLs: [String: URL]
    private let models: [String: MLModel]
    private let predictionLock = NSLock()

    private struct Specification {
        let shape: [Int] // -1 denotes a validated variable token axis.
        var type: MLMultiArrayDataType = .float32
    }

    private static let low = [1, 256, 64, 64]
    private static let high0 = [1, 32, 256, 256]
    private static let high1 = [1, 64, 128, 128]
    private static let maskOutputs: [String: Specification] = [
        "low_best_256": Specification(shape: [1, 1, 256, 256]),
        "high_best_1024": Specification(shape: [1, 1, 1024, 1024]),
        "ious": Specification(shape: [1, 3]),
        "object_pointer": Specification(shape: [1, 256]),
        "object_score": Specification(shape: [1, 1])
    ]

    init(packages: PackageURLs, allowPackageCompilationOnMac: Bool = false) throws {
        let urls = ["image": packages.image, "attention": packages.attention,
                    "point": packages.point, "noPoint": packages.noPoint, "memory": packages.memory]
        var loaded: [String: MLModel] = [:]
        var compiled: [String: URL] = [:]
        for name in ["image", "attention", "point", "noPoint", "memory"] {
            try Task.checkCancellation()
            let url = try Self.compiledURL(for: urls[name]!, component: name,
                                          allowCompilation: allowPackageCompilationOnMac)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = Self.computeUnits
            do {
                loaded[name] = try autoreleasepool {
                    try MLModel(contentsOf: url, configuration: configuration)
                }
                try Task.checkCancellation()
                compiled[name] = url
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw EdgeTAMNativeError.model("EdgeTAM \(name) load failed: \(error.localizedDescription)")
            }
        }
        models = loaded
        compiledModelURLs = compiled
        try validateModels()
    }

    convenience init(packageURLs: [String: URL], allowPackageCompilationOnMac: Bool = false) throws {
        try self.init(packages: PackageURLs(packageURLs), allowPackageCompilationOnMac: allowPackageCompilationOnMac)
    }

    func image(_ normalised: EdgeTAMTensor) throws -> EdgeTAMImageFeatures {
        try serial {
            let result = try predict("image", arrays: [
                "image_normalised": Self.array(normalised, shape: [1, 3, 1024, 1024], name: "image_normalised")
            ])
            return EdgeTAMImageFeatures(
                low: try output(result, "vision_features", shape: Self.low, component: "image"),
                high0: try output(result, "high_res_feat_0", shape: Self.high0, component: "image"),
                high1: try output(result, "high_res_feat_1", shape: Self.high1, component: "image"))
        }
    }

    func attention(current: EdgeTAMTensor, position: EdgeTAMTensor,
                   memory: EdgeTAMTensor, memoryPosition: EdgeTAMTensor,
                   pointers: EdgeTAMTensor) throws -> EdgeTAMTensor {
        try serial {
            guard memory.shape.count == 3, memory.shape[0] == 1, memory.shape[2] == 64,
                  (512...3584).contains(memory.shape[1]), memory.shape[1].isMultiple(of: 512) else {
                throw EdgeTAMNativeError.invalidTensor("Attention requires 1–7 complete 512-token spatial memories with 64 channels")
            }
            guard pointers.shape.count == 3, pointers.shape[0] == 1, pointers.shape[2] == 64,
                  (4...64).contains(pointers.shape[1]), pointers.shape[1].isMultiple(of: 4) else {
                throw EdgeTAMNativeError.invalidTensor("Attention requires 1–16 object pointers split into four 64-channel tokens each")
            }
            let result = try predict("attention", arrays: [
                "current_features": Self.array(current, shape: Self.low, name: "current_features"),
                "current_position": Self.array(position, shape: Self.low, name: "current_position"),
                "spatial_memory": Self.array(memory, shape: memory.shape, name: "spatial_memory"),
                "spatial_memory_position": Self.array(memoryPosition, shape: memory.shape, name: "spatial_memory_position"),
                "object_pointer_tokens": Self.array(pointers, shape: pointers.shape, name: "object_pointer_tokens")
            ])
            return try output(result, "fused_features", shape: Self.low, component: "attention")
        }
    }

    func masks(features: EdgeTAMImageFeatures, fused: EdgeTAMTensor,
               point: (x: Float, y: Float)?) throws -> EdgeTAMMaskOutput {
        try serial {
            _ = try features.low.requiringShape(Self.low)
            let name = point == nil ? "noPoint" : "point"
            var arrays: [String: MLMultiArray]
            if let point {
                guard point.x.isFinite, point.y.isFinite,
                      (0..<1024).contains(point.x), (0..<1024).contains(point.y) else {
                    throw EdgeTAMNativeError.invalidTensor("Point must be finite and inside the 1024-square model input")
                }
                let coordinates = try EdgeTAMTensor(shape: [1, 1, 2], values: [point.x, point.y])
                let labels = try MLMultiArray(shape: [1, 1], dataType: .int32)
                labels.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in buffer[0] = 1 }
                arrays = [
                    "backbone_features": try Self.array(fused, shape: Self.low, name: "backbone_features"),
                    "high_res_s0": try Self.array(features.high0, shape: Self.high0, name: "high_res_s0"),
                    "high_res_s1": try Self.array(features.high1, shape: Self.high1, name: "high_res_s1"),
                    "point_coords": try Self.array(coordinates, shape: [1, 1, 2], name: "point_coords"),
                    "point_labels": labels
                ]
            } else {
                arrays = [
                    "backbone": try Self.array(fused, shape: Self.low, name: "backbone"),
                    "s0": try Self.array(features.high0, shape: Self.high0, name: "s0"),
                    "s1": try Self.array(features.high1, shape: Self.high1, name: "s1")
                ]
            }
            let result = try predict(name, arrays: arrays)
            return EdgeTAMMaskOutput(
                lowMask: try output(result, "low_best_256", shape: [1, 1, 256, 256], component: name),
                highMask: try output(result, "high_best_1024", shape: [1, 1, 1024, 1024], component: name),
                ious: try output(result, "ious", shape: [1, 3], component: name),
                objectPointer: try output(result, "object_pointer", shape: [1, 256], component: name),
                objectScore: try output(result, "object_score", shape: [1, 1], component: name))
        }
    }

    func memory(features: EdgeTAMTensor, mask: EdgeTAMTensor,
                objectScore: EdgeTAMTensor, fromPoint: Bool) throws -> EdgeTAMMemoryOutput {
        try serial {
            let mode = try EdgeTAMTensor(shape: [1], values: [fromPoint ? 1 : 0])
            let result = try predict("memory", arrays: [
                "pix_feat": Self.array(features, shape: Self.low, name: "pix_feat"),
                "mask_logits": Self.array(mask, shape: [1, 1, 1024, 1024], name: "mask_logits"),
                "object_score_logits": Self.array(objectScore, shape: [1, 1], name: "object_score_logits"),
                "mask_mode": Self.array(mode, shape: [1], name: "mask_mode")
            ])
            return EdgeTAMMemoryOutput(
                features: try output(result, "memory_features", shape: [1, 512, 64], component: "memory"),
                position: try output(result, "memory_positions", shape: [1, 512, 64], component: "memory"))
        }
    }

    private func serial<T>(_ body: () throws -> T) rethrows -> T {
        predictionLock.lock()
        defer { predictionLock.unlock() }
        return try autoreleasepool(invoking: body)
    }

    private func predict(_ component: String, arrays: [String: MLMultiArray]) throws -> MLFeatureProvider {
        try Task.checkCancellation()
        guard let model = models[component] else {
            throw EdgeTAMNativeError.model("Missing loaded EdgeTAM component \(component)")
        }
        let values = arrays.mapValues { MLFeatureValue(multiArray: $0) }
        for (name, value) in values {
            guard model.modelDescription.inputDescriptionsByName[name]?.isAllowedValue(value) == true else {
                throw EdgeTAMNativeError.invalidTensor("\(component).\(name) does not satisfy the loaded model's dtype/shape constraint")
            }
        }
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: values)
            let result = try model.prediction(from: provider, options: MLPredictionOptions())
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EdgeTAMNativeError.model("EdgeTAM \(component) prediction failed: \(error.localizedDescription)")
        }
    }

    /// GPU-backed model heaps duplicate pressure in the app's unified memory budget.
    /// Keep physical iOS on CPU/ANE, retain `.all` for the established Mac parity
    /// harness, and avoid requesting unavailable accelerators in Simulator.
    private static var computeUnits: MLComputeUnits {
        #if targetEnvironment(simulator)
        .cpuOnly
        #elseif os(iOS)
        .cpuAndNeuralEngine
        #else
        .all
        #endif
    }

    private func output(_ provider: MLFeatureProvider, _ name: String,
                        shape: [Int], component: String) throws -> EdgeTAMTensor {
        guard let array = provider.featureValue(for: name)?.multiArrayValue else {
            throw EdgeTAMNativeError.model("EdgeTAM \(component) did not return multi-array \(name)")
        }
        guard array.shape.map(\.intValue) == shape else {
            throw EdgeTAMNativeError.invalidTensor("\(component).\(name) output has unexpected shape \(array.shape); expected \(shape)")
        }
        return try Self.copyTensor(array, name: "\(component).\(name)")
    }

    /// Copies Core ML storage into owned row-major values, including padded or
    /// transposed layouts. Exposed internally for synthetic stride diagnostics.
    static func copyTensor(_ array: MLMultiArray, name: String) throws -> EdgeTAMTensor {
        guard array.dataType == .float32 else {
            throw EdgeTAMNativeError.invalidTensor("\(name) must return float32, received \(array.dataType)")
        }
        let shape = array.shape.map(\.intValue)
        let count = try elementCount(shape, name: name)
        guard array.count == count else { throw EdgeTAMNativeError.invalidTensor("\(name) array count differs from shape") }
        let values = try array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
            // Query strides after obtaining the buffer; Core ML may materialise
            // a different backing layout when CPU access is requested.
            let strides = array.strides.map(\.intValue)
            let contiguous = try validateLayout(shape, strides: strides, bufferCount: buffer.count, name: name)
            if contiguous { return Array(buffer.prefix(count)) }
            var result = [Float](repeating: 0, count: count)
            try visitOffsets(shape, strides: strides) { index, offset in result[index] = buffer[offset] }
            return result
        }
        return try EdgeTAMTensor(shape: shape, values: values)
    }

    private static func array(_ tensor: EdgeTAMTensor, shape: [Int], name: String) throws -> MLMultiArray {
        guard tensor.shape == shape, tensor.values.count == (try elementCount(shape, name: name)),
              tensor.values.allSatisfy(\.isFinite) else {
            throw EdgeTAMNativeError.invalidTensor("\(name) requires finite float32 values with shape \(shape)")
        }
        let array = try MLMultiArray(shape: shape.map(NSNumber.init(value:)), dataType: .float32)
        try array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, strides in
            if try validateLayout(shape, strides: strides, bufferCount: buffer.count, name: name) {
                tensor.values.withUnsafeBufferPointer { source in
                    buffer.baseAddress!.update(from: source.baseAddress!, count: source.count)
                }
            } else {
                try visitOffsets(shape, strides: strides) { index, offset in buffer[offset] = tensor.values[index] }
            }
        }
        return array
    }

    private static func elementCount(_ shape: [Int], name: String) throws -> Int {
        guard !shape.isEmpty, shape.allSatisfy({ $0 > 0 }) else {
            throw EdgeTAMNativeError.invalidTensor("\(name) has an empty/non-positive shape")
        }
        return try shape.reduce(1) { result, dimension in
            let product = result.multipliedReportingOverflow(by: dimension)
            guard !product.overflow else { throw EdgeTAMNativeError.invalidTensor("\(name) shape overflows") }
            return product.partialValue
        }
    }

    private static func validateLayout(_ shape: [Int], strides: [Int], bufferCount: Int, name: String) throws -> Bool {
        guard strides.count == shape.count, strides.allSatisfy({ $0 >= 0 }) else {
            throw EdgeTAMNativeError.invalidTensor("\(name) has unsupported negative or incomplete strides")
        }
        var maximumOffset = 0
        var contiguous = true
        var rowStride = 1
        for axis in stride(from: shape.count - 1, through: 0, by: -1) {
            if shape[axis] > 1, strides[axis] != rowStride { contiguous = false }
            let extent = (shape[axis] - 1).multipliedReportingOverflow(by: strides[axis])
            let sum = maximumOffset.addingReportingOverflow(extent.partialValue)
            guard !extent.overflow, !sum.overflow else { throw EdgeTAMNativeError.invalidTensor("\(name) stride span overflows") }
            maximumOffset = sum.partialValue
            rowStride *= shape[axis] // elementCount validated the full product.
        }
        guard maximumOffset < bufferCount else {
            throw EdgeTAMNativeError.invalidTensor("\(name) strides exceed the accessible Core ML buffer")
        }
        return contiguous
    }

    private static func visitOffsets(_ shape: [Int], strides: [Int], body: (Int, Int) -> Void) throws {
        let count = try elementCount(shape, name: "strided tensor")
        var coordinates = [Int](repeating: 0, count: shape.count)
        var offset = 0
        for index in 0..<count {
            body(index, offset)
            for axis in stride(from: shape.count - 1, through: 0, by: -1) {
                coordinates[axis] += 1
                offset += strides[axis]
                if coordinates[axis] < shape[axis] { break }
                offset -= coordinates[axis] * strides[axis]
                coordinates[axis] = 0
            }
        }
    }

    private static func compiledURL(for source: URL, component: String, allowCompilation: Bool) throws -> URL {
        guard source.isFileURL else { throw EdgeTAMNativeError.model("\(component) requires a local model URL") }
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let compiled = source.pathExtension.lowercased() == "mlmodelc" ? source : source.deletingPathExtension().appendingPathExtension("mlmodelc")
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: compiled.path, isDirectory: &directory), directory.boolValue { return compiled }
        guard source.pathExtension.lowercased() == "mlpackage",
              FileManager.default.fileExists(atPath: source.path, isDirectory: &directory), directory.boolValue else {
            throw EdgeTAMNativeError.model("\(component) requires an existing .mlmodelc or .mlpackage directory")
        }
        #if os(macOS)
        guard allowCompilation else {
            throw EdgeTAMNativeError.model("\(component) is not compiled; enable Mac diagnostic package compilation explicitly")
        }
        do { return try MLModel.compileModel(at: source) }
        catch { throw EdgeTAMNativeError.model("\(component) compilation failed: \(error.localizedDescription)") }
        #else
        throw EdgeTAMNativeError.model("\(component) must be bundled as .mlmodelc on this platform")
        #endif
    }

    private func validateModels() throws {
        let imageInputs = ["image_normalised": Specification(shape: [1, 3, 1024, 1024])]
        try validate("image", inputs: imageInputs, outputs: [
            "vision_features": Specification(shape: Self.low), "high_res_feat_0": Specification(shape: Self.high0),
            "high_res_feat_1": Specification(shape: Self.high1)])
        try validate("attention", inputs: [
            "current_features": Specification(shape: Self.low), "current_position": Specification(shape: Self.low),
            "spatial_memory": Specification(shape: [1, -1, 64]), "spatial_memory_position": Specification(shape: [1, -1, 64]),
            "object_pointer_tokens": Specification(shape: [1, -1, 64])
        ], outputs: ["fused_features": Specification(shape: Self.low)])
        try validate("point", inputs: [
            "backbone_features": Specification(shape: Self.low), "high_res_s0": Specification(shape: Self.high0),
            "high_res_s1": Specification(shape: Self.high1), "point_coords": Specification(shape: [1, 1, 2]),
            "point_labels": Specification(shape: [1, 1], type: .int32)
        ], outputs: Self.maskOutputs)
        try validate("noPoint", inputs: ["backbone": Specification(shape: Self.low),
            "s0": Specification(shape: Self.high0), "s1": Specification(shape: Self.high1)], outputs: Self.maskOutputs)
        try validate("memory", inputs: ["pix_feat": Specification(shape: Self.low),
            "mask_logits": Specification(shape: [1, 1, 1024, 1024]), "object_score_logits": Specification(shape: [1, 1]),
            "mask_mode": Specification(shape: [1])], outputs: [
                "memory_features": Specification(shape: [1, 512, 64]), "memory_positions": Specification(shape: [1, 512, 64])])
        let attention = models["attention"]!
        for name in ["spatial_memory", "spatial_memory_position", "object_pointer_tokens"] {
            let counts = name == "object_pointer_tokens" ? (1...16).map { $0 * 4 } : (1...7).map { $0 * 512 }
            for count in counts {
                let probe = try MLMultiArray(shape: [1, NSNumber(value: count), 64], dataType: .float32)
                guard attention.modelDescription.inputDescriptionsByName[name]!.isAllowedValue(MLFeatureValue(multiArray: probe)) else {
                    throw EdgeTAMNativeError.model("Attention package does not support required \(name) token count \(count)")
                }
            }
        }
    }

    private func validate(_ component: String, inputs: [String: Specification], outputs: [String: Specification]) throws {
        let description = models[component]!.modelDescription
        for (kind, actual, expected) in [("input", description.inputDescriptionsByName, inputs),
                                         ("output", description.outputDescriptionsByName, outputs)] {
            guard Set(actual.keys) == Set(expected.keys) else {
                throw EdgeTAMNativeError.model("\(component) \(kind) names differ from the corrected component contract")
            }
            for (name, specification) in expected {
                guard let constraint = actual[name]?.multiArrayConstraint, constraint.dataType == specification.type else {
                    throw EdgeTAMNativeError.model("\(component).\(name) must declare \(specification.type) multi-array data")
                }
                let shape = constraint.shape.map(\.intValue)
                // Some output descriptions omit static dimensions; actual
                // predictions are always checked against the exact output shape.
                if kind == "output", shape.isEmpty { continue }
                guard shape.count == specification.shape.count,
                      zip(shape, specification.shape).allSatisfy({ $1 == -1 ? $0 > 0 : $0 == $1 }) else {
                    throw EdgeTAMNativeError.model("\(component).\(name) declared shape \(shape) differs from \(specification.shape)")
                }
            }
        }
    }
}
