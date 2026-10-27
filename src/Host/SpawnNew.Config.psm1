# SpawnNew.Config.psm1
# Version 1.1 | Konfiguration von SpawnNew laden und normalisieren.
# Zweck  : Die drei Konfigurationsschichten lesen, Pfade aufloesen und eine
#          nach Prioritaet sortierte, entdoppelte Quellenliste liefern.
# Input  : Konfigurationsdateien nach docs/Dateiliste.md Abschnitt 7.
# Output : Get-SpawnNewConfig liefert ein Objekt mit Einstellungen, Quellen
#          und Diagnosen. Expand-SpawnNewPath loest einzelne Pfade auf.
# Deps   : Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

$script:ScopeRank    = @{ personal = 0; shared = 1 }
$script:ModuleRoot   = $PSScriptRoot
$script:PortableName = 'spawnnew.portable.json'

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
    Loest Umgebungsvariablen, %SPAWNNEW_APP% und %SPAWNNEW_DATA% in einem
    Pfad auf.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    if ($Path.Length -eq 0) { return '' }

    $result = $Path.Replace('%SPAWNNEW_APP%', $AppDirectory)
    if ($result.Contains('%SPAWNNEW_DATA%')) {
        $result = $result.Replace('%SPAWNNEW_DATA%', (Get-SpawnNewDataDirectory -AppDirectory $AppDirectory))
    }
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

function Get-SpawnNewPortableFile {
    <#
    .SYNOPSIS
    Markierungsdatei einer Installation im Cloudordner.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$AppDirectory)

    return (Join-Path $AppDirectory $script:PortableName)
}

function Get-SpawnNewDataDirectory {
    <#
    .SYNOPSIS
    Datenverzeichnis fuer Einstellungen, persoenliche Aktionen und eigene
    Vorlagen, getrennt von den Programmdateien.
    .DESCRIPTION
    Liegt neben dem Programmverzeichnis eine Markierungsdatei, gilt das dort
    genannte Verzeichnis, relativ zum Programmverzeichnis. So zeigt eine
    Installation in OneDrive oder Google Drive auf jedem Rechner auf den
    eigenen Pfad des Cloudordners, unabhaengig von Laufwerk und Benutzer.
    Ohne Markierung gilt %LOCALAPPDATA%\SpawnNew.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$AppDirectory = $script:ModuleRoot)

    $marker = Get-SpawnNewPortableFile -AppDirectory $AppDirectory
    if ([System.IO.File]::Exists($marker)) {
        try {
            $data = ConvertFrom-Json ([System.IO.File]::ReadAllText($marker, [System.Text.Encoding]::UTF8))
            $relative = [string]$data.dataDirectory
            if ($relative.Length -gt 0) {
                return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($AppDirectory, $relative)).TrimEnd('\')
            }
        }
        catch {
            Write-Verbose ('Markierungsdatei unlesbar, es gilt das lokale Verzeichnis: ' + $_.Exception.Message)
        }
    }
    return (Get-SpawnNewLocalDirectory)
}

function Get-SpawnNewLocalDirectory {
    <#
    .SYNOPSIS
    Rechnergebundenes Verzeichnis fuer Geheimnisse, Cache und Protokolle.
    .DESCRIPTION
    Bleibt auch bei einer Installation im Cloudordner lokal: Geheimnisse
    sind an Benutzer und Rechner gebunden, Cache und Protokolle wuerden
    zwischen Rechnern Synchronisationskonflikte erzeugen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Join-Path $env:LOCALAPPDATA 'SpawnNew')
}

function Test-SpawnNewPortable {
    <#
    .SYNOPSIS
    Prueft, ob ein Programmverzeichnis zu einer Installation im
    Cloudordner gehoert.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$AppDirectory)

    return [System.IO.File]::Exists((Get-SpawnNewPortableFile -AppDirectory $AppDirectory))
}

function Get-SpawnNewConfigLayerPath {
    <#
    .SYNOPSIS
    Die Konfigurationsschichten in Auswertungsreihenfolge.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$AppDirectory)

    $layers = New-Object System.Collections.ArrayList

    if ($env:LOCALAPPDATA -or (Test-SpawnNewPortable -AppDirectory $AppDirectory)) {
        [void]$layers.Add((Join-Path (Get-SpawnNewDataDirectory -AppDirectory $AppDirectory) 'spawnnew.settings.json'))
    }
    if ($env:ProgramData) {
        [void]$layers.Add((Join-Path (Join-Path $env:ProgramData 'SpawnNew') 'spawnnew.settings.json'))
    }
    [void]$layers.Add((Join-Path $AppDirectory 'spawnnew.settings.default.json'))

    return [string[]]$layers.ToArray()
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

function ConvertTo-SpawnNewEndpoint {
    <#
    .SYNOPSIS
    Prueft einen Endpunkteintrag der KI-Anbindung. Liefert $null, wenn er
    unbrauchbar ist. Ein Schluessel steht nie hier, nur der Name des
    Geheimnisses.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Entry,
        [Parameter(Mandatory)][string]$LayerPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $name = ''
    $url  = ''
    if (Test-SpawnNewProperty $Entry 'name')    { $name = ([string]$Entry.name).Trim() }
    if (Test-SpawnNewProperty $Entry 'baseUrl') { $url  = ([string]$Entry.baseUrl).Trim() }

    if ($name.Length -eq 0 -or $url -notmatch '^https?://') {
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' -Area 'config' `
            -Path $LayerPath -Message "KI-Endpunkt '$name' braucht einen Namen und eine baseUrl mit http:// oder https://; er wird übersprungen."
        return $null
    }

    $model = ''
    if (Test-SpawnNewProperty $Entry 'model') { $model = ([string]$Entry.model).Trim() }

    $secret = ''
    if (Test-SpawnNewProperty $Entry 'secret') { $secret = ([string]$Entry.secret).Trim() }

    $timeout = Get-SpawnNewIntProperty -InputObject $Entry -Name 'timeoutSeconds' -Default 120 -Path $LayerPath -Diagnostics $Diagnostics
    if ($timeout -le 0) { $timeout = 120 }

    return [pscustomobject]@{
        Name           = $name
        BaseUrl        = $url
        Model          = $model
        TimeoutSeconds = $timeout
        Secret         = $secret
    }
}

function Get-SpawnNewEndpoint {
    <#
    .SYNOPSIS
    Ein KI-Endpunkt nach Namen, ohne Namen der voreingestellte. Liefert
    $null, wenn keiner konfiguriert ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$Name
    )

    $endpoints = @($Config.Llm.Endpoints)
    if ($endpoints.Count -eq 0) { return $null }

    $wanted = $Name
    if (-not $wanted) { $wanted = $Config.Llm.DefaultEndpoint }

    foreach ($endpoint in $endpoints) {
        if ($endpoint.Name -eq $wanted) { return $endpoint }
    }
    if ($Name) { return $null }
    return $endpoints[0]
}

function Get-SpawnNewSourceSortOrder {
    <#
    .SYNOPSIS
    Sortierschluessel der Quellen nach docs/Dateiliste.md Abschnitt 10.
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
    $endpoints = New-Object System.Collections.ArrayList
    $endpointSeen    = @{}
    $defaultEndpoint = ''

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

        # KI-Endpunkte: wie Quellen ueber alle Schichten verbunden, bei
        # gleichem Namen gewinnt die erste Schicht.
        if (Test-SpawnNewProperty $layer 'llm') {
            $llm = $layer.llm
            if ($defaultEndpoint.Length -eq 0 -and (Test-SpawnNewProperty $llm 'defaultEndpoint')) {
                $defaultEndpoint = ([string]$llm.defaultEndpoint).Trim()
            }
            if (Test-SpawnNewProperty $llm 'endpoints') {
                foreach ($entry in @($llm.endpoints)) {
                    $endpoint = ConvertTo-SpawnNewEndpoint -Entry $entry -LayerPath $LayerPath[$i] -Diagnostics $Diagnostics
                    if ($null -eq $endpoint) { continue }
                    $key = $endpoint.Name.ToLowerInvariant()
                    if ($endpointSeen.ContainsKey($key)) { continue }
                    $endpointSeen[$key] = $true
                    [void]$endpoints.Add($endpoint)
                }
            }
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
        Llm                = [pscustomobject]@{ DefaultEndpoint = $defaultEndpoint; Endpoints = $endpoints.ToArray() }
        Diagnostics        = $Diagnostics
    }
}

Export-ModuleMember -Function Add-SpawnNewDiagnostic, Expand-SpawnNewPath, Get-SpawnNewPathKey, Get-SpawnNewPortableFile, Get-SpawnNewDataDirectory, Get-SpawnNewLocalDirectory, Test-SpawnNewPortable, Get-SpawnNewConfigLayerPath, Test-SpawnNewProperty, ConvertTo-SpawnNewCommand, Read-SpawnNewJsonFile, Get-SpawnNewIntProperty, ConvertTo-SpawnNewEndpoint, Get-SpawnNewEndpoint, Get-SpawnNewConfig
