# SpawnNew.Config.psm1
# Version 1.0 | Konfiguration von SpawnNew laden und normalisieren.
# Zweck  : Die drei Konfigurationsschichten lesen, Pfade aufloesen und eine
#          nach Prioritaet sortierte, entdoppelte Quellenliste liefern.
# Input  : Konfigurationsdateien nach docs/Dateiliste.md Abschnitt 7.
# Output : Get-SpawnNewConfig liefert ein Objekt mit Einstellungen, Quellen
#          und Diagnosen. Expand-SpawnNewPath loest einzelne Pfade auf.
# Deps   : Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

$script:ScopeRank = @{ personal = 0; shared = 1 }

function Add-SpawnNewDiagnostic {
    <#
    .SYNOPSIS
    Haengt einen Diagnoseeintrag an eine Diagnoseliste an.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics,
        [Parameter(Mandatory)][ValidateSet('error', 'warning', 'info')][string]$Severity,
        [Parameter(Mandatory)][ValidateSet('config', 'source', 'action')][string]$Area,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$Message
    )

    $entry = [pscustomobject]@{
        Severity = $Severity
        Area     = $Area
        Path     = $Path
        Message  = $Message
    }
    [void]$Diagnostics.Add($entry)
}

function Expand-SpawnNewPath {
    <#
    .SYNOPSIS
    Loest Umgebungsvariablen und %SPAWNNEW_APP% in einem Pfad auf.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    if ($Path.Length -eq 0) { return '' }

    $result = $Path.Replace('%SPAWNNEW_APP%', $AppDirectory)
    return [System.Environment]::ExpandEnvironmentVariables($result)
}

function Get-SpawnNewPathKey {
    <#
    .SYNOPSIS
    Vergleichsschluessel eines Pfades fuer das Entdoppeln der Quellenliste.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    return $Path.TrimEnd('\', '/').ToLowerInvariant()
}

function Get-SpawnNewDataDirectory {
    <#
    .SYNOPSIS
    Benutzerdatenverzeichnis von SpawnNew, getrennt von den Programmdateien.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Join-Path $env:LOCALAPPDATA 'SpawnNew')
}

function Get-SpawnNewConfigLayerPath {
    <#
    .SYNOPSIS
    Die Konfigurationsschichten in Auswertungsreihenfolge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$AppDirectory)

    $machine = Join-Path (Join-Path $env:ProgramData 'SpawnNew') 'spawnnew.settings.json'
    $user    = Join-Path (Get-SpawnNewDataDirectory) 'spawnnew.settings.json'
    $default = Join-Path $AppDirectory 'spawnnew.settings.default.json'

    return [string[]]@($user, $machine, $default)
}

function Test-SpawnNewProperty {
    <#
    .SYNOPSIS
    Prueft, ob ein Objekt aus ConvertFrom-Json die genannte Eigenschaft hat.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $false }
    return ($InputObject.PSObject.Properties.Name -contains $Name)
}

function Read-SpawnNewJsonFile {
    <#
    .SYNOPSIS
    Liest eine UTF-8-JSON-Datei. Liefert $null, wenn sie fehlt oder
    ungueltig ist; der Grund landet in der Diagnoseliste.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('config', 'source', 'action')][string]$Area,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    try {
        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        return (ConvertFrom-Json -InputObject $text)
    }
    catch {
        $message = 'Datei ist keine gültige JSON: ' + $_.Exception.Message
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' `
            -Area $Area -Path $Path -Message $message
        return $null
    }
}

function Get-SpawnNewIntProperty {
    <#
    .SYNOPSIS
    Liest eine Ganzzahl aus einem JSON-Objekt. Bei fehlendem oder
    unbrauchbarem Wert gilt die Vorgabe.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Default,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    if (-not (Test-SpawnNewProperty $InputObject $Name)) { return $Default }

    $parsed = 0
    if ([int]::TryParse([string]$InputObject.$Name, [ref]$parsed)) { return $parsed }

    $message = "'$Name' ist keine Ganzzahl; es gilt $Default."
    Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
        -Area 'config' -Path $Path -Message $message
    return $Default
}

function ConvertTo-SpawnNewSource {
    <#
    .SYNOPSIS
    Prueft einen Quelleneintrag und ergaenzt Vorgaben. Liefert $null, wenn
    der Eintrag unbrauchbar ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Entry,
        [Parameter(Mandatory)][int]$LayerIndex,
        [Parameter(Mandatory)][int]$EntryIndex,
        [Parameter(Mandatory)][string]$LayerPath,
        [Parameter(Mandatory)][string]$AppDirectory,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $rawPath = ''
    if (Test-SpawnNewProperty $Entry 'path') { $rawPath = [string]$Entry.path }

    if ($rawPath.Trim().Length -eq 0) {
        $message = "Quelle $EntryIndex hat keinen Pfad und wird übersprungen."
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' `
            -Area 'config' -Path $LayerPath -Message $message
        return $null
    }

    $scope = 'shared'
    if (Test-SpawnNewProperty $Entry 'scope') { $scope = [string]$Entry.scope }

    if (-not $script:ScopeRank.ContainsKey($scope)) {
        $message = "Quelle '$rawPath' hat die unbekannte Ebene '$scope'; es gilt 'shared'."
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
            -Area 'config' -Path $LayerPath -Message $message
        $scope = 'shared'
    }

    $order = Get-SpawnNewIntProperty -InputObject $Entry -Name 'order' -Default 1000 `
        -Path $LayerPath -Diagnostics $Diagnostics

    $expanded = Expand-SpawnNewPath -Path $rawPath -AppDirectory $AppDirectory

    $name = $expanded
    if (Test-SpawnNewProperty $Entry 'name') { $name = [string]$Entry.name }

    return [pscustomobject]@{
        Name       = $name
        RawPath    = $rawPath
        Path       = $expanded
        Key        = (Get-SpawnNewPathKey -Path $expanded)
        Scope      = $scope
        Order      = $order
        ScopeRank  = $script:ScopeRank[$scope]
        LayerIndex = $LayerIndex
        EntryIndex = $EntryIndex
        LayerPath  = $LayerPath
    }
}

function ConvertTo-SpawnNewCommand {
    <#
    .SYNOPSIS
    Normalisiert einen Einzeiler aus der Konfiguration. Der Befehl wird
    aufgeloest, damit er vor der Ausfuehrung vollstaendig angezeigt werden kann.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Entry,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $command = ''
    if (Test-SpawnNewProperty $Entry 'command') { $command = [string]$Entry.command }
    if ($command.Trim().Length -eq 0) { return $null }

    $admin = $false
    if (Test-SpawnNewProperty $Entry 'requiresAdmin') { $admin = [bool]$Entry.requiresAdmin }

    return [pscustomobject]@{
        Command       = (Expand-SpawnNewPath -Path $command -AppDirectory $AppDirectory)
        RequiresAdmin = $admin
    }
}

function Get-SpawnNewSourceSortOrder {
    <#
    .SYNOPSIS
    Sortierschluessel der Quellen nach docs/Dateiliste.md Abschnitt 9.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    return [hashtable[]]@(
        @{ Expression = 'Order' },
        @{ Expression = 'ScopeRank' },
        @{ Expression = 'LayerIndex' },
        @{ Expression = 'EntryIndex' }
    )
}

function Get-SpawnNewConfig {
    <#
    .SYNOPSIS
    Liefert die zusammengefuehrte Konfiguration.
    .DESCRIPTION
    Einzelwerte stammen aus der ersten Schicht, die sie definiert. Die
    Quellenlisten aller Schichten werden verbunden, nach Prioritaet sortiert
    und anhand des aufgeloesten Pfades entdoppelt.
    #>
    [CmdletBinding()]
    param(
        [string]$AppDirectory = $PSScriptRoot,
        [string[]]$LayerPath,
        [System.Collections.ArrayList]$Diagnostics
    )

    if (-not $LayerPath) {
        $LayerPath = Get-SpawnNewConfigLayerPath -AppDirectory $AppDirectory
    }
    if ($null -eq $Diagnostics) {
        $Diagnostics = New-Object System.Collections.ArrayList
    }

    $defaults = @{ sourceTimeoutMs = 1500; cacheMaxAgeMinutes = 1440; scanDepth = 3 }
    $scalars  = @{}
    $install   = $null
    $update    = $null
    $collected = New-Object System.Collections.ArrayList

    for ($i = 0; $i -lt $LayerPath.Count; $i++) {
        $layer = Read-SpawnNewJsonFile -Path $LayerPath[$i] -Area 'config' -Diagnostics $Diagnostics
        if ($null -eq $layer) { continue }

        foreach ($key in @($defaults.Keys)) {
            if ($scalars.ContainsKey($key)) { continue }
            if (-not (Test-SpawnNewProperty $layer $key)) { continue }

            $scalars[$key] = Get-SpawnNewIntProperty -InputObject $layer -Name $key `
                -Default $defaults[$key] -Path $LayerPath[$i] -Diagnostics $Diagnostics
        }

        if ($null -eq $install -and (Test-SpawnNewProperty $layer 'install')) {
            $install = $layer.install
        }
        if ($null -eq $update -and (Test-SpawnNewProperty $layer 'update')) {
            $update = $layer.update
        }

        if (-not (Test-SpawnNewProperty $layer 'sources')) { continue }

        $entryIndex = 0
        foreach ($entry in @($layer.sources)) {
            $source = ConvertTo-SpawnNewSource -Entry $entry -LayerIndex $i `
                -EntryIndex $entryIndex -LayerPath $LayerPath[$i] `
                -AppDirectory $AppDirectory -Diagnostics $Diagnostics
            $entryIndex++
            if ($null -ne $source) { [void]$collected.Add($source) }
        }
    }

    foreach ($key in @($defaults.Keys)) {
        if (-not $scalars.ContainsKey($key)) { $scalars[$key] = $defaults[$key] }
    }

    $seen    = @{}
    $sources = New-Object System.Collections.ArrayList
    $ordered = $collected | Sort-Object -Property (Get-SpawnNewSourceSortOrder)

    foreach ($source in $ordered) {
        if ($seen.ContainsKey($source.Key)) {
            $message = "Quelle '$($source.Path)' ist mehrfach konfiguriert; der zuerst priorisierte Eintrag gilt."
            Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
                -Area 'config' -Path $source.LayerPath -Message $message
            continue
        }
        $seen[$source.Key] = $true
        [void]$sources.Add($source)
    }

    return [pscustomobject]@{
        AppDirectory       = $AppDirectory
        LayerPath          = $LayerPath
        SourceTimeoutMs    = $scalars['sourceTimeoutMs']
        CacheMaxAgeMinutes = $scalars['cacheMaxAgeMinutes']
        ScanDepth          = $scalars['scanDepth']
        Sources            = $sources.ToArray()
        Install            = (ConvertTo-SpawnNewCommand -Entry $install -AppDirectory $AppDirectory)
        Update             = (ConvertTo-SpawnNewCommand -Entry $update -AppDirectory $AppDirectory)
        Diagnostics        = $Diagnostics
    }
}

Export-ModuleMember -Function Add-SpawnNewDiagnostic, Expand-SpawnNewPath, Get-SpawnNewPathKey, Get-SpawnNewDataDirectory, Get-SpawnNewConfigLayerPath, Test-SpawnNewProperty, ConvertTo-SpawnNewCommand, Read-SpawnNewJsonFile, Get-SpawnNewIntProperty, Get-SpawnNewConfig
