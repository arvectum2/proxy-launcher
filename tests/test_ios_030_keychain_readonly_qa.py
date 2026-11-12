"""Safety gate for privileged physical-only iOS Keychain migration probe."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "mobile/ios/Tests/DeviceKeychainTests/PhysicalKeychainReadOnlyTests.swift"


def test_keychain_qa_requires_real_device_and_only_queries_passwords():
    text = SWIFT.read_text(encoding="utf-8")
    assert "#if targetEnvironment(simulator)" in text
    assert "throw XCTSkip" in text
    assert "let password = try store.password(for: profile.id)" in text
    assert "XCTAssertEqual(accessibleCredentials, 3)" in text
    for forbidden in (
        "store.save(", "store.delete(", "SecItemUpdate", "SecItemDelete",
        "SecItemAdd", "UserDefaults.standard.set", "print(", "NSLog(",
        "XCTAssertEqual(password,", "XCTAssertEqual(profile.username",
    ):
        assert forbidden not in text


def test_keychain_qa_has_separate_opt_in_scheme():
    spec = (ROOT / "mobile/ios/project.yml").read_text(encoding="utf-8")
    assert "PhysicalKeychainReadOnlyTests:" in spec
    assert "ArvectumKeychainReadOnlyQA:" in spec
    main_scheme = spec.split("  ArvectumProxyLauncher:\n", 1)[1]
    main_tests = main_scheme.split("  ArvectumKeychainReadOnlyQA:", 1)[0]
    assert "        - PhysicalKeychainReadOnlyTests" not in main_tests
    assert "        - PhysicalKeychainReadOnlyTests" in spec.split(
        "  ArvectumKeychainReadOnlyQA:", 1
    )[1]
