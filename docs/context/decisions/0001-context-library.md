# 0001: Repository-owned context library

**Status:** accepted

**Date:** 19 July 2026

## Context

Ronde relied on one Claude summary, source inspection and chat history. That did not reliably distinguish committed code from the large active working-tree pass or provide other tools with an executable handoff.

## Decision

Keep canonical context in the repository under `docs/context/`, with root adapters, generated Git indexes, pull-request checks and a lightweight Notion mirror.

## Consequences

- Git remains exact history.
- Product intent and current delivery state have explicit homes.
- Uncommitted work is labelled rather than treated as shared history.
- Maintainers must update curated context for material changes.
