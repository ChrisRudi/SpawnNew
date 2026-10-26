# SpawnNew.Target.psm1
# Version 1.0 | Zielpfad, Konflikte, Voraussetzungen und Zusammenfassung.
# Zweck  : Namen und Zielpfade nach den Windows-Regeln pruefen, Zielart und
#          Zielzustand bestimmen, freien Namen vorschlagen, fehlende
#          Voraussetzungen melden und den Text der Zusammenfassung bauen.
# Input  : Katalogeintrag aus SpawnNew.Catalog.psm1, Explorer-Pfad, Eingaben.
# Output : Pruefergebnisse, Zielpfad, Zielzustand, Zusammenfassungstext.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1, SpawnNew.Input.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Input.psm1')

# Windows-Zeichenverbote, bewusst festgeschrieben: SpawnNew laeuft nur unter
# Windows, und GetInvalidFileNameChars liefert je Plattform andere Mengen.
$script:InvalidNameChars = [char[]]@('<', '>', ':', '"', '/', '\', '|', '?', '*')
$script:InvalidPathChars = [char[]]@('<', '>', '"', '|', '?', '*')
$script:ReservedNames    = @('CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
$script:TargetKinds = @('folder', 'inPlace')

function Test-SpawnNewName {
    <#
    .SYNOPSIS
    Prueft einen Ordner- oder Dateinamen gegen die Windows-Regeln.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    $text = $Name.Trim()

    if ($text.Length -eq 0) {
        return (Get-SpawnNewCheckResult -Valid $false -Message 'Der Name fehlt.' -Value '')
    }

    if ($text.IndexOfAny($script:InvalidNameChars) -ge 0) {
        $list = ($script:InvalidNameChars -join ' ')
        return (Get-SpawnNewCheckResult -Valid $false -Message "Der Name darf diese Zeichen nicht enthalten: $list" -Value $text)
    }

    if ($text.EndsWith('.') -or $text.EndsWith(' ')) {
        return (Get-SpawnNewCheckResult -Valid $false -Message 'Der Name darf nicht mit Punkt oder Leerzeichen enden.' -Value $text)
    }

    $stem = $text
    if ($stem.Contains('.')) { $stem = $stem.Substring(0, $stem.IndexOf('.')) }

    if ($script:ReservedNames -contains $stem.ToUpperInvariant()) {
        return (Get-SpawnNewCheckResult -Valid $false -Message "'$stem' ist ein von Windows belegter Name." -Value $text)
    }

    return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $text)
}

function Test-SpawnNewBasePath {
    <#
    .SYNOPSIS
    Prueft und normalisiert ein Basisverzeichnis.
    .DESCRIPTION
    Erlaubt Laufwerkspfade und UNC-Freigaben. Die Pruefung ist bewusst selbst
    umgesetzt, damit sie auch beim Pruefen auf anderen Plattformen die
    Windows-Regeln anwendet.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $text = $Path.Trim().TrimEnd('\')

    if ($text.Length -eq 0) {
        return (Get-SpawnNewCheckResult -Valid $false -Message 'Der Zielpfad fehlt.' -Value '')
    }

    if ($text.IndexOfAny($script:InvalidPathChars) -ge 0) {
        $list = ($script:InvalidPathChars -join ' ')
        return (Get-SpawnNewCheckResult -Valid $false -Message "Der Zielpfad darf diese Zeichen nicht enthalten: $list" -Value $text)
    }

    if ($text -match '^[A-Za-z]:$') {
        return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value ($text + '\'))
    }

    if ($text -match '^[A-Za-z]:\\[^\\]') {
        return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $text)
    }

    if ($text -match '^\\\\[^\\]+\\[^\\]') {
        return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $text)
    }

    return (Get-SpawnNewCheckResult -Valid $false -Message 'Der Zielpfad muss mit einem Laufwerk oder einer Freigabe beginnen.' -Value $text)
}

function Get-SpawnNewBasePath {
    <#
    .SYNOPSIS
    Vorbelegtes Basisverzeichnis: der Aktionsstandard, sonst der
    Explorer-Ordner.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExplorerPath,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    if ($Action.DefaultTarget.Length -gt 0) {
        return (Expand-SpawnNewPath -Path $Action.DefaultTarget -AppDirectory $AppDirectory)
    }
    return $ExplorerPath
}

function Get-SpawnNewTargetKind {
    <#
    .SYNOPSIS
    Zielart einer Aktion: 'folder' legt einen benannten Unterordner an,
    'inPlace' arbeitet im Basisverzeichnis selbst.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    if (-not (Test-SpawnNewProperty $Action 'TargetKind')) { return 'folder' }

    $kind = [string]$Action.TargetKind
    if ($kind.Length -eq 0) { return 'folder' }

    if ($script:TargetKinds -notcontains $kind) {
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' -Area 'action' `
            -Path $Action.DescriptionPath -Message "targetKind '$kind' ist unbekannt; es gilt 'folder'."
        return 'folder'
    }
    return $kind
}

function Join-SpawnNewTargetPath {
    <#
    .SYNOPSIS
    Setzt Basisverzeichnis und Name zum Zielpfad zusammen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][ValidateSet('folder', 'inPlace')][string]$TargetKind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    if ($TargetKind -eq 'inPlace') { return $BasePath }
    return (Join-Path ($BasePath.TrimEnd('\')) $Name)
}

function Get-SpawnNewTargetState {
    <#
    .SYNOPSIS
    Zustand des Zielpfades fuer die Konfliktfrage aus Abschnitt 7.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $isFile    = [System.IO.File]::Exists($Path)
    $isFolder  = [System.IO.Directory]::Exists($Path)
    $entryCount = 0

    if ($isFolder) {
        $entryCount = @([System.IO.Directory]::EnumerateFileSystemEntries($Path)).Count
    }

    return [pscustomobject]@{
        IsFile     = $isFile
        IsFolder   = $isFolder
        Exists     = ($isFile -or $isFolder)
        IsEmpty    = ($isFolder -and $entryCount -eq 0)
        EntryCount = $entryCount
    }
}

function Get-SpawnNewFreeName {
    <#
    .SYNOPSIS
    Erster freier Name im Basisverzeichnis nach dem Muster 'Name (2)'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$Name,
        [int]$Limit = 999
    )

    $base = $BasePath.TrimEnd('\')
    for ($i = 2; $i -le $Limit; $i++) {
        $candidate = '{0} ({1})' -f $Name, $i
        if (-not (Get-SpawnNewTargetState -Path (Join-Path $base $candidate)).Exists) { return $candidate }
    }
    return ('{0} ({1})' -f $Name, [guid]::NewGuid().ToString('N').Substring(0, 8))
}

function Get-SpawnNewMissingPrerequisite {
    <#
    .SYNOPSIS
    Nicht erfuellte Voraussetzungen einer Aktion. Es wird nichts installiert.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)]$Action)

    $missing = New-Object System.Collections.ArrayList

    foreach ($entry in @($Action.Prerequisites)) {
        $kind = Get-SpawnNewStringOrDefault $entry 'kind' 'command'
        $name = Get-SpawnNewStringOrDefault -InputObject $entry -Name 'name' -Default ''
        if ($name.Length -eq 0) { continue }

        $found = switch ($kind) {
            'command' { $null -ne (Get-Command -Name $name -ErrorAction SilentlyContinue) }
            'module'  { @(Get-Module -Name $name -ListAvailable).Count -gt 0 }
            'file'    { Test-Path -LiteralPath (Join-Path $Action.ActionDirectory $name) }
            default   { $true }
        }

        if ($found) { continue }

        $entryHint = Get-SpawnNewStringOrDefault -InputObject $entry -Name 'hint' -Default ''
        $item = [pscustomobject]@{ Kind = $kind; Name = $name; Hint = $entryHint }
        [void]$missing.Add($item)
    }

    return [object[]]$missing.ToArray()
}

function Get-SpawnNewSummaryText {
    <#
    .SYNOPSIS
    Text der Zusammenfassung vor dem Start nach Abschnitt 3 Schritt 6.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Field,
        [Parameter(Mandatory)][hashtable]$Value,
        [Parameter(Mandatory)][ValidateSet('fail', 'rename', 'overwrite')][string]$ConflictPolicy,
        [Parameter(Mandatory)][bool]$TargetExisted
    )

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('Aktion: ' + $Action.Title)
    [void]$lines.Add('Quelle: ' + $Action.SourceName)
    [void]$lines.Add('Ziel:   ' + $TargetPath)

    if ($TargetExisted) { [void]$lines.Add('Hinweis: Der Zielordner ist vorhanden und wird weiterverwendet.') }

    [void]$lines.Add('')
    [void]$lines.Add('Eingaben:')

    if ($Field.Count -eq 0) {
        [void]$lines.Add('  keine')
    }
    foreach ($entry in $Field) {
        $shown = ''
        if ($Value.ContainsKey($entry.Name)) {
            $raw = $Value[$entry.Name]
            if ($raw -is [bool]) { $shown = if ($raw) { 'Ja' } else { 'Nein' } }
            else { $shown = [string]$raw }
        }
        if ($shown.Length -eq 0) { $shown = '(leer)' }
        [void]$lines.Add('  ' + $entry.Label + ': ' + $shown)
    }

    [void]$lines.Add('')
    [void]$lines.Add('Geplante Schritte:')

    if (@($Action.PlannedSteps).Count -eq 0) {
        [void]$lines.Add('  Die Aktion nennt keine Schritte.')
    }
    foreach ($step in @($Action.PlannedSteps)) {
        [void]$lines.Add('  - ' + [string]$step)
    }

    [void]$lines.Add('')
    [void]$lines.Add('Bei vorhandenen Dateien: ' + (Get-SpawnNewConflictText -ConflictPolicy $ConflictPolicy))

    if ($Action.RequiresAdmin) {
        [void]$lines.Add('Die Aktion fordert Administratorrechte an.')
    }

    return ($lines.ToArray() -join "`r`n")
}

function Get-SpawnNewConflictText {
    <#
    .SYNOPSIS
    Klartext zur gewaehlten Konfliktregel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateSet('fail', 'rename', 'overwrite')][string]$ConflictPolicy)

    switch ($ConflictPolicy) {
        'fail'      { return 'abbrechen, nichts wird überschrieben' }
        'rename'    { return 'neuen Namen verwenden, nichts wird überschrieben' }
        'overwrite' { return 'vorhandene Dateien überschreiben' }
    }
}

Export-ModuleMember -Function Test-SpawnNewName, Test-SpawnNewBasePath, Get-SpawnNewBasePath, Get-SpawnNewTargetKind, Join-SpawnNewTargetPath, Get-SpawnNewTargetState, Get-SpawnNewFreeName, Get-SpawnNewMissingPrerequisite, Get-SpawnNewSummaryText, Get-SpawnNewConflictText
