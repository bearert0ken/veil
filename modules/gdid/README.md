# GDID Shield

Removes Microsoft's **Global Device Identifier (GDID)** from a Windows 10/11 PC, blocks Windows from getting a new one, and keeps watching so it stays that way.

GDID is a persistent ID Microsoft's servers assign to each Windows installation. It survives updates, is not affected by VPNs, and Windows has no setting to turn it off. It became public in July 2026 through a federal court filing.

## What it does

| Feature | What it means for you |
|---|---|
| **Remove and block** | Deletes every known local copy of the ID (registry, credential vault, caches) and blocks the Microsoft servers that issue it. |
| **Hash-pinned engine** | The removal engine is checked against a fixed SHA-256 before every run. A swapped or edited engine is refused. |
| **Restore point** | Made automatically before any change. |
| **Watchdog** | Checks 3 minutes after you sign in and daily at noon. If a Windows update or firewall reset breaks the block, it repairs it (AutoFix) or tells you (Alert). |
| **Extra hardening** (optional) | Turns off other channels that send device IDs: activity feed, cross-device sync, cloud clipboard, ad ID, Delivery Optimization cloud, Edge diagnostics, and diagnostic data at the lowest level your edition allows. Originals are recorded, so Undo is exact. |
| **Undo all** | One step back to normal. |
| **Private logs** | The log stores verdicts and counts only, never your ID, user name, or SID. |

The removal itself is done by [deGDID](https://github.com/yegors/deGDID) from Windscribe (MIT license), pinned to commit `3a5d5a9`. Its source was reviewed before pinning: the only network activity is a DNS lookup and a TCP connect test to confirm the block works, and the one encoded command is a readable helper that runs `cmdkey` to delete two device credentials.

## Limits (read this)

- **It cannot delete what Microsoft already stored on its servers** about your old ID. Nothing on your PC can.
- While protected, these break or ask you to sign in: Microsoft account sign-in, Microsoft Store, Xbox app, OneDrive (Microsoft account), Phone Link, cross-device features, and possibly Windows Hello / passkeys tied to your Microsoft account. Normal desktop use, browsing, and Windows Update keep working.
- The engine only changes a PC that is **not** managed by work/school (no domain, Entra, or MDM) and has **one** signed-in user. Windows 11 25H2 (build 26200) is the lab-tested build; others work with a warning.
- Windows System Restore points made before protection contain old copies of the registry, including the ID. To clear them after you confirm everything works: **System Properties > System Protection > Configure > Delete**.

## How to use

1. Right-click the downloaded zip > **Properties** > tick **Unblock** > OK. Then extract it.
2. Double-click **`Run GDID Shield.cmd`** and allow the admin prompt.
3. Follow the menu's recommended order:
   - **1** Check status
   - **2** Remove and block
   - Restart your PC
   - **1** Check status again (should say PROTECTED)
   - **3** Turn on watchdog
   - **4** Extra hardening, if you want it

Keep the folder structure as-is (`engine\degdid.ps1` must stay next to `gdid-shield.ps1`). After step 2, a locked copy lives in `C:\ProgramData\GDIDShield` (only Administrators and SYSTEM can edit it, so the watchdog cannot be hijacked by normal programs).

### Command line

From an admin PowerShell in the folder:

```powershell
.\gdid-shield.ps1 -Status
.\gdid-shield.ps1 -Protect -Harden -InstallWatchdog          # full setup, asks to confirm
.\gdid-shield.ps1 -InstallWatchdog -WatchdogMode Alert       # notify only
.\gdid-shield.ps1 -UndoAll
```

`-Yes` skips confirmations. `-NoRestorePoint` skips the restore point.

## Status results

| Result | Meaning | What to do |
|---|---|---|
| PROTECTED | No ID on the PC, block working | Nothing |
| NOT PROTECTED | ID present | Run option 2 |
| PARTLY PROTECTED | No ID, but the block is incomplete | Run option 2 to repair |
| CANNOT CHANGE THIS PC | Work/school-managed or more than one user signed in | Sign out other users; managed PCs are not supported |
| CHECK FAILED | Engine could not read something | Restart and try again |

## Troubleshooting

- **Protect failed with code 6** - more than one user signed in, or the user could not be identified. Sign out other accounts and retry.
- **Code 4 (hosts file refused)** - some antivirus locks the hosts file. Pause it briefly, retry, then re-enable.
- **Microsoft Defender flags a "hosts file" change** - choose *Allow on device*. If Defender reverts it, the watchdog will detect the broken block.
- **Want Microsoft account features back** - use option 8 (Undo all) and restart. Windows will get a *new* ID, not your old one.
- The watchdog briefly flashes a PowerShell window when it runs. That is normal.

## Updating the engine

When deGDID releases a new version: review its changes, replace `engine\degdid.ps1`, then update `$script:EngineSha256` and `$script:EngineCommit` at the top of `gdid-shield.ps1` with the new file's SHA-256 (`Get-FileHash .\engine\degdid.ps1`). Until you do, GDID Shield refuses to run the new file.

## Tests

```powershell
pwsh -NoProfile -File tests\Run-Tests.ps1
```

18 tests cover the hash pin, report parsing, ID-free logging, exact hardening undo, state-file handling, and the watchdog flow (with a fake engine and in-memory registry, so they also run on Linux/macOS). Windows-only behavior (real registry, ACLs, scheduled task, restore point) is not covered by these tests.

## License

GDID Shield: MIT. Bundled deGDID engine: MIT, Copyright Windscribe / Yegor Sak, see `engine\LICENSE-deGDID.txt`.

Use it on your own PCs for privacy. It is not a tool for evading lawful process.
