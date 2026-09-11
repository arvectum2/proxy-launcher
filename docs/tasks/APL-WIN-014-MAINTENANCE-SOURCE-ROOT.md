# APL-WIN-014 maintenance source contract

Physical ARVECTUM-DEMO acceptance proved that the sealed `v0.2.3-ru.2` portable ZIP does not contain `build_manifest.json`, `upgrade_helper.ps1`, or `uninstall_helper.ps1`. The canonical Inno installer embeds the two maintenance helpers from the governed release source tree instead.

Canonical contract:

- release-policy commit: `47823585c42da54ab51dc2246583dc24d74d4ba6`
- source paths: `installer/upgrade_helper.ps1`, `installer/uninstall_helper.ps1`
- upgrade SHA256: `77e8bcb4d27aad5b2d1b40753f3ec2dfa2419e48a07f2eb17a7b15f2a9232218`
- uninstall SHA256: `7abc1fe332975440d2c84be608773a890c5bb4deb130eea54378a128e79b0a44`

`MaintenanceSourceRoot` is therefore an explicit immutable input to App Control trust-pack authoring and final-stand preparation. Missing files or hash drift are BLOCK. The production portable ZIP remains independently pinned for application identity but is not a maintenance-helper source. No product bytes or Windows protection settings are changed by this contract.