"""The canonical source and native stage must agree on the intended release identity."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"


def test_ios_source_version_is_frozen_for_unified_release():
    project = (IOS / "project.yml").read_text()
    pbx = (IOS / "ArvectumProxyLauncherIOS.xcodeproj/project.pbxproj").read_text()
    assert 'MARKETING_VERSION: "0.3.0"' in project
    assert 'CURRENT_PROJECT_VERSION: "49"' in project
    assert project.count('MARKETING_VERSION: "0.3.0"') == 1
    assert project.count('CURRENT_PROJECT_VERSION: "49"') == 1
    assert pbx.count('MARKETING_VERSION = 0.3.0;') == 2
    assert pbx.count('CURRENT_PROJECT_VERSION = 49;') == 2


def test_native_staging_checks_exact_version_without_silent_rewrite():
    stage = (IOS / "Tools/stage_ios_030_release_candidate.py").read_text()
    assert 's.count(\'MARKETING_VERSION: "0.3.0"\') == 1' in stage
    assert 's.count(\'CURRENT_PROJECT_VERSION: "49"\') == 1' in stage
    assert "s=s.replace(" not in stage
    assert "assert 'MARKETING_VERSION: \"0.2.0\"' not in s" in stage
    assert "'source_commit':commit" in stage
    assert "exist_ok=False" in stage
