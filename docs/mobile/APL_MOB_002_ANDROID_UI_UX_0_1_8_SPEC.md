# APL-MOB-002 — Android UI/UX refinement for 0.1.8-dogfood

Status: implementation specification  
Owner feedback source: physical 0.1.7 Android dogfood, 2026-09-18  
Scope: UI/UX and launcher branding only. Already-passing Auto/hot-switch transport behavior must not regress.

## Product objective

Make the Android client feel like a finished VPN product rather than a diagnostic form.

The primary flow must be immediately understandable:

1. choose a proxy profile or Auto;
2. tap one large central connection control;
3. see the connection state and actual selected proxy;
4. optionally switch proxy while connected.

The main screen should stay visually calm and fit on one phone screen in Auto mode with no need to scroll.

## Required behavior

### Main Auto screen

- Auto must render **no proxy input fields**.
- Remove the explanatory text/card “Авто: выбираем рабочий сохранённый прокси” and any equivalent Auto help copy from the main screen.
- No large duplicate “Состояние” card.
- The main connection control is the single primary state indicator.
- In Auto mode the whole actionable screen must fit on a typical 360×800dp-class Android display without vertical scrolling.

### Connection control

Use one large circular branded button, similar in interaction hierarchy to mature VPN clients but with Arvectum branding.

Button labels by state:

- disconnected: **Подключиться**
- connecting: **Подключение…**
- connected: **Подключено**
- disconnecting: **Отключение…**
- hot switching: **Переключение…**
- error returns to actionable **Подключиться**, with concise error detail nearby

The control must:
- use Arvectum Deep Navy / Mint palette;
- have ripple plus visible press-scale feedback;
- never show “ВЫКЛ” while the rest of the screen says “Подключено”.

### Profile selection

- Use a clearly affordant dropdown row.
- Always show a visible downward chevron on the right.
- Auto remains an option.
- Named profiles remain options.
- “Новый” is an explicit secondary action, not explanatory content.
- While VPN is connected, the profile dropdown remains active for hot switching.
- Profile creation/edit/delete remains unavailable while the VPN is active.

### Profile editor

Proxy data fields must appear only while creating a new profile or editing a concrete named profile.

The home screen must not show host/port/login/password/protocol fields for Auto.

Preferred UX:
- main screen remains compact;
- New/Edit opens a focused branded editor dialog rather than expanding the home screen into a long form.

### Connection detail

Show one concise supporting line below the main connection control, for example:

- `Авто → Основной · HTTP/HTTPS`
- `Основной · SOCKS5`
- `Проверяем Основной…`

Do not duplicate the connection state in a separate status chip/card.

### Android launcher icon

The canonical AV/globe artwork must remain at its original scale.

Do **not** crop the source squircle to a circle and do **not** shrink the source artwork to fit an adaptive safe-zone.

Generate an Android-specific circular composition by:
1. drawing a Deep Navy circle/background;
2. compositing the canonical squircle artwork centered at its original size;
3. leaving the original artwork unscaled and fully visible;
4. using the resulting Android-only resource for launcher icon/roundIcon.

Desktop and iOS source assets remain unchanged.

## Brand tokens

Use the canonical desktop Arvectum palette:

- Deep Navy: `#001432`
- Mint Primary: `#00C8A0`
- Mint Light: `#78FAE6`
- Soft Gray: `#C8D2DC`
- Graphite: `#283246`
- White: `#FFFFFF`

Visual language:
- strong Deep Navy base;
- Mint for active/primary state;
- restrained secondary text;
- rounded surfaces where useful;
- no decorative panels that do not support a task.

## Small-screen acceptance

For Auto mode:
- no ScrollView on the main screen;
- header, central power control, concise status detail, profile dropdown and New action are all visible simultaneously;
- bottom system navigation must not overlap the power control or selector.

Named-profile editing may use a scrollable modal/dialog if needed.

## Cross-review protocol

Before physical handoff, perform up to seven focused review/fix passes:

1. **Information architecture** — remove duplicate state/help and reduce steps.
2. **State semantics** — connection copy must match the action/state model.
3. **Touch ergonomics** — tap targets, dropdown affordance, button press feedback.
4. **Small-screen fit** — Auto screen without scrolling or clipped controls.
5. **Profile management** — Auto vs named/New editing clarity and hot-switch behavior.
6. **Brand/accessibility** — palette, hierarchy, contrast, disabled/error states.
7. **Launcher branding + regression** — full logo visibility, Android shape, transport/state regression review.

Every pass must record findings and concrete fixes (or “no blocking issue found”) in the task checkpoint/PR before physical handoff.

## Definition of Done

- Android dogfood version advances to 0.1.8 with the existing stable signer.
- Auto main screen satisfies all main-screen requirements.
- Named/New profile editor is focused and does not clutter Auto.
- Hot switching and Auto selection behavior remain unchanged.
- Android icon shows the full canonical squircle artwork inside a circular Deep Navy composition.
- Seven cross-review passes are completed or stopped earlier only if all remaining passes report no actionable issue.
- Exact-head Android CI is green.
- APK signer/branding resource/SHA-256 are verified.
- Owner physical acceptance confirms layout, power-control semantics, dropdown affordance and launcher icon.
