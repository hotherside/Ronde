@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

/// A short window of mono PCM energy extracted from an imported recording.
/// `strength` is a peak absolute sample amplitude in the normalised PCM range.
struct AudioImpactPeak: Sendable, Equatable, Comparable {
    let time: TimeInterval
    let strength: Double

    init(time: TimeInterval, strength: Double) {
        self.time = max(0, time)
        self.strength = max(0, strength)
    }

    static func < (lhs: AudioImpactPeak, rhs: AudioImpactPeak) -> Bool {
        lhs.time == rhs.time ? lhs.strength < rhs.strength : lhs.time < rhs.time
    }
}

struct ImpactAudioAnalysisConfiguration: Sendable, Equatable {
    /// 512 sample frames gives approximately 11 ms impact timing resolution at 48 kHz.
    var analysisWindowSamples: Int
    /// A quiet room or wind noise should not create a candidate solely because it is louder than silence.
    var minimumPeakAmplitude: Double
    /// Peaks inside this period represent the same club/ball impact.
    var clusterSeparation: TimeInterval
    /// A golfer cannot produce two independent full-shot impacts inside this period.
    var refractoryPeriod: TimeInterval
    /// Relative to the robust noise floor. Kept deliberately conservative for unattended range footage.
    var minimumSignalToNoiseRatio: Double

    static let golfTripod = ImpactAudioAnalysisConfiguration(
        analysisWindowSamples: 512,
        minimumPeakAmplitude: 0.035,
        clusterSeparation: 0.16,
        refractoryPeriod: 4.0,
        minimumSignalToNoiseRatio: 5.0
    )
}

enum AudioImpactAnalysisError: LocalizedError, Sendable {
    case unreadableAsset
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableAsset:
            "The selected video cannot be read on this device."
        case let .readerFailed(message):
            message
        }
    }
}

/// Pure candidate policy used by the asset reader and unit tests. It deliberately knows nothing
/// about Vision or ball flight. Audio yields a reviewable impact marker, never a real-shot claim.
struct AudioImpactPeakSelector: Sendable {
    func select(
        from rawPeaks: [AudioImpactPeak],
        configuration: ImpactAudioAnalysisConfiguration = .golfTripod
    ) -> [AudioImpactPeak] {
        let peaks = rawPeaks
            .filter { $0.time.isFinite && $0.strength.isFinite && $0.strength > 0 }
            .sorted()
        guard !peaks.isEmpty else { return [] }

        let noiseFloor = percentile(peaks.map(\.strength), percentile: 0.5)
        let threshold = max(
            configuration.minimumPeakAmplitude,
            noiseFloor * configuration.minimumSignalToNoiseRatio
        )
        let strongPeaks = peaks.filter { $0.strength >= threshold }
        guard !strongPeaks.isEmpty else { return [] }

        let merged = mergeClusters(strongPeaks, separation: configuration.clusterSeparation)
        return enforceRefractoryPeriod(merged, period: configuration.refractoryPeriod)
    }

    /// Keeps the highest amplitude peak for each immediately-adjacent burst.
    func mergeClusters(_ peaks: [AudioImpactPeak], separation: TimeInterval) -> [AudioImpactPeak] {
        guard let first = peaks.sorted().first else { return [] }
        let safeSeparation = max(0, separation)
        var selected: [AudioImpactPeak] = []
        var current = first
        var previousTime = first.time

        for peak in peaks.sorted().dropFirst() {
            if peak.time - previousTime <= safeSeparation {
                if peak.strength > current.strength {
                    current = peak
                }
            } else {
                selected.append(current)
                current = peak
            }
            previousTime = peak.time
        }
        selected.append(current)
        return selected
    }

    /// Applies a realistic full-swing cooldown. If two loud sounds occur inside the cooldown,
    /// retain the stronger one so a club/ball impact wins over a nearby incidental sound.
    func enforceRefractoryPeriod(_ peaks: [AudioImpactPeak], period: TimeInterval) -> [AudioImpactPeak] {
        guard let first = peaks.sorted().first else { return [] }
        let safePeriod = max(0, period)
        var selected: [AudioImpactPeak] = []
        var current = first

        for peak in peaks.sorted().dropFirst() {
            if peak.time - current.time < safePeriod {
                if peak.strength > current.strength {
                    current = peak
                }
            } else {
                selected.append(current)
                current = peak
            }
        }
        selected.append(current)
        return selected
    }

    private func percentile(_ values: [Double], percentile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(max(Int((Double(sorted.count - 1) * percentile).rounded()), 0), sorted.count - 1)
        return sorted[index]
    }
}

/// Extracts impact-like audio transients from the video's local audio track. It is designed for a
/// fixed tripod range setup and provides a useful single candidate for a short single-shot clip.
/// It does not use a generic Vision trajectory and does not claim that a ball tracer exists.
actor AudioImpactAnalysisService {
    private let selector: AudioImpactPeakSelector

    init(selector: AudioImpactPeakSelector = .init()) {
        self.selector = selector
    }

    func analyse(
        url: URL,
        configuration: ImpactAudioAnalysisConfiguration = .golfTripod,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [SwingCandidate] {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else { throw AudioImpactAnalysisError.unreadableAsset }
        let duration = try await asset.load(.duration)
        let durationSeconds = max(CMTimeGetSeconds(duration), 0.001)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).last else {
            progress?(1)
            return []
        }

        let reader = try AVAssetReader(asset: asset)
        // Request a single, interleaved float stream. Some iPhone MOV files contain multiple
        // AAC tracks with different channel layouts (for example quadraphonic plus stereo).
        // Asking for the source channel count can make Core Media's converter fail for the
        // quadraphonic track, while the analyser only needs a format-independent energy signal.
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: [audioTrack],
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioImpactAnalysisError.unreadableAsset }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioImpactAnalysisError.readerFailed(Self.readerMessage(reader.error, fallback: "Audio reader failed to start."))
        }

        var rawPeaks: [AudioImpactPeak] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = CMTimeGetSeconds(sampleTime)
            progress?(min(max(seconds / durationSeconds, 0), 1))
            rawPeaks.append(contentsOf: Self.peaks(in: sampleBuffer, windowSamples: configuration.analysisWindowSamples))
        }

        if reader.status == .failed {
            throw AudioImpactAnalysisError.readerFailed(Self.readerMessage(reader.error, fallback: "Audio analysis failed."))
        }

        progress?(1)
        return selector.select(from: rawPeaks, configuration: configuration).map { peak in
            SwingCandidate(
                impactTime: peak.time,
                classification: .provisional(
                    confidence: Self.confidence(for: peak.strength),
                    explanation: "A strong impact-like sound was found. Confirm the exact frame before saving the shot."
                ),
                evidence: [.audioTransient]
            )
        }
    }

    private static func peaks(in sampleBuffer: CMSampleBuffer, windowSamples: Int) -> [AudioImpactPeak] {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              streamDescription.mFormatID == kAudioFormatLinearPCM,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return []
        }

        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        let bytesPerSample = max(Int(streamDescription.mBitsPerChannel / 8), 1)
        guard byteCount >= bytesPerSample else { return [] }
        let scalarSampleCount = byteCount / bytesPerSample
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let copyStatus = bytes.withUnsafeMutableBytes { destinationBuffer in
            guard let destination = destinationBuffer.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: destination
            )
        }
        guard copyStatus == noErr else {
            return []
        }

        let channelCount = max(Int(streamDescription.mChannelsPerFrame), 1)
        let frameCount = scalarSampleCount / channelCount
        let safeWindow = max(1, windowSamples)
        let startTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let sampleRate = streamDescription.mSampleRate > 0 ? streamDescription.mSampleRate : 44_100
        var results: [AudioImpactPeak] = []

        for frameStart in stride(from: 0, to: frameCount, by: safeWindow) {
            let frameEnd = min(frameStart + safeWindow, frameCount)
            let scalarStart = frameStart * channelCount
            let scalarEnd = frameEnd * channelCount
            var maximum = 0.0
            for index in scalarStart..<scalarEnd {
                let byteOffset = index * bytesPerSample
                let value: Double
                if (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
                   streamDescription.mBitsPerChannel == 32 {
                    value = Double(bytes.withUnsafeBytes { rawBytes in
                        rawBytes.loadUnaligned(fromByteOffset: byteOffset, as: Float.self)
                    })
                } else if streamDescription.mBitsPerChannel == 16 {
                    let sample = bytes.withUnsafeBytes { rawBytes in
                        rawBytes.loadUnaligned(fromByteOffset: byteOffset, as: Int16.self)
                    }
                    value = Double(sample) / Double(Int16.max)
                } else if streamDescription.mBitsPerChannel == 32 {
                    let sample = bytes.withUnsafeBytes { rawBytes in
                        rawBytes.loadUnaligned(fromByteOffset: byteOffset, as: Int32.self)
                    }
                    value = Double(sample) / Double(Int32.max)
                } else {
                    continue
                }
                if value.isFinite { maximum = max(maximum, abs(value)) }
            }
            let time = startTime + (Double(frameStart) / sampleRate)
            results.append(AudioImpactPeak(time: time, strength: maximum))
        }
        return results
    }

    private static func confidence(for peakAmplitude: Double) -> Double {
        // Amplitude gives a small ordering signal only. It is not a shot classifier.
        min(max(0.38 + (peakAmplitude * 0.35), 0.38), 0.7)
    }

    private static func readerMessage(_ error: Error?, fallback: String) -> String {
        guard let error else { return fallback }
        let nsError = error as NSError
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map {
            " underlying: \($0.localizedDescription) [\($0.domain) \($0.code)]"
        } ?? ""
        return "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]\(underlying)"
    }
}
