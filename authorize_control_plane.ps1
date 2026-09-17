param(
  [Parameter(Mandatory=$true)][string]$PublicKeyPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $PublicKeyPath)) {
  throw "Public key file not found: $PublicKeyPath"
}
$key = (Get-Content -LiteralPath $PublicKeyPath -Raw -Encoding UTF8).Trim()
if ($key -notmatch '^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa)\s+[A-Za-z0-9+/=]+(?:\s+.*)?$') {
  throw 'Unsupported or malformed OpenSSH public key'
}

$sshDir = 'C:\ProgramData\ssh'
$dest = Join-Path $sshDir 'administrators_authorized_keys'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$existingKeys = New-Object 'System.Collections.Generic.List[string]'
if (Test-Path -LiteralPath $dest) {
  foreach ($line in (Get-Content -LiteralPath $dest -Encoding UTF8)) {
    $candidate = ([string]$line).Trim()
    if ($candidate -and -not $existingKeys.Contains($candidate)) {
      $existingKeys.Add($candidate)
    }
  }
}
if (-not $existingKeys.Contains($key)) { $existingKeys.Add($key) }
$utf8 = New-Object Text.UTF8Encoding($false)
$content = ($existingKeys -join [Environment]::NewLine) + [Environment]::NewLine
$tmp = $dest + '.tmp-' + [guid]::NewGuid().ToString('N')
try {
  [IO.File]::WriteAllText($tmp, $content, $utf8)
  Move-Item -LiteralPath $tmp -Destination $dest -Force
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

& icacls.exe $dest /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Failed to restrict administrators_authorized_keys ACL ($LASTEXITCODE)"
}
$readback = (Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
if ($readback -ne $content) {
  throw 'Control-plane public key read-back mismatch'
}

$sshKeygen = (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue).Source
if (-not $sshKeygen) {
  $candidate = 'C:\Program Files\OpenSSH\ssh-keygen.exe'
  if (Test-Path $candidate) { $sshKeygen = $candidate }
}
if (-not $sshKeygen) { throw 'ssh-keygen.exe not found for fingerprint verification' }

$fingerprint = & $sshKeygen -lf $dest -E sha256
if ($LASTEXITCODE -ne 0 -or -not $fingerprint) {
  throw 'Failed to compute installed control-plane key fingerprint'
}
Write-Host 'VIVEKA control-plane SSH public key authorized.'
Write-Host ('Authorized keys: ' + $dest)
Write-Host ('Fingerprint: ' + ($fingerprint -join ' | '))
