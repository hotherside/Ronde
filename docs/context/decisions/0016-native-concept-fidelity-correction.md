# 0016: Correct native concept fidelity after physical-device review

**Status:** Implemented; source delivery authorised; physical-device review remains open

**Date:** 19 September 2026

## Context and source

After installing the PR #12 native implementation on an iPhone, the owner rejected its visual fidelity: the design felt like an MVP, diverged from Clubhouse/Cutroom and used unnecessary headings, subheadings and weak typography. The earlier passing Simulator journeys establish functional behaviour only. They did not establish design acceptance.

The correction was prepared on `codex/concept-fidelity`, based on `7a6bd012484419faf3f23011cee7f4ae12b4a6b3`. Separate active tracer changes in the original checkout are preserved. After the correction and passing checks below, the owner explicitly instructed the agent to stop further testing, commit, push and merge so work could return to functionality. Git and the delivery PR record incorporation into `main`.

## Decision

Keep the accepted Clubhouse identity, Cutroom editing vocabulary, native Liquid Glass and the source-linked media model in ADR 0014. Correct the native translation instead of opening another concept exploration.

Use one compact identity per screen, Avenir Next typography tied to Dynamic Type, 16-point phone page insets and 8–12-point internal spacing. Sessions leads with a photographic cover, concise date/place metadata and two visible keeper cards. Ordinary iPhone shot collections use two columns; accessibility text reflows to one. Session detail uses compact recording rows and a shot grid.

Recording Studio begins with fitted media, compact transport and a sparse timeline. Bookmarks and created Shots share one inspector. Shot Studio keeps the media, trim timeline and Trim/Trace/Format controls close together. Format options use recognisable silhouettes in four columns at normal text sizes and reflow at larger sizes. Keeper, Export and overflow Details live in the native toolbar. Manual tracing belongs to Trace. Editors hide the root tab bar while retaining native navigation.

Glass is the material for navigation and controls. Content surfaces remain readable and opaque, and prominent actions must preserve contrast when Reduce Transparency is enabled or on earlier supported systems.

## Evidence and next gate

Populated Debug-only review routes use the existing fictional concept stills encoded as short local movies. They never enter a release build, write a library archive or initiate tracking. Captures are visual composition evidence, not golf-tracking, source-performance or signed-device evidence.

The complete seven-journey iPhone UI suite passed during the correction. Focused final runs verified populated native screens on iPhone, iPad and Duo; reachable format selection at the largest accessibility text size on iPad; and actual square MP4 export through to the system share sheet. [The native review board and validation record](../../design/2026-09-19-shot-media/native-fidelity/README.md) preserve the screenshots, provenance, precise result bundles and limits. Current State separates these results from earlier source validation.

The owner authorised source delivery without more testing. The remaining device gate is another signed-iPhone UAT pass; the earlier rejection remains the latest physical-device design result until that pass occurs. This source delivery does not install the correction on the owner's phone.
