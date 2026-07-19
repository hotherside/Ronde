#!/usr/bin/env bash
set -euo pipefail

RONDE_ROOT="$(git rev-parse --show-toplevel)"
RONDE_BASE_COMMIT="${1:-}"
cd "$RONDE_ROOT"

RONDE_REQUIRED=(
  AGENTS.md CLAUDE.md GEMINI.md PROJECT.md README.md
  .github/copilot-instructions.md
  docs/product-contract.md docs/context/README.md docs/context/CURRENT_STATE.md
  docs/context/ARCHITECTURE.md docs/context/ROADMAP.md docs/context/OPERATIONS.md
  docs/context/CHANGELOG.md docs/context/DOCUMENTATION_CONTRACT.md
  docs/context/NOTION_MIRROR.md docs/context/history/TIMELINE.md
  docs/context/history/commit-ledger.md docs/context/generated/repository-inventory.md
)

for required in "${RONDE_REQUIRED[@]}"; do
  [[ -f "$required" ]] || { printf 'Missing required context file: %s\n' "$required" >&2; exit 1; }
done

[[ -x scripts/update-context-library.sh ]] || { printf 'Update script must be executable.\n' >&2; exit 1; }
bash -n scripts/update-context-library.sh
bash -n scripts/check-context-library.sh

if rg -n --hidden -g '!.git/**' -g '!docs/context/history/commit-ledger.md' \
  'sk-ant-|sk-proj-|gh[opusr]_[A-Za-z0-9_]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
  AGENTS.md CLAUDE.md GEMINI.md PROJECT.md README.md docs .github; then
  printf 'Potential secret found in project documentation.\n' >&2
  exit 1
fi

if [[ -n "$RONDE_BASE_COMMIT" ]]; then
  RONDE_CHANGED="$(git diff --name-only "$RONDE_BASE_COMMIT"...HEAD)"
  RONDE_MATERIAL="$(printf '%s\n' "$RONDE_CHANGED" | rg '^(Ronde Watch App/|Ronde iOS App/|Ronde\.xcodeproj/|project\.yml$)' || true)"
  RONDE_CONTEXT="$(printf '%s\n' "$RONDE_CHANGED" | rg '^(docs/context/(CHANGELOG\.md|CURRENT_STATE\.md|ROADMAP\.md|ARCHITECTURE\.md|OPERATIONS\.md|decisions/)|docs/product-contract\.md$)' || true)"
  if [[ -n "$RONDE_MATERIAL" && -z "$RONDE_CONTEXT" ]]; then
    printf 'Material Ronde changes require a context update.\n%s\n' "$RONDE_MATERIAL" >&2
    exit 1
  fi
fi

printf 'Ronde context library checks passed.\n'
