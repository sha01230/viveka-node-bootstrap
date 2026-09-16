from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / 'bootstrap.ps1').read_text(encoding='utf-8')
BUILD = (ROOT / 'build_iexpress.ps1').read_text(encoding='utf-8')

MSI = 'OpenSSH-Win64-v9.8.3.0.msi'
SHA = 'C8A8C7E21136A099665C2FAD9ACCB41152D129466B719EA71678BAB665E03389'


def test_bundled_microsoft_openssh_fallback_is_pinned_and_verified():
    assert MSI in BOOT
    assert SHA in BOOT
    assert 'Get-AuthenticodeSignature' in BOOT
    assert "Microsoft Corporation" in BOOT
    assert 'msiexec.exe' in BOOT
    assert 'ADDLOCAL=Server' in BOOT


def test_iexpress_bundles_fallback_msi():
    assert MSI in BUILD
    assert 'FILE2=' in BUILD
    assert '%FILE2%=' in BUILD


def test_build_fetches_only_pinned_official_msi_and_verifies_it():
    assert 'PowerShell/Win32-OpenSSH/releases/download/v9.8.3.0p2-Preview/' in BUILD
    assert SHA in BUILD
    assert 'Get-AuthenticodeSignature' in BUILD
    assert 'Microsoft Corporation' in BUILD
