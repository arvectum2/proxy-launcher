# APL Adaptive UI contract

Task: **APL-UI-001**

The product uses one shared visual and interaction language across Android, iOS,
Windows, Linux and macOS. Consistency means the same mental model and state
semantics, not a pixel-identical phone layout on desktop.

## Shared design tokens

- Deep Navy: `#001432`
- Mint Primary: `#00C8A0`
- Mint Light: `#78FAE6`
- Graphite: `#283246`
- Soft Gray: `#C8D2DC`

Platform-native typography, focus, menu, window and accessibility behavior stay
native. Brand colors and semantic hierarchy stay recognizably Arvectum.
## Shared information architecture

Common destination order:

1. **Главная** — connection state, active profile context and the primary action.
2. **Профили** — profile selection, creation/editing and Auto/priority behavior.
3. **Активность** — connection checks, journal/events and diagnostics.
4. **Настройки** — exclusions, autostart, recovery and other non-daily controls.

Marketplace is not a top-level destination until it is a real product surface.

## Primary connection action

Every platform exposes exactly one primary stateful connection control:

- disconnected/error and recoverable: **Подключиться**;
- connecting: **Подключение…** and temporarily non-destructive;
- connected/reasserting: **Отключить**;
- disconnecting: **Отключение…** and temporarily disabled.

The control changes presentation only. Existing routing, recovery, confirmation,
ownership and security rules remain authoritative.
## Adaptive composition

### Android / iOS

- touch-first hierarchy;
- prominent connection control;
- active profile kept close to connection context;
- four common destinations remain easy to reach;
- editing and maintenance use platform-native dialogs, sheets and navigation.

### Windows / Linux / direct macOS

- compact, resizable desktop window;
- current state, active proxy summary and one primary action on Home;
- Profiles, Activity and Settings separated from the daily connection path;
- keyboard/pointer/native-window conventions remain available;
- diagnostics, connection test, restore-network and autostart are not Home controls.

### Mac Catalyst

- reuses the SwiftUI product language and underlying iOS model;
- uses a desktop sidebar and compact connection hero instead of an enlarged phone;
- keeps the same destination order and semantics as mobile.
## Non-regression boundary

APL-UI-001 must not change tunnel engines, proxy selection algorithms, credential
storage, NetworkExtension/VpnService behavior, desktop system-proxy ownership,
rollback semantics, wake guards, PolicyKit behavior, or application/site routing
rules merely for visual parity.

Automated contract coverage lives in `tests/test_adaptive_ui_contract.py` plus
existing platform-specific UI/recovery tests. Release-target builds and physical
visual/interaction acceptance remain required before the first public release
containing the newly unified UI and application-exclusion functionality.
