from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / "bootstrap.ps1").read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def test_openssh_install_is_actually_invoked_before_service_configuration():
    install = "  Ensure-WindowsCapability 'OpenSSH.Server*'"
    configure = "  Set-Service sshd -StartupType Automatic"
    assert "Step 'OpenSSH server substrate'\n" + install in BOOT
    assert BOOT.index(install) < BOOT.index(configure)


def test_capability_install_is_verified_and_sshd_must_exist():
    assert "post.State -ne 'Installed'" in BOOT
    assert "Get-Service -Name 'sshd'" in BOOT
    assert "OpenSSH Server capability is installed but sshd service was not created" in BOOT
