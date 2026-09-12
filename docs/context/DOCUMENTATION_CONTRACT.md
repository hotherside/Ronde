# Documentation Contract

## Goal

An authorised person or tool can understand Ronde, distinguish committed and local work, run the correct checks and continue without a previous conversation.

## Automatic facts

- Repository inventory from the working tree.
- Readable Git ledger from committed history.
- Required context structure and secret-pattern checks.
- Pull-request enforcement for material implementation changes.

## Judgement updates

Automation cannot decide product intent, hardware reliability, privacy acceptability or release readiness. Material changes require updates to the changelog and any affected state, roadmap, architecture, operations or decision page.

## Handoff requirements

State what changed, why, what was verified, what remains uncertain, whether the work is committed and which context and Notion pages were updated.

## Session completion across tools

For a session that changes accepted direction, implementation or verified state:

1. Update the existing affected context pages in the task branch, alongside the work. Keep `PROJECT.md` compact; avoid a duplicate session narrative when the changelog, current state or decision record already captures it.
2. Record the date, source repository, branch and commit, resulting branch/PR, accepted decisions, unresolved proposals, evidence actually checked and the next gate. Identify uncommitted or unpushed work explicitly. A suggestion is not an accepted product decision.
3. Separate source and Simulator checks from representative footage, signed-device, Watch hardware, hosted metadata and Apple distribution evidence.
4. Treat committed `main` as the canonical shared baseline. A task branch can be reviewed by its explicit ref; verify the merged commit before presenting its changes as part of the shared baseline. Preserve unrelated checkout changes.
5. Use repository-relative source paths in local and cloud work, with GitHub commit links when a fixed snapshot matters. Read the selected checkout/ref directly; machine-specific paths, uncommitted files and local memories are not portable context.
6. Supply ChatGPT/Work with `PROJECT.md` and only the relevant current-state, contract or decision pages through explicitly verified source access or upload. Record the source revision and whether access succeeded. Treat uploads as revision snapshots; do not assume changes in local, cloud or ChatGPT files or memories synchronise. Bring accepted discussion outcomes back into the task branch and review/merge them through the normal repository workflow.

Read-only exploration needs a concise outcome in the task, not a new repository document. Record a durable change only when the session actually establishes one.
