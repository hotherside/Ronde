# Ronde iOS redesign concepts

This concept board compares three possible visual and product directions for the universal iPhone reviewer:

1. **Caddie**: calm, editorial and media-first. This is the recommended direction.
2. **Flightline**: analytical, technical and evidence-first.
3. **Range Journal**: personal, place-led and retention-oriented.

Open `index.html` directly in a browser. The board is standalone and has no package or network dependencies.

## Shared product recommendation

- Use `Home`, `Library` and `Profile` as the three durable destinations.
- Keep import/record as a labelled navigation-toolbar action. Do not float a generic `+` above content or the tab bar. `Tracer` should not be a tab because it is a tool and result, not a collection.
- Keep raw videos, thumbnails, trajectory geometry, playback state and exports on-device.
- Use Supabase for Sign in with Apple, profile/preferences and lightweight sync metadata only in the first release.
- Make location entry optional and user-authored. Do not infer or upload precise coordinates without a separate consent decision.
- Do not show maximum distance until calibration and ground-truth validation make it a defensible product claim.

## Liquid Glass intent

The HTML uses CSS blur only to communicate hierarchy. Native SwiftUI should use iOS 26 system Liquid Glass for:

- the tab bar;
- labelled navigation-toolbar actions;
- compact filter controls;
- transient playback and contextual controls.

Media cards and analytics surfaces should remain content-first opaque surfaces. Earlier iOS versions need a restrained material fallback.

## Individual media interaction

Each concept now includes the same three-state media workflow:

1. **Review**: video-first playback, source-time scrubber, visible automatic-trace provenance and a compact sheet for Trim, Edit trace and Details.
2. **Trim & details**: a non-destructive impact-minus-five-seconds to impact-plus-five-seconds timeline, plus optional club, place and note metadata.
3. **Edit trace**: direct manipulation of Impact, Apex and Landing control points. Saving this state replaces the automatic presentation with `Manual trace`; observed evidence is never moved or relabelled.

This interaction stays consistent across the three concepts. Their visual tone changes, but the evidence and editing contract does not.

## Prototype boundary

All people, sessions, counts and places in the HTML remain illustrative. The initial concept pass changed no production state; the selected Caddie direction with Flightline evidence metrics is now implemented in SwiftUI and governed by [ADR 0009](../../context/decisions/0009-local-first-library-and-private-metadata-sync.md).
