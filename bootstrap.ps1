$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NodeRoot = 'C:\ProgramData\VIVEKA_NODE'
$IdentityDir = Join-Path $NodeRoot 'identity'
$PrivateKey = Join-Path $IdentityDir 'node_ed25519'
$PublicKey = $PrivateKey + '.pub'
$Receipt = Join-Path $NodeRoot 'VIVEKA_NODE_ENROLLMENT_REQUEST.json'
$LogOut = Join-Path $NodeRoot 'bootstrap.log'
$Utf8 = New-Object Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $NodeRoot,$IdentityDir | Out-Null
Start-Transcript -Path $LogOut -Append | Out-Null
function Step([string]$Message) { Write-Host "`n=== $Message ===" }

function Ensure-WindowsCapability([string]$Pattern) {
  $cap = Get-WindowsCapability -Online | Where-Object Name -Like $Pattern | Select-Object -First 1
  if (-not $cap) { throw "Windows capability unavailable: $Pattern" }
  if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
}

Step 'OpenSSH substrate'
Ensure-WindowsCapability 'OpenSSH.Client*'
Ensure-WindowsCapability 'OpenSSH.Server*'
Set-Service sshd -StartupType Automatic
Start-Service sshd
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Step 'Node identity'
if (-not (Test-Path $PrivateKey)) {
  & ssh-keygen.exe -q -t ed25519 -N '' -C 'viveka-node' -f $PrivateKey
  if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed ($LASTEXITCODE)" }
}
if (-not (Test-Path $PublicKey)) { throw "Public key missing after identity setup: $PublicKey" }
& icacls.exe $IdentityDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to restrict identity ACL ($LASTEXITCODE)" }

$PublicKeyText = [IO.File]::ReadAllText($PublicKey).Trim()
$FingerprintLine = (& ssh-keygen.exe -lf $PublicKey -E sha256 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "ssh-keygen fingerprint failed ($LASTEXITCODE)" }
$Fingerprint = ($FingerprintLine -split '\s+')[1]

$NonceBytes = New-Object byte[] 16
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($NonceBytes)
$Nonce = -join ($NonceBytes | ForEach-Object { $_.ToString('x2') })
$PairMaterial = [Text.Encoding]::UTF8.GetBytes($PublicKeyText + '|' + $Nonce)
$PairHash = [Security.Cryptography.SHA256]::Create().ComputeHash($PairMaterial)
$PairHex = -join ($PairHash | ForEach-Object { $_.ToString('X2') })
$PairingCode = $PairHex.Substring(0,4) + '-' + $PairHex.Substring(4,4) + '-' + $PairHex.Substring(8,4)
Step 'Observed host facts'
$System = Get-CimInstance Win32_ComputerSystem
$Product = Get-CimInstance Win32_ComputerSystemProduct
$Os = Get-CimInstance Win32_OperatingSystem
$Cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$Memory = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
  [ordered]@{
    capacity_bytes = [int64]$_.Capacity
    manufacturer = [string]$_.Manufacturer
    part_number = ([string]$_.PartNumber).Trim()
    speed_mts = [int]$_.Speed
    form_factor = [int]$_.FormFactor
  }
})

$Request = [ordered]@{
  schema_version = 'viveka.enrollment_request.v1'
  state = 'PENDING'
  request_id = [guid]::NewGuid().ToString()
  created_at_utc = [DateTime]::UtcNow.ToString('o')
  pairing_code = $PairingCode
  nonce = $Nonce
  identity = [ordered]@{
    algorithm = 'ed25519'
    public_key = $PublicKeyText
    fingerprint = $Fingerprint
  }
  probe = [ordered]@{
    hostname = $env:COMPUTERNAME
    vendor = [string]$System.Manufacturer
    system_model = [string]$System.Model
    system_product = [string]$Product.Name
    os_caption = [string]$Os.Caption
    os_version = [string]$Os.Version
    architecture = [string]$Os.OSArchitecture
    cpu = [string]$Cpu.Name
    installed_memory_bytes = [int64]$System.TotalPhysicalMemory
    memory_modules = $Memory
  }
  authority = [ordered]@{
    enrollment = $false
    activation = $false
    issuer = $false
  }
}

$Json = $Request | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($Receipt, ($Json + [Environment]::NewLine), $Utf8)
$Desktop = [Environment]::GetFolderPath('Desktop')
$DesktopReceipt = Join-Path $Desktop 'VIVEKA_NODE_ENROLLMENT_REQUEST.json'
[IO.File]::WriteAllText($DesktopReceipt, ($Json + [Environment]::NewLine), $Utf8)

Step 'READY TO ENROLL'
Write-Host ('State: PENDING')
Write-Host ('Pairing code: ' + $PairingCode)
Write-Host ('Identity fingerprint: ' + $Fingerprint)
Write-Host ('Enrollment request: ' + $DesktopReceipt)
Write-Host ('Durable copy: ' + $Receipt)
Write-Host ('Log: ' + $LogOut)
Write-Host 'This bootstrap grants no VIVEKA access and contains no enrollment authority.'
Stop-Transcript | Out-Null
Read-Host 'VIVEKA NODE PREPARED. Press Enter to close'
