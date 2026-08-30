# Ronde iOS redesign: proposed product and data direction

**Status:** selected direction; implementation authority moved to ADR 0009 and the product contract
**Prepared:** 30 August 2026

## Recommendation

Use **Caddie** as the shell, bring selected **Flightline** evidence details into the review screen, and use **Range Journal** as the places layer inside Home and Profile.

The durable information architecture should be:

1. **Home**: latest review, recent carousel, honest usage summary and quickest path back into unfinished work.
2. **Library**: all imported reviews and range sessions, with filters for traced, untracked and saved items.
3. **Profile**: identity, usage, optional places, privacy, local storage and sync controls.
4. **New review**: a labelled import/record action in the navigation toolbar rather than a fourth destination or a floating `+` control.

`Tracer` should not be a tab name. A tracer is a tool and one possible result. The library must still hold reviews where ball flight was not tracked.

## Individual media interaction

Opening a library item should push directly into a video-first review:

1. Playback uses source presentation time and keeps the media visually dominant.
2. A compact provenance label distinguishes the solid observed segment from the dashed estimated continuation.
3. `Trim`, `Edit trace` and `Details` live in a bottom control sheet rather than permanently covering the video.
4. Trim remains non-destructive and defaults to impact minus five seconds through impact plus five seconds.
5. Editing the displayed path creates a separately labelled `Manual trace`. Automatic observed points remain immutable evidence.
6. Export uses the saved reviewed geometry and does not rerun detection.

On iOS 26, the transient top controls and compact playback controls may use interactive system Liquid Glass. The video, evidence surfaces and editor sheet remain visually stable and content-first.

## Metric policy

Safe v1 summaries include:

- reviews created;
- reviews with an evidence-backed trace;
- saved/favourited reviews;
- sessions;
- optional places visited;
- local storage used;
- items needing review.

Do not present maximum distance, average distance, apex height or club-performance comparisons until Ronde has a calibrated setup and known-ground-truth validation. The current uncalibrated camera fit may support a deliberately broad experiment inside a review, but it is not yet a defensible dashboard record.

## Apple authentication

Use native Sign in with Apple as the only account provider. The native flow should:

1. create and hash a fresh nonce;
2. request the Apple credential with `ASAuthorizationAppleIDProvider`;
3. exchange the Apple identity token and raw nonce with Supabase Auth;
4. capture the person's name from the native credential on the first authorisation only;
5. restore the Supabase session on subsequent launches;
6. keep signed-in local review available when the network later disappears;
7. support sign-out, account deletion and Apple credential revocation as release gates.

### Resolved account boundary

Sign in with Apple is the only iPhone/iPad account method. A new install requires authentication; after an account activates its local archive, metadata-sync failure does not block local review. The independent Watch counter never depends on this account or network path.

## Storage boundary

### On-device authority

Keep these in an account-scoped local persistent store and local file storage:

- source videos and generated clips;
- thumbnails and playback proxies;
- exact observed, estimated and manual tracer geometry;
- analysis progress, diagnostic evidence and processing cost;
- clip windows, exports and temporary capture buffers;
- the complete working session needed to resume offline;
- precise capture coordinates, if the product ever collects them.

### Supabase authority

Use the supplied Ronde project initially for:

- Supabase Auth with Apple identity;
- private profile and app preferences;
- lightweight library metadata for cross-device continuity;
- favourites;
- optional user-authored place names;
- sync tombstones and device cursors;
- account-deletion orchestration.

Do not create a Storage bucket for raw reviewer video in this phase. Cloud media backup should be a later, separately consented product with an explicit storage, privacy, retention and cost decision.

## Initial proposed Supabase model

This section is retained as concept history. The implemented schema is the narrower pair of migrations in `supabase/migrations/`; `places`, device cursors, pull reconciliation and tombstones were deliberately not added in this execution.

All client-visible tables should have Row Level Security enabled. Every policy should constrain ownership with `auth.uid() = user_id`; the authenticated role alone is not authorisation.

### `profiles`

- `id uuid primary key references auth.users(id) on delete cascade`
- `display_name text null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Profiles are private in v1. Do not build a public golfer directory by accident.

### `library_items`

- `id uuid primary key` generated on the client
- `user_id uuid not null references auth.users(id) on delete cascade`
- `kind text not null` constrained to one-shot or range-session values
- `title text null`
- `captured_at timestamptz null`
- `duration_ms integer null`
- `review_state text not null`
- `tracer_provenance text null`
- `observed_point_count integer null`
- `is_favourite boolean not null default false`
- `place_id uuid null`
- `client_updated_at timestamptz not null`
- `deleted_at timestamptz null`

The ID points to a local record. It is not a public Photos identifier, filename or content hash.

### `places`

- `id uuid primary key` generated on the client
- `user_id uuid not null references auth.users(id) on delete cascade`
- `name text not null`
- `suburb text null`
- `source text not null default 'manual'`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`
- `deleted_at timestamptz null`

Do not add latitude/longitude to the initial sync schema. A human-readable place label is enough for the proposed experience.

### `sync_devices`

- `id uuid primary key` generated by the app installation
- `user_id uuid not null references auth.users(id) on delete cascade`
- `last_pull_at timestamptz null`
- `last_push_at timestamptz null`
- `app_version text null`
- `updated_at timestamptz not null`

Do not store advertising identifiers, hardware serial numbers or raw device names.

## Local-first sync shape

1. Write every review action locally first.
2. Add metadata mutations to an on-device outbox.
3. Push when authenticated and reachable.
4. Pull changes newer than the device cursor.
5. Resolve ordinary conflicts with the newest client mutation while retaining explicit deletion tombstones.
6. Never delete the local source video because a cloud metadata row disappeared.
7. Surface sync status in Profile, not as a blocking banner across the reviewer.

## Phased implementation

### Phase 1: approved shell

- Build the Caddie navigation and design system in SwiftUI.
- Add native Liquid Glass to structural interactive chrome on iOS 26, with a material fallback.
- Add the persistent local library and favourites.
- Keep existing import, evidence gate, manual rescue and export behaviour intact.
- Do not add Supabase yet beyond configuration scaffolding.

### Phase 2: identity and private metadata

- Configure Apple in the Apple Developer portal and Supabase Auth.
- Add the Supabase Swift package with a pinned version.
- Implement nonce-safe native Sign in with Apple and session restoration.
- Create reviewed migrations with RLS, ownership tests and account deletion.
- Sync profile, favourites, optional place labels and library summaries.

### Phase 3: richer product surfaces

- Add the places layer from Range Journal.
- Add evidence-level details from Flightline inside review and diagnostics.
- Validate on iPhone and iPad, including Dynamic Type, VoiceOver, Reduce Transparency and Reduce Motion.
- Revisit distance only after calibration and ground-truth validation.

## Current hosted evidence

Execution changed the supplied Supabase project `apaowuzliauwxbxylfpk` on 30 August 2026:

- project name `Ronde`;
- region `ap-southeast-2`;
- status `ACTIVE_HEALTHY`;
- Postgres 17;
- private `profiles` and `library_items` tables with row-level security;
- two applied migrations mirrored in `supabase/migrations/`;
- no Edge Functions;
- anonymous grants revoked;
- authenticated GraphQL visibility remains intentionally enabled so signed-in clients can use the tables, with row access constrained by ownership policies.

The Apple provider is enabled for native client ID `com.ronde` with no OAuth secret. Enabling the Apple Developer App ID capability and completing signed-device login remain external gates.
