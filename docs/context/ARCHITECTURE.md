# Architecture

## Runtime shape

```text
RondeApp
  -> SwiftData ModelContainer
  -> ContentView
      -> setup flow
      -> active ShotCounterView
      -> RoundSummaryView and history

Round lifecycle
  -> SwiftData Round + HoleScore
  -> optional HealthKit golf workout
  -> optional pedometer and location context
  -> App Intents shot action
```

## Boundaries

- `Ronde Watch App/RondeApp.swift`: application entry, persistence container and debug preview routing.
- `ContentView.swift`: selects home, active round or summary from persisted state.
- `Models/`: SwiftData round and hole state plus course data structures.
- `Views/SetupFlow/`: course, hole, par and ready flow.
- `Views/InRound/`: scoring and hole-transition surfaces.
- `Views/Summary/`: completed-round review.
- `Services/WorkoutManager.swift`: HealthKit workout lifecycle and recovery.
- `Services/LocationService.swift`: permission and nearby-course location.
- `Services/PedometerService.swift`: walking metrics.
- `Services/CourseLibrary.swift` and `Resources/SydneyCourses.json`: bundled course data.
- `Intents/ShotCountIntent.swift`: Action Button-compatible App Intents.
- `project.yml`: XcodeGen definition for targets, settings, entitlements and schemes.

## Data and privacy

Round history is local SwiftData. HealthKit, location and motion access are optional capability inputs. Do not add analytics, remote round storage or background location without an explicit product, privacy and operational decision.
