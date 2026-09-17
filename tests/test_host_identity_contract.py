from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / "bootstrap.ps1").read_text(encoding="utf-8")
BUILD = (ROOT / "build_iexpress.ps1").read_text(encoding="utf-8")


def test_public_host_profile_preserves_raw_identity_anchors():
    text = (ROOT / "emit_host_profile.ps1").read_text(encoding="utf-8")
    assert "viveka.node.host_profile.v1" in text
    assert "Win32_ComputerSystemProduct" in text
    assert "Win32_BaseBoard" in text
    for key in ("host_identity", "system_uuid", "manufacturer", "product", "serial_number"):
        assert key in text


def test_bootstrap_consumes_shared_host_profile_and_packages_helper():
    assert "emit_host_profile.ps1" in BOOT
    assert "$profile.host_identity" in BOOT
    assert "$profile.host" in BOOT
    assert "FILE5=emit_host_profile.ps1" in BUILD
    assert "%FILE5%=" in BUILD
