
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('gdid-shield-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

$env:ProgramData = Join-Path $work 'ProgramData'
if (-not $env:SystemRoot) { $env:SystemRoot = Join-Path $work 'Windows' }
New-Item -ItemType Directory -Path $env:ProgramData -Force | Out-Null

. (Join-Path $root 'gdid-shield.ps1') -NoRun

$script:Passed = 0
$script:Failed = 0
function Test-Case([string]$Name, [scriptblock]$Body) {
  try {
    & $Body
    $script:Passed++
    Report ('PASS  ' + $Name) 'Green'
  } catch {
    $script:Failed++
    Report ('FAIL  ' + $Name + ' :: ' + $_.Exception.Message) 'Red'
  }
}
function Assert-Equal($Expected, $Actual, [string]$What = 'value') {
  if ($Expected -ne $Actual) { throw ('{0}: expected [{1}] got [{2}]' -f $What, $Expected, $Actual) }
}
function Assert-True($Condition, [string]$What) { if (-not $Condition) { throw $What } }
function Assert-Throws([scriptblock]$Body, [string]$Pattern) {
  $threw = $false
  try { & $Body } catch {
    $threw = $true
    if ($Pattern -and $_.Exception.Message -notmatch $Pattern) { throw ('wrong error: ' + $_.Exception.Message) }
  }
  if (-not $threw) { throw 'expected an error, none thrown' }
}

function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }
function Show-Notification { param($Title, $Text, $Icon) $script:Notifications.Add($Text) }
function Set-LockedAcl { param($Path) }
$script:Notifications = New-Object System.Collections.Generic.List[string]
$realWriteHost = Get-Command Microsoft.PowerShell.Utility\Write-Host
function Report([string]$Text, [string]$Color) { & $realWriteHost $Text -ForegroundColor $Color }

$script:Reg = @{}
$script:Keys = @{}
function Get-RegValueInfo {
  param([string]$Path, [string]$Name)
  $info = [pscustomobject]@{ KeyExists = $false; Exists = $false; Value = $null; Kind = $null }
  if (-not $script:Keys.ContainsKey($Path)) { return $info }
  $info.KeyExists = $true
  $k = "$Path|$Name"
  if ($script:Reg.ContainsKey($k)) { $info.Exists = $true; $info.Value = $script:Reg[$k].Value; $info.Kind = $script:Reg[$k].Kind }
  return $info
}
function Set-RegValue {
  param([string]$Path, [string]$Name, [object]$Value, [string]$Kind = 'DWord')
  $script:Keys[$Path] = $true
  $script:Reg["$Path|$Name"] = @{ Value = $Value; Kind = $Kind }
}
function Remove-RegValue { param([string]$Path, [string]$Name) $script:Reg.Remove("$Path|$Name") }
function Remove-RegKeyIfEmpty {
  param([string]$Path)
  $left = @($script:Reg.Keys | Where-Object { $_.StartsWith("$Path|") })
  if ($left.Count -eq 0) { $script:Keys.Remove($Path) }
}
function Reset-Registry { $script:Reg = @{}; $script:Keys = @{} }

Test-Case 'Pinned hash matches the bundled engine' {
  $engine = Join-Path $root 'engine/degdid.ps1'
  Assert-Equal $script:EngineSha256 (Get-FileSha256 $engine) 'engine sha256'
  Assert-Equal $engine (Assert-EngineHash -Path $engine) 'returned path'
}

Test-Case 'Tampered engine is refused' {
  $copy = Join-Path $work 'tampered.ps1'
  Copy-Item (Join-Path $root 'engine/degdid.ps1') $copy
  Add-Content $copy '# one extra line'
  Assert-Throws { Assert-EngineHash -Path $copy } 'does not match the verified version'
}

Test-Case 'Missing engine gives a clear error' {
  Assert-Throws { Assert-EngineHash -Path (Join-Path $work 'nope.ps1') } 'Engine not found'
}

Test-Case 'JSON report is found between warning lines' {
  $lines = @('WARNING: build not lab-validated {odd}', '{', '  "Verdict": "RealGdidPresent",', '  "Nested": { "A": 1 }', '}', 'WARNING: trailing')
  $report = ConvertFrom-EngineJson -Lines $lines
  Assert-Equal 'RealGdidPresent' $report.Verdict 'verdict'
  Assert-Equal 1 $report.Nested.A 'nested'
}

Test-Case 'Unparseable engine output returns null, summary says Error' {
  Assert-True ($null -eq (ConvertFrom-EngineJson -Lines @('Unexpected error: boom'))) 'should be null'
  Assert-True ($null -eq (ConvertFrom-EngineJson -Lines @())) 'empty should be null'
  Assert-Equal 'Error' (Get-StatusSummary -Report $null).Verdict 'verdict'
}

Test-Case 'Summary reads engine fields and keeps no identifiers' {
  $report = @'
{
  "Timestamp": "2026-10-11T12:00:00-04:00",
  "Environment": { "Build": 26200, "DisplayVersion": "25H2", "IsLabValidatedBuild": true,
                   "UnsupportedReasons": [], "TargetFailureReasons": [], "Warnings": ["w1"] },
  "TargetUser": { "UserName": "SECRETUSER", "Sid": "S-1-5-21-1-2-3-1001" },
  "Gdids": [ { "Puid": "0018000012345678", "Gdid": "g:6755399441055736" } ],
  "Hosts": { "Canonical": true },
  "Firewall": { "Health": "Healthy" },
  "ActiveStoreInventory": { "RealShapedCount": 0 },
  "ResidualCaches": { "RealPuidCount": 0 },
  "Verdict": "ProtectedNoRealGdid"
}
'@ | ConvertFrom-Json
  $s = Get-StatusSummary -Report $report
  Assert-Equal 'ProtectedNoRealGdid' $s.Verdict 'verdict'
  Assert-Equal '25H2 26200' $s.Build 'build'
  Assert-Equal 0 $s.RealIdCount 'count'
  Assert-Equal 'w1' $s.Warnings[0] 'warning'
  $flat = ($s | ConvertTo-Json -Depth 5)
  Assert-True ($flat -notmatch 'SECRETUSER|0018000012345678|6755399441055736|S-1-5-21') 'summary leaked an identifier'
}

Test-Case 'Unsupported reasons are surfaced' {
  $report = '{"Environment":{"UnsupportedReasons":["Domain-joined"],"TargetFailureReasons":["Two profiles loaded"]},"Verdict":"UnsupportedEnvironment"}' | ConvertFrom-Json
  $s = Get-StatusSummary -Report $report
  Assert-Equal 2 $s.Reasons.Count 'reason count'
  Assert-Equal 'Domain-joined' $s.Reasons[0] 'reason'
}

Test-Case 'Relaunch argument string keeps switches and quoted values' {
  $text = ConvertTo-ArgumentString -Bound ([ordered]@{ Protect = [switch]$true; WatchdogMode = 'Alert'; EnginePath = 'C:\My Files\degdid.ps1'; Harden = [switch]$false })
  Assert-Equal '-Protect -WatchdogMode "Alert" -EnginePath "C:\My Files\degdid.ps1"' $text 'args'
}

Test-Case 'Hardening records originals and Undo restores exactly' {
  Reset-Registry
  $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
  Set-RegValue -Path $p -Name 'EnableCdp' -Value 1 -Kind 'DWord'
  Set-RegValue -Path $p -Name 'Unrelated' -Value 'keep' -Kind 'String'
  $state = New-EmptyState
  $settings = Get-HardeningSettings -TelemetryValue 1
  $changed = Invoke-Hardening -State $state -Settings $settings
  Assert-Equal $settings.Count $changed 'changed count'
  Assert-Equal 0 (Get-RegValueInfo $p 'EnableCdp').Value 'EnableCdp applied'
  Assert-Equal 99 (Get-RegValueInfo 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode').Value 'DO mode'

  $state = ($state | ConvertTo-Json -Depth 6) | ConvertFrom-Json
  $skipped = @(Undo-Hardening -State $state)
  Assert-Equal 0 $skipped.Count 'skipped'
  Assert-Equal 1 (Get-RegValueInfo $p 'EnableCdp').Value 'EnableCdp restored'
  Assert-Equal 'keep' (Get-RegValueInfo $p 'Unrelated').Value 'unrelated kept'
  Assert-True (-not (Get-RegValueInfo $p 'EnableActivityFeed').Exists) 'new value removed'
  Assert-True (-not (Get-RegValueInfo 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData').KeyExists) 'created key removed'
  Assert-True ((Get-RegValueInfo $p 'Unrelated').KeyExists) 'pre-existing key kept'
}

Test-Case 'A key shared by several settings that we created is removed on undo' {
  Reset-Registry
  $state = New-EmptyState
  [void](Invoke-Hardening -State $state -Settings (Get-HardeningSettings -TelemetryValue 1))
  [void](Undo-Hardening -State $state)
  Assert-True (-not (Get-RegValueInfo 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableCdp').KeyExists) 'System key removed'
  Assert-Equal 0 $script:Keys.Count 'no keys left behind'
}

Test-Case 'Running hardening twice never overwrites the original record' {
  Reset-Registry
  $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
  Set-RegValue -Path $p -Name 'EnableCdp' -Value 1 -Kind 'DWord'
  $state = New-EmptyState
  $settings = Get-HardeningSettings -TelemetryValue 1
  [void](Invoke-Hardening -State $state -Settings $settings)
  $second = Invoke-Hardening -State $state -Settings $settings
  Assert-Equal 0 $second 'second run changes nothing'
  Assert-Equal $settings.Count @($state.Hardening).Count 'one record per setting'
  [void](Undo-Hardening -State $state)
  Assert-Equal 1 (Get-RegValueInfo $p 'EnableCdp').Value 'original value from first run'
}

Test-Case 'Undo leaves alone a setting someone else changed' {
  Reset-Registry
  $state = New-EmptyState
  [void](Invoke-Hardening -State $state -Settings (Get-HardeningSettings -TelemetryValue 1))
  $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
  Set-RegValue -Path $edge -Name 'DiagnosticData' -Value 2 -Kind 'DWord'
  $skipped = @(Undo-Hardening -State $state)
  Assert-Equal 1 $skipped.Count 'skipped'
  Assert-Equal 2 (Get-RegValueInfo $edge 'DiagnosticData').Value 'left alone'
  Assert-Equal 0 @($state.Hardening).Count 'state cleared'
}

Test-Case 'State file round-trips and fills missing fields' {
  $state = New-EmptyState
  $state.LastVerdict = 'BlockDegraded'
  Save-ShieldState -State $state
  $back = Read-ShieldState
  Assert-Equal 'BlockDegraded' $back.LastVerdict 'verdict'
  Set-Content -LiteralPath $script:StatePath -Value '{"Hardening":null}'
  $back = Read-ShieldState
  Assert-True ($back.PSObject.Properties.Name -contains 'Watchdog') 'missing field added'
  Assert-Equal 0 @($back.Hardening).Count 'null hardening -> empty'
  Set-Content -LiteralPath $script:StatePath -Value 'not json{'
  Assert-Throws { Read-ShieldState } 'damaged'
  Remove-Item -LiteralPath $script:StatePath
}

$pwshExe = (Get-Process -Id $PID).Path
$script:PowerShell64 = $pwshExe
$fakeEngine = Join-Path $script:InstallEngineDir 'degdid.ps1'
$verdictFile = Join-Path $work 'verdict.txt'
New-Item -ItemType Directory -Path $script:InstallEngineDir -Force | Out-Null
@"
param([switch]`$Status, [switch]`$Json, [switch]`$Protect, [switch]`$Unblock)
`$f = '$verdictFile'
if (`$Status) {
  [Console]::Error.WriteLine('stderr noise that must not abort the caller')
  Write-Output 'WARNING: fake engine'
  Write-Output ('{ "Verdict": "' + (Get-Content `$f -Raw).Trim() + '", "Gdids": [ { "Puid": "0018FFFF00001111" } ] }')
  exit 0
}
if (`$Protect) { Set-Content `$f 'ProtectedNoRealGdid'; Add-Content '$work/protect-calls.txt' 'x'; exit 0 }
if (`$Unblock) { exit 0 }
exit 1
"@ | Set-Content -LiteralPath $fakeEngine
$script:EngineSha256 = Get-FileSha256 $fakeEngine
$installedScript = Join-Path $script:InstallDir $script:ScriptFileName
Copy-Item (Join-Path $root 'gdid-shield.ps1') $installedScript

Test-Case 'Engine runs in a child process; exit code captured; stderr does not abort' {
  Set-Content $verdictFile 'RealGdidPresent'
  $ErrorActionPreference = 'Stop'
  $run = Invoke-Engine -Path $fakeEngine -Arguments @('-Status', '-Json')
  Assert-Equal 0 $run.ExitCode 'exit code'
  Assert-Equal 'RealGdidPresent' (ConvertFrom-EngineJson -Lines $run.Output).Verdict 'verdict'
  $bad = Invoke-Engine -Path $fakeEngine -Arguments @('-Nonsense')
  Assert-Equal 1 $bad.ExitCode 'failing exit code'
}

Test-Case 'Watchdog refuses to run from outside the install folder' {
  $code = Invoke-WatchdogRun -ScriptPath (Join-Path $work 'elsewhere.ps1') -Mode 'AutoFix'
  Assert-Equal 1 $code 'exit code'
  Assert-True (-not (Test-Path (Join-Path $work 'protect-calls.txt'))) 'must not call engine'
}

Test-Case 'Watchdog AutoFix repairs, notifies, and logs no identifiers' {
  Set-Content $verdictFile 'BlockDegraded'
  $script:Notifications.Clear()
  $code = Invoke-WatchdogRun -ScriptPath $installedScript -Mode 'AutoFix'
  Assert-Equal 0 $code 'exit code'
  Assert-Equal 1 @(Get-Content (Join-Path $work 'protect-calls.txt')).Count 'protect called once'
  Assert-True ($script:Notifications[0] -match 'repaired automatically') 'notification'
  $log = Get-Content -LiteralPath $script:LogPath -Raw
  Assert-True ($log -match 'Watchdog auto-fix exit code 0, verdict ProtectedNoRealGdid') 'log line'
  Assert-True ($log -notmatch '0018FFFF00001111') 'log leaked the ID'
  Assert-Equal 'ProtectedNoRealGdid' (Read-ShieldState).LastVerdict 'state verdict'
}

Test-Case 'Watchdog Alert mode only notifies' {
  Remove-Item (Join-Path $work 'protect-calls.txt') -ErrorAction SilentlyContinue
  Set-Content $verdictFile 'RealGdidPresent'
  $script:Notifications.Clear()
  $code = Invoke-WatchdogRun -ScriptPath $installedScript -Mode 'Alert'
  Assert-Equal 1 $code 'exit code'
  Assert-True (-not (Test-Path (Join-Path $work 'protect-calls.txt'))) 'protect must not run'
  Assert-True ($script:Notifications[0] -match 'needs attention') 'notification'
}

Test-Case 'Watchdog refuses a swapped engine' {
  Add-Content -LiteralPath $fakeEngine '# swapped'
  $script:Notifications.Clear()
  $code = Invoke-WatchdogRun -ScriptPath $installedScript -Mode 'AutoFix'
  Assert-Equal 1 $code 'exit code'
  Assert-True ((Get-Content -LiteralPath $script:LogPath -Raw) -match 'engine hash mismatch') 'logged'
  Assert-True ($script:Notifications[0] -match 'changed unexpectedly') 'notified'
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
$color = 'Green'
if ($script:Failed -gt 0) { $color = 'Red' }
Report ('{0} passed, {1} failed' -f $script:Passed, $script:Failed) $color
exit $script:Failed
