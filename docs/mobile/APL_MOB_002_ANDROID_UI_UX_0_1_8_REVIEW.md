# APL-MOB-002 Android 0.1.8 — UI/UX cross-review log

Date: 2026-09-18  
Scope: PR #105 Android home/profile editor/launcher branding.  
Reference: owner physical screenshots of 0.1.7 and the Amnezia VPN interaction example.

## Pass 1 — Information architecture

**Finding:** 0.1.7 duplicated state in a top status card and the power control, kept a large Auto explanation card, exposed a long inline editor, and required scrolling.

**Fixes applied:**
- removed the separate state card;
- removed all Auto explanatory/help copy from the main screen;
- removed main-screen ScrollView;
- moved proxy fields out of the home screen into a focused editor dialog;
- reduced home to brand header, one state control, one concise connection-detail line, profile selector, New/Edit actions.

**Result:** no blocking IA issue remains for Auto home.

## Pass 2 — State semantics

**Finding:** “Подключено” above “ВЫКЛ” made the screen describe state and action with conflicting language. Hot-switch completion could also leave the transient “Переключение…” label visible after the connection had already reached CONNECTED.

**Fixes applied:**
- central control now says `Подключиться`, `Подключение…`, `Подключено`, `Отключение…`, or `Переключение…`;
- supporting text carries profile/transport detail instead of repeating the state;
- hot-switch completion re-renders from persisted final VPN state after clearing the switching flag.

**Result:** one source of truth for connection state.

## Pass 3 — Touch ergonomics and affordance

**Finding:** custom Spinner styling hid the normal dropdown arrow; “profile field” did not clearly look interactive. Small secondary controls needed standard Android touch targets.

**Fixes applied:**
- replaced the ambiguous profile field with an explicit clickable selector shell;
- added a permanent Mint chevron;
- selector height is 56dp;
- New/Edit/editor actions are 48dp;
- popup marks the currently selected profile;
- power control has Android ripple plus 0.965 press-scale animation.

**Result:** primary and secondary tap targets are visually obvious and comfortably sized.

## Pass 4 — Small-screen fit

**Finding:** the 0.1.7 Auto layout overflowed the owner device and pushed the power control below the fold.

**Fixes applied:**
- Auto home has no ScrollView;
- header and profile panel use compact fixed spacing;
- central power area uses flexible weight;
- power diameter adapts to screen height: 150/164/176dp;
- connection detail is capped at two lines with ellipsis;
- editor scrolling is confined to its modal and cannot expand the home screen.

**Result:** Auto home is structurally bounded to one screen; no user action requires vertical scrolling.

## Pass 5 — Profile-management clarity

**Finding:** Auto should never look like an editable proxy. Named/New configuration and connection selection were mixed into the same long form.

**Fixes applied:**
- Auto has no host/port/login/password/protocol UI anywhere on the home screen;
- New is a dedicated secondary action;
- named profile selection stays on the home screen;
- named profile editing opens a focused dialog;
- Edit/New remain disabled while VPN is active;
- profile selector remains enabled while connected for existing hot-switch behavior.

**Result:** “choose/connect” and “configure” are separate tasks.

## Pass 6 — Brand and accessibility

**Finding:** 0.1.7 used the correct palette but still looked like a styled diagnostic form. Error/destructive action contrast and accessibility labels also needed tightening.

**Fixes applied:**
- home is now Deep Navy, with Graphite profile surface and Mint active accents;
- status bar and navigation bar use Deep Navy for a continuous branded canvas;
- destructive editor action uses dark `#8A1C1C` text rather than pale red on white;
- power and selector have content descriptions;
- text sizes remain >=12.5sp and primary action is 21sp;
- disabled actions use reduced alpha without removing state information.

**Result:** visual hierarchy is closer to a consumer VPN while remaining within desktop Arvectum tokens.

## Pass 7 — Launcher branding and regression boundary

**Finding:** 0.1.6 cropped the source into a circle; 0.1.7 expanded the adaptive foreground canvas, which made the launcher artwork visually smaller and still subject to OEM adaptive masking.

**Fixes applied:**
- removed the unused adaptive-icon XML masks from the Android source tree;
- Android build now creates one circular Deep Navy composition;
- canonical source bitmap is drawn at original pixel size with no crop and no scale;
- the background fills around the squircle rather than resizing the squircle;
- manifest icon and roundIcon both point to the Android-only round composition;
- CI branding check now targets the packaged round PNG;
- networking / Auto / hot-switch service code is intentionally untouched by this UI refinement.

**Result before build:** source-level icon composition matches the owner requirement. Final packaged-image verification remains part of exact-head artifact inspection.

## Cross-review conclusion

All seven review passes produced concrete fixes. No further source-level blocking issue was found after Pass 7.

Remaining gates:
1. exact-head Android compile/signing/branding CI;
2. inspect packaged round PNG dimensions/alpha and visually confirm full canonical artwork is present;
3. physical owner acceptance on the same Android device.


## Physical 0.1.8 acceptance delta → 0.1.9

Owner screenshots on the target Android device exposed three residual presentation defects that source review alone did not catch:

1. **Power copy wrap:** `Подключиться` wrapped inside the circle.
   - 0.1.9 forces a single line and uses bounded Android autosizing (14–21sp) for every state label.

2. **Selection semantics:** the platform `PopupMenu` rendered square checkmarks, visually suggesting multi-select.
   - 0.1.9 replaces it with a branded anchored popup of circular `RadioButton` rows; exactly one saved selection is marked.

3. **Launcher mask:** the legacy circular bitmap was itself inset by the OEM launcher into a white circular mask.
   - 0.1.9 restores a true adaptive icon: Deep Navy fills the complete Android launcher mask and the canonical source is used as an unpadded foreground. The source is not cropped, scaled down or wrapped in another circle.

These are physical-device corrections only. Auto selection, hot switching, profile storage and tunnel transport remain unchanged.


## Physical 0.1.11 review → 0.1.12

Owner screenshots confirm the one-screen hierarchy, circular state control, profile panel and compact editor direction are now stable. The remaining issues are purely visual polish.

### Finding 1 — launcher still carries the desktop squircle seam
The 0.1.11 adaptive foreground scales the entire desktop product icon, so the beveled squircle edge remains visible inside the Android circle even though it no longer clips.

**0.1.12 fix:** the adaptive foreground no longer reuses the desktop squircle background. It is recomposed from the clean canonical AV brand mark plus the circular globe badge only; the full-bleed Deep Navy adaptive background is responsible for the Android circle.

### Finding 2 — header typography is internally inconsistent
Using the canonical wordmark bitmap for “Arvectum” next to Android-rendered “Proxy Launcher” necessarily produces different font metrics and baseline behavior.

**0.1.12 fix:** keep the canonical AV brand mark image, but render the complete text `Arvectum Proxy Launcher` as one single-line Android TextView using one typeface, one weight, one size and one baseline. This is the cleanest way to satisfy both brand recognition and typographic consistency.

### Finding 3 — platform/build labels are implementation noise
`Android · 0.1.11-dogfood` exposes build-channel detail that has no value in the normal connection flow.

**0.1.12 fix:** visible metadata is reduced to the bare semantic version only. Internal signing remains dogfood, but the Android `versionName` is also simplified to `0.1.12`.

### Finding 4 — status copy is more technical than the core UX requires
`HTTP/HTTPS (CONNECT)` is diagnostically correct but unnecessarily implementation-specific on the main screen.

**0.1.12 fix:** the home status simplifies it to `HTTP/HTTPS` and strips transient “Создаём VPN…” noise. The editor still exposes concrete protocol choices.

### Critical UI/UX conclusion

No new controls should be added to this version. The current information architecture is already close to the product goal:

- one primary connection action;
- one concise connection-detail line;
- one profile selector;
- one secondary New/Edit path.

Adding settings, diagnostics, ping, IP address, failover controls or extra cards now would weaken the “install → choose → connect” model. Those belong in later dedicated surfaces only if a real user need appears.

No further home-screen element is recommended for 0.1.12.


## Physical 0.1.12 review → 0.1.13

Two residual visual issues remain on the target launcher/header.

### Launcher
The clean 0.1.12 AV+globe recomposition removed squircle seams but changed the relative geometry enough that the artwork clips under the OEM circular mask.

**0.1.13 correction:** restore the accepted 0.1.11 geometry exactly — source artwork at 60% centered — but pre-clean the source so all squircle/background pixels become transparent. Only Mint AV pixels and the complete globe badge survive. The adaptive Deep Navy background remains the only launcher background.

This preserves the better 0.1.11 scale while removing the square/squircle traces that caused the earlier defect.

### Header
Version should not occupy a second line.

**0.1.13 correction:** AV mark, `Arvectum Proxy Launcher`, and semantic version are rendered in one horizontal row with `Gravity.BOTTOM`. The version sits at the far right and shares the row's lower edge.

No home-screen controls or connection behavior change.
