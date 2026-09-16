from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / 'bootstrap.ps1').read_text(encoding='utf-8')
LAUNCH = (ROOT / 'launch.cmd').read_text(encoding='utf-8')

def test_identity_uses_windows_cng_not_ssh_keygen():
    assert 'CngAlgorithm]::ECDsaP256' in BOOT
    assert 'ProtectedData]::Protect' in BOOT
    assert 'DataProtectionScope]::LocalMachine' in BOOT
    assert 'ssh-keygen' not in BOOT
    assert 'identity_algorithm' in BOOT
    assert 'public_key_blob_b64' in BOOT

def test_failures_are_persisted_and_visible():
    assert "state='FAILED'" in BOOT
    assert 'bootstrap_failure.json' in BOOT
    assert "Read-Host 'Bootstrap failed. Press Enter to close'" in BOOT
    assert 'try {' in BOOT and 'catch {' in BOOT

def test_public_bootstrap_remains_non_authoritative():
    for forbidden in ('reality-lab.git','github.com/sha01230/reality-lab','ENROLLMENT_ISSUER','token=','password='):
        assert forbidden not in BOOT
    assert "state = 'PENDING'" in BOOT


def test_powershell_script_parses_cleanly():
    import subprocess
    command = "$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile('bootstrap.ps1',[ref]$t,[ref]$e)|Out-Null;if($e.Count){exit 1}"
    result = subprocess.run(['powershell.exe','-NoProfile','-Command',command], cwd=ROOT)
    assert result.returncode == 0
