$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$NodeRoot = 'C:\ProgramData\VIVEKA_NODE'
$IdentityDir = Join-Path $NodeRoot 'identity'
$SubstrateDir = Join-Path $NodeRoot 'substrate'
$SubstrateManifest = Join-Path $NodeRoot 'substrate\manifest.json'
$PayloadManifestPath = Join-Path $PSScriptRoot 'payload_manifest.json'
$PrivateIdentity = Join-Path $IdentityDir 'node_identity.dpapi'
$PublicIdentity = Join-Path $IdentityDir 'node_identity.cngpub'
$Receipt = Join-Path $NodeRoot 'VIVEKA_NODE_ENROLLMENT_REQUEST.json'
$FailureReceipt = Join-Path $NodeRoot 'bootstrap_failure.json'
$LogOut = Join-Path $NodeRoot 'bootstrap.log'
$Utf8 = New-Object Text.UTF8Encoding($false)
$TranscriptStarted = $false
function Step([string]$Message) { Write-Host "`n=== $Message ===" }
function Write-JsonUtf8([string]$Path, $Object) {
  [IO.File]::WriteAllText($Path, (($Object | ConvertTo-Json -Depth 8) + [Environment]::NewLine), $Utf8)
}
function Ensure-BundledPython($Manifest) {
  if ($Manifest.schema -ne 'viveka.bootstrap.payload_manifest.v1') { throw 'Unsupported payload manifest schema' }
  $Zip = Join-Path $PSScriptRoot ([string]$Manifest.python.filename)
  if (-not (Test-Path $Zip)) { throw "Bundled Python ZIP missing: $Zip" }
  $Expected = ([string]$Manifest.python.sha256).ToUpperInvariant()
  $Actual = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($Actual -ne $Expected) { throw "Bundled Python ZIP hash mismatch: $Actual" }
  $Version = [string]$Manifest.python.version
  $PythonBase = Join-Path $NodeRoot 'substrate\python'
  $PythonRoot = Join-Path $PythonBase $Version
  $PythonExe = Join-Path $PythonRoot 'python.exe'
  New-Item -ItemType Directory -Force -Path $PythonBase | Out-Null
  if (-not (Test-Path $PythonExe)) {
    $Stage = $PythonRoot + '.staging-' + [guid]::NewGuid().ToString('N')
    try {
      Expand-Archive -LiteralPath $Zip -DestinationPath $Stage -Force
      $StageExe = Join-Path $Stage 'python.exe'
      if (-not (Test-Path $StageExe)) { throw 'Embedded Python archive has no python.exe' }
      $StageVersion = & $StageExe -c 'import json,sys; print(json.dumps(list(sys.version_info[:3])))'
      if ($LASTEXITCODE -ne 0) { throw "Embedded Python version probe failed ($LASTEXITCODE)" }
      $Parts = $StageVersion | ConvertFrom-Json
      if (($Parts -join '.') -ne $Version) { throw "Embedded Python version mismatch: $($Parts -join '.')" }
      if (Test-Path $PythonRoot) { Remove-Item $PythonRoot -Recurse -Force }
      Move-Item -LiteralPath $Stage -Destination $PythonRoot
    } finally {
      if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
  }
  $Readback = & $PythonExe -c 'import json,sys; print(json.dumps(list(sys.version_info[:3])))'
  if ($LASTEXITCODE -ne 0) { throw "Embedded Python read-back failed ($LASTEXITCODE)" }
  $ReadbackParts = $Readback | ConvertFrom-Json
  if (($ReadbackParts -join '.') -ne $Version) { throw "Installed Python version mismatch: $($ReadbackParts -join '.')" }
  return [ordered]@{ source='BUNDLED_EMBEDDED'; version=$Version; executable=$PythonExe; payload_sha256=$Expected }
}

function Ensure-OpenSSHServer {
  $existing = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
  if ($existing) { return 'EXISTING' }

  $cap = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Server*' | Select-Object -First 1
  if ($cap) {
    if ($cap.State -ne 'Installed') {
      try { Add-WindowsCapability -Online -Name $cap.Name | Out-Null } catch { Write-Host ('FoD install failed, using bundled MSI: ' + $_.Exception.Message) }
    }
    $existing = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
    if ($existing) { return 'FOD' }
  }

  $msi = Join-Path $PSScriptRoot 'OpenSSH-Win64-v9.8.3.0.msi'
  if (-not (Test-Path $msi)) { throw "Bundled OpenSSH MSI missing: $msi" }
  $expected = 'C8A8C7E21136A099665C2FAD9ACCB41152D129466B719EA71678BAB665E03389'
  $actual = (Get-FileHash $msi -Algorithm SHA256).Hash.ToUpperInvariant()
  if ($actual -ne $expected) { throw "Bundled OpenSSH MSI hash mismatch: $actual" }
  $sig = Get-AuthenticodeSignature $msi
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike '*Microsoft Corporation*') {
    throw "Bundled OpenSSH MSI signature is not valid Microsoft Corporation Authenticode"
  }
  $msiLog = Join-Path $NodeRoot 'openssh-msi.log'
  $args = @('/i', $msi, 'ADDLOCAL=Server', '/qn', '/norestart', '/L*v', $msiLog)
  $proc = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
  if ($proc.ExitCode -notin 0,3010) { throw "Bundled OpenSSH MSI failed ($($proc.ExitCode)); log: $msiLog" }
  $existing = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
  if (-not $existing) {
    $installScript = 'C:\Program Files\OpenSSH\install-sshd.ps1'
    if (Test-Path $installScript) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScript | Out-Null }
    $existing = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
  }
  if (-not $existing) { throw 'OpenSSH MSI completed but sshd service still does not exist' }
  return 'BUNDLED_MSI'
}
try {
  New-Item -ItemType Directory -Force -Path $NodeRoot,$IdentityDir,$SubstrateDir | Out-Null
  Start-Transcript -Path $LogOut -Append | Out-Null
  $TranscriptStarted = $true
  Step 'OpenSSH server substrate'
  $OpenSSHSource = Ensure-OpenSSHServer
  Write-Host ('OpenSSH source: ' + $OpenSSHSource)
  Step 'Embedded Python substrate'
  $PayloadManifest = Get-Content -Raw -Encoding UTF8 $PayloadManifestPath | ConvertFrom-Json
  $PythonReceipt = Ensure-BundledPython $PayloadManifest
  Write-Host ('Python source/version: ' + $PythonReceipt.source + ' / ' + $PythonReceipt.version)
  $SubstrateReceipt = [ordered]@{ schema='viveka.node.substrate.v1'; python=$PythonReceipt; openssh=[ordered]@{ source=$OpenSSHSource }; written_at_utc=[DateTime]::UtcNow.ToString('o') }
  Write-JsonUtf8 $SubstrateManifest $SubstrateReceipt
  $SubstrateReadback = Get-Content -Raw -Encoding UTF8 $SubstrateManifest | ConvertFrom-Json
  if ($SubstrateReadback.schema -ne 'viveka.node.substrate.v1' -or $SubstrateReadback.python.version -ne $PythonReceipt.version) { throw 'Substrate manifest read-back mismatch' }
  $sshd = Get-Service -Name 'sshd' -ErrorAction Stop
  Set-Service sshd -StartupType Automatic
  Start-Service sshd
  if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
  }
  Step 'Node enrollment identity'
  if (-not (Test-Path $PrivateIdentity) -or -not (Test-Path $PublicIdentity)) {
    $keyParams = New-Object Security.Cryptography.CngKeyCreationParameters
    $keyParams.ExportPolicy = [Security.Cryptography.CngExportPolicies]::AllowPlaintextExport
    $keyParams.KeyUsage = [Security.Cryptography.CngKeyUsages]::Signing
    $keyParams.Provider = [Security.Cryptography.CngProvider]::MicrosoftSoftwareKeyStorageProvider
    $keyName = 'viveka-bootstrap-' + [guid]::NewGuid().ToString('N')
    $key = [Security.Cryptography.CngKey]::Create([Security.Cryptography.CngAlgorithm]::ECDsaP256, $keyName, $keyParams)
    try {
      $pub = $key.Export([Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
      $priv = $key.Export([Security.Cryptography.CngKeyBlobFormat]::EccPrivateBlob)
    } finally { try { $key.Delete() } catch { }; $key.Dispose() }
    $protected = [Security.Cryptography.ProtectedData]::Protect($priv, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [IO.File]::WriteAllBytes($PrivateIdentity, $protected)
    [IO.File]::WriteAllBytes($PublicIdentity, $pub)
  }
  & icacls.exe $IdentityDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to restrict identity ACL ($LASTEXITCODE)" }
  $PublicBytes = [IO.File]::ReadAllBytes($PublicIdentity)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $FingerprintBytes = $sha.ComputeHash($PublicBytes) } finally { $sha.Dispose() }
  $Fingerprint = 'SHA256:' + [Convert]::ToBase64String($FingerprintBytes).TrimEnd('=')
  $NonceBytes = New-Object byte[] 16
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($NonceBytes)
  $PairMaterial = New-Object byte[] ($PublicBytes.Length + $NonceBytes.Length)
  [Array]::Copy($PublicBytes,0,$PairMaterial,0,$PublicBytes.Length)
  [Array]::Copy($NonceBytes,0,$PairMaterial,$PublicBytes.Length,$NonceBytes.Length)
  $sha2 = [Security.Cryptography.SHA256]::Create()
  try { $PairHash = $sha2.ComputeHash($PairMaterial) } finally { $sha2.Dispose() }
  $PairHex = (($PairHash[0..7] | ForEach-Object { $_.ToString('X2') }) -join '')
  $PairingCode = 'VIVEKA-' + $PairHex.Substring(0,4) + '-' + $PairHex.Substring(4,4) + '-' + $PairHex.Substring(8,4) + '-' + $PairHex.Substring(12,4)
  Step 'Observed host facts'
  $HostProfilePath = Join-Path $PSScriptRoot 'emit_host_profile.ps1'
  $profile = & $HostProfilePath | ConvertFrom-Json
  if ($profile.schema -ne 'viveka.node.host_profile.v1') { throw 'Invalid host profile schema' }
  $request = [ordered]@{
    schema = 'viveka.node.enrollment_request.v1'
    state = 'PENDING'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    pairing_code = $PairingCode
    nonce_b64 = [Convert]::ToBase64String($NonceBytes)
    identity_algorithm = 'ECDSA_P256_CNG_BLOB_V1'
    identity_fingerprint = $Fingerprint
    public_key_blob_b64 = [Convert]::ToBase64String($PublicBytes)
    host_identity = $profile.host_identity
    host = $profile.host
    authority = [ordered]@{
      enrolled=$false; activated=$false; enrollment_issuer=$false
      note='Public bootstrap creates no VIVEKA authority. Approval must occur on an authorized issuer.'
    }
  }
  Write-JsonUtf8 $Receipt $request
  $DesktopReceipt = Join-Path ([Environment]::GetFolderPath('Desktop')) 'VIVEKA_NODE_ENROLLMENT_REQUEST.json'
  Write-JsonUtf8 $DesktopReceipt $request
  Remove-Item $FailureReceipt -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'VIVEKA_NODE_BOOTSTRAP_FAILED.json') -Force -ErrorAction SilentlyContinue
  Step 'PENDING - HUMAN/ISSUER APPROVAL REQUIRED'
  Write-Host ('Pairing code: ' + $PairingCode)
  Write-Host ('Identity: ' + $Fingerprint)
  Write-Host ('Receipt: ' + $DesktopReceipt)
  Write-Host ('Log: ' + $LogOut)
  Write-Host 'PUBLIC DOWNLOAD != ENROLLMENT != ACTIVATION != CAPABILITY ATTESTATION'
  if ($TranscriptStarted) { Stop-Transcript | Out-Null; $TranscriptStarted=$false }
  Read-Host 'VIVEKA NODE PREPARED. Press Enter to close'
}catch {
  $message = $_.Exception.Message
  $failure = [ordered]@{
    schema='viveka.node.bootstrap_failure.v1'
    state='FAILED'
    failed_at_utc=[DateTime]::UtcNow.ToString('o')
    message=$message
    script_line=$_.InvocationInfo.ScriptLineNumber
    log=$LogOut
  }
  try {
    New-Item -ItemType Directory -Force -Path $NodeRoot | Out-Null
    Write-JsonUtf8 $FailureReceipt $failure
    $DesktopFailure = Join-Path ([Environment]::GetFolderPath('Desktop')) 'VIVEKA_NODE_BOOTSTRAP_FAILED.json'
    Write-JsonUtf8 $DesktopFailure $failure
  } catch { }
  Write-Host "`nVIVEKA NODE BOOTSTRAP FAILED" -ForegroundColor Red
  Write-Host $message -ForegroundColor Red
  Write-Host ('Failure receipt: ' + $FailureReceipt)
  Write-Host ('Log: ' + $LogOut)
  if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch { }; $TranscriptStarted=$false }
  Read-Host 'Bootstrap failed. Press Enter to close'
  exit 1
}