# 0011: Library and shot studio with observed-only automatic media

**Status:** Accepted

**Date:** 7 September 2026

## Context

The owner rejected the fragmented typography and navigation and requested a substantial Linear/Notion-inspired golf media workspace: review shots, cut clips and share them. The preceding audit also reproduced committed-track replacement, source-cadence acquisition holes, unrecoverable tracking loss, pause/restart behaviour, import navigation failure and destructive archive recovery. Passing synthetic tests had not translated into accepted real-video tracking.

## Decision

- Replace Home, Library and Profile with one searchable media library. Put account and storage in Settings. Use neutral surfaces, large media and semantic body/subheadline text; remove decorative metrics, duplicate evidence cards and tiny overlines.
- Give each shot one studio for playback, source-frame navigation, trimming, trace selection and sharing. Persist reversible trim bounds, output aspect and overlay choice separately from source media and analysis.
- Export original-aspect, vertical, square or landscape H.264 MP4 with source audio when available. Fit the whole video into the selected canvas. Preview, annotation and output use the same source-to-canvas transform and source timestamps.
- Present only accepted detector observations in the automatic studio line. Stop at the last supported observation. Remove model carry, predicted landing and extrapolated full-flight geometry from the active studio. Keep manual annotation explicitly labelled and removable.
- Preserve a committed ball-track lineage through final validation. Retain decoder cadence phase and schedule acquisition by elapsed source time. Reacquisition requires a uniquely prediction-matched three-point tracklet; low-speed apex turns need motion and prediction support. These are deterministic repairs, not an accuracy acceptance claim.
- Treat corrupt/unreadable archives as a blocked write state. Preserve bytes, show the failure and allow retry. Surface failed saves, retain unsaved state and prevent destructive navigation through sign-out. Commit metadata deletion before removing owned media.
- Capture import ownership before the Photos/Files picker begins. Check account generation throughout transfer and analysis; return a typed result and navigate only to that import's prepared session. Interrupted analysis is recoverable.

## Supersedes

The primary Home/Library/Profile navigation of ADR 0009, the hidden-navigation/glass overlay presentation of ADR 0010, and the active estimated full-flight/carry presentation of ADRs 0007 and 0008 are superseded. Their local-only privacy, original-source preservation, immutable observed evidence and manual draft semantics remain in force. Older analysis/export components remain for compatibility and experiments, but do not define the active studio.

## Trade-offs and limits

Fitting landscape footage into a vertical canvas creates letterboxing. It preserves the golfer and ball; user-controlled crop/reframing can follow with an explicit crop preview. Observed-only lines can be short or absent. This is preferable to a visually convincing unsupported flight. The tennis-domain model is unchanged, so a labelled golf validation set and licence-checked training route are still required before declaring accurate tracking. Offline authentication, remote deletion reconciliation and signed-device performance remain separate follow-up work. The independent Watch counter is unchanged.
