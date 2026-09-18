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

- Ronde is a local-first universal iPhone/iPad media library for golf-shot videos, evidence-backed shot tracing and non-destructive editing/export.
- Ronde has no watchOS product, Watch target, round counter, Action Button workflow or HealthKit workout boundary.
- Imported source video, edits and tracer geometry stay on-device unless a later explicit product and privacy decision changes that boundary.
- Never infer App Store publication, physical-device behaviour, tracer accuracy or persistence reliability from a successful build.
- Reviewer uploads accept any source FPS and use source timestamps. Estimated geometry must never be presented as observed ball flight or numerical distance.

## Repository map

- `Ronde iOS App/`: universal iPhone/iPad media library, Shot Studio, tracer, capture foundations and account boundary.
- `project.yml`: XcodeGen source configuration.
- `Ronde.xcodeproj/`: generated Xcode project and shared schemes.
- `docs/context/`: cross-tool context library.

## Portable session handoff

Use repository-relative sources at the selected branch/commit in local and cloud sessions. At completion, follow [the documentation contract](docs/context/DOCUMENTATION_CONTRACT.md#session-completion-across-tools) to record accepted decisions, evidence and the next gate in the task branch; committed `main` is the shared baseline. Never assume local uncommitted work or memory reaches cloud or ChatGPT/Work.

## Documentation maintenance

For every material product, behaviour, architecture, persistence, permission, release or user-visible change:

1. Update `docs/context/CHANGELOG.md`.
2. Update the affected current-state, roadmap, architecture or operations page.
3. Add or supersede a decision record for durable choices.
4. Run `./scripts/update-context-library.sh`.
5. Run `./scripts/check-context-library.sh`.
6. Update the mapped Notion page when the change matters at product or stage level.

Never store credentials, signing secrets, private shot media or account data in documentation, logs, fixtures, screenshots, Notion or agent memory.
