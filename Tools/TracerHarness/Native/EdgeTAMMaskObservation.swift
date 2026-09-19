import Foundation

struct EdgeTAMMaskObservation: Sendable {
    let width: Int
    let height: Int
    let binaryMask: [UInt8]
    let componentCount: Int
    let selectedArea: Int
    let positiveArea: Int
    let centroidX: Double?
    let centroidY: Double?

    /// Matches the original output route: low 256 mask directly to source crop,
    /// bilinear align_corners=false, then logits > 0 and the largest 8-connected
    /// component. It never resizes the already-upsampled 1024 memory mask.
    static func extract(lowMask: EdgeTAMTensor, width: Int, height: Int) throws -> Self {
        _ = try lowMask.requiringShape([1, 1, 256, 256])
        guard width > 0, height > 0, width <= 4096, height <= 4096 else {
            throw EdgeTAMNativeError.invalidTensor("Output crop dimensions are invalid")
        }
        var binary = [UInt8](repeating: 0, count: width * height)
        let xScale = Float(256) / Float(width)
        let yScale = Float(256) / Float(height)
        var positive = 0
        for y in 0..<height {
            let sourceY = max(0, (Float(y) + 0.5) * yScale - 0.5)
            let y0 = min(255, Int(sourceY))
            let y1 = min(255, y0 + 1)
            let fy = sourceY - Float(y0)
            for x in 0..<width {
                let sourceX = max(0, (Float(x) + 0.5) * xScale - 0.5)
                let x0 = min(255, Int(sourceX))
                let x1 = min(255, x0 + 1)
                let fx = sourceX - Float(x0)
                let upper = (1 - fx) * lowMask.values[y0 * 256 + x0] + fx * lowMask.values[y0 * 256 + x1]
                let lower = (1 - fx) * lowMask.values[y1 * 256 + x0] + fx * lowMask.values[y1 * 256 + x1]
                let value = (1 - fy) * upper + fy * lower
                if value > 0 { binary[y * width + x] = 255; positive += 1 }
            }
        }
        var visited = [Bool](repeating: false, count: binary.count)
        var stack: [Int] = []
        var components = 0
        var bestArea = 0
        var bestSumX: Int64 = 0
        var bestSumY: Int64 = 0
        for start in binary.indices where binary[start] != 0 && !visited[start] {
            components += 1
            var area = 0
            var sumX: Int64 = 0
            var sumY: Int64 = 0
            stack.append(start)
            visited[start] = true
            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                area += 1
                sumX += Int64(x)
                sumY += Int64(y)
                for nextY in max(0, y - 1)...min(height - 1, y + 1) {
                    for nextX in max(0, x - 1)...min(width - 1, x + 1) {
                        let next = nextY * width + nextX
                        if binary[next] != 0 && !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            // On a tie retain the first row-major component, like NumPy argmax.
            if area > bestArea { bestArea = area; bestSumX = sumX; bestSumY = sumY }
        }
        return Self(width: width, height: height, binaryMask: binary,
                    componentCount: components, selectedArea: bestArea, positiveArea: positive,
                    centroidX: bestArea > 0 ? Double(bestSumX) / Double(bestArea) + 0.5 : nil,
                    centroidY: bestArea > 0 ? Double(bestSumY) / Double(bestArea) + 0.5 : nil)
    }
}
