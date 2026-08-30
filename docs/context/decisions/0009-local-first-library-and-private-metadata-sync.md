# ADR 0009: Local-first reviewer library and private metadata sync

**Status:** accepted

**Date:** 30 August 2026

## Context

The one-video reviewer could analyse and export a shot, but a relaunch discarded the review session and there was no coherent app-level Home, Library or Profile experience. The redesign also needs one account boundary without turning private golf footage into a cloud-media product.

The Watch counter must remain independently usable offline. Automatic tracer evidence must continue to fail closed, and remote storage must not blur the difference between app metadata and raw media.

## Decision

- The iPhone/iPad reviewer requires Sign in with Apple and exposes no other sign-in method.
- The primary shell is Home, Library and Profile with system Liquid Glass navigation on iOS 26 and a material fallback on earlier supported iOS versions.
- Review sessions, app-owned source URLs, tracer geometry and edits are persisted in an account-scoped local archive protected with complete file protection. Signing out removes that account's library from the active UI without deleting its local archive.
- Raw video, local file paths, decoded frames, tracer analysis and exports remain on device.
- Supabase stores only the private profile and lightweight `library_items` metadata needed for account continuity and future reconciliation. Row-level security limits every read and mutation to `auth.uid()`, and anonymous table privileges are revoked.
- Home metrics and charts are derived from the local archive. Empty production libraries show honest zero or unavailable states.
- Each media detail retains the video-first review workspace and adds favourite, place/course, club, note, impact-time adjustment, evidence summary and deletion. Deletion removes the app-owned local media and the matching remote metadata; it does not delete the original Photos or Files item.
- Import remains a labelled toolbar or empty-state action. Ronde does not use a floating plus button.
- The hosted Apple provider must allow native client ID `com.ronde`, and the Apple Developer App ID must carry the matching capability. Source configuration and a Simulator build do not prove live native sign-in.

## Alternatives considered

- Store all media in Supabase Storage. Rejected because it expands privacy, cost, upload reliability and deletion obligations without being needed for the review loop.
- Keep one device-wide archive without accounts. Rejected because changing Apple accounts on a shared device could expose or sync another person's reviews.
- Use multiple identity providers. Rejected for this Apple-only product surface and the additional account-linking complexity.
- Use cloud metadata as the authoritative library. Rejected for the MVP because the reviewer must remain responsive and useful without network access after authentication.

## Consequences

- A signed-in golfer gets a durable, private local library and real dashboard metrics without uploading footage.
- A second Apple account on the same device cannot see the first account's archive.
- Metadata sync can pause without blocking local review. The current app uploads metadata but does not yet rebuild a missing device library from remote rows.
- The Supabase provider is configured for `com.ronde`; Apple Developer capability, signed-device login, session restoration, row-level-security behaviour and deletion reconciliation remain explicit validation gates.
- Any future remote media backup or cross-device restoration requires a new privacy, product and operational decision.
