import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOT = (ROOT / "bootstrap.ps1").read_text(encoding="utf-8")
MANIFEST = json.loads((ROOT / "payload_manifest.json").read_text(encoding="utf-8"))


def test_bootstrap_uses_only_bundled_python():
    assert "function Ensure-BundledPython" in BOOT
    assert "winget" not in BOOT.lower()
    assert "Get-Command python" not in BOOT
    assert "Manifest.python.sha256" in BOOT
    assert "substrate\\python" in BOOT
    assert "Expand-Archive" in BOOT
    assert "& $PythonExe -c" in BOOT
    assert MANIFEST["python"]["sha256"] == "D1F04D990AEE1253D8569E8E5104E30FA9F5FA830899F14843448872D936A2CF"


def test_bootstrap_persists_and_reads_back_substrate_manifest():
    assert "viveka.node.substrate.v1" in BOOT
    assert "substrate\\manifest.json" in BOOT
    assert "BUNDLED_EMBEDDED" in BOOT
    assert "ConvertFrom-Json" in BOOT
