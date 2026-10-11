#Requires -Version 5.1

[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$Protect,
  [switch]$Harden,
  [switch]$InstallWatchdog,
  [ValidateSet('AutoFix', 'Alert')]
  [string]$WatchdogMode = 'AutoFix',
  [switch]$UninstallWatchdog,
  [switch]$UndoHardening,
  [switch]$UndoAll,
  [switch]$Yes,
  [switch]$NoRestorePoint,
  [string]$EnginePath,
  [switch]$AllowUnpinnedEngine,

  [Parameter(DontShow = $true)]
  [switch]$Watchdog,

  [Parameter(DontShow = $true)]
  [switch]$NoRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ShieldVersion = '1.0.0'

$script:EngineCommit = '3a5d5a90f1c90e2a99900d1fc9bd6884ee1f17fe'
$script:EngineSha256 = '4F02F58A42E7C907B9E30CF74F7702E3762ECDBDBF9242DC4DDC22356EE951F0'

$script:InstallDir = Join-Path $env:ProgramData 'GDIDShield'
$script:InstallEngineDir = Join-Path $script:InstallDir 'engine'
$script:StatePath = Join-Path $script:InstallDir 'state.json'
$script:LogPath = Join-Path $script:InstallDir 'gdid-shield.log'
$script:TaskName = 'GDID Shield Watchdog'
$script:ScriptFileName = 'gdid-shield.ps1'
$script:EngineFileName = 'degdid.ps1'

$script:PowerShell64 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$script:VerdictText = @{
  'ProtectedNoRealGdid'    = 'PROTECTED - no Microsoft device ID found on this PC, and the block is working.'
  'RealGdidPresent'        = 'NOT PROTECTED - this PC has a Microsoft device ID (GDID). Run "Remove and block".'
  'BlockDegraded'          = 'PARTLY PROTECTED - no ID found, but the block is not fully working. Run "Remove and block" to repair it.'
  'UnsupportedEnvironment' = 'CANNOT CHANGE THIS PC SAFELY - see the reason below.'
  'Error'                  = 'CHECK FAILED - the engine could not read everything it needs.'
}

function Write-Info([string]$Message) { Write-Host $Message }
function Write-Good([string]$Message) { Write-Host $Message -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Bad([string]$Message) { Write-Host $Message -ForegroundColor Red }

function Write-Section([string]$Title) {
  Write-Host ''
  Write-Host ('== {0} ==' -f $Title) -ForegroundColor Cyan
}

function Write-ShieldLog {

  param([string]$Message)
  try {
    if (-not (Test-Path -LiteralPath $script:InstallDir)) { return }
    $line = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8

    $lines = @(Get-Content -LiteralPath $script:LogPath -Encoding UTF8)
    if ($lines.Count -gt 600) {
      $lines[($lines.Count - 500)..($lines.Count - 1)] |
        Set-Content -LiteralPath $script:LogPath -Encoding UTF8
    }
  } catch {

  }
}

function Confirm-Action {
  param([string]$Question)
  if ($Yes -or $Watchdog) { return $true }
  $answer = Read-Host ('{0} [y/N]' -f $Question)
  return ($answer -match '^\s*(y|yes)\s*$')
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-ArgumentString {

  param([System.Collections.IDictionary]$Bound)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($key in $Bound.Keys) {
    $value = $Bound[$key]
    if ($value -is [System.Management.Automation.SwitchParameter]) {
      if ($value.IsPresent) { $parts.Add('-' + $key) }
    } elseif ($value -is [bool]) {
      if ($value) { $parts.Add('-' + $key) }
    } else {
      $text = [string]$value
      $parts.Add('-' + $key)
      $parts.Add('"' + $text.Replace('"', '\"') + '"')
    }
  }
  return ($parts -join ' ')
}

function Restart-Correctly {

  param([System.Collections.IDictionary]$Bound, [string]$ScriptPath)

  $isDesktop = ($PSVersionTable.PSEdition -ne 'Core')
  $is64 = [Environment]::Is64BitProcess
  $isAdmin = Test-IsAdministrator
  if ($isDesktop -and $is64 -and $isAdmin) { return $false }

  $exe = $script:PowerShell64
  if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {

    $exe = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
  }
  $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $ScriptPath, (ConvertTo-ArgumentString -Bound $Bound)

  $script:Relaunched = $true
  if (-not $isAdmin) {
    Write-Info 'GDID Shield needs administrator rights. Windows will ask you to allow it...'
    try {
      Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
      Write-Bad 'Administrator permission was not granted, so nothing was changed.'
    }
  } else {

    Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -Wait | Out-Null
  }
  return $true
}

function New-EmptyState {
  return [pscustomobject][ordered]@{
    ShieldVersion = $script:ShieldVersion
    Hardening     = @()
    HardenedAt    = $null
    Watchdog      = $null
    LastVerdict   = $null
    LastChecked   = $null
  }
}

function Read-ShieldState {
  if (-not (Test-Path -LiteralPath $script:StatePath)) { return New-EmptyState }
  try {
    $raw = Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8
    $state = $raw | ConvertFrom-Json
    $defaults = New-EmptyState
    foreach ($property in $defaults.PSObject.Properties) {
      if (-not ($state.PSObject.Properties.Name -contains $property.Name)) {
        $state | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
      }
    }
    if ($null -eq $state.Hardening) { $state.Hardening = @() }
    $state.Hardening = @($state.Hardening)
    return $state
  } catch {
    throw ('The GDID Shield state file is damaged: {0}. Fix or delete it before continuing.' -f $script:StatePath)
  }
}

function Save-ShieldState {
  param([object]$State)
  Initialize-InstallDir
  $State.ShieldVersion = $script:ShieldVersion
  $json = $State | ConvertTo-Json -Depth 6
  $temp = $script:StatePath + '.tmp'
  [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $temp -Destination $script:StatePath -Force
}

function Set-LockedAcl {

  param([string]$Path)
  $admins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
  $system = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
  $acl = New-Object System.Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  $acl.SetOwner($admins)
  $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
  $propagate = [System.Security.AccessControl.PropagationFlags]::None
  $allow = [System.Security.AccessControl.AccessControlType]::Allow
  $full = [System.Security.AccessControl.FileSystemRights]::FullControl
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($admins, $full, $inherit, $propagate, $allow)))
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($system, $full, $inherit, $propagate, $allow)))
  Set-Acl -LiteralPath $Path -AclObject $acl
}

function Initialize-InstallDir {
  if (-not (Test-Path -LiteralPath $script:InstallDir)) {
    New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
    Set-LockedAcl -Path $script:InstallDir
  }
  if (-not (Test-Path -LiteralPath $script:InstallEngineDir)) {
    New-Item -ItemType Directory -Path $script:InstallEngineDir -Force | Out-Null
  }
}

function Install-ShieldFiles {

  param([string]$SourceScript, [string]$SourceEngine)
  Initialize-InstallDir
  Set-LockedAcl -Path $script:InstallDir
  $targetScript = Join-Path $script:InstallDir $script:ScriptFileName
  $targetEngine = Join-Path $script:InstallEngineDir $script:EngineFileName
  if ($SourceScript -and ((Resolve-Path -LiteralPath $SourceScript).Path -ne $targetScript)) {
    Copy-Item -LiteralPath $SourceScript -Destination $targetScript -Force
  }
  if ($SourceEngine -and ((Resolve-Path -LiteralPath $SourceEngine).Path -ne $targetEngine)) {
    Copy-Item -LiteralPath $SourceEngine -Destination $targetEngine -Force
  }
  $licenseSource = Join-Path (Split-Path -Parent $SourceEngine) 'LICENSE-deGDID.txt'
  if (Test-Path -LiteralPath $licenseSource) {
    $licenseTarget = Join-Path $script:InstallEngineDir 'LICENSE-deGDID.txt'
    if ((Resolve-Path -LiteralPath $licenseSource).Path -ne $licenseTarget) {
      Copy-Item -LiteralPath $licenseSource -Destination $licenseTarget -Force
    }
  }

  [void](Assert-EngineHash -Path $targetEngine)
  return $targetScript
}

function Get-FileSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-EngineHash {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw ('Engine not found at {0}. Keep the "engine" folder next to gdid-shield.ps1.' -f $Path)
  }
  $actual = Get-FileSha256 -Path $Path
  if ($actual -ne $script:EngineSha256) {
    if ($AllowUnpinnedEngine) {
      Write-Warn ('WARNING: engine hash {0} does not match the pinned version. Running it because -AllowUnpinnedEngine was given.' -f $actual)
      return $Path
    }
    throw ("The engine file does not match the verified version, so it was NOT run.`n" +
      "  Expected SHA-256: {0}`n  Found SHA-256:    {1}`n" +
      'If you deliberately updated deGDID, review it, then run with -AllowUnpinnedEngine.') -f $script:EngineSha256, $actual
  }
  return $Path
}

function Resolve-EnginePath {
  param([string]$ScriptRoot)
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($EnginePath) { $candidates.Add($EnginePath) }
  if ($ScriptRoot) {
    $candidates.Add((Join-Path (Join-Path $ScriptRoot 'engine') $script:EngineFileName))
    $candidates.Add((Join-Path $ScriptRoot $script:EngineFileName))
  }
  $candidates.Add((Join-Path $script:InstallEngineDir $script:EngineFileName))
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Assert-EngineHash -Path (Resolve-Path -LiteralPath $candidate).Path)
    }
  }
  throw 'Could not find the deGDID engine (engine\degdid.ps1). Keep the folder structure from the download.'
}

function Invoke-Engine {

  param(
    [string]$Path,
    [string[]]$Arguments,
    [switch]$Live
  )
  [void](Assert-EngineHash -Path $Path)
  $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $Arguments
  $lines = New-Object System.Collections.Generic.List[string]

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $script:PowerShell64 @argList 2>&1 | ForEach-Object {
      $text = [string]$_
      $lines.Add($text)
      if ($Live) { Write-Host ('  | ' + $text) }
    }
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  return [pscustomobject]@{ ExitCode = $code; Output = $lines.ToArray() }
}

function ConvertFrom-EngineJson {

  param([string[]]$Lines)
  if ($null -eq $Lines -or $Lines.Count -eq 0) { return $null }
  $start = -1
  $end = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($start -lt 0 -and $Lines[$i].TrimStart().StartsWith('{')) { $start = $i }
    if ($Lines[$i].TrimEnd().EndsWith('}')) { $end = $i }
  }
  if ($start -lt 0 -or $end -lt $start) { return $null }
  try {
    return (($Lines[$start..$end] -join "`n") | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Get-PropertyValue {

  param([object]$Object, [string[]]$Path)
  $current = $Object
  foreach ($name in $Path) {
    if ($null -eq $current) { return $null }
    $property = $current.PSObject.Properties[$name]
    if ($null -eq $property) { return $null }
    $current = $property.Value
  }
  return $current
}

function Get-StatusSummary {

  param([object]$Report)
  if ($null -eq $Report) {
    return [pscustomobject]@{
      Verdict = 'Error'; Reasons = @('The engine did not return a readable report.')
      RealIdCount = $null; ResidualCount = $null; HostsBlock = $null
      FirewallHealth = $null; Build = $null; LabValidated = $null; Warnings = @()
    }
  }
  $verdict = [string](Get-PropertyValue $Report @('Verdict'))
  if (-not $verdict) { $verdict = 'Error' }
  $reasons = @()
  $reasons += @(Get-PropertyValue $Report @('Environment', 'UnsupportedReasons') | Where-Object { $_ })
  $reasons += @(Get-PropertyValue $Report @('Environment', 'TargetFailureReasons') | Where-Object { $_ })
  $errorText = Get-PropertyValue $Report @('Error')
  if ($errorText) { $reasons += [string]$errorText }
  $build = Get-PropertyValue $Report @('Environment', 'Build')
  $display = Get-PropertyValue $Report @('Environment', 'DisplayVersion')
  return [pscustomobject]@{
    Verdict        = $verdict
    Reasons        = @($reasons)
    RealIdCount    = Get-PropertyValue $Report @('ActiveStoreInventory', 'RealShapedCount')
    ResidualCount  = Get-PropertyValue $Report @('ResidualCaches', 'RealPuidCount')
    HostsBlock     = Get-PropertyValue $Report @('Hosts', 'Canonical')
    FirewallHealth = Get-PropertyValue $Report @('Firewall', 'Health')
    Build          = $(if ($build) { ('{0} {1}' -f $display, $build).Trim() } else { $null })
    LabValidated   = Get-PropertyValue $Report @('Environment', 'IsLabValidatedBuild')
    Warnings       = @(Get-PropertyValue $Report @('Environment', 'Warnings') | Where-Object { $_ })
  }
}

function Get-GdidStatus {
  param([string]$Engine)
  $result = Invoke-Engine -Path $Engine -Arguments @('-Status', '-Json')
  $report = ConvertFrom-EngineJson -Lines $result.Output
  $summary = Get-StatusSummary -Report $report
  try {
    $state = Read-ShieldState
    $state.LastVerdict = $summary.Verdict
    $state.LastChecked = (Get-Date).ToString('o')
    if (Test-Path -LiteralPath $script:InstallDir) { Save-ShieldState -State $state }
  } catch { }
  return $summary
}

function Show-StatusSummary {
  param([object]$Summary)
  $line = $script:VerdictText[$Summary.Verdict]
  if (-not $line) { $line = $Summary.Verdict }
  switch ($Summary.Verdict) {
    'ProtectedNoRealGdid' { Write-Good $line }
    'BlockDegraded' { Write-Warn $line }
    'UnsupportedEnvironment' { Write-Warn $line }
    default { Write-Bad $line }
  }
  if ($Summary.Build) {
    $validated = ''
    if ($Summary.LabValidated -eq $false) { $validated = ' (works, but not the exact build the engine was lab-tested on)' }
    Write-Info ('  Windows:           {0}{1}' -f $Summary.Build, $validated)
  }
  if ($null -ne $Summary.RealIdCount) { Write-Info ('  Device ID copies:  {0}' -f $Summary.RealIdCount) }
  if ($null -ne $Summary.ResidualCount) { Write-Info ('  Leftover caches:   {0}' -f $Summary.ResidualCount) }
  if ($null -ne $Summary.HostsBlock) {
    $hostsText = 'not active'
    if ($Summary.HostsBlock) { $hostsText = 'active' }
    Write-Info ('  Network block:     {0}' -f $hostsText)
  }
  if ($Summary.FirewallHealth) { Write-Info ('  Firewall backup:   {0}' -f $Summary.FirewallHealth) }
  foreach ($reason in $Summary.Reasons) { Write-Warn ('  Reason: {0}' -f $reason) }
  foreach ($warning in $Summary.Warnings) { Write-Warn ('  Note: {0}' -f $warning) }
}

function New-SafetyRestorePoint {
  $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
  $name = 'SystemRestorePointCreationFrequency'
  $previous = $null
  $hadValue = $false
  try {
    $item = Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    if ($null -ne $item) { $hadValue = $true; $previous = $item.$name }

    New-ItemProperty -LiteralPath $key -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
    Checkpoint-Computer -Description 'GDID Shield - before removing device ID' -RestorePointType 'MODIFY_SETTINGS' -WarningAction Stop
    Write-Good '  Restore point created.'
    return $true
  } catch {
    Write-Warn ('  Could not create a restore point: {0}' -f $_.Exception.Message)
    Write-Warn '  (Usually this means System Restore is turned off for drive C:.)'
    return $false
  } finally {
    try {
      if ($hadValue) {
        New-ItemProperty -LiteralPath $key -Name $name -Value $previous -PropertyType DWord -Force | Out-Null
      } else {
        Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
      }
    } catch { }
  }
}

function Show-ProtectWarning {
  Write-Section 'What "Remove and block" does'
  Write-Info '  1. Blocks the Microsoft servers that hand out device IDs (hosts file + firewall).'
  Write-Info '  2. Deletes every known copy of the ID from the registry and credential vault.'
  Write-Info '  3. Verifies the ID is gone and the block works.'
  Write-Host ''
  Write-Warn '  Expect these to stop working or ask you to sign in while protected:'
  Write-Warn '    - Signing in with a Microsoft account, Microsoft Store, Xbox app'
  Write-Warn '    - OneDrive (Microsoft account), Phone Link, cross-device features'
  Write-Warn '    - Possibly Windows Hello and passkeys tied to your Microsoft account'
  Write-Info '  Normal desktop use, web browsing, and Windows Update keep working.'
  Write-Info '  "Undo all" reverses this at any time (Windows then makes a NEW ID).'
}

function Invoke-Protect {
  param([string]$Engine, [string]$ScriptPath)

  Show-ProtectWarning
  Write-Host ''
  if (-not (Confirm-Action 'Remove the device ID and block it now?')) {
    Write-Info 'Cancelled. Nothing was changed.'
    return $false
  }

  Write-Section 'Step 1 of 4: checking this PC'
  $before = Get-GdidStatus -Engine $Engine
  Show-StatusSummary -Summary $before
  if ($before.Verdict -eq 'UnsupportedEnvironment') {
    Write-Bad 'The engine refuses to change this PC (see reason above), so nothing was changed.'
    Write-ShieldLog ('Protect refused: UnsupportedEnvironment')
    return $false
  }

  Write-Section 'Step 2 of 4: safety restore point'
  if ($NoRestorePoint) {
    Write-Info '  Skipped (-NoRestorePoint).'
  } elseif (-not (New-SafetyRestorePoint)) {
    if (-not (Confirm-Action 'Continue WITHOUT a restore point?')) {
      Write-Info 'Cancelled. Nothing was changed.'
      return $false
    }
  }

  Write-Section 'Step 3 of 4: removing and blocking (this can take a minute)'

  [void](Install-ShieldFiles -SourceScript $ScriptPath -SourceEngine $Engine)
  $installedEngine = Join-Path $script:InstallEngineDir $script:EngineFileName
  $run = Invoke-Engine -Path $installedEngine -Arguments @('-Protect') -Live
  Write-ShieldLog ('Protect engine exit code {0}' -f $run.ExitCode)

  Write-Section 'Step 4 of 4: verifying'
  $after = Get-GdidStatus -Engine $installedEngine
  Show-StatusSummary -Summary $after
  Write-ShieldLog ('Protect result verdict {0}' -f $after.Verdict)

  if ($after.Verdict -eq 'ProtectedNoRealGdid') {
    Write-Host ''
    Write-Good 'Done. The device ID is removed from this PC and blocked from coming back.'
    Write-Info 'Restart once, then run "Check status" again to confirm it stayed gone.'
    return $true
  }
  Write-Host ''
  Write-Bad ('Protection did not fully complete (engine exit code {0}).' -f $run.ExitCode)
  Write-Info 'Engine exit codes: 2 unsupported PC, 3 block check failed, 4 hosts file refused,'
  Write-Info '  5 removal check failed, 6 could not identify the signed-in user.'
  Write-Info 'Common fixes: restart and try again; make sure only ONE user is signed in;'
  Write-Info '  temporarily pause third-party antivirus that locks the hosts file.'
  return $false
}

function Invoke-Unblock {
  param([string]$Engine)
  $run = Invoke-Engine -Path $Engine -Arguments @('-Unblock') -Live
  Write-ShieldLog ('Unblock engine exit code {0}' -f $run.ExitCode)
  return ($run.ExitCode -eq 0)
}

function Get-TelemetryFloor {

  try {
    $edition = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID).EditionID
  } catch { $edition = '' }
  if ($edition -match 'Enterprise|Education|Server') { return 0 }
  return 1
}

function Get-HardeningSettings {
  param([int]$TelemetryValue = 1)
  $system = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
  return @(
    [pscustomobject]@{ Path = $system; Name = 'EnableActivityFeed'; Value = 0; Label = 'Activity history feed: off' }
    [pscustomobject]@{ Path = $system; Name = 'PublishUserActivities'; Value = 0; Label = 'Publish user activities: off' }
    [pscustomobject]@{ Path = $system; Name = 'UploadUserActivities'; Value = 0; Label = 'Upload user activities to Microsoft: off' }
    [pscustomobject]@{ Path = $system; Name = 'EnableCdp'; Value = 0; Label = 'Cross-device "continue experiences": off' }
    [pscustomobject]@{ Path = $system; Name = 'AllowCrossDeviceClipboard'; Value = 0; Label = 'Cloud clipboard sync: off' }
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Value = 1; Label = 'Advertising ID: off' }
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = $TelemetryValue; Label = 'Diagnostic data: lowest level this edition allows' }
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Value = 99; Label = 'Delivery Optimization cloud service: off (updates still download)' }
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Value = 0; Label = 'Microsoft Edge diagnostic data: off' }
  )
}

function Get-RegValueInfo {
  param([string]$Path, [string]$Name)
  $info = [pscustomobject]@{ KeyExists = $false; Exists = $false; Value = $null; Kind = $null }
  if (-not (Test-Path -LiteralPath $Path)) { return $info }
  $info.KeyExists = $true
  $key = Get-Item -LiteralPath $Path
  if ($key.GetValueNames() -contains $Name) {
    $info.Exists = $true
    $info.Value = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    $info.Kind = [string]$key.GetValueKind($Name)
  }
  return $info
}

function Set-RegValue {
  param([string]$Path, [string]$Name, [object]$Value, [string]$Kind = 'DWord')
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
  New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
}

function Remove-RegValue {
  param([string]$Path, [string]$Name)
  if (Test-Path -LiteralPath $Path) {
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
  }
}

function Remove-RegKeyIfEmpty {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $key = Get-Item -LiteralPath $Path
  if ($key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Test-SameRegistrySetting([object]$A, [object]$B) {
  return ($A.Path -eq $B.Path -and $A.Name -eq $B.Name)
}

function Invoke-Hardening {

  param([object]$State, [object[]]$Settings)
  $records = New-Object System.Collections.Generic.List[object]
  foreach ($record in @($State.Hardening)) { $records.Add($record) }
  $changed = 0
  foreach ($setting in $Settings) {
    $existing = $null
    foreach ($record in $records) {
      if (Test-SameRegistrySetting $record $setting) { $existing = $record; break }
    }
    $current = Get-RegValueInfo -Path $setting.Path -Name $setting.Name
    if ($null -eq $existing) {
      $records.Add([pscustomobject][ordered]@{
          Path          = $setting.Path
          Name          = $setting.Name
          Label         = $setting.Label
          AppliedValue  = $setting.Value
          HadValue      = $current.Exists
          PreviousValue = $current.Value
          PreviousKind  = $current.Kind
          CreatedKey    = (-not $current.KeyExists)
        })
    } else {
      $existing.AppliedValue = $setting.Value
    }
    $alreadySet = ($current.Exists -and $current.Kind -eq 'DWord' -and [int64]$current.Value -eq [int64]$setting.Value)
    if (-not $alreadySet) {
      Set-RegValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Kind 'DWord'
      $changed++
    }
    Write-Good ('  [on] {0}' -f $setting.Label)
  }
  $State.Hardening = $records.ToArray()
  $State.HardenedAt = (Get-Date).ToString('o')
  return $changed
}

function Undo-Hardening {

  param([object]$State)
  $skipped = New-Object System.Collections.Generic.List[object]
  foreach ($record in @($State.Hardening)) {
    $current = Get-RegValueInfo -Path $record.Path -Name $record.Name
    $stillOurs = ($current.Exists -and [string]$current.Value -eq [string]$record.AppliedValue)
    if (-not $stillOurs) {
      $skipped.Add($record)
      Write-Warn ('  [left alone, changed since] {0}' -f $record.Label)
      continue
    }
    if ($record.HadValue) {
      $kind = $record.PreviousKind
      if (-not $kind) { $kind = 'DWord' }
      Set-RegValue -Path $record.Path -Name $record.Name -Value $record.PreviousValue -Kind $kind
    } else {
      Remove-RegValue -Path $record.Path -Name $record.Name
    }
    Write-Good ('  [restored] {0}' -f $record.Label)
  }

  $createdPaths = @(@($State.Hardening) | Where-Object { $_.CreatedKey } | ForEach-Object { $_.Path } | Select-Object -Unique)
  foreach ($path in $createdPaths) { Remove-RegKeyIfEmpty -Path $path }
  $State.Hardening = @()
  $State.HardenedAt = $null
  return $skipped.ToArray()
}

function Invoke-HardeningInteractive {
  Write-Section 'Extra privacy hardening'
  Write-Info '  These policies turn off other Windows features that send device IDs to Microsoft.'
  Write-Info '  Every original value is saved, so "Undo" puts things back exactly.'
  Write-Warn '  Side effects: Edge will say "managed by your organization"; Phone Link,'
  Write-Warn '  cloud clipboard and Timeline-style activity sync stop. Restart to apply all.'
  Write-Host ''
  if (-not (Confirm-Action 'Apply extra hardening?')) {
    Write-Info 'Cancelled. Nothing was changed.'
    return
  }
  $state = Read-ShieldState
  $settings = Get-HardeningSettings -TelemetryValue (Get-TelemetryFloor)
  $changed = Invoke-Hardening -State $state -Settings $settings
  Save-ShieldState -State $state
  Write-ShieldLog ('Hardening applied, {0} values changed' -f $changed)
  Write-Good ('Hardening applied ({0} settings changed). Restart to make all of them take effect.' -f $changed)
}

function Invoke-UndoHardeningInteractive {
  $state = Read-ShieldState
  if (@($state.Hardening).Count -eq 0) {
    Write-Info 'No hardening is recorded, so there is nothing to undo.'
    return
  }
  Write-Section 'Undoing extra hardening'
  $skipped = @(Undo-Hardening -State $state)
  Save-ShieldState -State $state
  Write-ShieldLog ('Hardening undone, {0} left alone' -f $skipped.Count)
  if ($skipped.Count -gt 0) {
    Write-Warn ('{0} setting(s) were changed by something else after GDID Shield set them, so they were left as they are.' -f $skipped.Count)
  }
}

function Get-InteractiveUser {

  try {
    $user = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    if ($user) { return $user }
  } catch { }
  return ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
}

function Get-WatchdogTask {
  return (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue)
}

function Install-Watchdog {
  param([string]$ScriptPath, [string]$Engine, [string]$Mode)
  $installedScript = Install-ShieldFiles -SourceScript $ScriptPath -SourceEngine $Engine
  $user = Get-InteractiveUser
  $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Watchdog -WatchdogMode {1}' -f $installedScript, $Mode
  $action = New-ScheduledTaskAction -Execute $script:PowerShell64 -Argument $arguments
  $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
  $logon.Delay = 'PT3M'
  $daily = New-ScheduledTaskTrigger -Daily -At '12:00'

  $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger @($logon, $daily) -Principal $principal -Settings $settings -Description 'Checks that the Microsoft device ID (GDID) is still removed and blocked. Installed by GDID Shield.' -Force | Out-Null

  $state = Read-ShieldState
  $state.Watchdog = [pscustomobject]@{ Mode = $Mode; InstalledAt = (Get-Date).ToString('o') }
  Save-ShieldState -State $state
  Write-ShieldLog ('Watchdog installed, mode {0}' -f $Mode)
  Write-Good ('Watchdog installed ({0}). It checks 3 minutes after you sign in and daily at noon.' -f $Mode)
}

function Uninstall-Watchdog {
  if (Get-WatchdogTask) {
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
    Write-Good 'Watchdog removed.'
  } else {
    Write-Info 'Watchdog was not installed.'
  }
  try {
    $state = Read-ShieldState
    $state.Watchdog = $null
    if (Test-Path -LiteralPath $script:InstallDir) { Save-ShieldState -State $state }
  } catch { }
  Write-ShieldLog 'Watchdog removed'
}

function Show-Notification {
  param([string]$Title, [string]$Text, [ValidateSet('Info', 'Warning', 'Error')][string]$Icon = 'Info')
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Shield
    $notify.Visible = $true
    $notify.BalloonTipTitle = $Title
    $notify.BalloonTipText = $Text
    $notify.BalloonTipIcon = $Icon
    $notify.ShowBalloonTip(15000)
    Start-Sleep -Seconds 12
    $notify.Dispose()
  } catch { }
}

function Invoke-WatchdogRun {
  param([string]$ScriptPath, [string]$Mode)

  $expected = Join-Path $script:InstallDir $script:ScriptFileName
  if ($ScriptPath -ne $expected) {
    Write-ShieldLog 'Watchdog refused: not running from the install folder'
    return 1
  }
  $engine = Join-Path $script:InstallEngineDir $script:EngineFileName
  try {
    [void](Assert-EngineHash -Path $engine)
  } catch {
    Write-ShieldLog 'Watchdog refused: engine hash mismatch'
    Show-Notification -Title 'GDID Shield' -Text 'The engine file changed unexpectedly, so the check did not run. Open GDID Shield.' -Icon Error
    return 1
  }

  $summary = Get-GdidStatus -Engine $engine
  Write-ShieldLog ('Watchdog check verdict {0}' -f $summary.Verdict)
  if ($summary.Verdict -eq 'ProtectedNoRealGdid') { return 0 }

  $fixable = @('RealGdidPresent', 'BlockDegraded')
  if ($Mode -eq 'AutoFix' -and ($fixable -contains $summary.Verdict)) {
    $run = Invoke-Engine -Path $engine -Arguments @('-Protect')
    $after = Get-GdidStatus -Engine $engine
    Write-ShieldLog ('Watchdog auto-fix exit code {0}, verdict {1}' -f $run.ExitCode, $after.Verdict)
    if ($after.Verdict -eq 'ProtectedNoRealGdid') {
      Show-Notification -Title 'GDID Shield' -Text 'Your device ID protection had slipped (probably a Windows update). It was repaired automatically.' -Icon Info
      return 0
    }
    Show-Notification -Title 'GDID Shield' -Text 'Device ID protection is broken and could not be repaired automatically. Open GDID Shield.' -Icon Error
    return 1
  }

  Show-Notification -Title 'GDID Shield' -Text ('Device ID protection needs attention: {0}. Open GDID Shield.' -f $summary.Verdict) -Icon Warning
  return 1
}

function Invoke-UndoAll {
  param([string]$Engine)
  Write-Section 'Undo all'
  Write-Info '  This removes the network block, restores hardening settings, and removes the watchdog.'
  Write-Warn '  Windows will then request a NEW device ID the next time it is online.'
  Write-Warn '  (Your old ID does not come back; Microsoft issues a different one.)'
  Write-Host ''
  if (-not (Confirm-Action 'Undo everything GDID Shield did?')) {
    Write-Info 'Cancelled. Nothing was changed.'
    return
  }
  Uninstall-Watchdog
  Invoke-UndoHardeningInteractive
  Write-Section 'Removing the network block'
  if (Invoke-Unblock -Engine $Engine) {
    Write-Good 'Network block removed.'
  } else {
    Write-Bad 'The engine could not remove the network block cleanly (see output above).'
  }
  Write-Info 'Restart, then sign back in to your Microsoft account where needed.'
  Write-ShieldLog 'Undo all completed'
  if (Confirm-Action ('Also delete the GDID Shield folder ({0})?' -f $script:InstallDir)) {
    Remove-Item -LiteralPath $script:InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Good 'Folder deleted.'
  }
}

function Show-Header {
  $state = $null
  try { $state = Read-ShieldState } catch { }
  Write-Host ''
  Write-Host ('GDID Shield {0}  -  remove and block the Windows device ID' -f $script:ShieldVersion) -ForegroundColor Cyan
  Write-Host ('-' * 64)
  if ($state) {
    $last = 'never checked'
    if ($state.LastVerdict) { $last = '{0} ({1})' -f $state.LastVerdict, ([datetime]$state.LastChecked).ToString('MMM d, h:mm tt') }
    $watch = 'off'
    if (Get-WatchdogTask) {
      $watch = 'on'
      if ($state.Watchdog) { $watch = 'on, ' + $state.Watchdog.Mode }
    }
    $hard = 'off'
    if (@($state.Hardening).Count -gt 0) { $hard = 'on' }
    Write-Host ('Last check: {0}   Watchdog: {1}   Hardening: {2}' -f $last, $watch, $hard)
  }
}

function Show-Menu {
  Write-Host ''
  Write-Host '  1) Check status'
  Write-Host '  2) Remove and block the device ID      <- main step'
  Write-Host '  3) Turn on watchdog (keeps it removed)'
  Write-Host '  4) Extra privacy hardening (optional)'
  Write-Host '  5) Show full engine details (private - do not share)'
  Write-Host '  6) Undo hardening only'
  Write-Host '  7) Turn off watchdog'
  Write-Host '  8) Undo all'
  Write-Host '  9) View log'
  Write-Host '  0) Exit'
  Write-Host ''
  Write-Host '  Recommended first time: 1, then 2, restart, then 1 and 3.' -ForegroundColor DarkGray
}

function Start-Menu {
  param([string]$Engine, [string]$ScriptPath)
  while ($true) {
    Show-Header
    Show-Menu
    $choice = (Read-Host 'Choose').Trim()
    try {
      switch ($choice) {
        '1' { Write-Section 'Status'; Show-StatusSummary -Summary (Get-GdidStatus -Engine $Engine) }
        '2' { [void](Invoke-Protect -Engine $Engine -ScriptPath $ScriptPath) }
        '3' {
          Write-Section 'Watchdog'
          Write-Info '  AutoFix: repairs protection on its own and tells you.'
          Write-Info '  Alert:   only tells you, you fix it from this menu.'
          $mode = 'AutoFix'
          if ((Read-Host 'Type A for Alert-only, or press Enter for AutoFix').Trim() -match '^[aA]') { $mode = 'Alert' }
          Install-Watchdog -ScriptPath $ScriptPath -Engine $Engine -Mode $mode
        }
        '4' { Invoke-HardeningInteractive }
        '5' {
          Write-Section 'Full engine report (contains your private IDs - do not post it)'
          $run = Invoke-Engine -Path $Engine -Arguments @('-Status')
          $run.Output | ForEach-Object { Write-Host $_ }
        }
        '6' { Invoke-UndoHardeningInteractive }
        '7' { Uninstall-Watchdog }
        '8' { Invoke-UndoAll -Engine $Engine }
        '9' {
          if (Test-Path -LiteralPath $script:LogPath) {
            Get-Content -LiteralPath $script:LogPath -Tail 40 | ForEach-Object { Write-Host ('  ' + $_) }
          } else { Write-Info 'No log yet.' }
        }
        '0' { return }
        '' { }
        default { Write-Warn 'Pick a number from the menu.' }
      }
    } catch {
      Write-Bad ('Error: {0}' -f $_.Exception.Message)
    }
    if ($choice -ne '0') { [void](Read-Host 'Press Enter to continue') }
  }
}

function Invoke-ShieldMain {
  param([System.Collections.IDictionary]$Bound, [string]$ScriptPath, [string]$ScriptRoot)

  if ($Watchdog) {
    return (Invoke-WatchdogRun -ScriptPath $ScriptPath -Mode $WatchdogMode)
  }

  if (Restart-Correctly -Bound $Bound -ScriptPath $ScriptPath) { return 0 }

  try {
    $engine = Resolve-EnginePath -ScriptRoot $ScriptRoot
  } catch {
    Write-Bad $_.Exception.Message
    return 1
  }

  $anyAction = ($Status -or $Protect -or $Harden -or $InstallWatchdog -or $UninstallWatchdog -or $UndoHardening -or $UndoAll)
  if (-not $anyAction) {
    Start-Menu -Engine $engine -ScriptPath $ScriptPath
    return 0
  }

  $exitCode = 0
  try {
    if ($Status) {
      $summary = Get-GdidStatus -Engine $engine
      Show-StatusSummary -Summary $summary
      if ($summary.Verdict -ne 'ProtectedNoRealGdid') { $exitCode = 1 }
    }
    if ($Protect) {
      if (-not (Invoke-Protect -Engine $engine -ScriptPath $ScriptPath)) { $exitCode = 1 }
      if (Test-Path -LiteralPath (Join-Path $script:InstallEngineDir $script:EngineFileName)) {
        $engine = Join-Path $script:InstallEngineDir $script:EngineFileName
      }
    }
    if ($Harden) { Invoke-HardeningInteractive }
    if ($InstallWatchdog) { Install-Watchdog -ScriptPath $ScriptPath -Engine $engine -Mode $WatchdogMode }
    if ($UninstallWatchdog) { Uninstall-Watchdog }
    if ($UndoHardening) { Invoke-UndoHardeningInteractive }
    if ($UndoAll) { Invoke-UndoAll -Engine $engine }
  } catch {
    Write-Bad ('Error: {0}' -f $_.Exception.Message)
    $exitCode = 1
  }
  return $exitCode
}

$script:Relaunched = $false

if (-not $NoRun) {
  $results = @(Invoke-ShieldMain -Bound $PSBoundParameters -ScriptPath $PSCommandPath -ScriptRoot $PSScriptRoot)
  $code = 1
  if ($results.Count -gt 0 -and $results[-1] -is [int]) { $code = $results[-1] }
  if ($Watchdog) { exit $code }
  $anyAction = ($Status -or $Protect -or $Harden -or $InstallWatchdog -or $UninstallWatchdog -or $UndoHardening -or $UndoAll)
  if ($anyAction -and -not $Yes -and -not $script:Relaunched) {
    [void](Read-Host 'Press Enter to close')
  }
  exit $code
}
