"""Release QA safety contract: never mutate a real user's proxy profiles in XCUITest."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "mobile/ios/Tests/UITests/PhysicalUpgradeReadOnlyUITests.swift"


def test_real_iphone_acceptance_does_not_use_qa_profile_fixtures_or_mutators():
    source = TARGET.read_text(encoding="utf-8")
    assert "PhysicalUpgradeReadOnlyUITests" in source
    assert "testExistingThreeProfilesAreVisibleAfterInPlaceUpgrade" in source
    assert "app.launch()" in source
    assert "app.launchArguments" not in source
    assert 'identifier BEGINSWITH %@"' in source
    assert 'XCTAssertEqual(rows.count, 3' in source
    assert 'app.staticTexts["0.3.0"]' in source
    for forbidden in (
        "profiles.import", "profiles.bulk.delete", "Удалить безвозвратно",
        "Подключиться", "tun2proxy", "vpn.connect", "resetAll",
        "UserDefaults.standard.set", "keychainDelete", "removeAll",
    ):
        assert forbidden not in source


def test_real_user_data_test_is_skipped_on_ci_simulators():
    source = TARGET.read_text(encoding="utf-8")
    assert "#if targetEnvironment(simulator)" in source
    assert 'throw XCTSkip("Physical iPhone-only migration acceptance")' in source
    assert "#endif" in source
