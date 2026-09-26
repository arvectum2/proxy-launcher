# APL UI/UX cross-check — 2026-09-26

## Scope
Compare the current mobile/iOS + Mac Catalyst visual model with the desktop Windows/Linux/direct-macOS model. This is a design review only; no product UI code is changed here.

## Executive conclusion
Use the **mobile visual/product language as the common design foundation**, but **do not copy the mobile layout literally to desktop**. The target should be one Arvectum design system with adaptive platform compositions: mobile-first touch composition on phones, desktop composition on Windows/Linux/macOS, and native platform conventions for menus/settings/keyboard/windowing.

The current Mac App Store screen is a useful proof of the new design language, but it is visibly an iPhone/iPad composition enlarged into a Mac window. The current classic desktop UI is more efficient on a desktop, but exposes too many maintenance/admin controls on the home screen and lacks the stronger primary-task hierarchy of the mobile UI.

## Nine review passes

### 1. Primary job-to-be-done
APL's primary job is: choose a proxy when needed, connect/disconnect immediately, understand current state, recover if something fails.
- Mobile/Catalyst: strongest hierarchy; connection state and action are unmistakable.
- Desktop classic: clear, but On/Off buttons, port details, check tools and service controls compete for attention.
Result: **mobile direction wins**.

### 2. Cognitive load / novice learnability
- Mobile groups the experience around one obvious action and one current profile.
- Desktop exposes troubleshooting and configuration capabilities before the user asks for them.
Result: **mobile direction wins**. Secondary tools should move behind Settings/Diagnostics.

### 3. Desktop information density and pointer ergonomics
- Direct desktop UI uses space efficiently and keeps related controls visible.
- Current Catalyst screenshot wastes a large central area and places the profile card far from the connection control.
- A 174 pt circular text button is appropriate as a touch hero but oversized for mouse/trackpad.
Result: **desktop composition wins on desktop**.

### 4. Mobile touch ergonomics
- Large targets, simple card hierarchy and the central connect action work well for handheld use.
- The desktop control-panel layout would be cramped and cognitively heavy on a phone.
Result: **mobile composition wins decisively on mobile**.

### 5. Advanced workflows and troubleshooting
- Desktop currently surfaces connection check, diagnostics, restore-network, autostart and technical status directly.
- Mobile correctly keeps the home screen simpler, but advanced functions become less discoverable as features grow.
Result: **desktop has better expert discoverability**, but the right solution is progressive disclosure rather than exposing everything on Home.

### 6. Product-roadmap scalability
Profiles, Auto/failover, exclusions, marketplace/supplier routing, monetization, per-app routing and diagnostics will not fit gracefully into either current one-screen model.
Result: **neither current layout scales unchanged**. A stable top-level information architecture is required.

Recommended shared destinations:
- Home
- Profiles
- Diagnostics / Activity
- Settings
Optional future Marketplace as a separate top-level destination only when it becomes a real product surface.

On phones use tabs/navigation stacks. On desktop use a sidebar, top-level toolbar/segmented navigation, or compact navigation surface depending on window width.

### 7. Platform conventions
Apple's current HIG explicitly distinguishes iOS and macOS ergonomics: iOS prioritizes primary tasks and limited controls, while macOS should exploit larger displays, keyboard/pointer input, menu bar commands and fewer nested modal levels. Mac Catalyst guidance also expects deliberate Mac adaptation rather than an unchanged iPad layout.
Windows guidance similarly emphasizes familiar native patterns, standard command surfaces, keyboard/pointer support and adaptive layouts.
Result: **pixel-identical UI across platforms is not the professional target**. Shared mental model + platform-adaptive shell is.

### 8. Accessibility and system integration
- SwiftUI gives the mobile/App Store lane a stronger foundation for semantic accessibility, Dynamic Type and native system behavior, although the current fixed-size hero still needs adaptive treatment on Mac.
- The direct Tk desktop UI uses native-ish controls on macOS and works, but has weaker long-term accessibility/theming integration and more manual styling.
Result: **mobile/native design foundation has the better long-term ceiling**, while desktop layouts still need desktop-specific controls.

### 9. Brand coherence and competitive benchmark
The mobile visual language has the clearer Arvectum identity: navy canvas, mint accent, profile card and strong connection state. Desktop products in this category commonly keep a shared product identity while adapting layout: Proton makes Quick Connect primary but separates profiles/settings on desktop; Mullvad preserves a consistent simple connection model across desktop/mobile; Tailscale now combines a full windowed desktop UI with a compact mini-player.
Result: **unify the brand and interaction model, not the exact geometry**.

## Recommended target: “APL Adaptive UI”

### Shared across every platform
- Same Arvectum navy/mint tokens and typography hierarchy.
- Same connection-state semantics and wording.
- One stateful primary Connect/Disconnect control, never separate competing On and Off buttons.
- Same profile naming, Auto behavior, health/status indicators and exclusions concepts.
- Same icons and order for the common destinations.
- Same error language and recovery concepts.

### Mobile
Keep the current direction, with refinement:
- prominent connection control;
- current profile close to the connection action;
- quick access to profile selection;
- bottom/top navigation for Home, Profiles, Activity, Settings as the product grows;
- secondary controls in sheets/navigation stacks.

### Desktop
Adopt the mobile visual language but recompose it:
- compact connection hero rather than a giant circle in empty space;
- connection status + active profile in one visual cluster;
- profile selector and Connect/Disconnect within short pointer travel;
- diagnostics, connection test, restore-network and autostart moved out of the main Home surface;
- keyboard shortcuts, native menus and Settings conventions;
- responsive layout that uses available width instead of scaling a phone screen.

A good desktop Home can fit in roughly a 700–900 px wide window:
1. compact header/identity;
2. connection card with status, active profile and primary action;
3. quick profile controls;
4. small recent/health area;
5. secondary navigation to Profiles, Diagnostics and Settings.

## Decision
If forced to choose one current interface as the **design seed**, choose the **mobile UI**. If forced to ship that exact UI unchanged on every platform, choose neither.

The recommended modernization is:
**mobile design language + desktop interaction model + native platform shell**.

This gives APL one recognizable product without making a Mac/Windows/Linux user operate an enlarged phone interface or making a phone user operate a desktop control panel.
