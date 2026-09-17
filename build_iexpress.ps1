$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out = Join-Path $Here 'VIVEKA_NODE_SETUP.exe'
$Sed = Join-Path $Here 'viveka_node_setup.sed'
$ManifestPath = Join-Path $Here 'payload_manifest.json'
$Manifest = Get-Content -Raw -Encoding UTF8 $ManifestPath | ConvertFrom-Json
if ($Manifest.schema -ne 'viveka.bootstrap.payload_manifest.v1') { throw 'Unsupported payload manifest schema' }

function Resolve-Payload($Entry) {
  $Path = Join-Path $Here ([string]$Entry.filename)
  if (-not (Test-Path $Path)) {
    Invoke-WebRequest -UseBasicParsing -Uri ([string]$Entry.url) -OutFile $Path
  }
  $Actual = (Get-FileHash $Path -Algorithm SHA256).Hash.ToUpperInvariant()
  $Expected = ([string]$Entry.sha256).ToUpperInvariant()
  if ($Actual -ne $Expected) { throw "Payload hash mismatch for $($Entry.filename): $Actual" }
  return $Path
}

$Msi = Resolve-Payload $Manifest.openssh
$PythonZip = Resolve-Payload $Manifest.python
$sig = Get-AuthenticodeSignature $Msi
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike '*Microsoft Corporation*') {
  throw 'OpenSSH MSI Authenticode signature is not valid Microsoft Corporation'
}
$lines = @(
'[Version]','Class=IEXPRESS','SEDVersion=3',
'[Options]','PackagePurpose=InstallApp','ShowInstallProgramWindow=1','HideExtractAnimation=0',
'UseLongFileName=1','InsideCompressed=0','CAB_FixedSize=0','CAB_ResvCodeSigning=0',
'RebootMode=N','InstallPrompt=%InstallPrompt%','DisplayLicense=','FinishMessage=',
'TargetName=%TargetName%','FriendlyName=%FriendlyName%','AppLaunched=%AppLaunched%',
'PostInstallCmd=<None>','AdminQuietInstCmd=','UserQuietInstCmd=','SourceFiles=SourceFiles',
'[Strings]','InstallPrompt=Prepare this computer for VIVEKA enrollment?',
'FriendlyName=VIVEKA NODE BOOTSTRAP','AppLaunched=launch.cmd',('TargetName=' + $Out),
'FILE0=launch.cmd','FILE1=bootstrap.ps1',
('FILE2=' + [string]$Manifest.openssh.filename),
('FILE3=' + [string]$Manifest.python.filename),
'FILE4=payload_manifest.json','FILE5=emit_host_profile.ps1','FILE6=authorize_control_plane.ps1','[SourceFiles]',('SourceFiles0=' + $Here + '\'),
'[SourceFiles0]','%FILE0%=','%FILE1%=','%FILE2%=','%FILE3%=','%FILE4%=','%FILE5%=','%FILE6%='
)
[IO.File]::WriteAllLines($Sed,$lines,(New-Object Text.ASCIIEncoding))
if (Test-Path $Out) { Remove-Item $Out -Force }
$p = Start-Process "$env:SystemRoot\System32\iexpress.exe" -ArgumentList @('/N','/Q',$Sed) -Wait -PassThru
if ($p.ExitCode -ne 0 -or -not (Test-Path $Out)) { throw "IExpress build failed ($($p.ExitCode))" }
Get-Item $Out | Select-Object FullName,Length
Get-FileHash $Out -Algorithm SHA256
