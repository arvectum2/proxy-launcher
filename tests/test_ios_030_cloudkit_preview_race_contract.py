"""Dependency-free source gates for opt-in CloudKit concurrent edits."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "mobile/ios/SharedCore/ExclusionSyncContract.swift"
UI = ROOT / "mobile/ios/App/ExclusionCloudSyncView.swift"
SERVICE = ROOT / "mobile/ios/App/ExclusionCloudKitService.swift"
APP = ROOT / "mobile/ios/App/ExclusionsView.swift"


class CloudKitPreviewConcurrencyContracts(unittest.TestCase):
    def test_both_preview_versions_must_match_before_remote_apply(self):
        ui = UI.read_text()
        method = ui.split("private func apply() async {", 1)[1].split(
            "private func upload() async {", 1)[0]
        self.assertIn("cloud.previewRemote()", method)
        self.assertIn("ExclusionSyncContract.remoteUnchanged(", method)
        self.assertIn("expectedRecord.recordID == currentRecord.recordID", method)
        self.assertIn("expectedRecord.recordChangeTag", method)
        self.assertIn("currentRecord.recordChangeTag", method)
        self.assertIn("checked = false", method)
        self.assertLess(method.index("remoteUnchanged("), method.index("model.saveExclusions("))

    def test_changed_local_list_never_gets_overwritten_or_uploaded(self):
        ui = UI.read_text()
        apply = ui.split("private func apply() async {", 1)[1].split(
            "private func upload() async {", 1)[0]
        upload = ui.split("private func upload() async {", 1)[1]
        self.assertGreaterEqual(apply.count("ExclusionSyncContract.localUnchanged("), 2)
        self.assertIn("ExclusionSyncContract.localUnchanged(", upload)
        self.assertIn("cloud.upload(manualDomains: localAtPreview", upload)
        self.assertNotIn("cloud.upload(manualDomains: model.manualExclusions", upload)

    def test_payload_and_change_tag_both_required_in_core(self):
        core = CORE.read_text()
        self.assertIn("static func remoteUnchanged(", core)
        self.assertIn("previewed == current", core)
        self.assertIn("previewTag == currentTag", core)
        self.assertIn("guard let previewTag, !previewTag.isEmpty", core)
        self.assertIn("static func localUnchanged(", core)
        self.assertIn("approved == previewed", core)
        self.assertIn("live == approved", core)

    def test_cloud_upload_rechecks_reviewed_payload_and_nonempty_tag(self):
        service = SERVICE.read_text()
        snippet = service.split("func upload(", 1)[1].split("private func deviceID()", 1)[0]
        for required in (
            "expectedRemote.recordID == currentRecord.recordID",
            "expectedRemote.recordType == Self.recordType",
            'expectedRemote["payload"] as? Data',
            "ExclusionSyncContract.decode(reviewedBytes)",
            "ExclusionSyncContract.remoteUnchanged(",
            "previewTag: expectedRemote.recordChangeTag",
            "currentTag: currentRecord.recordChangeTag",
            "savePolicy: .ifServerRecordUnchanged",
        ):
            self.assertIn(required, snippet)
        self.assertLess(snippet.index("remoteUnchanged("), snippet.index("database.modifyRecords("))

    def test_existing_cloudkit_kill_switch_and_server_cas_preserved(self):
        self.assertIn("#if APL_CLOUDKIT_ENABLED", APP.read_text())
        service = SERVICE.read_text()
        self.assertIn("privateCloudDatabase", service)
        self.assertIn("ifServerRecordUnchanged", service)
        self.assertIn("observedRemoteWasAbsent", service)
        self.assertNotIn("publicCloudDatabase", service)


if __name__ == "__main__":
    unittest.main()
