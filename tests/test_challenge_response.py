from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESPONDER = (ROOT / 'respond_challenge.ps1').read_text(encoding='utf-8-sig') if (ROOT / 'respond_challenge.ps1').exists() else ''


def test_responder_is_bound_to_local_identity_and_challenge():
    assert "node_identity.dpapi" in RESPONDER
    assert "node_identity.cngpub" in RESPONDER
    assert "identity_fingerprint" in RESPONDER
    assert "challenge_b64" in RESPONDER
    assert "SignData" in RESPONDER
    assert "ECDSA_P256_CNG_BLOB_V1" in RESPONDER


def test_responder_never_exports_private_key_material():
    assert "private_key" not in RESPONDER.lower()
    assert "EccPrivateBlob" in RESPONDER
    assert "signature_b64" in RESPONDER
    assert "VIVEKA_NODE_ENROLLMENT_RESPONSE.json" in RESPONDER
