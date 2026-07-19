# Current State

**Reviewed:** 19 July 2026

**Committed baseline:** `5d30cad` on `main`, aligned with `origin/main`

**Working-tree status:** active uncommitted app hardening across watchOS source, shared schemes, Xcode project and `project.yml`

## Stage

Ronde is in local product hardening and device-readiness validation. The committed repository contains the core watch golf round flow. The active checkout adds a substantial uncommitted reliability and visual pass and must not be described as published on GitHub until it is reviewed and committed separately.

## Capability status

| Capability | Status | Current truth |
| --- | --- | --- |
| watchOS product | Implemented | Standalone watchOS 10+ SwiftUI app; iOS target remains a minimal companion. |
| Round setup | Implemented | Quick 9, Quick 18, manual par and bundled Sydney course selection exist. |
| Shot counting | Implemented | Add, undo and hole transitions exist; Action Button uses App Intents. |
| Local history | Implemented, hardening active | SwiftData stores rounds and hole scores. The local pass adds recovery and degraded storage modes. |
| Workout session | Implemented, hardening active | HealthKit golf workout supports long-running rounds; local work adds recovery and safer ending. |
| Location and walking | Implemented foundation | Nearby-course detection and pedometer support exist; permission and real-device behaviour need validation. |
| Preview routing | Local only | `RONDE_PREVIEW_SCREEN` support exists in the uncommitted working tree. |
| Automated tests | Missing | No test target or test source is present. |
| Simulator build | Verified 19 July 2026 | Both `Ronde Watch App` and `Ronde iOS` shared schemes build for generic simulators. |
| Hardware validation | Unverified | Action Button, HealthKit recovery and outdoor legibility need a real Apple Watch pass. |
| App Store state | Unverified | Do not infer archive, TestFlight or App Store availability from the repository. |

## Current risks

- A large uncommitted implementation pass is not recoverable from GitHub.
- No automated test target protects scoring, persistence or workout state transitions.
- Simulator success cannot prove Action Button or HealthKit behaviour on hardware.
- Location, HealthKit and motion data increase privacy and permission-copy obligations.
- Xcode project changes and `project.yml` must remain synchronised.

## Immediate gate

1. Review and commit the active implementation pass separately from this documentation work.
2. Generate or reconcile the Xcode project from `project.yml` and confirm the diff is intentional.
3. Build both shared schemes.
4. Validate the complete round on a supported watch simulator.
5. Validate Action Button, workout recovery, permission denial and persistence on real hardware.
6. Add unit coverage for score, round lifecycle and recovery-sensitive state.

## Validation completed on 19 July 2026

- XcodeGen is installed and `project.yml` is available as the project definition.
- Xcode lists the expected `Ronde Watch App` and `Ronde iOS` targets and schemes.
- The watch scheme built successfully for both a specific Apple Watch Ultra 3 simulator and the generic watchOS Simulator destination.
- The iOS companion scheme built successfully for the generic iOS Simulator destination.
- No automated test target exists, so no test pass is claimed.
