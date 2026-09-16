$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out = Join-Path $Here 'VIVEKA_NODE_SETUP.exe'
$Sed = Join-Path $Here 'viveka_node_setup.sed'
$lines = @(
'[Version]','Class=IEXPRESS','SEDVersion=3',
'[Options]','PackagePurpose=InstallApp','ShowInstallProgramWindow=1','HideExtractAnimation=0',
'UseLongFileName=1','InsideCompressed=0','CAB_FixedSize=0','CAB_ResvCodeSigning=0',
'RebootMode=N','InstallPrompt=%InstallPrompt%','DisplayLicense=','FinishMessage=',
'TargetName=%TargetName%','FriendlyName=%FriendlyName%','AppLaunched=%AppLaunched%',
'PostInstallCmd=<None>','AdminQuietInstCmd=','UserQuietInstCmd=','SourceFiles=SourceFiles',
'[Strings]','InstallPrompt=Prepare this computer for VIVEKA enrollment?',
'FriendlyName=VIVEKA NODE BOOTSTRAP','AppLaunched=launch.cmd',('TargetName=' + $Out),
'FILE0=launch.cmd','FILE1=bootstrap.ps1','[SourceFiles]',('SourceFiles0=' + $Here + '\'),
'[SourceFiles0]','%FILE0%=','%FILE1%='
)
[IO.File]::WriteAllLines($Sed,$lines,(New-Object Text.ASCIIEncoding))
if (Test-Path $Out) { Remove-Item $Out -Force }
$p = Start-Process "$env:SystemRoot\System32\iexpress.exe" -ArgumentList @('/N','/Q',$Sed) -Wait -PassThru
if ($p.ExitCode -ne 0 -or -not (Test-Path $Out)) { throw "IExpress build failed ($($p.ExitCode))" }
Get-Item $Out | Select-Object FullName,Length
Get-FileHash $Out -Algorithm SHA256
