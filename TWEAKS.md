# Veil - full tweak reference

_This file is generated from `catalog/tweaks.psd1` by `tools/Build-TweaksDoc.ps1`. Do not edit by hand._

Total: 28 tweaks. Every change is reversible via -Undo.

## Ads & Suggestions

| Id | Tier | What it does | What it changes | Source |
|----|------|--------------|-----------------|--------|
| `advertising-id` | Safe | Turn off the advertising ID | Apps can no longer use a per-user ad ID to personalize ads. | MS AdvertisingInfo policy + user setting |
| `tailored-experiences` | Safe | Turn off tailored experiences with diagnostic data | Windows stops using your diagnostic data to personalize tips and ads. | MS CloudContent policy + user Privacy key |
| `start-recommendations` | Safe | Remove Start menu recommendations and account notifications | Start stops showing recommended/promoted items and account nags. | Explorer\Advanced: Start_IrisRecommendations / Start_AccountNotifications |
| `lockscreen-ads` | Safe | Turn off lock screen fun facts, tips and tricks | The lock screen stops showing Spotlight tips and promos. | ContentDeliveryManager: RotatingLockScreenOverlayEnabled / SubscribedContent-338387 |
| `settings-suggestions` | Safe | Turn off suggested content in the Settings app | Settings stops showing suggested content banners. | ContentDeliveryManager: SubscribedContent-338393/353694/353696 |
| `tips-notifications` | Safe | Turn off tips, tricks and suggestion notifications | Windows stops sending "tip" notifications. | ContentDeliveryManager: SubscribedContent-338389 |
| `finish-setup` | Safe | Stop the "Let's finish setting up your device" nag | The post-update SCOOBE setup prompt stops appearing. | UserProfileEngagement: ScoobeSystemSettingEnabled |
| `welcome-experience` | Safe | Turn off the Windows welcome experience after updates | The "what's new" welcome screen stops appearing after updates. | ContentDeliveryManager: SubscribedContent-310093 |
| `explorer-ads` | Safe | Remove File Explorer sync-provider ads | File Explorer stops showing OneDrive/Office promotional banners. | Explorer\Advanced: ShowSyncProviderNotifications |
| `cloud-softlanding` | Balanced | Block Windows "spotlight" soft-landing suggestions (machine-wide) | Suggested apps and spotlight content are blocked for all users. | MS CloudContent policy: DisableSoftLanding / DisableWindowsConsumerFeatures |

## AI & Copilot

| Id | Tier | What it does | What it changes | Source |
|----|------|--------------|-----------------|--------|
| `copilot-windows` | Safe | Turn off Windows Copilot | The Copilot button/panel stops opening. | MS WindowsAI ADMX: TurnOffWindowsCopilot |
| `copilot-remove-app` | Balanced | Uninstall the Copilot app (policy) | Removes the Copilot app. You can reinstall it from the Store. | MS WindowsAI ADMX: RemoveMicrosoftCopilotApp |
| `copilot-key` | Safe | Free the Copilot hardware key (remap in Settings after) | The dedicated Copilot key no longer forces Copilot; you can reassign it. | MS WindowsAI ADMX: SetCopilotHardwareKey (cleared) |
| `recall-snapshots` | Safe | Disable Recall screenshots (AI data analysis) | Windows Recall stops saving snapshots of your screen. | MS WindowsAI ADMX: DisableAIDataAnalysis |
| `recall-enablement` | Balanced | Make Recall unavailable entirely | Recall cannot be turned on at all. | MS WindowsAI ADMX: AllowRecallEnablement = 0 |
| `click-to-do` | Safe | Disable Click to Do | The Click to Do AI overlay stops working. | MS WindowsAI ADMX: DisableClickToDo |
| `settings-agent` | Safe | Disable the AI agent in Settings | The "ask Copilot" agent in the Settings app is turned off. | MS WindowsAI ADMX: DisableSettingsAgent |
| `notepad-ai` | Safe | Disable AI features in Notepad | Rewrite / Summarize / Write disappear from Notepad. | MS policy: WindowsNotepad\DisableAIFeatures |
| `paint-ai` | Safe | Disable AI features in Paint (Cocreator, Generative fill, Image Creator) | Paint loses its AI image tools. | MS WindowsAI ADMX: DisableCocreator / DisableGenerativeFill / DisableImageCreator |
| `edge-copilot` | Safe | Disable Copilot / sidebar in Microsoft Edge | The Edge sidebar (and its Copilot) is turned off. | MS Edge policy: HubsSidebarEnabled = 0 |

## Device identity

| Id | Tier | What it does | What it changes | Source |
|----|------|--------------|-----------------|--------|
| `gdid` | Aggressive | Remove and block the Global Device Identifier (GDID) | Microsoft account sign-in, Store, Xbox, OneDrive MSA, Phone Link may stop. See the GDID module README. | Bundled GDID Shield module (wraps Windscribe deGDID) |

## Input & Speech

| Id | Tier | What it does | What it changes | Source |
|----|------|--------------|-----------------|--------|
| `inking-typing` | Safe | Stop sending inking and typing data to Microsoft | Personalized handwriting/typing suggestions stop improving from your data. | MS TextInput / Personalization policies |
| `activity-feed` | Balanced | Turn off Activity History / Timeline upload | Windows stops collecting and uploading your activity history. | MS System policy: EnableActivityFeed / PublishUserActivities / UploadUserActivities |

## Telemetry

| Id | Tier | What it does | What it changes | Source |
|----|------|--------------|-----------------|--------|
| `telemetry-level` | Safe | Set diagnostic data to the lowest level this edition allows | Optional diagnostic data stops being sent. Security data (and updates) are unaffected. | MS DataCollection ADMX: AllowTelemetry (edition-aware, set at runtime) |
| `diagtrack-service` | Balanced | Stop the Connected User Experiences and Telemetry service (DiagTrack) | The DiagTrack telemetry uploader is disabled. Feedback Hub may be limited. | DiagTrack service |
| `telemetry-tasks` | Balanced | Disable CEIP / compatibility telemetry scheduled tasks | Background "customer experience" and app-compatibility data collection stops. | Windows built-in scheduled tasks (CEIP / Application Experience) |
| `edge-telemetry` | Safe | Turn off Microsoft Edge diagnostic data and personalization | Edge stops sending optional diagnostic/usage data. | MS Edge policy: DiagnosticData / PersonalizationReportingEnabled |
| `delivery-optimization` | Balanced | Stop Delivery Optimization peer sharing (updates still download) | Your PC no longer shares update files with other machines over the internet. | MS DO policy: DODownloadMode = 99 (Simple) |

