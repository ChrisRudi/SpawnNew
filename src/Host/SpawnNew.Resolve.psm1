# SpawnNew.Resolve.psm1
# Version 1.0 | Katalog aus allen Quellen aufloesen.
# Zweck  : Jede Quelle mit Zeitlimit abtasten, bei nicht rechtzeitig
#          erreichbarer Quelle den Metadaten-Cache verwenden, Aktions-IDs
#          nach Quellenprioritaet aufloesen und eine Aktion unmittelbar vor
#          der Ausfuehrung erneut pruefen.
# Input  : Konfigurationsobjekt aus Get-SpawnNewConfig.
# Output : Get-SpawnNewCatalog liefert Aktionen und Diagnosen.
#          Test-SpawnNewAction liefert Gueltigkeit und frische Aktionsdaten.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1, SpawnNew.Catalog.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Catalog.psm1')

$script:CacheSchemaVersion = 1

function Get-SpawnNewCacheFilePath {
    <#
    .SYNOPSIS
    Cachedatei einer Quelle. Der Dateiname leitet sich aus dem
    Vergleichsschluessel des Quellenpfades ab.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Source)

    $directory = Join-Path (Get-SpawnNewDataDirectory) 'Cache'
    return (Join-Path $directory ((Get-SpawnNewShortHash -Text $Source.Key) + '.json'))
}

function Save-SpawnNewSourceCache {
    <#
    .SYNOPSIS
    Schreibt die Metadaten einer Quelle in den Cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $path = Get-SpawnNewCacheFilePath -Source $Source

    $payload = [pscustomobject]@{
        schemaVersion = $script:CacheSchemaVersion
        savedUtc      = [System.DateTime]::UtcNow.ToString('o')
        sourceKey     = $Source.Key
        actions       = $Actions
    }

    try {
        $directory = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $directory -Force)
        }
        $json = ConvertTo-Json -InputObject $payload -Depth 8
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))
    }
    catch {
        $message = 'Cache konnte nicht geschrieben werden: ' + $_.Exception.Message
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
            -Area 'source' -Path $path -Message $message
    }
}

function Import-SpawnNewSourceCache {
    <#
    .SYNOPSIS
    Liest die Metadaten einer Quelle aus dem Cache.
    .DESCRIPTION
    Nur zu verwenden, wenn die Quelle nicht rechtzeitig erreichbar ist. Alle
    Eintraege werden mit Stale = $true geliefert und gelten als
    moeglicherweise veraltet.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][int]$MaxAgeMinutes,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $path    = Get-SpawnNewCacheFilePath -Source $Source
    $payload = Read-SpawnNewJsonFile -Path $path -Area 'source' -Diagnostics $Diagnostics

    if ($null -eq $payload) { return @() }

    $version = Get-SpawnNewIntProperty -InputObject $payload -Name 'schemaVersion' `
        -Default 0 -Path $path -Diagnostics $Diagnostics

    if ($version -ne $script:CacheSchemaVersion) {
        $message = "Cache hat die nicht unterstützte Version $version und wird verworfen."
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
            -Area 'source' -Path $path -Message $message
        return @()
    }

    $saved = [System.DateTime]::MinValue
    if (Test-SpawnNewProperty $payload 'savedUtc') {
        $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
        [void][System.DateTime]::TryParse([string]$payload.savedUtc,
            [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$saved)
    }

    $ageMinutes = ([System.DateTime]::UtcNow - $saved).TotalMinutes
    if ($ageMinutes -gt $MaxAgeMinutes) {
        $message = ('Cache ist {0:N0} Minuten alt und wird nicht verwendet.' -f $ageMinutes)
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
            -Area 'source' -Path $path -Message $message
        return @()
    }

    if (-not (Test-SpawnNewProperty $payload 'actions')) { return @() }

    $actions = @($payload.actions)
    foreach ($action in $actions) { $action.Stale = $true }
    return $actions
}

function Invoke-SpawnNewSourceScan {
    <#
    .SYNOPSIS
    Taestet eine Quelle in einem eigenen Runspace mit Zeitlimit ab.
    .DESCRIPTION
    Ein blockierender Zugriff auf eine nicht erreichbare Netzwerkfreigabe
    laesst sich nicht abbrechen. Nach Ablauf des Zeitlimits wird der Runspace
    zum Stoppen angestossen und nicht weiter abgewartet, damit das
    Kontextmenue nicht haengt.

    Runspace und Modulimport laufen vor der Zeitmessung. Sie haengen nicht an
    der Quelle, und ihr Aufwand haette sonst das Zeitlimit aufgebraucht,
    bevor die Quelle ueberhaupt angefasst wird.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][int]$MaxDepth,
        [Parameter(Mandatory)][int]$TimeoutMs,
        [Parameter(Mandatory)][string]$CatalogModulePath
    )

    $worker = {
        param($Source, $MaxDepth)

        $diagnostics = New-Object System.Collections.ArrayList
        $scan = Get-SpawnNewSourceScan -Source $Source -MaxDepth $MaxDepth -Diagnostics $diagnostics

        [pscustomobject]@{
            Reachable   = $scan.Reachable
            Actions     = $scan.Actions
            Diagnostics = $diagnostics.ToArray()
        }
    }

    $shell = [powershell]::Create()

    [void]$shell.AddScript('param($ModulePath) Import-Module $ModulePath')
    [void]$shell.AddArgument($CatalogModulePath)
    [void]$shell.Invoke()
    $shell.Commands.Clear()

    [void]$shell.AddScript($worker)
    [void]$shell.AddArgument($Source)
    [void]$shell.AddArgument($MaxDepth)

    $handle = $shell.BeginInvoke()

    if (-not $handle.AsyncWaitHandle.WaitOne($TimeoutMs)) {
        [void]$shell.BeginStop($null, $null)
        return [pscustomobject]@{
            Reachable = $false
            Actions   = @()
            Errors    = @()
            TimedOut  = $true
        }
    }

    try {
        $output = @($shell.EndInvoke($handle))
        $errors = @($shell.Streams.Error)
    }
    finally {
        $shell.Dispose()
    }

    $result = $output | Select-Object -First 1

    return [pscustomobject]@{
        Reachable   = [bool]$result.Reachable
        Actions     = @($result.Actions)
        Diagnostics = @($result.Diagnostics)
        Errors      = $errors
        TimedOut    = $false
    }
}

function Get-SpawnNewCatalog {
    <#
    .SYNOPSIS
    Loest den vollstaendigen Menuekatalog auf.
    .DESCRIPTION
    Die Quellen werden in der Prioritaetsreihenfolge aus Get-SpawnNewConfig
    abgetastet. Bei gleicher Aktions-ID gewinnt die zuerst einsortierte
    Quelle; die verdeckte Aktion wird als Diagnose erfasst. Eine fehlerhafte
    Quelle blockiert die anderen nicht.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $diagnostics = $Config.Diagnostics
    $catalogPath = Join-Path $PSScriptRoot 'SpawnNew.Catalog.psm1'
    $actions     = New-Object System.Collections.ArrayList
    $seen        = @{}

    foreach ($source in $Config.Sources) {
        $scan = Invoke-SpawnNewSourceScan -Source $source -MaxDepth $Config.ScanDepth `
            -TimeoutMs $Config.SourceTimeoutMs -CatalogModulePath $catalogPath

        if ($scan.TimedOut) {
            $message = "Quelle '$($source.Name)' hat das Zeitlimit von $($Config.SourceTimeoutMs) ms überschritten; es gelten die zwischengespeicherten Angaben."
            Add-SpawnNewDiagnostic -Diagnostics $diagnostics -Severity 'warning' `
                -Area 'source' -Path $source.Path -Message $message
        }
        else {
            foreach ($entry in $scan.Diagnostics) { [void]$diagnostics.Add($entry) }
            foreach ($record in $scan.Errors) {
                Add-SpawnNewDiagnostic -Diagnostics $diagnostics -Severity 'warning' `
                    -Area 'source' -Path $source.Path -Message ([string]$record)
            }
        }

        if ($scan.TimedOut -or -not $scan.Reachable) {
            $sourceActions = @(
                Import-SpawnNewSourceCache -Source $source `
                    -MaxAgeMinutes $Config.CacheMaxAgeMinutes -Diagnostics $diagnostics
            )
        }
        else {
            $sourceActions = @($scan.Actions)
            Save-SpawnNewSourceCache -Source $source -Actions $sourceActions -Diagnostics $diagnostics
        }

        foreach ($action in $sourceActions) {
            if ($seen.ContainsKey($action.Id)) {
                $winner  = $seen[$action.Id]
                $message = "Aktion '$($action.Title)' wird von '$($winner.Title)' aus Quelle '$($winner.SourceName)' verdeckt."
                Add-SpawnNewDiagnostic -Diagnostics $diagnostics -Severity 'info' `
                    -Area 'action' -Path $action.EntryPoint -Message $message
                continue
            }
            $seen[$action.Id] = $action
            [void]$actions.Add($action)
        }
    }

    return [pscustomobject]@{
        Actions     = $actions.ToArray()
        Diagnostics = $diagnostics
    }
}

function Test-SpawnNewAction {
    <#
    .SYNOPSIS
    Prueft eine Aktion unmittelbar vor der Ausfuehrung erneut.
    .DESCRIPTION
    Deckt Abnahmekriterium 14 ab: eine zwischen Menueanzeige und Ausfuehrung
    entfernte oder geaenderte Aktion wird nicht gestartet. Geprueft werden
    Quelle, Beschreibung, Einstiegspunkt und Aktions-ID.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Action)

    $invalid = {
        param($Reason)
        [pscustomobject]@{ Valid = $false; Message = $Reason; Action = $null }
    }

    if ($Action.Stale) {
        return (& $invalid 'Die Aktion stammt aus dem Zwischenspeicher und wurde nicht erneut geprüft.')
    }

    if (-not [System.IO.Directory]::Exists($Action.SourcePath)) {
        return (& $invalid "Die Quelle '$($Action.SourceName)' ist nicht erreichbar.")
    }

    if ($Action.DescriptionPath.Length -eq 0) {
        if (-not (Test-Path -LiteralPath $Action.EntryPoint -PathType Leaf)) {
            return (& $invalid 'Das Skript der Aktion ist nicht mehr vorhanden.')
        }
        return [pscustomobject]@{ Valid = $true; Message = ''; Action = $Action }
    }

    $source = [pscustomobject]@{
        Name  = $Action.SourceName
        Path  = $Action.SourcePath
        Key   = (Get-SpawnNewPathKey -Path $Action.SourcePath)
        Scope = $Action.SourceScope
    }

    $diagnostics = New-Object System.Collections.ArrayList
    $fresh = Read-SpawnNewActionFolder -Directory $Action.ActionDirectory `
        -RelativePath $Action.RelativePath -Source $source -Diagnostics $diagnostics

    if ($null -eq $fresh) {
        $reason = 'Die Aktion ist nicht mehr gültig.'
        if ($diagnostics.Count -gt 0) { $reason = $diagnostics[0].Message }
        return (& $invalid $reason)
    }

    if ($fresh.Id -ne $Action.Id) {
        return (& $invalid 'Die Aktions-ID hat sich seit dem Öffnen des Menüs geändert.')
    }

    return [pscustomobject]@{ Valid = $true; Message = ''; Action = $fresh }
}

Export-ModuleMember -Function Get-SpawnNewCacheFilePath, Save-SpawnNewSourceCache, Import-SpawnNewSourceCache, Invoke-SpawnNewSourceScan, Get-SpawnNewCatalog, Test-SpawnNewAction
