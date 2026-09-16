from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / "bootstrap.ps1").read_text(encoding="utf-8")
LAUNCH = (ROOT / "launch.cmd").read_text(encoding="utf-8")


def test_public_bootstrap_has_no_private_dependency_or_secret():
    assert "reality-lab" not in BOOT.lower()
    assert "github.com/sha01230/reality-lab" not in BOOT.lower()
    assert "git clone" not in BOOT.lower()
    assert "Python.Python" not in BOOT
    for forbidden in ("TOKEN=", "PASSWORD=", "Ollama.Ollama", "Docker.DockerDesktop", "ROCm", "CUDA"):
        assert forbidden not in BOOT


def test_bootstrap_is_elevated_pending_identity_setup():
    assert "-Verb RunAs" in LAUNCH
    assert "OpenSSH.Server" in BOOT
    assert "OpenSSH.Client" not in BOOT
    assert "ssh-keygen" not in BOOT
    assert "CngAlgorithm]::ECDsaP256" in BOOT
    assert "PENDING" in BOOT
    assert "pairing_code" in BOOT
    assert "VIVEKA_NODE_ENROLLMENT_REQUEST.json" in BOOT
    assert "UTF8Encoding($false)" in BOOT

def test_bootstrap_does_not_claim_activation_or_issuer_authority():
    assert "ACTIVE_NODE" not in BOOT
    assert "ENROLLMENT_ISSUER" not in BOOT
    assert "PENDING - HUMAN/ISSUER APPROVAL REQUIRED" in BOOT
