import Foundation

/// Per-swing metrics derived from accelerometer data during the swing window.
///
/// Persisted on `HoleScore.swingData` as a Codable array.
/// The `accelerationProfile` is excluded from encoding (only used for the live arc overlay).
struct SwingMetrics: Sendable, Identifiable, Codable {
    let id: UUID
    let timestamp: Date

    /// Peak acceleration magnitude in g's during the swing window.
    /// Range: accelerationThreshold (~8g) to ~30g for powerful swings.
    let peakG: Double

    /// Estimated hand speed in m/s.
    /// Computed by integrating acceleration magnitude above baseline
    /// over the impulse duration.
    let estimatedSpeedMPS: Double

    /// Duration in seconds from the first threshold crossing to peak g.
    /// Represents the tempo of the backswing-to-impact transition.
    let tempoSeconds: Double

    /// Sampled acceleration magnitudes over the swing window.
    /// Only used for the live SwingArcView overlay — excluded from Codable encoding.
    var accelerationProfile: [Double]

    // MARK: - Codable (exclude accelerationProfile)

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, peakG, estimatedSpeedMPS, tempoSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        peakG = try container.decode(Double.self, forKey: .peakG)
        estimatedSpeedMPS = try container.decode(Double.self, forKey: .estimatedSpeedMPS)
        tempoSeconds = try container.decode(Double.self, forKey: .tempoSeconds)
        accelerationProfile = []
    }

    init(
        id: UUID,
        timestamp: Date,
        peakG: Double,
        estimatedSpeedMPS: Double,
        tempoSeconds: Double,
        accelerationProfile: [Double]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.peakG = peakG
        self.estimatedSpeedMPS = estimatedSpeedMPS
        self.tempoSeconds = tempoSeconds
        self.accelerationProfile = accelerationProfile
    }

    // MARK: - Derived Display Values

    /// Estimated clubhead speed in km/h using centripetal acceleration model.
    ///
    /// During a golf swing the wrist follows a circular arc, so peak
    /// acceleration is primarily centripetal:  a = v² / r
    ///   → v_wrist = √((peakG − 1) × 9.81 × r)
    ///
    /// Constants:
    ///   - `wristArcRadius` 0.7 m — typical radius of the wrist's swing arc
    ///   - `wristToClubheadRatio` 3.3 — empirical average across clubs
    ///     (shaft acts as a lever, clubhead travels ~3–4× faster than the wrist)
    var estimatedSpeedKMH: Double {
        let netG = max(peakG - 1.0, 0.0)          // subtract gravity baseline
        let wristArcRadius = 0.7                    // metres
        let wristToClubheadRatio = 3.3              // empirical average
        let wristSpeedMPS = (netG * 9.81 * wristArcRadius).squareRoot()
        return wristSpeedMPS * 3.6 * wristToClubheadRatio
    }

    /// Speed for display: "103"
    var estimatedSpeedFormatted: String {
        String(format: "%.0f", estimatedSpeedKMH)
    }

    /// Peak g formatted: "12.4g"
    var peakGFormatted: String {
        String(format: "%.1fg", peakG)
    }

    /// Tempo in milliseconds: "240ms"
    var tempoFormatted: String {
        String(format: "%.0fms", tempoSeconds * 1000)
    }

    /// Normalized speed from 0.0 to 1.0 for arc fill.
    /// Maps 40 km/h → 0.0 and 180 km/h → 1.0, clamped.
    var normalizedSpeed: Double {
        let minSpeed = 40.0
        let maxSpeed = 180.0
        return min(max((estimatedSpeedKMH - minSpeed) / (maxSpeed - minSpeed), 0.0), 1.0)
    }
}
