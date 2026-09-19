import Foundation

/// Integer source rectangle in top-left image coordinates.
struct EdgeTAMSourceCrop: Codable, Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

/// Pillow-compatible RGB crop and bicubic input preparation for EdgeTAM.
///
/// The resize is separable and uses Pillow's a=-0.5 bicubic kernel, centre
/// mapping, edge renormalisation and 22-bit integer coefficient path. Keeping
/// the intermediate image as UInt8 is intentional: Pillow rounds after the
/// horizontal pass before the vertical pass.
struct EdgeTAMImagePreprocessor: Sendable {
    static let outputSize = 1024
    static let mean: (Float, Float, Float) = (0.485, 0.456, 0.406)
    static let standardDeviation: (Float, Float, Float) = (0.229, 0.224, 0.225)
    private static let precisionBits = 22 // Pillow: 32 - 8 - 2

    func tensor(
        rgbBytes: [UInt8],
        width: Int,
        height: Int,
        crop: EdgeTAMSourceCrop
    ) throws -> EdgeTAMTensor {
        let resized = try resizedRGB(rgbBytes: rgbBytes, width: width, height: height, crop: crop)
        let planeSize = Self.outputSize * Self.outputSize
        var values = Array(repeating: Float.zero, count: planeSize * 3)
        let means = [Self.mean.0, Self.mean.1, Self.mean.2]
        let deviations = [Self.standardDeviation.0, Self.standardDeviation.1, Self.standardDeviation.2]
        for y in 0..<Self.outputSize {
            for x in 0..<Self.outputSize {
                let pixel = (y * Self.outputSize + x) * 3
                let plane = y * Self.outputSize + x
                for channel in 0..<3 {
                    let unit = Float(resized[pixel + channel]) / 255.0
                    values[channel * planeSize + plane] = (unit - means[channel]) / deviations[channel]
                }
            }
        }
        return try EdgeTAMTensor(shape: [1, 3, Self.outputSize, Self.outputSize], values: values)
    }

    /// Exposed for the standalone parity harness; production callers use `tensor`.
    func resizedRGB(
        rgbBytes: [UInt8],
        width: Int,
        height: Int,
        crop: EdgeTAMSourceCrop
    ) throws -> [UInt8] {
        guard width > 0, height > 0 else {
            throw EdgeTAMNativeError.invalidState("Source dimensions must be positive")
        }
        let sourceCount = width.multipliedReportingOverflow(by: height)
        guard !sourceCount.overflow else { throw EdgeTAMNativeError.invalidState("Source dimensions overflow") }
        let byteCount = sourceCount.partialValue.multipliedReportingOverflow(by: 3)
        guard !byteCount.overflow, rgbBytes.count == byteCount.partialValue else {
            throw EdgeTAMNativeError.invalidState("RGB storage does not match source dimensions")
        }
        guard crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
              crop.x <= width - crop.width, crop.y <= height - crop.height else {
            throw EdgeTAMNativeError.invalidState("Crop is outside the source image")
        }

        let horizontal = try resizeHorizontal(
            rgbBytes: rgbBytes,
            sourceWidth: width,
            crop: crop,
            destinationWidth: Self.outputSize
        )
        return try resizeVertical(
            rgbBytes: horizontal,
            sourceWidth: Self.outputSize,
            sourceHeight: crop.height,
            destinationHeight: Self.outputSize
        )
    }

    private struct Coefficients {
        let bounds: [Int]
        let weights: [Int32]
        let kernelSize: Int
    }

    private static func bicubic(_ input: Double) -> Double {
        let x = abs(input)
        if x < 1.0 { return ((1.5 * x - 2.5) * x * x) + 1.0 }
        if x < 2.0 { return ((x - 5.0) * x + 8.0) * x * -0.5 + 2.0 }
        return 0.0
    }

    private static func coefficients(inputSize: Int, outputSize: Int) -> Coefficients {
        let scale = Double(inputSize) / Double(outputSize)
        let filterScale = max(scale, 1.0)
        let support = 2.0 * filterScale
        let kernelSize = Int(ceil(support)) * 2 + 1
        let inverseFilterScale = 1.0 / filterScale
        var bounds = Array(repeating: 0, count: outputSize * 2)
        var weights = Array(repeating: Int32.zero, count: outputSize * kernelSize)
        let coefficientScale = Double(1 << precisionBits)

        for output in 0..<outputSize {
            let center = (Double(output) + 0.5) * scale
            var lower = Int(center - support + 0.5)
            lower = max(lower, 0)
            var upper = Int(center + support + 0.5)
            upper = min(upper, inputSize)
            let count = max(upper - lower, 0)
            bounds[output * 2] = lower
            bounds[output * 2 + 1] = count

            var floating = Array(repeating: 0.0, count: kernelSize)
            var sum = 0.0
            for index in 0..<count {
                let weight = bicubic((Double(index + lower) - center + 0.5) * inverseFilterScale)
                floating[index] = weight
                sum += weight
            }
            if sum != 0.0 {
                for index in 0..<count {
                    let value = floating[index] / sum * coefficientScale
                    // Matches Pillow's signed normalize_coeffs_8bpc truncation.
                    floating[index] = value < 0.0 ? value - 0.5 : value + 0.5
                    weights[output * kernelSize + index] = Int32(floating[index])
                }
            }
        }
        return Coefficients(bounds: bounds, weights: weights, kernelSize: kernelSize)
    }

    private func resizeHorizontal(
        rgbBytes: [UInt8],
        sourceWidth: Int,
        crop: EdgeTAMSourceCrop,
        destinationWidth: Int
    ) throws -> [UInt8] {
        let coefficients = Self.coefficients(inputSize: crop.width, outputSize: destinationWidth)
        let count = destinationWidth.multipliedReportingOverflow(by: crop.height)
        guard !count.overflow else { throw EdgeTAMNativeError.invalidState("Horizontal resize overflow") }
        var output = Array(repeating: UInt8.zero, count: count.partialValue * 3)
        let rounding = Int64(1 << (Self.precisionBits - 1))
        for y in 0..<crop.height {
            let sourceRow = (crop.y + y) * sourceWidth
            for x in 0..<destinationWidth {
                let lower = coefficients.bounds[x * 2]
                let count = coefficients.bounds[x * 2 + 1]
                let coefficientStart = x * coefficients.kernelSize
                var accumulators = (rounding, rounding, rounding)
                for index in 0..<count {
                    let sourcePixel = ((sourceRow + crop.x + lower + index) * 3)
                    let coefficient = Int64(coefficients.weights[coefficientStart + index])
                    accumulators.0 += Int64(rgbBytes[sourcePixel]) * coefficient
                    accumulators.1 += Int64(rgbBytes[sourcePixel + 1]) * coefficient
                    accumulators.2 += Int64(rgbBytes[sourcePixel + 2]) * coefficient
                }
                let destinationPixel = (y * destinationWidth + x) * 3
                output[destinationPixel] = Self.clip8(accumulators.0)
                output[destinationPixel + 1] = Self.clip8(accumulators.1)
                output[destinationPixel + 2] = Self.clip8(accumulators.2)
            }
        }
        return output
    }

    private func resizeVertical(
        rgbBytes: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        destinationHeight: Int
    ) throws -> [UInt8] {
        let coefficients = Self.coefficients(inputSize: sourceHeight, outputSize: destinationHeight)
        let count = sourceWidth.multipliedReportingOverflow(by: destinationHeight)
        guard !count.overflow else { throw EdgeTAMNativeError.invalidState("Vertical resize overflow") }
        var output = Array(repeating: UInt8.zero, count: count.partialValue * 3)
        let rounding = Int64(1 << (Self.precisionBits - 1))
        for y in 0..<destinationHeight {
            let lower = coefficients.bounds[y * 2]
            let count = coefficients.bounds[y * 2 + 1]
            let coefficientStart = y * coefficients.kernelSize
            for x in 0..<sourceWidth {
                var accumulators = (rounding, rounding, rounding)
                for index in 0..<count {
                    let sourcePixel = ((lower + index) * sourceWidth + x) * 3
                    let coefficient = Int64(coefficients.weights[coefficientStart + index])
                    accumulators.0 += Int64(rgbBytes[sourcePixel]) * coefficient
                    accumulators.1 += Int64(rgbBytes[sourcePixel + 1]) * coefficient
                    accumulators.2 += Int64(rgbBytes[sourcePixel + 2]) * coefficient
                }
                let destinationPixel = (y * sourceWidth + x) * 3
                output[destinationPixel] = Self.clip8(accumulators.0)
                output[destinationPixel + 1] = Self.clip8(accumulators.1)
                output[destinationPixel + 2] = Self.clip8(accumulators.2)
            }
        }
        return output
    }

    private static func clip8(_ accumulator: Int64) -> UInt8 {
        let value = accumulator >> Int64(precisionBits)
        return UInt8(max(0, min(255, value)))
    }
}
