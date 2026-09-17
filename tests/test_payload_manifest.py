import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_payload_manifest_pins_exact_python_and_openssh():
    manifest = json.loads((ROOT / "payload_manifest.json").read_text(encoding="utf-8"))
    assert manifest["schema"] == "viveka.bootstrap.payload_manifest.v1"
    assert manifest["python"]["version"] == "3.13.15"
    assert manifest["python"]["filename"] == "python-3.13.15-embed-amd64.zip"
    assert manifest["python"]["sha256"] == "D1F04D990AEE1253D8569E8E5104E30FA9F5FA830899F14843448872D936A2CF"
    assert manifest["openssh"]["version"] == "9.8.3.0p2-Preview"
    assert manifest["openssh"]["sha256"] == "C8A8C7E21136A099665C2FAD9ACCB41152D129466B719EA71678BAB665E03389"


def test_build_script_reads_manifest_and_packages_python():
    text = (ROOT / "build_iexpress.ps1").read_text(encoding="utf-8")
    assert "payload_manifest.json" in text
    assert "FILE3=" in text
    assert "%FILE3%=" in text
