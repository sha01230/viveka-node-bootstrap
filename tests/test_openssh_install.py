from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / "bootstrap.ps1").read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def test_openssh_is_ensured_before_service_configuration():
    ensure = "  $OpenSSHSource = Ensure-OpenSSHServer"
    configure = "  Set-Service sshd -StartupType Automatic"
    assert "Step 'OpenSSH server substrate'\n" + ensure in BOOT
    assert BOOT.index(ensure) < BOOT.index(configure)


def test_ensure_openssh_supports_existing_fod_and_bundled_msi_paths():
    assert "Get-Service -Name 'sshd'" in BOOT
    assert "Get-WindowsCapability -Online" in BOOT
    assert "Add-WindowsCapability -Online" in BOOT
    assert "return 'EXISTING'" in BOOT
    assert "return 'FOD'" in BOOT
    assert "return 'BUNDLED_MSI'" in BOOT
    assert "OpenSSH MSI completed but sshd service still does not exist" in BOOT
