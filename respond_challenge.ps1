param(
  [Parameter(Mandatory=$true)][string]$ChallengeId,
  [Parameter(Mandatory=$true)][string]$ChallengeB64,
  [Parameter(Mandatory=$true)][string]$IdentityFingerprint,
  [Parameter(Mandatory=$true)][string]$ExpiresAtUtc
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$NodeRoot = 'C:\ProgramData\VIVEKA_NODE'
$IdentityDir = Join-Path $NodeRoot 'identity'
$PrivateIdentity = Join-Path $IdentityDir 'node_identity.dpapi'
$PublicIdentity = Join-Path $IdentityDir 'node_identity.cngpub'
$Out = Join-Path $NodeRoot 'VIVEKA_NODE_ENROLLMENT_RESPONSE.json'
$Utf8 = New-Object Text.UTF8Encoding($false)
if (-not (Test-Path $PrivateIdentity) -or -not (Test-Path $PublicIdentity)) {
  throw 'VIVEKA node identity is missing. Run the bootstrap first.'
}
$expires = [DateTimeOffset]::Parse($ExpiresAtUtc).ToUniversalTime()
if ([DateTimeOffset]::UtcNow -ge $expires) { throw 'Enrollment challenge has expired.' }
$pub = [IO.File]::ReadAllBytes($PublicIdentity)
$sha = [Security.Cryptography.SHA256]::Create()
try { $fpBytes = $sha.ComputeHash($pub) } finally { $sha.Dispose() }
$localFingerprint = 'SHA256:' + [Convert]::ToBase64String($fpBytes).TrimEnd('=')
if ($localFingerprint -ne $IdentityFingerprint) {
  throw "Challenge identity mismatch. Local=$localFingerprint Expected=$IdentityFingerprint"
}
$challenge = [Convert]::FromBase64String($ChallengeB64)
$protected = [IO.File]::ReadAllBytes($PrivateIdentity)
$privateBlob = [Security.Cryptography.ProtectedData]::Unprotect(
  $protected, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine
)
$key = [Security.Cryptography.CngKey]::Import(
  $privateBlob, [Security.Cryptography.CngKeyBlobFormat]::EccPrivateBlob
)
$ecdsa = New-Object Security.Cryptography.ECDsaCng($key)
try {
  $signature = $ecdsa.SignData($challenge, [Security.Cryptography.HashAlgorithmName]::SHA256)
} finally {
  $ecdsa.Dispose(); $key.Dispose()
}
$response = [ordered]@{
  schema = 'viveka.node.enrollment_response.v1'
  state = 'SIGNED'
  challenge_id = $ChallengeId
  identity_algorithm = 'ECDSA_P256_CNG_BLOB_V1'
  signature_algorithm = 'ECDSA_P256_SHA256_P1363'
  identity_fingerprint = $localFingerprint
  challenge_b64 = $ChallengeB64
  signature_b64 = [Convert]::ToBase64String($signature)
  signed_at_utc = [DateTime]::UtcNow.ToString('o')
}
$json = $response | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($Out, ($json + [Environment]::NewLine), $Utf8)
$DesktopOut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'VIVEKA_NODE_ENROLLMENT_RESPONSE.json'
[IO.File]::WriteAllText($DesktopOut, ($json + [Environment]::NewLine), $Utf8)
Write-Host 'VIVEKA enrollment challenge signed.'
Write-Host ('Identity: ' + $localFingerprint)
Write-Host ('Response: ' + $DesktopOut)
