# Ronde repository instructions

These instructions apply to the entire Ronde repository and are the starting point for repository-aware tools.

## Start every task here

1. Read [PROJECT.md](PROJECT.md).
2. Read [docs/product-contract.md](docs/product-contract.md).
3. Read [docs/context/README.md](docs/context/README.md) and [docs/context/CURRENT_STATE.md](docs/context/CURRENT_STATE.md).
4. Read the relevant architecture, roadmap, operations, decision and history pages linked from the context library.
5. Inspect the live Swift, `project.yml`, Xcode project and current working tree before changing claims or code.
6. Run `git status --short --branch`. Preserve any active work that appeared after the current release candidate; never stage or overwrite unrelated changes without explicit scope.

## Source-of-truth boundaries

- Product intent: `docs/product-contract.md`.
- Current implementation: Swift source, entitlements, `project.yml` and the Xcode project.
- Current delivery status: `docs/context/CURRENT_STATE.md` and `docs/context/ROADMAP.md`.
- Architecture and commands: `docs/context/ARCHITECTURE.md` and `docs/context/OPERATIONS.md`.
- Major rationale: `docs/context/decisions/`.
- Exact committed history: Git. The generated ledger is an index only.
- Notion: a lightweight high-level mirror, downstream of the repository.

If product intent and implementation disagree, report both. Do not silently describe unfinished local work as shipped or available on GitHub.

## Product invariants

- Ronde is an offline-first Apple Watch golf shot counter with a local-only universal iPhone/iPad Shot Reviewer.
- The Apple Watch app remains the independent core product; the iOS target is now an active reviewer product surface as well as the required packaging companion.
- A golfer must be able to start, count, undo, change holes and finish a round without connectivity.
- Action Button, HealthKit, location and motion permissions must degrade honestly when unavailable or denied.
- Never infer App Store publication, hardware behaviour or persistence reliability from a successful build.
- Reviewer uploads accept any source FPS and use source timestamps. Estimated geometry must never be presented as observed ball flight or numerical distance.

## Repository map

- `Ronde Watch App/`: watchOS application, views, models, services, intents and resources.
- `Ronde iOS App/`: universal iPhone/iPad Shot Reviewer and packaging companion target.
- `project.yml`: XcodeGen source configuration.
- `Ronde.xcodeproj/`: generated Xcode project and shared schemes.
- `docs/context/`: cross-tool context library.

## Documentation maintenance

For every material product, behaviour, architecture, persistence, permission, release or user-visible change:

1. Update `docs/context/CHANGELOG.md`.
2. Update the affected current-state, roadmap, architecture or operations page.
3. Add or supersede a decision record for durable choices.
4. Run `./scripts/update-context-library.sh`.
5. Run `./scripts/check-context-library.sh`.
6. Update the mapped Notion page when the change matters at product or stage level.

Never store credentials, signing secrets, private location traces, HealthKit data or real round data in documentation, logs, fixtures, screenshots, Notion or agent memory.
