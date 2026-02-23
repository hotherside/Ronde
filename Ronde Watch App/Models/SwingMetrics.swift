import Foundation

/// Per-swing metrics derived from accelerometer data during the swing window.
///
/// Ephemeral — displayed for ~3.5 seconds per swing, then discarded.
/// Not persisted in SwiftData (future enhancement could store on HoleScore).
struct SwingMetrics: Sendable, Identifiable {
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
    /// Downsampled to ~60 points for arc profile rendering.
    let accelerationProfile: [Double]

    // MARK: - Derived Display Values

    /// Peak g formatted: "12.4g"
    var peakGFormatted: String {
        String(format: "%.1fg", peakG)
    }

    /// Estimated speed in km/h (hand speed × ~3.0 wrist-to-club multiplier).
    var estimatedSpeedKMH: Double {
        estimatedSpeedMPS * 3.6 * 3.0
    }

    /// Speed for display: "97"
    var estimatedSpeedFormatted: String {
        String(format: "%.0f", estimatedSpeedKMH)
    }

    /// Tempo in milliseconds: "240ms"
    var tempoFormatted: String {
        String(format: "%.0fms", tempoSeconds * 1000)
    }

    /// Normalized force from 0.0 to 1.0 for arc fill.
    /// Maps 8g (threshold) → 0.0 and 25g → 1.0, clamped.
    var normalizedForce: Double {
        let minG = 8.0
        let maxG = 25.0
        return min(max((peakG - minG) / (maxG - minG), 0.0), 1.0)
    }
}
