from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTH = ROOT / "authorize_control_plane.ps1"
BUILD = (ROOT / "build_iexpress.ps1").read_text(encoding="utf-8")


def test_authorizer_requires_external_public_key_and_restricts_acl():
    text = AUTH.read_text(encoding="utf-8")
    assert "PublicKeyPath" in text
    assert "administrators_authorized_keys" in text
    assert "PRIVATE KEY" not in text
    assert "PASSWORD=" not in text
    assert "BEGIN OPENSSH PRIVATE KEY" not in text
    assert "/inheritance:r" in text
    assert "*S-1-5-18:F" in text
    assert "*S-1-5-32-544:F" in text
    assert "read-back mismatch" in text.lower()
    assert "ssh-keygen" in text.lower()


def test_authorizer_is_packaged_but_contains_no_embedded_key():
    assert "FILE6=authorize_control_plane.ps1" in BUILD
    assert "%FILE6%=" in BUILD
