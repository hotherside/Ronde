# 0013: Clubhouse and a bookmarked recording Studio

**Status:** Accepted product/design intent; HTML refinement and native implementation remain separate gates

**Date:** 19 September 2026

## Context and source

After reviewing the three [shot-media HTML concepts](../../design/2026-09-19-shot-media/README.md), the owner said Clubhouse's overall concept was sound and requested much more refinement. They clarified that Studio should bookmark points in a 10–20-minute recording and produce a list of smaller shots with quick before/after range adjustment. This decision was initially recorded during local exploration against `main` at `d9b405c`; native implementation had not started at that checkpoint. [ADR 0014](0014-native-recording-studio-and-source-linked-shots.md) records the subsequent native execution and source delivery.

## Decision

Use Clubhouse as the design foundation, retaining its warm photographic collection while refining the complete recording-to-shots workflow. Recording Studio must preserve access to the full source, support manual time bookmarks and create batches of source-linked Shots. Keep the original intact and provide a connected individual-shot editor. A bookmark marks a point in the source; favouriting a Shot makes it a keeper. The golfer chooses what is worth keeping, and manual clipping must work without automatic suggestions or a successful ball trace.

The detailed local model and extraction rules remain proposals. For this HTML refinement, use five seconds before and after a bookmark, adjustable per bookmark and clamped to the source. Propose a stable bookmark-to-shot relationship so repeating extraction skips bookmarks that already have a shot, preserving existing edits and avoiding duplicates. The owner requested quick five-second adjustments but did not separately approve these exact defaults, overlap handling or conflicts with existing shot edits.

## Alternatives and consequences

Cutroom and Fieldwork remain comparison explorations rather than the chosen foundation. An automatic-detection-first workflow would make useful clipping depend on an unresolved perception pipeline; optional moment suggestions can follow the manual workflow. Automatic shot acceptance and observed ball traces retain their existing evidence gates.

This changes the intended future short-video/single-shot surface described in ADRs 0008 and 0011, while retaining their source-preservation and honest-trace boundaries. The current native importer still accepts one video up to 60 seconds. Long-source import, bookmarks, batch creation, archive migration and device performance are not delivered by the HTML work. Next: review the refined flow and proposed edge cases, then agree and validate the first native slice.
