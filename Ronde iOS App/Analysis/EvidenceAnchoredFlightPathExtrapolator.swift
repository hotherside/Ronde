import Foundation

/// Fits a perspective-aware ballistic presentation model to a verified source-frame ball track.
///
/// The detector remains the identity gate. This type may estimate the missing connector back to
/// impact, the apex, landing and a broad carry range, but it cannot upgrade generic motion into a
/// golf-ball observation. All generated geometry remains explicitly inferred.
struct EvidenceAnchoredFlightPathExtrapolator: Sendable {
    struct Configuration: Sendable, Equatable {
        var gravity: Double
        var dragRate: Double
        var cameraHeight: Double
        var sampleRate: Double
        var minimumObservedPoints: Int
        var minimumObservedDuration: TimeInterval
        var maximumFitError: Double
        var nearFitTolerance: Double
        var maximumLaunchConnectorDuration: TimeInterval
        var maximumLaunchScreenDisplacement: Double
        var minimumFlightDuration: TimeInterval
        var minimumCarryMetres: Double
        var maximumCarryMetres: Double

        static let automaticTracer = Configuration(
            gravity: 8.2,
            dragRate: 0.35,
            cameraHeight: 1.4,
            sampleRate: 60,
            minimumObservedPoints: 6,
            minimumObservedDuration: 0.16,
            maximumFitError: 0.018,
            nearFitTolerance: 0.0025,
            maximumLaunchConnectorDuration: 0.55,
            maximumLaunchScreenDisplacement: 0.62,
            minimumFlightDuration: 1.6,
            minimumCarryMetres: 25,
            maximumCarryMetres: 320
        )
    }

    private struct ModelParameters: Sendable {
        var speed: Double
        var elevation: Double
        var horizonY: Double
        var launchDistance: Double
        var scale: Double
        var vanishingX: Double
        var launchX: Double
        var lateralRate: Double
    }

    private struct FittedModel: Sendable {
        var parameters: ModelParameters
        var error: Double
        var selectionScore: Double
        var flightDuration: TimeInterval
        var carryMetres: Double
    }

    /// Imported single-camera footage cannot identify world scale. Screen-rate is used only to
    /// separate a chip-like fragment from a fast full-shot fragment before the broad physical
    /// range is calculated. It is a modelling prior, not a speed measurement.
    private struct LaunchSpeedPrior: Sendable {
        var lowerBound: Double
        var upperBound: Double
        var centre: Double
        var uncertainty: Double
        var elevationLowerBound: Double
        var elevationUpperBound: Double
        var elevationCentre: Double
        var elevationUncertainty: Double

        func penalty(for speed: Double, elevationDegrees: Double) -> Double {
            let speedDistance = abs(speed - centre) / max(1, uncertainty)
            let elevationDistance = abs(elevationDegrees - elevationCentre)
                / max(1, elevationUncertainty)
            return (0.000_55 * speedDistance * speedDistance)
                + (0.000_35 * elevationDistance * elevationDistance)
        }
    }

    let configuration: Configuration

    init(configuration: Configuration = .automaticTracer) {
        self.configuration = configuration
    }

    func path(
        from estimate: BallFlightEstimate,
        impactTime: TimeInterval? = nil
    ) -> EvidenceAnchoredFlightPath? {
        guard estimate.source == .observed || estimate.source == .observedAndInferred,
              estimate.observedPointCount >= 3,
              let trajectory = estimate.observedTrajectory,
              trajectory.detectedPoints.count >= 3 else {
            return nil
        }

        let observed = trajectory.detectedPoints
        let timestamps = Self.usableTimestamps(trajectory.presentationTimes, matching: observed.count)
        guard timestamps.count == observed.count,
              observed.count >= configuration.minimumObservedPoints,
              let firstTime = timestamps.first,
              let lastTime = timestamps.last,
              lastTime - firstTime >= configuration.minimumObservedDuration else {
            return EvidenceAnchoredFlightPath(
                observedPoints: observed,
                observedPresentationTimes: timestamps,
                confidence: estimate.confidence
            )
        }

        guard let impactTime,
              impactTime.isFinite,
              firstTime > impactTime,
              lastTime > impactTime else {
            return EvidenceAnchoredFlightPath(
                observedPoints: observed,
                observedPresentationTimes: timestamps,
                confidence: estimate.confidence
            )
        }
        // Physics time begins at impact, not at the first mid-air observation. Treating the first
        // observed point as height zero was the direct cause of the foreground launch spike and
        // the continuation ending in the sky.
        let samples = zip(observed, timestamps).map { point, time in
            (x: point.x, y: point.y, time: time - impactTime)
        }
        let speedPrior = launchSpeedPrior(for: samples)
        let fits = fittedModels(for: samples, speedPrior: speedPrior)
        guard let best = fits.min(by: { $0.selectionScore < $1.selectionScore }),
              best.error <= configuration.maximumFitError else {
            return EvidenceAnchoredFlightPath(
                observedPoints: observed,
                observedPresentationTimes: timestamps,
                confidence: estimate.confidence
            )
        }

        let firstObservedFlightTime = firstTime - impactTime
        let lastObservedFlightTime = lastTime - impactTime
        let connectorDuration = min(
            configuration.maximumLaunchConnectorDuration,
            firstObservedFlightTime
        )
        let connector = launchConnector(
            model: best.parameters,
            firstObserved: observed[0],
            firstObservedFlightTime: firstObservedFlightTime,
            duration: connectorDuration
        )
        let continuation = landingContinuation(
            model: best.parameters,
            observed: observed,
            lastObservedFlightTime: lastObservedFlightTime,
            flightDuration: best.flightDuration
        )
        guard !connector.isEmpty,
              !continuation.isEmpty,
              connector.allSatisfy(Self.isSafeEstimatedPoint),
              continuation.allSatisfy(Self.isSafeEstimatedPoint) else {
            return EvidenceAnchoredFlightPath(
                observedPoints: observed,
                observedPresentationTimes: timestamps,
                confidence: estimate.confidence
            )
        }
        let continuationDuration = max(0.01, best.flightDuration - lastObservedFlightTime)

        return EvidenceAnchoredFlightPath(
            inferredLaunchConnector: connector,
            observedPoints: observed,
            inferredContinuation: continuation,
            observedPresentationTimes: timestamps,
            inferredLaunchPresentationDuration: connectorDuration,
            inferredPresentationDuration: continuationDuration,
            estimatedFlightDuration: best.flightDuration,
            estimatedCarry: carryEstimate(from: fits, bestScore: best.selectionScore),
            fitError: best.error,
            confidence: estimate.confidence
        )
    }

    private func fittedModels(
        for samples: [(x: Double, y: Double, time: Double)],
        speedPrior: LaunchSpeedPrior
    ) -> [FittedModel] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var fits: [FittedModel] = []
        fits.reserveCapacity(256)

        for launchDistance in [2.0, 3.0, 4.5] {
            for speed in stride(from: speedPrior.lowerBound, through: speedPrior.upperBound, by: 4.0) {
                for elevationDegrees in stride(
                    from: speedPrior.elevationLowerBound,
                    through: speedPrior.elevationUpperBound,
                    by: 2.0
                ) {
                    let elevation = elevationDegrees * .pi / 180
                    let flightDuration = hangTime(speed: speed, elevation: elevation)
                    guard flightDuration >= configuration.minimumFlightDuration,
                          flightDuration - last.time >= 0.18 else { continue }

                    var parameters = ModelParameters(
                        speed: speed,
                        elevation: elevation,
                        horizonY: first.y,
                        launchDistance: launchDistance,
                        scale: 1,
                        vanishingX: first.x,
                        launchX: first.x,
                        lateralRate: 0
                    )
                    guard fitVertical(&parameters, samples: samples) else { continue }
                    guard fitLateral(&parameters, samples: samples) else { continue }
                    let launch = project(parameters, at: 0)
                    let landing = project(parameters, at: flightDuration)
                    let modelAtLastObservation = project(parameters, at: last.time)
                    let joinedLanding = (
                        x: landing.x + (last.x - modelAtLastObservation.x),
                        y: landing.y + (last.y - modelAtLastObservation.y)
                    )
                    guard parameters.horizonY >= 0.20,
                          parameters.horizonY <= 0.72,
                          (0.035...0.965).contains(launch.x),
                          launch.y >= min(0.98, first.y + 0.08),
                          launch.y <= 0.98,
                          (0.035...0.965).contains(landing.x),
                          (0.035...0.965).contains(landing.y),
                          landing.y > parameters.horizonY,
                          landing.y < launch.y,
                          (0.035...0.965).contains(joinedLanding.x),
                          (0.035...0.965).contains(joinedLanding.y) else { continue }
                    let error = fitError(parameters, samples: samples)
                    guard error <= configuration.maximumFitError else { continue }

                    let carry = carryDistance(for: parameters, at: flightDuration)
                    guard carry >= configuration.minimumCarryMetres,
                          carry <= configuration.maximumCarryMetres else { continue }
                    fits.append(FittedModel(
                        parameters: parameters,
                        error: error,
                        selectionScore: error + speedPrior.penalty(
                            for: speed,
                            elevationDegrees: elevationDegrees
                        ),
                        flightDuration: flightDuration,
                        carryMetres: carry
                    ))
                }
            }
        }
        return fits
    }

    private func launchConnector(
        model: ModelParameters,
        firstObserved: NormalizedPoint,
        firstObservedFlightTime: TimeInterval,
        duration: TimeInterval
    ) -> [NormalizedPoint] {
        guard duration > 0.01 else { return [] }
        let modelJoin = project(model, at: firstObservedFlightTime)
        let joinOffset = (x: firstObserved.x - modelJoin.x, y: firstObserved.y - modelJoin.y)
        let step = 1 / configuration.sampleRate
        var result: [NormalizedPoint] = []
        let startTime = max(0, firstObservedFlightTime - duration)
        let modelStart = project(model, at: startTime)
        // The single-view fit can push the estimated impact point below the frame because camera
        // distance and pitch are underdetermined. Bound only that estimated presentation segment;
        // detector-attributed points and the fitted landing remain untouched.
        let maximumLaunchY = min(
            0.90,
            firstObserved.y + configuration.maximumLaunchScreenDisplacement
        )
        let startAdjustmentY = min(0, maximumLaunchY - modelStart.y)
        var time = startTime
        while time < firstObservedFlightTime - (step / 2) {
            let projected = project(model, at: time)
            let blend = time / max(firstObservedFlightTime, 0.001)
            let connectorProgress = (time - startTime)
                / max(firstObservedFlightTime - startTime, 0.001)
            result.append(NormalizedPoint(
                x: projected.x + (joinOffset.x * blend),
                y: projected.y
                    + (joinOffset.y * blend)
                    + (startAdjustmentY * (1 - connectorProgress))
            ))
            time += step
        }
        return result
    }

    private func landingContinuation(
        model: ModelParameters,
        observed: [NormalizedPoint],
        lastObservedFlightTime: TimeInterval,
        flightDuration: TimeInterval
    ) -> [NormalizedPoint] {
        guard let last = observed.last,
              flightDuration - lastObservedFlightTime >= 0.18 else { return [] }

        let joinReference = project(model, at: lastObservedFlightTime)
        let joinOffset = (x: last.x - joinReference.x, y: last.y - joinReference.y)
        let step = 1 / configuration.sampleRate
        var result: [NormalizedPoint] = []
        var time = lastObservedFlightTime + step
        while time <= flightDuration + (step / 2) {
            let projected = project(model, at: min(time, flightDuration))
            result.append(NormalizedPoint(
                x: projected.x + joinOffset.x,
                y: projected.y + joinOffset.y
            ))
            time += step
        }
        return result
    }

    /// For fixed physical parameters, image `y` is linear in
    /// `(cameraHeight - ballHeight) / downrangeDistance`. Solving both terms from all observed
    /// points prevents the first mid-air point from being mistaken for the launch plane.
    private func fitVertical(
        _ parameters: inout ModelParameters,
        samples: [(x: Double, y: Double, time: Double)]
    ) -> Bool {
        guard samples.count >= 3 else { return false }
        var sumZ = 0.0
        var sumY = 0.0
        var sumZZ = 0.0
        var sumZY = 0.0
        for sample in samples {
            let world = worldState(parameters, at: sample.time)
            let z = (configuration.cameraHeight - world.height)
                / max(parameters.launchDistance * 0.25, world.distance)
            sumZ += z
            sumY += sample.y
            sumZZ += z * z
            sumZY += z * sample.y
        }
        let count = Double(samples.count)
        let determinant = (count * sumZZ) - (sumZ * sumZ)
        guard abs(determinant) > 1e-9 else { return false }
        let scale = ((count * sumZY) - (sumZ * sumY)) / determinant
        let horizon = (sumY - (scale * sumZ)) / count
        guard scale.isFinite, horizon.isFinite, scale > 0 else { return false }
        parameters.scale = scale
        parameters.horizonY = horizon
        return true
    }

    private func carryEstimate(
        from fits: [FittedModel],
        bestScore: Double
    ) -> EstimatedCarryDistance? {
        let plausible = fits
            .filter { $0.selectionScore <= bestScore + configuration.nearFitTolerance }
            .map(\.carryMetres)
            .sorted()
        guard !plausible.isEmpty else { return nil }

        let lower = percentile(0.20, in: plausible)
        let upper = percentile(0.80, in: plausible)
        let roundedLower = max(0, Int(floor(lower / 5) * 5))
        let roundedUpper = max(roundedLower + 10, Int(ceil(upper / 5) * 5))
        return EstimatedCarryDistance(
            lowerMetres: roundedLower,
            upperMetres: min(Int(configuration.maximumCarryMetres), roundedUpper)
        )
    }

    private func launchSpeedPrior(
        for samples: [(x: Double, y: Double, time: Double)]
    ) -> LaunchSpeedPrior {
        guard let first = samples.first,
              let last = samples.last,
              last.time > first.time else {
            return LaunchSpeedPrior(
                lowerBound: 28,
                upperBound: 72,
                centre: 46,
                uncertainty: 16,
                elevationLowerBound: 10,
                elevationUpperBound: 34,
                elevationCentre: 18,
                elevationUncertainty: 8
            )
        }
        let screenDisplacement = hypot(last.x - first.x, last.y - first.y)
        let screenRate = screenDisplacement / (last.time - first.time)
        switch screenRate {
        case 0.40...:
            return LaunchSpeedPrior(
                lowerBound: 44,
                upperBound: 80,
                centre: 60,
                uncertainty: 12,
                elevationLowerBound: 12,
                elevationUpperBound: 28,
                elevationCentre: 17,
                elevationUncertainty: 6
            )
        case 0.20..<0.40:
            return LaunchSpeedPrior(
                lowerBound: 34,
                upperBound: 76,
                centre: 50,
                uncertainty: 14,
                elevationLowerBound: 10,
                elevationUpperBound: 32,
                elevationCentre: 18,
                elevationUncertainty: 8
            )
        default:
            return LaunchSpeedPrior(
                lowerBound: 24,
                upperBound: 68,
                centre: 40,
                uncertainty: 16,
                elevationLowerBound: 8,
                elevationUpperBound: 38,
                elevationCentre: 20,
                elevationUncertainty: 10
            )
        }
    }

    private func percentile(_ fraction: Double, in values: [Double]) -> Double {
        guard let first = values.first else { return 0 }
        guard values.count > 1 else { return first }
        let position = min(1, max(0, fraction)) * Double(values.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return values[lowerIndex] }
        let blend = position - Double(lowerIndex)
        return values[lowerIndex] + ((values[upperIndex] - values[lowerIndex]) * blend)
    }

    private func worldState(
        _ parameters: ModelParameters,
        at time: TimeInterval
    ) -> (height: Double, distance: Double) {
        let verticalSpeed = parameters.speed * sin(parameters.elevation)
        let downrangeSpeed = parameters.speed * cos(parameters.elevation)
        let height = (verticalSpeed * time) - (0.5 * configuration.gravity * time * time)
        let distance = parameters.launchDistance
            + (downrangeSpeed / configuration.dragRate) * (1 - exp(-configuration.dragRate * time))
        return (height, distance)
    }

    private func hangTime(speed: Double, elevation: Double) -> TimeInterval {
        max(0.6, 2 * speed * sin(elevation) / configuration.gravity)
    }

    private func carryDistance(
        for parameters: ModelParameters,
        at flightDuration: TimeInterval
    ) -> Double {
        // Screen-space convergence needs stronger damping than a real golf ball's down-range
        // flight. Reusing the projection damping here was the direct cause of chip-sized carry
        // ranges for visibly fast full swings. This remains a prior-driven estimate, not a
        // measurement; a dedicated aerodynamic model can replace it once calibration exists.
        let carryDragRate = 0.10
        let downrangeSpeed = parameters.speed * cos(parameters.elevation)
        return max(
            0,
            (downrangeSpeed / carryDragRate)
                * (1 - exp(-carryDragRate * flightDuration))
        )
    }

    private func project(
        _ parameters: ModelParameters,
        at time: TimeInterval
    ) -> (x: Double, y: Double) {
        let world = worldState(parameters, at: time)
        let safeDistance = max(parameters.launchDistance * 0.25, world.distance)
        let y = parameters.horizonY
            + (configuration.cameraHeight - world.height) * parameters.scale / safeDistance
        let perspective = parameters.launchDistance / safeDistance
        let x = parameters.vanishingX
            + ((parameters.launchX - parameters.vanishingX + (parameters.lateralRate * time)) * perspective)
        return (x, y)
    }

    /// Lateral projection contains three linear unknowns for fixed physical parameters:
    /// vanishing point, launch position and cross-range rate. Solving all three avoids pinning the
    /// estimated impact X coordinate to the first mid-air observation.
    private func fitLateral(
        _ parameters: inout ModelParameters,
        samples: [(x: Double, y: Double, time: Double)]
    ) -> Bool {
        var normal = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        var target = Array(repeating: 0.0, count: 3)
        for sample in samples {
            let world = worldState(parameters, at: sample.time)
            let u = parameters.launchDistance / max(parameters.launchDistance * 0.25, world.distance)
            let coefficients = [1 - u, u, sample.time * u]
            for row in 0..<3 {
                target[row] += coefficients[row] * sample.x
                for column in 0..<3 {
                    normal[row][column] += coefficients[row] * coefficients[column]
                }
            }
        }
        guard let solution = solve3x3(normal, target: target),
              solution.allSatisfy(\.isFinite),
              (-1.5...2.5).contains(solution[0]),
              (-0.5...1.5).contains(solution[1]) else { return false }
        parameters.vanishingX = solution[0]
        parameters.launchX = solution[1]
        parameters.lateralRate = solution[2]
        return true
    }

    private func fitError(
        _ parameters: ModelParameters,
        samples: [(x: Double, y: Double, time: Double)]
    ) -> Double {
        var total = 0.0
        for sample in samples {
            let projected = project(parameters, at: sample.time)
            let dx = projected.x - sample.x
            let dy = projected.y - sample.y
            total += (dy * dy) + (0.5 * dx * dx)
        }
        return sqrt(total / Double(samples.count))
    }

    private func solve3x3(_ matrix: [[Double]], target: [Double]) -> [Double]? {
        guard matrix.count == 3,
              matrix.allSatisfy({ $0.count == 3 }),
              target.count == 3 else { return nil }
        var augmented = (0..<3).map { matrix[$0] + [target[$0]] }
        for column in 0..<3 {
            guard let pivotRow = (column..<3).max(by: {
                abs(augmented[$0][column]) < abs(augmented[$1][column])
            }), abs(augmented[pivotRow][column]) > 1e-10 else { return nil }
            if pivotRow != column { augmented.swapAt(pivotRow, column) }
            let pivot = augmented[column][column]
            for index in column..<4 { augmented[column][index] /= pivot }
            for row in 0..<3 where row != column {
                let factor = augmented[row][column]
                for index in column..<4 {
                    augmented[row][index] -= factor * augmented[column][index]
                }
            }
        }
        return augmented.map { $0[3] }
    }

    private static func usableTimestamps(
        _ timestamps: [TimeInterval],
        matching count: Int
    ) -> [TimeInterval] {
        guard timestamps.count == count,
              timestamps.allSatisfy(\.isFinite),
              zip(timestamps, timestamps.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            return []
        }
        return timestamps
    }

    private static func isSafeEstimatedPoint(_ point: NormalizedPoint) -> Bool {
        (0.035...0.965).contains(point.x) && (0.035...0.965).contains(point.y)
    }
}
