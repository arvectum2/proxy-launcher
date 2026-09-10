from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "tools" / "windows_app_control_enterprise_trust_pack.ps1"


def test_enterprise_trust_manifest_is_final_before_checksum_inventory():
    body = PACK.read_text(encoding="utf-8")
    result = body.index("result = 'PASS'")
    manifest_write = body.index("$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath")
    checksums = body.index("$checksums = @(")
    checksum_write = body.index("Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt')")

    assert result < manifest_write < checksums < checksum_write
    assert "$manifest.result" not in body[checksums:]
    assert "Set-Content -LiteralPath $manifestPath" not in body[checksums:]
