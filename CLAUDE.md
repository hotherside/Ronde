# HoleCount

Golf shot counter for Apple Watch. Tap the Action Button to count shots per hole,
see score vs par in real-time, review rounds after completion.

## Tech Stack
- watchOS 10+ / SwiftUI / SwiftData
- `WKRunsIndependentlyOfCompanionApp = YES` (standalone watch, future iPhone companion)
- Bundle ID: com.ronde.HoleCount
- Action Button: App Intents framework (StartWorkoutIntent + AppShortcutsProvider)
- HealthKit: HKWorkoutActivityType.golf (keeps app alive during round)
- Course data: GolfCourseAPI.com (free tier, 300 req/day) — stubbed with mock data initially

## Architecture
- Offline-first: entire round works without connectivity
- SwiftData for local persistence (rounds, hole scores, cached courses)
- GPS + API for course auto-detect (happy path), manual setup as fallback
- Workout session keeps app foregrounded for 4-5 hour rounds

## Key Paths
- Models: HoleCount Watch App/Models/ (Round.swift, HoleScore.swift, CourseData.swift)
- Views: HoleCount Watch App/Views/ (SetupFlow/, InRound/, Summary/)
- Services: HoleCount Watch App/Services/ (LocationService, CourseAPIService)
- Intents: HoleCount Watch App/Intents/ (ShotCountIntent — Action Button)

## Data Model
- Round: id, date, courseName?, numberOfHoles, totalPar, isComplete, currentHoleIndex
  - @Relationship(deleteRule: .cascade) holeScores: [HoleScore]
- HoleScore: id, holeNumber, par (3-5), shots, isComplete — belongs to Round
- CourseData: id, name, address, lat, lng, holes[] — Codable, cached in SwiftData

## Conventions
- Swift 6 concurrency (async/await, @MainActor for UI)
- SwiftUI views: small, composable, preview-friendly
- Haptics: distinct patterns for shot logged / undo / hole complete
- No force unwraps. No print() in production — use os.Logger

## UX Flow
1. App opens → GPS detects course (or manual setup fallback)
2. Choose 9/18 holes → par per hole auto-filled or manual +/- adjust (default par 4)
3. Review & start round
4. In-round: Action Button = +1 shot, screen [-1] = undo, swipe = finish hole
5. Hole transition card → auto-advance to next hole
6. End of round → summary with total shots vs par + per-hole breakdown → save

## Phase Roadmap
1. MVP Watch App: manual setup + shot counter + Action Button + round summary + history
2. Course Auto-Detect: GPS + API + caching
3. iPhone Companion: history, stats, iCloud sync
4. Social/Multiplayer: events, live leaderboard, post-round review
5. Platform: crowdsourced courses, handicap, GPS distances

## Session Plan
Detailed implementation plan: .claude/plans/mellow-knitting-owl.md
