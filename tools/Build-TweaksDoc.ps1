
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$catalog = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'catalog/tweaks.psd1')

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Veil - full tweak reference')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('_This file is generated from `catalog/tweaks.psd1` by `tools/Build-TweaksDoc.ps1`. Do not edit by hand._')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Total: $($catalog.Tweaks.Count) tweaks. Every change is reversible via `-Undo`.")
[void]$sb.AppendLine('')

foreach ($area in ($catalog.Tweaks | Group-Object Area)) {
    [void]$sb.AppendLine("## $($area.Name)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Id | Tier | What it does | What it changes | Source |')
    [void]$sb.AppendLine('|----|------|--------------|-----------------|--------|')
    foreach ($t in $area.Group) {
        $breaks = if ($t.ContainsKey('Breaks') -and $t.Breaks) { $t.Breaks } else { '-' }
        $src = if ($t.ContainsKey('Source')) { $t.Source } else { '-' }
        [void]$sb.AppendLine("| ``$($t.Id)`` | $($t.Tier) | $($t.Name) | $breaks | $src |")
    }
    [void]$sb.AppendLine('')
}

$out = Join-Path $root 'TWEAKS.md'
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $out"
