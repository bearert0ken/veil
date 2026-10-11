# Veil

**A transparent, fully reversible privacy hardener for Windows 10 & 11.**

Veil turns off Windows' telemetry, AI features (Copilot, Recall, Click to Do), and the ads/suggestions scattered through the OS — using Microsoft's own documented Group Policy and settings keys. Nothing is hidden: every single change lives in a plain-text catalog you can read before you run anything, and every change is journaled so one command puts it all back.

```powershell
.\veil.ps1                       # menu
.\veil.ps1 -Apply -Tier Safe     # apply the safe set
.\veil.ps1 -Undo                 # revert everything, exactly
```

## Why another debloater?

Most "debloat" scripts are a wall of `reg add` lines you have to trust blindly, and half of them quietly disable your antivirus or Windows Update. Veil is built the opposite way:

- **Everything is data, not buried code.** All tweaks are in [`catalog/tweaks.psd1`](catalog/tweaks.psd1), one entry each, with a source for every key. [`TWEAKS.md`](TWEAKS.md) is generated from it so the docs can't lie.
- **Exact undo.** Before each change Veil records the *previous* value to `C:\ProgramData\Veil\journal.json`. `-Undo` restores originals and deletes values that didn't exist before — it doesn't just slam everything to 0.
- **It refuses to make you less safe.** See the line below.
- **Restore point first.** `-Apply` creates a System Restore point before touching anything.
- **Dry run.** `-Apply -DryRun` prints every change it *would* make and touches nothing.
- **Tested.** 15 engine tests + 18 GDID-module tests, runnable on any OS with PowerShell 7.

## The security line (read this)

Veil **does not** disable Microsoft Defender, Tamper Protection, SmartScreen, the Windows Firewall, UAC, BitLocker, or security updates. Those aren't "privacy" — they're what keeps the machine from getting owned. Scripts that rip them out to look hardcore are how people end up with ransomware. If you want those off, Veil is not your tool, and you should reconsider.

What Veil *does* turn off is data collection, AI, and advertising — things that send your data out or nag you, not things that protect you.

## Tiers

| Tier | For | Examples |
|------|-----|----------|
| **Safe** | Everyone. No loss of real functionality. | Copilot off, Recall off, ads/suggestions off, ad ID off, Edge telemetry off |
| **Balanced** | People who don't use MS cross-device features. | DiagTrack service off, CEIP tasks off, Activity History off, Delivery Optimization peer-sharing off, uninstall Copilot app |
| **Aggressive** | Privacy diehards who accept breakage. | Everything above **plus** GDID removal (breaks Microsoft account sign-in, Store, Xbox, OneDrive, Phone Link) |

Applying a tier includes the tiers below it. Full list: [`TWEAKS.md`](TWEAKS.md).

## Install & run

1. Download the repo (**Code → Download ZIP**), right-click the ZIP → **Properties** → tick **Unblock** → OK, then extract.
2. Double-click **`Run Veil.cmd`** (or run `veil.ps1` from an admin PowerShell) and allow the admin prompt.
3. Start with **Check status**, then **Preview Safe tier** (dry run), then **Apply Safe tier**.
4. Sign out and back in (or restart) so everything takes effect.

Keep the folder structure intact — `catalog\` and `modules\` must sit next to `veil.ps1`.

### Command line

```powershell
.\veil.ps1 -Status                                   # what's currently applied
.\veil.ps1 -Apply -Tier Balanced                     # apply Safe + Balanced
.\veil.ps1 -Apply -Id copilot-windows,advertising-id # just these
.\veil.ps1 -Apply -Tier Safe -DryRun                 # preview only
.\veil.ps1 -Undo                                     # revert everything
.\veil.ps1 -Undo -Id gdid                             # revert just one tweak
```

`-Yes` skips confirmations (for unattended use). `-NoRestorePoint` skips the restore point.

## The GDID module

The Aggressive tier includes **GDID removal**, which lives in [`modules/gdid/`](modules/gdid/) as its own tool (GDID Shield). It removes Microsoft's Global Device Identifier and blocks a new one, wrapping Windscribe's open-source [deGDID](https://github.com/yegors/deGDID) engine (pinned by SHA-256). It can break Microsoft account sign-in, the Store, Xbox, and OneDrive. Read [`modules/gdid/README.md`](modules/gdid/README.md) before using it. No local tool can delete the ID records Microsoft already holds on its servers.

## What it can't do

- It can't remove data Microsoft (or anyone) has already collected. It stops future collection.
- It isn't a VPN or a network blocker (except where a tweak like GDID adds one). Your IP and traffic are a separate problem.
- Some settings need a sign-out/restart, and a few (like consumer-feature suggestions) can be partly re-seeded by major Windows feature updates — re-run `-Apply` after a big update, or check `-Status`.

## Add your own tweaks

Add an entry to `catalog/tweaks.psd1` (copy an existing one), then run `pwsh -File tools/Build-TweaksDoc.ps1` to refresh `TWEAKS.md`. No engine changes needed — it's fully data-driven. PRs welcome; please include a documentation source for every key.

## Tests

```powershell
pwsh -NoProfile -File tests/Run-Tests.ps1              # engine (15)
pwsh -NoProfile -File modules/gdid/tests/Run-Tests.ps1 # GDID module (18)
```

Both use in-memory fakes for the registry/services/tasks, so they run on Windows, Linux, or macOS. Real registry/service/task/appx writes and the restore point are Windows-only and aren't exercised by these tests — test on a spare machine or VM before trusting it on your daily driver.

## License

MIT. The bundled deGDID engine is MIT by Windscribe / Yegor Sak; see `modules/gdid/engine/LICENSE-deGDID.txt`.

Veil changes settings on **your own** computer. It is not a tool for evading monitoring on machines you don't control.
