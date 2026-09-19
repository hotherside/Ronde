# 0018: Choose clips first, then trace the ball

**Status:** accepted; local implementation and validation in progress

**Date:** 19 September 2026

## Context

The owner reported a signed-iPhone stall at 10% in ball-point tracking followed by an app crash. They also clarified the intended flow: an already cut video should not require a bookmark; longer recordings need a predictable bookmark window, followed by individual clips with one tracing action and straightforward correction. The broader visual redesign remains separate.

## Decision

- An imported recording shorter than 20 seconds opens directly in Shot Studio without bookmarking or waiting for analysis. Exactly 20 seconds and longer sources retain the recording selection flow, up to the existing 20-minute import limit. Originals and session ownership remain intact.
- Name the long-recording step **Choose shots**. Save the default before/after window per session, with ±5 and ±10 second presets and individual side adjustments. New bookmarks inherit it; existing bookmarks retain their own windows. Create source-linked clips before opening Shot Studio. Repeated creation preserves existing edits.
- Offer one primary **Trace shot** action for a selected clip of up to 20 seconds. Restrict impact discovery to the selected source interval, consider at most two timing candidates, and start EdgeTAM only from an accepted ball observation. Prefer an interior source-timed observation after initial launch blur. Never invent a centre point when acquisition fails.
- Keep **Correct trace** secondary: select the ball on a clearer source frame and retrack, or draw/adjust a manual path. Preview and export use the same saved geometry. A visibility switch replaces the list of model/overlay choices and remembers the selected trace.
- Persist detected versus person-selected seed provenance. Model output retains exact source timestamps, frame indices and gaps; drawn geometry remains labelled **Manual trace**, including exports. Manual correction does not upload footage or train a model in the background.
- Keep Close available during tracking and explain preparation/finding/tracking stages rather than showing a fixed 10% before the first model inference completes. Release the source RGB cache before inference, check cancellation around model loads/predictions, and use CPU/Neural Engine on physical iOS to avoid GPU-backed allocation pressure. One Core ML prediction is not cooperatively interruptible midway through execution.

## Evidence and limits

The reported 10% state localises to the first inference after resource/model loading. Subsequent device-log retrieval found no matching main-app crash or jetsam report. Older diagnostic-app SIGTRAP reports identify a separate missing scene-lifecycle configuration, now corrected in the diagnostic harnesses. Memory pressure remains a hypothesis for the reported main-app failure.

The supplied-seed app-service test subsequently passed on the physical iPhone 18 Pro/iOS 27 in 73.104 seconds, covering both private clips, short MP4 export/decode and archive round-trip. Tracking took 33.979 seconds for daylight and 38.032 seconds for night; thermal state changed from nominal to fair during night. Offline scoring against provisional agent-reviewed references gives 101/113 and 102/103 positions within 12 source pixels. This confirms this bounded repeat completed without the reported crash; it does not identify the original termination cause or establish repeated-run reliability.

The earlier supplied-point development scores do not validate the new automatic seed acquisition or physical iPhone compute configuration. Preserve those results as assisted Mac evidence and measure the new path separately. See [Current State](../CURRENT_STATE.md) for subsequent validation and delivery.

This supersedes the mandatory point-selection entry flow and ten-second UI limit in [ADR 0017](0017-opt-in-on-device-ball-tracking.md), and refines the bookmark defaults/navigation in [ADR 0014](0014-native-recording-studio-and-source-linked-shots.md). Their source-preservation, privacy and evidence boundaries remain in force.
