# tools/PSScriptAnalyzerSettings.psd1
# Version 1.0 | PSScriptAnalyzer-Regelsatz fuer SpawnNew.
# Zweck  : Prueft den gesamten PowerShell-Code gegen Windows PowerShell 5.1.
# Input  : keiner, wird von tools/Invoke-Lint.ps1 uebergeben.
# Output : keiner.
# Deps   : PSScriptAnalyzer 1.23 oder neuer.

@{
    IncludeDefaultRules = $true

    Rules = @{
        # Syntax, die erst ab PowerShell 7 existiert, melden.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }

        # Cmdlets, die es in Windows PowerShell 5.1 nicht gibt, melden.
        # Profil: Windows 10 1809 mit Windows PowerShell 5.1.17763.
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
            )
        }

        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSUseConsistentIndentation = @{
            Enable          = $true
            Kind            = 'space'
            IndentationSize = 4
        }
    }
}
