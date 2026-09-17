$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$cs = Get-CimInstance Win32_ComputerSystem
$csp = Get-CimInstance Win32_ComputerSystemProduct
$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object {
  [ordered]@{
    name = $_.Name
    driver_version = $_.DriverVersion
    reported_adapter_ram_bytes = [uint64]$_.AdapterRAM
  }
})
$memory = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
  [ordered]@{
    manufacturer = $_.Manufacturer
    part_number = (($_.PartNumber -as [string]).Trim())
    capacity_bytes = [uint64]$_.Capacity
    speed_mts = $_.Speed
    form_factor = $_.FormFactor
  }
})
$profile = [ordered]@{
  schema = 'viveka.node.host_profile.v1'
  observed_at_utc = [DateTime]::UtcNow.ToString('o')
  host_identity = [ordered]@{
    system_uuid = [string]$csp.UUID
    baseboard = [ordered]@{
      manufacturer = [string]$board.Manufacturer
      product = [string]$board.Product
      serial_number = [string]$board.SerialNumber
    }
  }
  host = [ordered]@{
    hostname = $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { $cs.Name })
    vendor = $cs.Manufacturer
    model = $cs.Model
    os = $os.Caption
    os_version = $os.Version
    architecture = $os.OSArchitecture
    cpu = $cpu.Name
    total_memory_bytes = [uint64]$cs.TotalPhysicalMemory
    gpus = $gpus
    memory_modules = $memory
  }
}
$profile | ConvertTo-Json -Depth 8 -Compress
