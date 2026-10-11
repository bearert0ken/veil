@{

    SchemaVersion = 1

    Tweaks = @(

        @{
            Id = 'copilot-windows'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Turn off Windows Copilot'
            Breaks = 'The Copilot button/panel stops opening.'
            Source = 'MS WindowsAI ADMX: TurnOffWindowsCopilot'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'copilot-remove-app'; Area = 'AI & Copilot'; Tier = 'Balanced'
            Name = 'Uninstall the Copilot app (policy)'
            Breaks = 'Removes the Copilot app. You can reinstall it from the Store.'
            Source = 'MS WindowsAI ADMX: RemoveMicrosoftCopilotApp'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Policies\Microsoft\Windows\WindowsAI'; Name = 'RemoveMicrosoftCopilotApp'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'copilot-key'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Free the Copilot hardware key (remap in Settings after)'
            Breaks = 'The dedicated Copilot key no longer forces Copilot; you can reassign it.'
            Source = 'MS WindowsAI ADMX: SetCopilotHardwareKey (cleared)'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'recall-snapshots'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Disable Recall screenshots (AI data analysis)'
            Breaks = 'Windows Recall stops saving snapshots of your screen.'
            Source = 'MS WindowsAI ADMX: DisableAIDataAnalysis'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'recall-enablement'; Area = 'AI & Copilot'; Tier = 'Balanced'
            Name = 'Make Recall unavailable entirely'
            Breaks = 'Recall cannot be turned on at all.'
            Source = 'MS WindowsAI ADMX: AllowRecallEnablement = 0'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'click-to-do'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Disable Click to Do'
            Breaks = 'The Click to Do AI overlay stops working.'
            Source = 'MS WindowsAI ADMX: DisableClickToDo'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'settings-agent'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Disable the AI agent in Settings'
            Breaks = 'The "ask Copilot" agent in the Settings app is turned off.'
            Source = 'MS WindowsAI ADMX: DisableSettingsAgent'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableSettingsAgent'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'notepad-ai'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Disable AI features in Notepad'
            Breaks = 'Rewrite / Summarize / Write disappear from Notepad.'
            Source = 'MS policy: WindowsNotepad\DisableAIFeatures'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\WindowsNotepad'; Name = 'DisableAIFeatures'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'paint-ai'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Disable AI features in Paint (Cocreator, Generative fill, Image Creator)'
            Breaks = 'Paint loses its AI image tools.'
            Source = 'MS WindowsAI ADMX: DisableCocreator / DisableGenerativeFill / DisableImageCreator'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'Software\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableCocreator'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'Software\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableGenerativeFill'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'Software\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableImageCreator'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'edge-copilot'; Area = 'AI & Copilot'; Tier = 'Safe'
            Name = 'Disable Copilot / sidebar in Microsoft Edge'
            Breaks = 'The Edge sidebar (and its Copilot) is turned off.'
            Source = 'MS Edge policy: HubsSidebarEnabled = 0'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled'; Type = 'DWord'; Value = 0 }
            )
        },

        @{
            Id = 'telemetry-level'; Area = 'Telemetry'; Tier = 'Safe'
            Name = 'Set diagnostic data to the lowest level this edition allows'
            Breaks = 'Optional diagnostic data stops being sent. Security data (and updates) are unaffected.'
            Source = 'MS DataCollection ADMX: AllowTelemetry (edition-aware, set at runtime)'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Type = 'DWord'; Value = '@TelemetryFloor' }
            )
        },
        @{
            Id = 'diagtrack-service'; Area = 'Telemetry'; Tier = 'Balanced'
            Name = 'Stop the Connected User Experiences and Telemetry service (DiagTrack)'
            Breaks = 'The DiagTrack telemetry uploader is disabled. Feedback Hub may be limited.'
            Source = 'DiagTrack service'
            Actions = @(
                @{ Kind = 'Service'; Name = 'DiagTrack'; StartupType = 'Disabled' }
                @{ Kind = 'Service'; Name = 'dmwappushservice'; StartupType = 'Disabled' }
            )
        },
        @{
            Id = 'telemetry-tasks'; Area = 'Telemetry'; Tier = 'Balanced'
            Name = 'Disable CEIP / compatibility telemetry scheduled tasks'
            Breaks = 'Background "customer experience" and app-compatibility data collection stops.'
            Source = 'Windows built-in scheduled tasks (CEIP / Application Experience)'
            Actions = @(
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Application Experience\'; TaskName = 'Microsoft Compatibility Appraiser'; State = 'Disabled' }
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Application Experience\'; TaskName = 'ProgramDataUpdater'; State = 'Disabled' }
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; TaskName = 'Consolidator'; State = 'Disabled' }
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; TaskName = 'UsbCeip'; State = 'Disabled' }
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Feedback\Siuf\'; TaskName = 'DmClient'; State = 'Disabled' }
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Feedback\Siuf\'; TaskName = 'DmClientOnScenarioDownload'; State = 'Disabled' }
                @{ Kind = 'ScheduledTask'; Path = '\Microsoft\Windows\Autochk\'; TaskName = 'Proxy'; State = 'Disabled' }
            )
        },
        @{
            Id = 'edge-telemetry'; Area = 'Telemetry'; Tier = 'Safe'
            Name = 'Turn off Microsoft Edge diagnostic data and personalization'
            Breaks = 'Edge stops sending optional diagnostic/usage data.'
            Source = 'MS Edge policy: DiagnosticData / PersonalizationReportingEnabled'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'PersonalizationReportingEnabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'delivery-optimization'; Area = 'Telemetry'; Tier = 'Balanced'
            Name = 'Stop Delivery Optimization peer sharing (updates still download)'
            Breaks = 'Your PC no longer shares update files with other machines over the internet.'
            Source = 'MS DO policy: DODownloadMode = 99 (Simple)'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Name = 'DODownloadMode'; Type = 'DWord'; Value = 99 }
            )
        },

        @{
            Id = 'advertising-id'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Turn off the advertising ID'
            Breaks = 'Apps can no longer use a per-user ad ID to personalize ads.'
            Source = 'MS AdvertisingInfo policy + user setting'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'tailored-experiences'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Turn off tailored experiences with diagnostic data'
            Breaks = 'Windows stops using your diagnostic data to personalize tips and ads.'
            Source = 'MS CloudContent policy + user Privacy key'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableTailoredExperiencesWithDiagnosticData'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'start-recommendations'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Remove Start menu recommendations and account notifications'
            Breaks = 'Start stops showing recommended/promoted items and account nags.'
            Source = 'Explorer\Advanced: Start_IrisRecommendations / Start_AccountNotifications'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'lockscreen-ads'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Turn off lock screen fun facts, tips and tricks'
            Breaks = 'The lock screen stops showing Spotlight tips and promos.'
            Source = 'ContentDeliveryManager: RotatingLockScreenOverlayEnabled / SubscribedContent-338387'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338387Enabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'settings-suggestions'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Turn off suggested content in the Settings app'
            Breaks = 'Settings stops showing suggested content banners.'
            Source = 'ContentDeliveryManager: SubscribedContent-338393/353694/353696'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'tips-notifications'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Turn off tips, tricks and suggestion notifications'
            Breaks = 'Windows stops sending "tip" notifications.'
            Source = 'ContentDeliveryManager: SubscribedContent-338389'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'finish-setup'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Stop the "Let''s finish setting up your device" nag'
            Breaks = 'The post-update SCOOBE setup prompt stops appearing.'
            Source = 'UserProfileEngagement: ScoobeSystemSettingEnabled'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'welcome-experience'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Turn off the Windows welcome experience after updates'
            Breaks = 'The "what''s new" welcome screen stops appearing after updates.'
            Source = 'ContentDeliveryManager: SubscribedContent-310093'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'explorer-ads'; Area = 'Ads & Suggestions'; Tier = 'Safe'
            Name = 'Remove File Explorer sync-provider ads'
            Breaks = 'File Explorer stops showing OneDrive/Office promotional banners.'
            Source = 'Explorer\Advanced: ShowSyncProviderNotifications'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Type = 'DWord'; Value = 0 }
            )
        },
        @{
            Id = 'cloud-softlanding'; Area = 'Ads & Suggestions'; Tier = 'Balanced'
            Name = 'Block Windows "spotlight" soft-landing suggestions (machine-wide)'
            Breaks = 'Suggested apps and spotlight content are blocked for all users.'
            Source = 'MS CloudContent policy: DisableSoftLanding / DisableWindowsConsumerFeatures'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableSoftLanding'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Type = 'DWord'; Value = 1 }
            )
        },

        @{
            Id = 'inking-typing'; Area = 'Input & Speech'; Tier = 'Safe'
            Name = 'Stop sending inking and typing data to Microsoft'
            Breaks = 'Personalized handwriting/typing suggestions stop improving from your data.'
            Source = 'MS TextInput / Personalization policies'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\Input\TIPC'; Name = 'Enabled'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Type = 'DWord'; Value = 1 }
                @{ Kind = 'Registry'; Hive = 'HKCU'; Path = 'Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Type = 'DWord'; Value = 1 }
            )
        },
        @{
            Id = 'activity-feed'; Area = 'Input & Speech'; Tier = 'Balanced'
            Name = 'Turn off Activity History / Timeline upload'
            Breaks = 'Windows stops collecting and uploading your activity history.'
            Source = 'MS System policy: EnableActivityFeed / PublishUserActivities / UploadUserActivities'
            Actions = @(
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Type = 'DWord'; Value = 0 }
                @{ Kind = 'Registry'; Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Type = 'DWord'; Value = 0 }
            )
        },

        @{
            Id = 'gdid'; Area = 'Device identity'; Tier = 'Aggressive'
            Name = 'Remove and block the Global Device Identifier (GDID)'
            Breaks = 'Microsoft account sign-in, Store, Xbox, OneDrive MSA, Phone Link may stop. See the GDID module README.'
            Source = 'Bundled GDID Shield module (wraps Windscribe deGDID)'
            Actions = @(
                @{ Kind = 'Command'; Module = 'gdid' }
            )
        }
    )
}
