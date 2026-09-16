$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$NodeRoot = 'C:\ProgramData\VIVEKA_NODE'
$IdentityDir = Join-Path $NodeRoot 'identity'
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
function Ensure-WindowsCapability([string]$Pattern) {
  $cap = Get-WindowsCapability -Online | Where-Object Name -Like $Pattern | Select-Object -First 1
  if (-not $cap) { throw "Windows capability unavailable: $Pattern" }
  if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
}
try {
  New-Item -ItemType Directory -Force -Path $NodeRoot,$IdentityDir | Out-Null
  Start-Transcript -Path $LogOut -Append | Out-Null
  $TranscriptStarted = $true
  Step 'OpenSSH server substrate'  Ensure-WindowsCapability 'OpenSSH.Server*'
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
  $cs = Get-CimInstance Win32_ComputerSystem
  $os = Get-CimInstance Win32_OperatingSystem
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object {
    [ordered]@{ name=$_.Name; driver_version=$_.DriverVersion; reported_adapter_ram_bytes=[uint64]$_.AdapterRAM }
  })
  $memory = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    [ordered]@{ manufacturer=$_.Manufacturer; part_number=(($_.PartNumber -as [string]).Trim()); capacity_bytes=[uint64]$_.Capacity; speed_mts=$_.Speed; form_factor=$_.FormFactor }
  })
  $request = [ordered]@{
    schema = 'viveka.node.enrollment_request.v1'
    state = 'PENDING'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    pairing_code = $PairingCode
    nonce_b64 = [Convert]::ToBase64String($NonceBytes)
    identity_algorithm = 'ECDSA_P256_CNG_BLOB_V1'
    identity_fingerprint = $Fingerprint
    public_key_blob_b64 = [Convert]::ToBase64String($PublicBytes)
    host = [ordered]@{
      hostname=$(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { $cs.Name }); vendor=$cs.Manufacturer; model=$cs.Model
      os=$os.Caption; os_version=$os.Version; architecture=$os.OSArchitecture
      cpu=$cpu.Name; total_memory_bytes=[uint64]$cs.TotalPhysicalMemory
      gpus=$gpus; memory_modules=$memory
    }
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