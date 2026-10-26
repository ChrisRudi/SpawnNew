# SpawnNew.Catalog.psm1
# Version 1.0 | Aktionsquellen abtasten und den Menuekatalog aufloesen.
# Zweck  : Aktionen in den konfigurierten Quellen finden, Aktions-IDs bilden,
#          Beschreibungen pruefen, Prioritaet aufloesen und bei nicht
#          erreichbarer Quelle auf den Metadaten-Cache zurueckfallen.
# Input  : Konfigurationsobjekt aus Get-SpawnNewConfig.
# Output : Get-SpawnNewCatalog liefert Aktionen und Diagnosen.
#          Test-SpawnNewAction prueft eine Aktion erneut vor der Ausfuehrung.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')

$script:EntryPointName    = 'Invoke-SpawnAction.ps1'
$script:DescriptionName   = 'action.json'
$script:ExplicitIdPattern = '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$'
$script:SchemaVersion     = 1

function Get-SpawnNewShortHash {
    <#
    .SYNOPSIS
    Erste 16 Hexstellen des SHA256 einer Zeichenkette.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash  = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 8; $i++) {
        [void]$builder.Append($hash[$i].ToString('x2'))
    }
    return $builder.ToString()
}

function Get-SpawnNewAutoActionId {
    <#
    .SYNOPSIS
    Deterministische Aktions-ID aus Quelle und relativem Pfad.
    .DESCRIPTION
    Das Praefix 'auto:' enthaelt einen Doppelpunkt, der im Muster der
    expliziten ID nicht erlaubt ist. Eine automatische ID kann deshalb keine
    explizite ID verdraengen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $key = (Get-SpawnNewPathKey -Path $SourcePath) + '|' + $RelativePath.ToLowerInvariant()
    return 'auto:' + (Get-SpawnNewShortHash -Text $key)
}

function Test-SpawnNewExplicitActionId {
    <#
    .SYNOPSIS
    Prueft eine explizit deklarierte Aktions-ID gegen das festgelegte Muster.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Id)

    return ($Id -match $script:ExplicitIdPattern)
}

function Resolve-SpawnNewContainedPath {
    <#
    .SYNOPSIS
    Loest einen relativen Pfad innerhalb eines Verzeichnisses auf. Liefert
    $null, wenn der Pfad das Verzeichnis verlaesst.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$RelativePath
    )

    try {
        $root = [System.IO.Path]::GetFullPath($Directory)
        $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, $RelativePath))
    }
    catch {
        return $null
    }

    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    $prefix    = $root.TrimEnd($separator) + $separator

    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    return $full
}

function Get-SpawnNewBoolProperty {
    <#
    .SYNOPSIS
    Liest einen Wahrheitswert aus einem JSON-Objekt mit Vorgabe.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Default
    )

    if (-not (Test-SpawnNewProperty $InputObject $Name)) { return $Default }
    return [bool]$InputObject.$Name
}

function Get-SpawnNewStringProperty {
    <#
    .SYNOPSIS
    Liest eine Zeichenkette aus einem JSON-Objekt mit Vorgabe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Default
    )

    if (-not (Test-SpawnNewProperty $InputObject $Name)) { return $Default }

    $value = [string]$InputObject.$Name
    if ($value.Trim().Length -eq 0) { return $Default }
    return $value
}

function ConvertTo-SpawnNewActionEntry {
    <#
    .SYNOPSIS
    Baut einen Katalogeintrag mit allen Feldern, die Formular, Zusammenfassung
    und Ausfuehrung benoetigen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('explicit', 'auto')][string]$IdKind,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$EntryPoint,
        [Parameter(Mandatory)][string]$ActionDirectory,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][AllowNull()]$Description,
        [Parameter(Mandatory)][AllowEmptyString()][string]$DescriptionPath,
        [Parameter(Mandatory)]$Source
    )

    $fields        = @()
    $prerequisites = @()
    $plannedSteps  = @()
    $cleanup       = ''

    if (Test-SpawnNewProperty $Description 'fields')        { $fields        = @($Description.fields) }
    if (Test-SpawnNewProperty $Description 'prerequisites') { $prerequisites = @($Description.prerequisites) }
    if (Test-SpawnNewProperty $Description 'plannedSteps')  { $plannedSteps  = @($Description.plannedSteps) }
    if (Test-SpawnNewProperty $Description 'cleanup')       { $cleanup       = [string]$Description.cleanup }

    return [pscustomobject]@{
        Id              = $Id
        IdKind          = $IdKind
        Title           = $Title
        Category        = (Get-SpawnNewStringProperty -InputObject $Description -Name 'category' -Default '')
        Icon            = (Get-SpawnNewStringProperty -InputObject $Description -Name 'icon' -Default '')
        EntryPoint      = $EntryPoint
        ActionDirectory = $ActionDirectory
        RelativePath    = $RelativePath
        DescriptionPath = $DescriptionPath
        RequiresAdmin   = (Get-SpawnNewBoolProperty -InputObject $Description -Name 'requiresAdmin' -Default $false)
        SupportsCancel  = (Get-SpawnNewBoolProperty -InputObject $Description -Name 'supportsCancel' -Default $false)
        AllowsOverwrite = (Get-SpawnNewBoolProperty -InputObject $Description -Name 'allowsOverwrite' -Default $false)
        DefaultTarget   = (Get-SpawnNewStringProperty -InputObject $Description -Name 'defaultTarget' -Default '')
        Fields          = $fields
        Prerequisites   = $prerequisites
        PlannedSteps    = $plannedSteps
        Cleanup         = $cleanup
        SourceName      = $Source.Name
        SourcePath      = $Source.Path
        SourceScope     = $Source.Scope
        Stale           = $false
    }
}

function Read-SpawnNewActionFolder {
    <#
    .SYNOPSIS
    Liest einen Aktionsordner. Liefert $null, wenn er ungueltig ist; der
    Grund landet in der Diagnoseliste.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $folderName      = Split-Path -Leaf $Directory
    $descriptionPath = Join-Path $Directory $script:DescriptionName
    $hasDescription  = Test-Path -LiteralPath $descriptionPath -PathType Leaf
    $description     = $null

    if ($hasDescription) {
        $description = Read-SpawnNewJsonFile -Path $descriptionPath -Area 'action' -Diagnostics $Diagnostics
        if ($null -eq $description) { return $null }

        $version = Get-SpawnNewIntProperty -InputObject $description -Name 'schemaVersion' `
            -Default 0 -Path $descriptionPath -Diagnostics $Diagnostics

        if ($version -ne $script:SchemaVersion) {
            $message = "schemaVersion $version wird nicht unterstützt; erwartet wird $($script:SchemaVersion)."
            Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' `
                -Area 'action' -Path $descriptionPath -Message $message
            return $null
        }
    }
    else {
        $descriptionPath = ''
    }

    $id     = ''
    $idKind = 'auto'

    if (Test-SpawnNewProperty $description 'id') {
        $id = ([string]$description.id).Trim()
        if (-not (Test-SpawnNewExplicitActionId -Id $id)) {
            $message = "Aktions-ID '$id' entspricht nicht dem festgelegten Muster."
            Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' `
                -Area 'action' -Path $descriptionPath -Message $message
            return $null
        }
        $idKind = 'explicit'
    }
    else {
        $id = Get-SpawnNewAutoActionId -SourcePath $Source.Path -RelativePath $RelativePath
    }

    $relativeEntry = Get-SpawnNewStringProperty -InputObject $description -Name 'entryPoint' -Default $script:EntryPointName
    $entryPoint    = Resolve-SpawnNewContainedPath -Directory $Directory -RelativePath $relativeEntry

    if ($null -eq $entryPoint) {
        $message = "entryPoint '$relativeEntry' liegt außerhalb des Aktionsordners."
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' `
            -Area 'action' -Path $Directory -Message $message
        return $null
    }

    if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) {
        $message = "Einstiegsskript '$relativeEntry' fehlt."
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' `
            -Area 'action' -Path $Directory -Message $message
        return $null
    }

    $title  = Get-SpawnNewStringProperty -InputObject $description -Name 'title' -Default $folderName
    $action = ConvertTo-SpawnNewActionEntry -Id $id -IdKind $idKind -Title $title `
        -EntryPoint $entryPoint -ActionDirectory $Directory -RelativePath $RelativePath `
        -Description $description -DescriptionPath $descriptionPath -Source $Source

    if ($action.Cleanup.Length -gt 0) {
        $cleanupPath = Resolve-SpawnNewContainedPath -Directory $Directory -RelativePath $action.Cleanup
        if ($null -eq $cleanupPath -or -not (Test-Path -LiteralPath $cleanupPath -PathType Leaf)) {
            $message = "Aufräumskript '$($action.Cleanup)' fehlt; die Aktion läuft ohne Aufräumen."
            Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
                -Area 'action' -Path $Directory -Message $message
            $action.Cleanup = ''
        }
        else {
            $action.Cleanup = $cleanupPath
        }
    }

    return $action
}

function ConvertTo-SpawnNewScriptAction {
    <#
    .SYNOPSIS
    Katalogeintrag fuer ein einzelnes Skript ohne Beschreibung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)]$Source
    )

    $id    = Get-SpawnNewAutoActionId -SourcePath $Source.Path -RelativePath $RelativePath
    $title = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)

    return ConvertTo-SpawnNewActionEntry -Id $id -IdKind 'auto' -Title $title `
        -EntryPoint $ScriptPath -ActionDirectory (Split-Path -Parent $ScriptPath) `
        -RelativePath $RelativePath -Description $null -DescriptionPath '' -Source $Source
}

function Get-SpawnNewDirectoryAction {
    <#
    .SYNOPSIS
    Taestet ein Verzeichnis ab. Erkennt Aktionsordner und Einzelskripte nach
    docs/Dateiliste.md Abschnitt 10 und steigt nicht in erkannte
    Aktionsordner ab.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RelativePath,
        [Parameter(Mandatory)][int]$Depth,
        [Parameter(Mandatory)][int]$MaxDepth,
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $isRoot = ($RelativePath.Length -eq 0)

    if (-not $isRoot) {
        $hasDescription = Test-Path -LiteralPath (Join-Path $Directory $script:DescriptionName) -PathType Leaf
        $hasEntryPoint  = Test-Path -LiteralPath (Join-Path $Directory $script:EntryPointName) -PathType Leaf

        if ($hasDescription -or $hasEntryPoint) {
            $action = Read-SpawnNewActionFolder -Directory $Directory -RelativePath $RelativePath `
                -Source $Source -Diagnostics $Diagnostics
            if ($null -ne $action) { Write-Output $action }
            return
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.ps1')) {
        $relative = if ($isRoot) { $file.Name } else { $RelativePath + '/' + $file.Name }
        Write-Output (ConvertTo-SpawnNewScriptAction -ScriptPath $file.FullName -RelativePath $relative -Source $Source)
    }

    if ($Depth -ge $MaxDepth) { return }

    foreach ($child in @(Get-ChildItem -LiteralPath $Directory -Directory)) {
        $relative = if ($isRoot) { $child.Name } else { $RelativePath + '/' + $child.Name }
        Get-SpawnNewDirectoryAction -Directory $child.FullName -RelativePath $relative `
            -Depth ($Depth + 1) -MaxDepth $MaxDepth -Source $Source -Diagnostics $Diagnostics
    }
}

function Get-SpawnNewSourceScan {
    <#
    .SYNOPSIS
    Taestet eine Quelle vollstaendig ab.
    .DESCRIPTION
    Liefert die Erreichbarkeit mit, damit der Aufrufer bei einer nicht
    erreichbaren Quelle auf den Metadaten-Cache zurueckfallen kann.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][int]$MaxDepth,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    if (-not [System.IO.Directory]::Exists($Source.Path)) {
        $message = "Quelle '$($Source.Name)' ist nicht erreichbar."
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' `
            -Area 'source' -Path $Source.Path -Message $message
        return [pscustomobject]@{ Reachable = $false; Actions = @() }
    }

    $actions = @(
        Get-SpawnNewDirectoryAction -Directory $Source.Path -RelativePath '' -Depth 0 `
            -MaxDepth $MaxDepth -Source $Source -Diagnostics $Diagnostics
    )
    return [pscustomobject]@{ Reachable = $true; Actions = $actions }
}

Export-ModuleMember -Function Get-SpawnNewShortHash, Get-SpawnNewAutoActionId, Test-SpawnNewExplicitActionId, Resolve-SpawnNewContainedPath, Read-SpawnNewActionFolder, Get-SpawnNewDirectoryAction, Get-SpawnNewSourceScan
