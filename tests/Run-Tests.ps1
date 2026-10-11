
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('veil-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$env:ProgramData = Join-Path $work 'ProgramData'
if (-not $env:SystemRoot) { $env:SystemRoot = Join-Path $work 'Windows' }

. (Join-Path $root 'veil.ps1') -NoRun
$script:StateDir = Join-Path $env:ProgramData 'Veil'
$script:JournalPath = Join-Path $script:StateDir 'journal.json'

$pass = 0; $fail = 0
$realHost = Get-Command Microsoft.PowerShell.Utility\Write-Host
function Note($t, $c) { & $realHost $t -ForegroundColor $c }
function Say { param([string]$Text, [string]$Color = 'Gray') }
function It($name, $body) {
    try { & $body; $script:pass++; Note "PASS  $name" Green }
    catch { $script:fail++; Note "FAIL  $name :: $($_.Exception.Message)" Red }
}
function Eq($exp, $act, $what = 'value') { if ($exp -ne $act) { throw "${what}: expected [$exp] got [$act]" } }
function True($cond, $what) { if (-not $cond) { throw $what } }
function Throws($body, $pat) {
    $t = $false
    try { & $body } catch { $t = $true; if ($pat -and $_.Exception.Message -notmatch $pat) { throw "wrong error: $($_.Exception.Message)" } }
    if (-not $t) { throw 'expected an error' }
}

$script:Reg = @{}; $script:Keys = @{}
function Get-RegState {
    param([string]$Hive, [string]$Path, [string]$Name)
    $k = "$Hive|$Path"; $s = [pscustomobject]@{ KeyExists = $false; ValueExists = $false; Value = $null; Type = $null }
    if (-not $script:Keys.ContainsKey($k)) { return $s }
    $s.KeyExists = $true; $vk = "$k|$Name"
    if ($script:Reg.ContainsKey($vk)) { $s.ValueExists = $true; $s.Value = $script:Reg[$vk].Value; $s.Type = $script:Reg[$vk].Type }
    return $s
}
function Set-RegState { param($Hive, $Path, $Name, $Value, $Type = 'DWord') $script:Keys["$Hive|$Path"] = $true; $script:Reg["$Hive|$Path|$Name"] = @{ Value = $Value; Type = $Type } }
function Remove-RegState { param($Hive, $Path, $Name) $script:Reg.Remove("$Hive|$Path|$Name") }
function Reset-Reg { $script:Reg = @{}; $script:Keys = @{} }

$script:Services = @{ DiagTrack = 'Auto'; dmwappushservice = 'Manual' }
function Get-ServiceStartupType { param($Name) if ($script:Services.ContainsKey($Name)) { return $script:Services[$Name] } else { return $null } }
function Set-ServiceStartupType { param($Name, $StartupType) $script:Services[$Name] = $StartupType }

$script:Tasks = @{ '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser' = 'Ready' }
function Get-TaskState { param($Path, $TaskName) $k = "$Path|$TaskName"; if ($script:Tasks.ContainsKey($k)) { return $script:Tasks[$k] } else { return $null } }
function Set-TaskState { param($Path, $TaskName, $State) $script:Tasks["$Path|$TaskName"] = $State }

$script:Appx = @{ 'Microsoft.Test' = $true }
function Test-AppxPresent { param($Package) return [bool]($script:Appx.ContainsKey($Package) -and $script:Appx[$Package]) }
function Remove-AppxByName { param($Package) $script:Appx[$Package] = $false }

$script:ModuleCalls = New-Object System.Collections.Generic.List[string]

function Invoke-ModuleCommand { param($Module, $Mode) $script:ModuleCalls.Add("$Module/$Mode"); return 0 }
function New-SafetyRestorePoint { return $true }

function Get-ManagementState { return [pscustomobject]@{ IsManaged = $false; Details = @() } }

It 'Catalog imports and validates' {
    $tweaks = Import-Catalog -Path (Join-Path $root 'catalog/tweaks.psd1')
    True ($tweaks.Count -ge 20) 'expected many tweaks'
    True (@($tweaks | Where-Object { $_.Id -eq 'gdid' }).Count -eq 1) 'gdid tweak present'
}

It 'Catalog rejects duplicate ids, bad tier, missing field, bad action kind' {
    $mk = {
        param($body)
        $p = Join-Path $work ('cat-' + [guid]::NewGuid().ToString('N') + '.psd1')
        Set-Content -LiteralPath $p -Value $body
        $p
    }
    Throws { Import-Catalog -Path (& $mk '@{ Tweaks = @( @{Id="a";Name="a";Area="x";Tier="Safe";Actions=@()}, @{Id="a";Name="b";Area="x";Tier="Safe";Actions=@()} ) }') } 'Duplicate'
    Throws { Import-Catalog -Path (& $mk '@{ Tweaks = @( @{Id="a";Name="a";Area="x";Tier="Nope";Actions=@()} ) }') } 'unknown tier'
    Throws { Import-Catalog -Path (& $mk '@{ Tweaks = @( @{Id="a";Name="a";Area="x";Actions=@()} ) }') } "missing 'Tier'"
    Throws { Import-Catalog -Path (& $mk '@{ Tweaks = @( @{Id="a";Name="a";Area="x";Tier="Safe";Actions=@(@{Kind="Nonsense"})} ) }') } 'unknown action kind'
    Throws { Import-Catalog -Path (& $mk '@{ NotTweaks = @() }') } "no 'Tweaks'"
}

It 'Tier selection includes lower tiers; Id selection is exact' {
    $all = Import-Catalog -Path (Join-Path $root 'catalog/tweaks.psd1')
    $safe = Select-Tweaks -All $all -Tier 'Safe'
    $agg = Select-Tweaks -All $all -Tier 'Aggressive'
    True ($safe.Count -lt $agg.Count) 'aggressive should be a superset'
    True (@($safe | Where-Object { $_.Tier -ne 'Safe' }).Count -eq 0) 'safe tier should only contain Safe'
    True (@($agg | Where-Object { $_.Id -eq 'gdid' }).Count -eq 1) 'aggressive includes gdid'
    $pick = Select-Tweaks -All $all -Id @('copilot-windows', 'advertising-id')
    Eq 2 $pick.Count 'picked count'
    Throws { Select-Tweaks -All $all -Id @('does-not-exist') } 'No tweak with Id'
}

It 'Telemetry placeholder resolves to a number' {
    $v = Resolve-ActionValue -Value '@TelemetryFloor'
    True ($v -eq 0 -or $v -eq 1) 'floor is 0 or 1'
    Eq 5 (Resolve-ActionValue -Value 5) 'passthrough'
}

It 'Registry apply writes our value and journals the original; undo restores it' {
    Reset-Reg
    Set-RegState -Hive 'HKCU' -Path 'A\B' -Name 'Existing' -Value 7 -Type 'DWord'
    $tweak = @{ Id = 't'; Name = 'n'; Area = 'x'; Tier = 'Safe'; Actions = @(
            @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'A\B'; Name = 'Existing'; Type = 'DWord'; Value = 0 }
            @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'C\D'; Name = 'Fresh'; Type = 'DWord'; Value = 1 }
        ) }
    Invoke-Apply -Tweaks @($tweak) -SkipRestorePoint
    Eq 0 (Get-RegState HKCU 'A\B' 'Existing').Value 'existing overwritten'
    Eq 1 (Get-RegState HKLM 'C\D' 'Fresh').Value 'fresh written'
    $j = Read-Journal
    Eq 2 @($j.Entries).Count 'two journal entries'
    Invoke-Undo
    Eq 7 (Get-RegState HKCU 'A\B' 'Existing').Value 'restored to original 7'
    True (-not (Get-RegState HKLM 'C\D' 'Fresh').ValueExists) 'fresh value removed'
    Eq 0 @((Read-Journal).Entries).Count 'journal emptied'
}

It 'Service apply/undo restores original start mode; missing service is a no-op' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    $script:Services = @{ DiagTrack = 'Auto' }
    $tweak = @{ Id = 'svc'; Name = 'n'; Area = 'x'; Tier = 'Balanced'; Actions = @(
            @{ Kind = 'Service'; Name = 'DiagTrack'; StartupType = 'Disabled' }
            @{ Kind = 'Service'; Name = 'dmwappushservice'; StartupType = 'Disabled' }
        ) }
    Invoke-Apply -Tweaks @($tweak) -SkipRestorePoint
    Eq 'Disabled' $script:Services['DiagTrack'] 'DiagTrack disabled'
    True (-not $script:Services.ContainsKey('dmwappushservice')) 'absent service untouched'
    Invoke-Undo
    Eq 'Auto' $script:Services['DiagTrack'] 'DiagTrack restored to Auto'
}

It 'Scheduled task apply/undo restores original state' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    $script:Tasks = @{ '\P\|T1' = 'Ready' }
    $tweak = @{ Id = 'task'; Name = 'n'; Area = 'x'; Tier = 'Balanced'; Actions = @(
            @{ Kind = 'ScheduledTask'; Path = '\P\'; TaskName = 'T1'; State = 'Disabled' }
            @{ Kind = 'ScheduledTask'; Path = '\P\'; TaskName = 'Absent'; State = 'Disabled' }
        ) }
    Invoke-Apply -Tweaks @($tweak) -SkipRestorePoint
    Eq 'Disabled' $script:Tasks['\P\|T1'] 'task disabled'
    Invoke-Undo
    Eq 'Ready' $script:Tasks['\P\|T1'] 'task restored to Ready'
}

It 'Appx removal is journaled and undo warns (cannot auto-reinstall)' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    $script:Appx = @{ 'Microsoft.Test' = $true }
    $tweak = @{ Id = 'appx'; Name = 'n'; Area = 'x'; Tier = 'Aggressive'; Actions = @(
            @{ Kind = 'Appx'; Package = 'Microsoft.Test'; Action = 'Remove' }
        ) }
    Invoke-Apply -Tweaks @($tweak) -SkipRestorePoint
    Eq $false $script:Appx['Microsoft.Test'] 'package removed'
    $entry = (Read-Journal).Entries[0]
    Eq $true $entry.Reinstallable 'marked reinstallable'
    Invoke-Undo
}

It 'Command action delegates to the module on apply and undo' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    $script:ModuleCalls.Clear()
    $tweak = @{ Id = 'gdid'; Name = 'n'; Area = 'x'; Tier = 'Aggressive'; Actions = @(@{ Kind = 'Command'; Module = 'gdid' }) }
    Invoke-Apply -Tweaks @($tweak) -SkipRestorePoint
    Eq 'gdid/Apply' $script:ModuleCalls[0] 'apply delegated'
    $entries = @((Read-Journal).Entries)
    Eq 1 $entries.Count 'command journaled as exactly one entry'
    Eq 'run module: gdid' $entries[0].Description 'description intact (no leaked exit code)'
    Invoke-Undo
    Eq 'gdid/Undo' $script:ModuleCalls[1] 'undo delegated'
}

It 'Dry run changes nothing and writes no journal' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    $tweak = @{ Id = 't'; Name = 'n'; Area = 'x'; Tier = 'Safe'; Actions = @(@{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'A\B'; Name = 'V'; Type = 'DWord'; Value = 0 }) }
    Invoke-Apply -Tweaks @($tweak) -DryRun
    True (-not (Get-RegState HKCU 'A\B' 'V').ValueExists) 'nothing written'
    True (-not (Test-Path $script:JournalPath)) 'no journal file'
}

It 'Undo by Id removes only those entries' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    $t1 = @{ Id = 'one'; Name = 'n'; Area = 'x'; Tier = 'Safe'; Actions = @(@{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'K'; Name = 'A'; Type = 'DWord'; Value = 0 }) }
    $t2 = @{ Id = 'two'; Name = 'n'; Area = 'x'; Tier = 'Safe'; Actions = @(@{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'K'; Name = 'B'; Type = 'DWord'; Value = 0 }) }
    Invoke-Apply -Tweaks @($t1, $t2) -SkipRestorePoint
    Invoke-Undo -Id @('one')
    $left = @((Read-Journal).Entries)
    Eq 1 $left.Count 'one entry left'
    Eq 'two' $left[0].TweakId 'the remaining entry is two'
}

It 'Status reports registry tweaks as on when values are present' {
    Reset-Reg
    $all = Import-Catalog -Path (Join-Path $root 'catalog/tweaks.psd1')
    $cw = $all | Where-Object { $_.Id -eq 'copilot-windows' }
    Eq $false (Test-TweakApplied -Tweak $cw) 'not applied yet'
    foreach ($a in $cw.Actions) { Set-RegState -Hive $a.Hive -Path $a.Path -Name $a.Name -Value (Resolve-ActionValue $a.Value) }
    Eq $true (Test-TweakApplied -Tweak $cw) 'now applied'
}

It 'dsregcmd parser detects Entra / Workplace / domain state' {
    $managed = @(
        '             AzureAdJoined : YES'
        '          EnterpriseJoined : NO'
        '              DomainJoined : NO'
        '           WorkplaceJoined : YES'
    )
    $p = ConvertFrom-DsregStatus -Lines $managed
    Eq $true $p.EntraJoined 'entra'
    Eq $true $p.WorkplaceJoined 'workplace'
    Eq $false $p.DomainJoined 'domain'
    $clean = @('AzureAdJoined : NO', 'DomainJoined : NO', 'WorkplaceJoined : NO')
    $q = ConvertFrom-DsregStatus -Lines $clean
    Eq $false $q.EntraJoined 'clean entra'
    Eq $false $q.WorkplaceJoined 'clean workplace'
}

It 'A failing Command action is reported and NOT journaled as done' {
    Reset-Reg; Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
    function Invoke-ModuleCommand { param($Module, $Mode) throw 'refuses managed PC' }
    $tweak = @{ Id = 'gdid'; Name = 'n'; Area = 'x'; Tier = 'Aggressive'; Actions = @(@{ Kind = 'Command'; Module = 'gdid' }) }
    Invoke-Apply -Tweaks @($tweak) -SkipRestorePoint
    Eq 0 @((Read-Journal).Entries).Count 'failed command must not be journaled'

    function Invoke-ModuleCommand { param($Module, $Mode) $script:ModuleCalls.Add("$Module/$Mode") }
}

It 'Damaged journal is reported, not silently ignored' {
    if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }
    Set-Content -LiteralPath $script:JournalPath -Value 'not json{'
    Throws { Read-Journal } 'damaged'
    Remove-Item $script:JournalPath -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Note ("`n{0} passed, {1} failed" -f $pass, $fail) $(if ($fail) { 'Red' } else { 'Green' })
exit $fail
