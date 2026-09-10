from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREP = ROOT / "tools" / "windows_app_control_prepare_production_runtime_trust.ps1"
PACK = ROOT / "tools" / "windows_app_control_enterprise_trust_pack.ps1"
RUNTIME = ROOT / "tools" / "windows_app_control_inno_runtime_material.ps1"
VERIFY = ROOT / "tools" / "windows_app_control_verify_runtime_trust_pack.ps1"

PRODUCTION_SETUP_SHA256 = "5808bde9d0ac45048d50bc256878519257f53bf0a9fa523a81ccb2eff0e21414"
HISTORICAL_V1064_SETUP_SHA256 = "7e7640fe434067415840a154cfbeba0df443caf155fed38cff7ede1bc7d7d600"
RUNTIME_SHA256 = "b37446a70e4ce841b58c1fcc35edd1295769184e5e9206188a3949ed02dc76d8"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_production_runtime_authoring_is_bound_to_exact_production_setup():
    body = text(PREP)
    assert PRODUCTION_SETUP_SHA256 in body
    assert HISTORICAL_V1064_SETUP_SHA256 not in body
    assert "Arvectum-Proxy-Launcher-0.2.3-windows-x64-setup.exe" in body
    assert "Get-FileHash -LiteralPath $setup -Algorithm SHA256" in body


def test_production_runtime_is_extracted_before_trust_pack_generation():
    body = text(PREP)
    extraction = body.index("$extractor $setup $runtimePath --evidence $runtimeEvidencePath")
    validation = body.index("-File $validator")
    pack = body.index("-Mode ReferenceFullHash")
    assert extraction < validation < pack
    assert "-AsJson" in body
    assert "ConvertFrom-Json" in body
    assert ". $validator" not in body
    assert "pefile version mismatch" in body
    assert "2024.8.26" in body


def test_production_runtime_authoring_requires_independent_runtime_anchor():
    prep = text(PREP)
    helper = text(RUNTIME)
    assert RUNTIME_SHA256 in prep
    assert RUNTIME_SHA256 in helper
    assert "33669452947" in helper
    assert "33666343748" in helper
    assert "cfdf48923178df4b4f040e038b423aa555a61ffc" in helper
    assert "static_to_behavioral_anchor" in prep


def test_production_runtime_authoring_generates_and_reverifies_reference_full_hash_pack():
    body = text(PREP)
    assert "windows_app_control_enterprise_trust_pack.ps1" in body
    assert "windows_app_control_verify_runtime_trust_pack.ps1" in body
    assert "ReferenceFullHash" in body
    assert "runtime\\production-runtime-extraction.json" in text(PACK)
    assert "hash_policy_integrated = $true" in text(PACK)
    assert "SigningScenario 12" in text(VERIFY)


def test_production_runtime_authoring_never_deploys_or_weakens_app_control():
    body = text(PREP).lower()
    for forbidden in (
        "--update-policy",
        "--remove-policy",
        "verifiedandreputablepolicystate",
        "set-ruleoption",
        "set-itemproperty",
        "reg.exe add",
        "disable-windowsoptionalfeature",
    ):
        assert forbidden not in body
    assert "policy deployed: no" in body
    assert "security controls modified: no" in body
    assert "product rebuilt: no" in body


def test_authoring_output_paths_are_canonical_and_fail_closed_on_overwrite():
    body = text(PREP)
    assert "C:\\Arvectum\\Evidence\\APL-WIN-014\\runtime" in body
    assert "C:\\Arvectum\\Evidence\\APL-WIN-014\\trust-pack" in body
    assert "refusing to overwrite prior evidence" in body
    assert "production-runtime-authoring.json" in body
    assert "SHA256SUMS.txt" in body
