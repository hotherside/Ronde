# Ronde product contract

**Status:** current working contract

**Reviewed:** 19 July 2026

## Product

Ronde is an Apple Watch golf shot counter for golfers who want to keep an honest score without repeatedly handling a phone or navigating a complex golf application.

The essential loop is:

1. Start a quick 9, quick 18 or known course round.
2. Confirm hole count and par.
3. Start a golf workout when permission allows.
4. Log one shot with the on-screen control or configured Action Button action.
5. Undo mistakes and move between holes without losing state.
6. Finish and review shots, par delta, walking distance and duration.
7. Keep the completed round locally.

## Experience rules

- The current hole, shots and score must be legible at a glance outdoors.
- Core counting works offline and without HealthKit, location or motion permission.
- Permission denial is a degraded capability, not a blocked round.
- An incomplete active round returns after relaunch when persistence is available.
- Destructive actions such as discarding a round require deliberate confirmation.
- Haptics support actions but never replace visible state.
- Ronde does not claim automatic swing detection, GPS yardage, handicap calculation or social competition unless those behaviours are implemented and verified.

## Platform boundary

- The watchOS application is the current product.
- The iOS target is a minimal packaging companion, not a promised phone experience.
- SwiftData owns local round history.
- HealthKit owns the optional golf workout session.
- Core Location and the bundled Sydney course library support nearby-course selection.
- App Intents supplies the Action Button-compatible shot action, but real hardware configuration and invocation require manual verification.

## Release gate

Release confidence requires more than compilation:

- clean watchOS build;
- simulator state review;
- real Apple Watch Ultra Action Button validation;
- permission-denied behaviour;
- round persistence and recovery after termination;
- workout start, recovery and end behaviour;
- accessibility and small-screen review;
- confirmation of signing, archive and App Store state.
