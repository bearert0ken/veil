#Requires -Version 5.1

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'Status')][switch]$Status,
    [Parameter(ParameterSetName = 'Apply')][switch]$Apply,
    [Parameter(ParameterSetName = 'Undo')][switch]$Undo,
    [Parameter(ParameterSetName = 'Apply')]
    [ValidateSet('Safe', 'Balanced', 'Aggressive')]
    [string]$Tier = 'Safe',
    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Undo')]
    [string[]]$Id,
    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Undo')]
    [switch]$DryRun,
    [Parameter(ParameterSetName = 'Apply')][switch]$NoRestorePoint,
    [switch]$Yes,
    [string]$CatalogPath,
    [Parameter(DontShow = $true)][switch]$NoRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppName     = 'Veil'
$script:Version     = '1.0.1'
$script:TierOrder   = @{ Safe = 0; Balanced = 1; Aggressive = 2 }
$script:StateDir    = Join-Path $env:ProgramData 'Veil'
$script:JournalPath = Join-Path $script:StateDir 'journal.json'
$script:LogPath     = Join-Path $script:StateDir 'veil.log'
$script:ModulesDir  = $null
$script:Relaunched  = $false

function Say  { param([string]$Text, [string]$Color = 'Gray') Write-Host $Text -ForegroundColor $Color }
function Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text ==") -ForegroundColor Cyan }

function Write-Log {
    param([string]$Message)
    try {
        if (-not (Test-Path -LiteralPath $script:StateDir)) { return }
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value ('{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message)
    } catch { }
}

function Confirm-Action {
    param([string]$Question)
    if ($Yes) { return $true }
    return ((Read-Host ('{0} [y/N]' -f $Question)) -match '^\s*(y|yes)\s*$')
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-Catalog {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Catalog not found: $Path" }
    $data = Import-PowerShellDataFile -LiteralPath $Path
    if (-not $data.ContainsKey('Tweaks')) { throw "Catalog has no 'Tweaks' entry: $Path" }
    $seen = @{}
    foreach ($tweak in $data.Tweaks) {
        foreach ($field in 'Id', 'Name', 'Area', 'Tier', 'Actions') {
            if (-not $tweak.ContainsKey($field)) { throw "Tweak '$($tweak.Id)' is missing '$field'." }
        }
        if (-not $script:TierOrder.ContainsKey($tweak.Tier)) { throw "Tweak '$($tweak.Id)' has unknown tier '$($tweak.Tier)'." }
        if ($seen.ContainsKey($tweak.Id)) { throw "Duplicate tweak Id '$($tweak.Id)'." }
        $seen[$tweak.Id] = $true
        foreach ($action in $tweak.Actions) {
            if (-not $action.ContainsKey('Kind')) { throw "Tweak '$($tweak.Id)' has an action with no 'Kind'." }
            if ($action.Kind -notin 'Registry', 'Service', 'ScheduledTask', 'Appx', 'Command') {
                throw "Tweak '$($tweak.Id)' has unknown action kind '$($action.Kind)'."
            }
        }
    }
    return $data.Tweaks
}

function Select-Tweaks {

    param([object[]]$All, [string[]]$Id, [string]$Tier)
    if ($Id) {
        $byId = @{}
        foreach ($t in $All) { $byId[$t.Id] = $t }
        $chosen = foreach ($wanted in $Id) {
            if (-not $byId.ContainsKey($wanted)) { throw "No tweak with Id '$wanted'. See TWEAKS.md." }
            $byId[$wanted]
        }
        return @($chosen)
    }
    $ceiling = $script:TierOrder[$Tier]
    return @($All | Where-Object { $script:TierOrder[$_.Tier] -le $ceiling })
}

function Get-TelemetryFloor {

    try {
        $edition = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
    } catch { $edition = '' }
    if ($edition -match 'Enterprise|Education|Server') { return 0 }
    return 1
}

function Resolve-ActionValue {
    param([object]$Value)
    if ($Value -is [string] -and $Value -eq '@TelemetryFloor') { return (Get-TelemetryFloor) }
    return $Value
}

function ConvertFrom-DsregStatus {

    param([string[]]$Lines)
    $read = {
        param($key)
        foreach ($line in $Lines) {
            if ($line -match ('^\s*{0}\s*:\s*(\S+)' -f [regex]::Escape($key))) { return $Matches[1] }
        }
        return $null
    }
    $isYes = { param($v) [bool]($v -and $v.Trim().ToUpperInvariant() -eq 'YES') }
    return [pscustomobject]@{
        EntraJoined     = (& $isYes (& $read 'AzureAdJoined'))
        WorkplaceJoined = (& $isYes (& $read 'WorkplaceJoined'))
        DomainJoined    = (& $isYes (& $read 'DomainJoined'))
    }
}

function Get-ManagementState {
    $entra = $false; $workplace = $false; $domain = $false; $mdm = $false; $details = @()
    try {
        $out = & (Join-Path $env:SystemRoot 'System32\dsregcmd.exe') /status 2>$null
        if ($out) {
            $p = ConvertFrom-DsregStatus -Lines $out
            $entra = $p.EntraJoined; $workplace = $p.WorkplaceJoined; $domain = $p.DomainJoined
        }
    } catch { }
    try { if ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain) { $domain = $true } } catch { }
    try {
        $enroll = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
        if (Test-Path -LiteralPath $enroll) {
            foreach ($k in Get-ChildItem -LiteralPath $enroll -ErrorAction SilentlyContinue) {
                $es = Get-ItemProperty -LiteralPath $k.PSPath -Name EnrollmentState -ErrorAction SilentlyContinue
                if ($es -and $es.EnrollmentState -eq 1) { $mdm = $true }
            }
        }
    } catch { }
    if ($entra)     { $details += 'joined to Microsoft Entra (Azure AD)' }
    if ($workplace) { $details += 'Workplace/Entra registered (a work or school account is connected)' }
    if ($domain)    { $details += 'joined to an Active Directory domain' }
    if ($mdm)       { $details += 'enrolled in MDM / Intune management' }
    return [pscustomobject]@{
        IsManaged = ($entra -or $workplace -or $domain -or $mdm)
        EntraJoined = $entra; WorkplaceJoined = $workplace; DomainJoined = $domain; MdmEnrolled = $mdm
        Details = $details
    }
}

function Read-Journal {
    if (-not (Test-Path -LiteralPath $script:JournalPath)) {
        return [pscustomobject]@{ Version = $script:Version; Entries = @() }
    }
    try {
        $j = Get-Content -LiteralPath $script:JournalPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq ($j.PSObject.Properties['Entries'])) {
            $j | Add-Member -NotePropertyName Entries -NotePropertyValue @()
        }
        $j.Entries = @($j.Entries)
        return $j
    } catch {
        throw "The Veil journal is damaged ($script:JournalPath). Fix or delete it before continuing."
    }
}

function Save-Journal {
    param([object]$Journal)
    if (-not (Test-Path -LiteralPath $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }
    $tmp = $script:JournalPath + '.tmp'
    [System.IO.File]::WriteAllText($tmp, ($Journal | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $script:JournalPath -Force
}

function Get-AppliedIds {
    param([object]$Journal)
    return @($Journal.Entries | ForEach-Object { $_.TweakId } | Select-Object -Unique)
}

function ConvertTo-PsDrivePath {
    param([string]$Hive, [string]$Path)
    $prefix = if ($Hive -eq 'HKLM') { 'HKLM:' } elseif ($Hive -eq 'HKCU') { 'HKCU:' } else { throw "Unknown hive '$Hive'." }
    return ($prefix + '\' + $Path)
}

function Get-RegState {
    param([string]$Hive, [string]$Path, [string]$Name)
    $full = ConvertTo-PsDrivePath -Hive $Hive -Path $Path
    $state = [pscustomobject]@{ KeyExists = $false; ValueExists = $false; Value = $null; Type = $null }
    if (-not (Test-Path -LiteralPath $full)) { return $state }
    $state.KeyExists = $true
    $key = Get-Item -LiteralPath $full
    if ($key.GetValueNames() -contains $Name) {
        $state.ValueExists = $true
        $state.Value = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
        $state.Type = [string]$key.GetValueKind($Name)
    }
    return $state
}

function Set-RegState {
    param([string]$Hive, [string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    $full = ConvertTo-PsDrivePath -Hive $Hive -Path $Path
    if (-not (Test-Path -LiteralPath $full)) { New-Item -Path $full -Force | Out-Null }
    New-ItemProperty -LiteralPath $full -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Remove-RegState {
    param([string]$Hive, [string]$Path, [string]$Name)
    $full = ConvertTo-PsDrivePath -Hive $Hive -Path $Path
    if (Test-Path -LiteralPath $full) { Remove-ItemProperty -LiteralPath $full -Name $Name -ErrorAction SilentlyContinue }
}

function Get-ServiceStartupType {
    param([string]$Name)
    $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction SilentlyContinue
    if ($null -eq $svc) { return $null }
    return $svc.StartMode
}

function Set-ServiceStartupType {
    param([string]$Name, [string]$StartupType)
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
    if ($StartupType -eq 'Disabled') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
}

function Get-TaskState {
    param([string]$Path, [string]$TaskName)
    $task = Get-ScheduledTask -TaskPath $Path -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { return $null }
    return [string]$task.State
}

function Set-TaskState {
    param([string]$Path, [string]$TaskName, [string]$State)
    if ($State -eq 'Disabled') { Disable-ScheduledTask -TaskPath $Path -TaskName $TaskName -ErrorAction Stop | Out-Null }
    else { Enable-ScheduledTask -TaskPath $Path -TaskName $TaskName -ErrorAction Stop | Out-Null }
}

function Test-AppxPresent {
    param([string]$Package)
    return [bool](Get-AppxPackage -Name $Package -ErrorAction SilentlyContinue)
}

function Remove-AppxByName {
    param([string]$Package)
    Get-AppxPackage -Name $Package -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction Stop
}

function Invoke-ApplyAction {
    param([object]$Action, [switch]$DryRun)
    switch ($Action.Kind) {
        'Registry' {
            $value = Resolve-ActionValue -Value $Action.Value
            $before = Get-RegState -Hive $Action.Hive -Path $Action.Path -Name $Action.Name
            $desc = '{0}\{1} [{2}] = {3}' -f $Action.Hive, $Action.Path, $Action.Name, $value
            if (-not $DryRun) { Set-RegState -Hive $Action.Hive -Path $Action.Path -Name $Action.Name -Value $value -Type $Action.Type }
            return [pscustomobject]@{
                Kind = 'Registry'; Hive = $Action.Hive; Path = $Action.Path; Name = $Action.Name
                Before = $before; Description = $desc
            }
        }
        'Service' {
            $before = Get-ServiceStartupType -Name $Action.Name
            $desc = 'service {0} -> {1}' -f $Action.Name, $Action.StartupType
            if ($null -eq $before) { return [pscustomobject]@{ Kind = 'Service'; Name = $Action.Name; Missing = $true; Description = "$desc (not present)" } }
            if (-not $DryRun) { Set-ServiceStartupType -Name $Action.Name -StartupType $Action.StartupType }
            return [pscustomobject]@{ Kind = 'Service'; Name = $Action.Name; Before = $before; Description = $desc }
        }
        'ScheduledTask' {
            $before = Get-TaskState -Path $Action.Path -TaskName $Action.TaskName
            $desc = 'task {0}{1} -> {2}' -f $Action.Path, $Action.TaskName, $Action.State
            if ($null -eq $before) { return [pscustomobject]@{ Kind = 'ScheduledTask'; Path = $Action.Path; TaskName = $Action.TaskName; Missing = $true; Description = "$desc (not present)" } }
            if (-not $DryRun) { Set-TaskState -Path $Action.Path -TaskName $Action.TaskName -State $Action.State }
            return [pscustomobject]@{ Kind = 'ScheduledTask'; Path = $Action.Path; TaskName = $Action.TaskName; Before = $before; Description = $desc }
        }
        'Appx' {
            $present = Test-AppxPresent -Package $Action.Package
            $desc = 'remove appx {0}' -f $Action.Package
            if (-not $present) { return [pscustomobject]@{ Kind = 'Appx'; Package = $Action.Package; Missing = $true; Description = "$desc (not installed)" } }
            if (-not $DryRun) { Remove-AppxByName -Package $Action.Package }

            return [pscustomobject]@{ Kind = 'Appx'; Package = $Action.Package; Before = 'installed'; Reinstallable = $true; Description = $desc }
        }
        'Command' {
            $desc = 'run module: {0}' -f $Action.Module

            if (-not $DryRun) { [void](Invoke-ModuleCommand -Module $Action.Module -Mode 'Apply') }
            return [pscustomobject]@{ Kind = 'Command'; Module = $Action.Module; Description = $desc }
        }
    }
}

function Invoke-UndoAction {
    param([object]$Entry)
    switch ($Entry.Kind) {
        'Registry' {
            $b = $Entry.Before
            if ($b.ValueExists) {
                $type = if ($b.Type) { $b.Type } else { 'DWord' }
                Set-RegState -Hive $Entry.Hive -Path $Entry.Path -Name $Entry.Name -Value $b.Value -Type $type
            } else {
                Remove-RegState -Hive $Entry.Hive -Path $Entry.Path -Name $Entry.Name
            }
        }
        'Service' {
            if ($Entry.PSObject.Properties['Missing'] -and $Entry.Missing) { return }
            Set-ServiceStartupType -Name $Entry.Name -StartupType $Entry.Before
        }
        'ScheduledTask' {
            if ($Entry.PSObject.Properties['Missing'] -and $Entry.Missing) { return }
            Set-TaskState -Path $Entry.Path -TaskName $Entry.TaskName -State $Entry.Before
        }
        'Appx' {
            if ($Entry.PSObject.Properties['Missing'] -and $Entry.Missing) { return }
            Say ('  note: {0} was removed; reinstall it from the Microsoft Store if you want it back.' -f $Entry.Package) 'Yellow'
        }
        'Command' {
            [void](Invoke-ModuleCommand -Module $Entry.Module -Mode 'Undo')
        }
    }
}

function Invoke-ModuleCommand {
    param([string]$Module, [ValidateSet('Apply', 'Undo')][string]$Mode)
    if ($Module -ne 'gdid') { throw "Unknown module '$Module'." }
    $shield = Join-Path $script:ModulesDir 'gdid\gdid-shield.ps1'
    if (-not (Test-Path -LiteralPath $shield)) { throw "GDID module not found at $shield" }
    $arg = if ($Mode -eq 'Apply') { '-Protect' } else { '-UndoAll' }
    Say ("  handing off to the GDID module ({0})..." -f $arg) 'DarkGray'
    & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $shield $arg '-Yes' 2>&1 | ForEach-Object { Say ('  | ' + $_) }
    $code = $LASTEXITCODE

    if ($Mode -eq 'Apply' -and $code -ne 0) {
        Say '' 'Gray'
        Say '  GDID removal was refused. The usual cause is a work/school account' 'Yellow'
        Say '  registered on this PC (Settings > Accounts > Access work or school).' 'Yellow'
        Say '  Disconnect it, reboot, confirm with "dsregcmd /status" (WorkplaceJoined : NO),' 'Yellow'
        Say '  then re-run. This is the engine''s own safety gate, not an ownership check.' 'DarkGray'
        throw "the GDID module did not complete (exit $code) - it refuses Entra/Workplace-registered or otherwise managed PCs. Nothing was blocked, so there is nothing to undo for it."
    }
    if ($Mode -eq 'Undo' -and $code -ne 0) {
        Say ("  note: the GDID module reported exit {0} during undo." -f $code) 'Yellow'
    }
    return $code
}

function Test-TweakApplied {

    param([object]$Tweak)
    $regActions = @($Tweak.Actions | Where-Object { $_.Kind -eq 'Registry' })
    if ($regActions.Count -eq 0) { return $null }
    foreach ($a in $regActions) {
        $want = Resolve-ActionValue -Value $a.Value
        $cur = Get-RegState -Hive $a.Hive -Path $a.Path -Name $a.Name
        if (-not $cur.ValueExists -or [string]$cur.Value -ne [string]$want) { return $false }
    }
    return $true
}

function Show-Status {
    param([object[]]$Tweaks, [object]$Journal)
    $appliedIds = Get-AppliedIds -Journal $Journal
    Head 'Status'
    $byArea = $Tweaks | Group-Object Area
    foreach ($group in $byArea) {
        Say ('  {0}' -f $group.Name) 'White'
        foreach ($t in $group.Group) {
            $reg = Test-TweakApplied -Tweak $t
            if ($null -ne $reg) {
                $mark = if ($reg) { '[on] ' } else { '[off]' }
                $color = if ($reg) { 'Green' } else { 'DarkGray' }
            } else {
                $inJournal = $appliedIds -contains $t.Id
                $mark = if ($inJournal) { '[on] ' } else { '[off]' }
                $color = if ($inJournal) { 'Green' } else { 'DarkGray' }
            }
            Say ('    {0} {1}  ({2}, {3})' -f $mark, $t.Name, $t.Id, $t.Tier) $color
        }
    }
    Say ('  {0} tweak(s) recorded in the journal.' -f $appliedIds.Count) 'DarkGray'
}

function New-SafetyRestorePoint {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $name = 'SystemRestorePointCreationFrequency'; $had = $false; $prev = $null
    try {
        $item = Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
        if ($item) { $had = $true; $prev = $item.$name }
        New-ItemProperty -LiteralPath $key -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
        Checkpoint-Computer -Description 'Veil - before privacy tweaks' -RestorePointType 'MODIFY_SETTINGS' -WarningAction Stop
        Say '  Restore point created.' 'Green'; return $true
    } catch {
        Say ('  Could not create a restore point: {0}' -f $_.Exception.Message) 'Yellow'
        Say '  (System Restore may be turned off for drive C:.)' 'Yellow'; return $false
    } finally {
        try {
            if ($had) { New-ItemProperty -LiteralPath $key -Name $name -Value $prev -PropertyType DWord -Force | Out-Null }
            else { Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue }
        } catch { }
    }
}

function Invoke-Apply {
    param([object[]]$Tweaks, [switch]$DryRun, [switch]$SkipRestorePoint)
    Head ('Applying {0} tweak(s){1}' -f $Tweaks.Count, $(if ($DryRun) { ' - DRY RUN' } else { '' }))

    if (-not $DryRun) {
        $mgmt = Get-ManagementState
        if ($mgmt.IsManaged) {
            Head 'Heads up: this looks like a managed device'
            foreach ($d in $mgmt.Details) { Say ("  - $d") 'Yellow' }
            Say '  Applying machine-wide privacy policies here can conflict with your' 'Yellow'
            Say "  organization's management and may break against its IT policy. If this is a" 'Yellow'
            Say '  work or school managed PC, stop and check with whoever manages it first.' 'Yellow'
            Say '  (Everything is still reversible with -Undo.)' 'DarkGray'
            if (-not (Confirm-Action 'Apply anyway?')) { Say 'Cancelled - nothing was changed.' 'Yellow'; return }
        }
    }

    if (-not $DryRun -and -not $SkipRestorePoint) {
        Head 'Safety restore point'
        if (-not (New-SafetyRestorePoint) -and -not (Confirm-Action 'Continue WITHOUT a restore point?')) {
            Say 'Cancelled.' 'Yellow'; return
        }
    }

    $journal = Read-Journal
    $failures = 0

    foreach ($tweak in $Tweaks) {
        Say ('  {0}' -f $tweak.Name) 'White'
        if ($tweak.PSObject.Properties['Breaks'] -and $tweak.Breaks) { Say ('    will change: {0}' -f $tweak.Breaks) 'DarkGray' }
        foreach ($action in $tweak.Actions) {
            try {
                $record = Invoke-ApplyAction -Action $action -DryRun:$DryRun
                $prefix = if ($DryRun) { '    would set ' } else { '    set ' }
                Say ($prefix + $record.Description) 'Green'
                if (-not $DryRun) {
                    $record | Add-Member -NotePropertyName TweakId -NotePropertyValue $tweak.Id
                    $record | Add-Member -NotePropertyName AppliedAt -NotePropertyValue (Get-Date).ToString('o')
                    $journal.Entries = @($journal.Entries + $record)
                }
            } catch {
                $failures++
                Say ('    FAILED: {0}' -f $_.Exception.Message) 'Red'
                Write-Log ('apply failed, tweak {0}: {1}' -f $tweak.Id, $_.Exception.Message)
            }
        }
    }

    if (-not $DryRun) {
        Save-Journal -Journal $journal
        Write-Log ('applied {0} tweak(s), {1} failure(s)' -f $Tweaks.Count, $failures)
        Say ''
        if ($failures -gt 0) {
            Say ("Finished with {0} item(s) that could not be applied (see FAILED above)." -f $failures) 'Yellow'
            Say 'Everything that did apply is journaled and can be reversed with -Undo.' 'Gray'
        } else {
            Say 'Done. Sign out and back in (or restart) to apply everything.' 'Green'
            Say 'Run with -Undo to reverse all of this at any time.' 'Gray'
        }
    }
}

function Invoke-Undo {
    param([string[]]$Id, [switch]$DryRun)
    $journal = Read-Journal
    if (@($journal.Entries).Count -eq 0) { Say 'Nothing to undo - the journal is empty.' 'Yellow'; return }

    $targets = if ($Id) { @($journal.Entries | Where-Object { $Id -contains $_.TweakId }) } else { @($journal.Entries) }
    if ($targets.Count -eq 0) { Say 'No journal entries match those Ids.' 'Yellow'; return }

    Head ('Undoing {0} change(s){1}' -f $targets.Count, $(if ($DryRun) { ' - DRY RUN' } else { '' }))

    $ordered = @($targets); [array]::Reverse($ordered)
    $undoneKeys = @{}
    foreach ($entry in $ordered) {
        try {
            if (-not $DryRun) { Invoke-UndoAction -Entry $entry }
            Say ('  reverted ' + $entry.Description) 'Green'
            $undoneKeys[([string]$entry.TweakId + '|' + $entry.Description)] = $true
        } catch {
            Say ('  FAILED to revert {0}: {1}' -f $entry.Description, $_.Exception.Message) 'Red'
            Write-Log ('undo failed: {0}: {1}' -f $entry.Description, $_.Exception.Message)
        }
    }

    if (-not $DryRun) {
        if ($Id) {
            $journal.Entries = @($journal.Entries | Where-Object { -not ($undoneKeys.ContainsKey([string]$_.TweakId + '|' + $_.Description)) })
        } else {
            $journal.Entries = @()
        }
        Save-Journal -Journal $journal
        Write-Log ('undid {0} change(s)' -f $targets.Count)
        Say ''; Say 'Reverted. Sign out and back in (or restart) to finish.' 'Green'
    }
}

function Request-Elevation {
    param([string]$ScriptPath, [string]$ArgLine)
    if (Test-IsAdministrator) { return $false }
    $script:Relaunched = $true
    Say 'Veil needs administrator rights. Windows will ask you to allow it...' 'Gray'
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        Start-Process -FilePath $exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $ScriptPath, $ArgLine) | Out-Null
    } catch {
        Say 'Administrator permission was not granted, so nothing was changed.' 'Red'
    }
    return $true
}

function Start-Menu {
    param([object[]]$Tweaks, [string]$ScriptPath)
    while ($true) {
        Write-Host ''
        Write-Host ('{0} {1} - transparent, reversible Windows privacy hardener' -f $script:AppName, $script:Version) -ForegroundColor Cyan
        Write-Host ('-' * 66)
        Write-Host '  1) Check status'
        Write-Host '  2) Preview Safe tier        (dry run, changes nothing)'
        Write-Host '  3) Apply Safe tier           <- recommended start'
        Write-Host '  4) Apply Balanced tier'
        Write-Host '  5) Apply Aggressive tier     (includes GDID; read the warnings)'
        Write-Host '  6) Pick individual tweaks'
        Write-Host '  7) Undo everything'
        Write-Host '  0) Exit'
        Write-Host ''
        switch ((Read-Host 'Choose').Trim()) {
            '1' { Show-Status -Tweaks $Tweaks -Journal (Read-Journal) }
            '2' { Invoke-Apply -Tweaks (Select-Tweaks -All $Tweaks -Tier 'Safe') -DryRun }
            '3' { if (Confirm-Action 'Apply the Safe tier?')       { Invoke-Apply -Tweaks (Select-Tweaks -All $Tweaks -Tier 'Safe') } }
            '4' { if (Confirm-Action 'Apply the Balanced tier?')   { Invoke-Apply -Tweaks (Select-Tweaks -All $Tweaks -Tier 'Balanced') } }
            '5' {
                Say 'Aggressive includes device-identity changes that can break Microsoft sign-in, Store, Xbox and OneDrive.' 'Yellow'
                if (Confirm-Action 'Apply the Aggressive tier?')   { Invoke-Apply -Tweaks (Select-Tweaks -All $Tweaks -Tier 'Aggressive') }
            }
            '6' { Start-PickerMenu -Tweaks $Tweaks }
            '7' { if (Confirm-Action 'Undo every change Veil has made?') { Invoke-Undo } }
            '0' { return }
            default { Say 'Pick a number from the menu.' 'Yellow' }
        }
        [void](Read-Host "`nPress Enter to continue")
    }
}

function Start-PickerMenu {
    param([object[]]$Tweaks)
    for ($i = 0; $i -lt $Tweaks.Count; $i++) {
        Say ('  {0,2}) [{1}] {2} ({3})' -f ($i + 1), $Tweaks[$i].Tier, $Tweaks[$i].Name, $Tweaks[$i].Id) 'Gray'
    }
    $raw = Read-Host 'Enter numbers separated by commas (or blank to cancel)'
    if (-not $raw.Trim()) { return }
    $ids = foreach ($tok in ($raw -split ',')) {
        $n = 0
        if ([int]::TryParse($tok.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Tweaks.Count) { $Tweaks[$n - 1].Id }
    }
    $ids = @($ids | Select-Object -Unique)
    if ($ids.Count -eq 0) { Say 'No valid choices.' 'Yellow'; return }
    if (Confirm-Action ('Apply {0} selected tweak(s)?' -f $ids.Count)) {
        Invoke-Apply -Tweaks (Select-Tweaks -All $Tweaks -Id $ids)
    }
}

function Invoke-Main {
    param([string]$ScriptPath, [string]$ScriptRoot)
    $script:PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:ModulesDir = Join-Path $ScriptRoot 'modules'
    $catalog = if ($CatalogPath) { $CatalogPath } else { Join-Path $ScriptRoot 'catalog\tweaks.psd1' }

    $tweaks = Import-Catalog -Path $catalog

    $needsAdmin = ($Apply -and -not $DryRun) -or ($Undo -and -not $DryRun)
    if ($needsAdmin -and (Request-Elevation -ScriptPath $ScriptPath -ArgLine (Build-ArgLine))) { return 0 }

    if ($Status)      { Show-Status -Tweaks $tweaks -Journal (Read-Journal); return 0 }
    if ($Apply)       { Invoke-Apply -Tweaks (Select-Tweaks -All $tweaks -Id $Id -Tier $Tier) -DryRun:$DryRun -SkipRestorePoint:$NoRestorePoint; return 0 }
    if ($Undo)        { Invoke-Undo -Id $Id -DryRun:$DryRun; return 0 }

    if (-not (Test-IsAdministrator)) {
        Say 'Tip: run as administrator to apply changes. Opening the menu in read-only mode is fine for Status/preview.' 'DarkGray'
    }
    Start-Menu -Tweaks $tweaks -ScriptPath $ScriptPath
    return 0
}

function Build-ArgLine {
    $parts = New-Object System.Collections.Generic.List[string]
    if ($Status) { $parts.Add('-Status') }
    if ($Apply)  { $parts.Add('-Apply'); $parts.Add('-Tier'); $parts.Add($Tier) }
    if ($Undo)   { $parts.Add('-Undo') }
    if ($Id)     { $parts.Add('-Id'); $parts.Add(($Id -join ',')) }
    if ($DryRun) { $parts.Add('-DryRun') }
    if ($NoRestorePoint) { $parts.Add('-NoRestorePoint') }
    if ($Yes)    { $parts.Add('-Yes') }
    return ($parts -join ' ')
}

if (-not $NoRun) {
    $results = @(Invoke-Main -ScriptPath $PSCommandPath -ScriptRoot $PSScriptRoot)
    $code = if ($results.Count -gt 0 -and $results[-1] -is [int]) { $results[-1] } else { 0 }
    if (($Apply -or $Undo -or $Status) -and -not $Yes -and -not $script:Relaunched) { [void](Read-Host 'Press Enter to close') }
    exit $code
}
