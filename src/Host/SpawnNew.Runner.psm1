# SpawnNew.Runner.psm1
# Version 1.0 | Start und Auswertung einer Aktion nach docs/Aktionsvertrag.md.
# Zweck  : Laufverzeichnis anlegen, Kontextdatei schreiben, Argumente fuer
#          Windows PowerShell 5.1 bauen, Aktion normal oder erhoeht starten,
#          Fortschritt mitlesen, Ergebnis und Rueckgabewert zu einem Status
#          zusammenfuehren, Abbruch anfordern und Aufraeumen aufrufen.
# Input  : Katalogeintrag, bestaetigter Zielpfad, geprueifte Formularwerte.
# Output : Laufobjekt, Fortschrittseintraege, Statusobjekt.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')

$script:ContextSchemaVersion = 1
$script:ProgressTypes = @('step', 'info', 'warn', 'created')
$script:ResultStates  = @('success', 'partial', 'nochange', 'cancelled', 'failed')

# Rueckgabewerte nach docs/Aktionsvertrag.md Abschnitt 5.
$script:ExitStates = @{ 0 = 'success'; 1 = 'failed'; 2 = 'partial'; 3 = 'cancelled' }

function Get-SpawnNewPowerShellPath {
    <#
    .SYNOPSIS
    Pfad zu Windows PowerShell 5.1, der einzigen unterstuetzten Laufzeit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return ($env:SystemRoot.TrimEnd('\') + '\System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Get-SpawnNewRun {
    <#
    .SYNOPSIS
    Legt ein Laufverzeichnis an und benennt die Dateien des Vertrags.
    #>
    [CmdletBinding()]
    param([string]$Root = ([System.IO.Path]::GetTempPath()))

    $directory = Join-Path $Root ('spawnnew-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
    [void](New-Item -ItemType Directory -Path $directory -Force)

    return [pscustomobject]@{
        Directory    = $directory
        ContextFile  = (Join-Path $directory 'context.json')
        ProgressFile = (Join-Path $directory 'progress.jsonl')
        ResultFile   = (Join-Path $directory 'result.json')
        CancelFile   = (Join-Path $directory 'cancel.flag')
    }
}

function Write-SpawnNewContextFile {
    <#
    .SYNOPSIS
    Schreibt die Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
    .DESCRIPTION
    Alle Eingaben und Pfade gehen ausschliesslich ueber diese Datei an die
    Aktion, damit kein Eingabewert in einen PowerShell-Ausdruck geraet.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExplorerPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][bool]$TargetExisted,
        [Parameter(Mandatory)][ValidateSet('fail', 'rename', 'overwrite')][string]$ConflictPolicy,
        [Parameter(Mandatory)][hashtable]$Value
    )

    $fields = [pscustomobject]@{}
    foreach ($key in @($Value.Keys | Sort-Object)) {
        Add-Member -InputObject $fields -MemberType NoteProperty -Name $key -Value $Value[$key]
    }

    $context = [pscustomobject]@{
        schemaVersion   = $script:ContextSchemaVersion
        actionId        = $Action.Id
        actionDirectory = $Action.ActionDirectory
        explorerPath    = $ExplorerPath
        targetPath      = $TargetPath
        targetExisted   = $TargetExisted
        conflictPolicy  = $ConflictPolicy
        fields          = $fields
        progressFile    = $Run.ProgressFile
        resultFile      = $Run.ResultFile
        cancelFile      = $Run.CancelFile
        culture         = (Get-Culture).Name
    }

    $json = ConvertTo-Json -InputObject $context -Depth 6
    [System.IO.File]::WriteAllText($Run.ContextFile, $json, (New-Object System.Text.UTF8Encoding $false))
    return $Run.ContextFile
}

function Get-SpawnNewActionArgument {
    <#
    .SYNOPSIS
    Argumentliste fuer den Start einer Aktion oder ihres Aufraeumskripts.
    .DESCRIPTION
    Die Liste wird als Feld uebergeben, nicht als zusammengesetzte
    Befehlszeile. Pfade mit Leerzeichen und Umlauten bleiben dadurch intakt.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ContextFile,
        [string]$ResultFile
    )

    $argument = [System.Collections.ArrayList]@(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $ScriptPath, '-ContextFile', $ContextFile
    )

    if ($PSBoundParameters.ContainsKey('ResultFile')) {
        [void]$argument.Add('-ResultFile')
        [void]$argument.Add($ResultFile)
    }

    return [string[]]$argument.ToArray()
}

function Invoke-SpawnNewActionProcess {
    <#
    .SYNOPSIS
    Startet eine Aktion in einem eigenen Prozess.
    .DESCRIPTION
    Bei RequiresAdmin wird RunAs verwendet, was die Windows-Rechteabfrage
    ausloest. Lehnt der Benutzer ab, liefert diese Funktion $null und es
    erfolgt keine fachliche Aenderung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ContextFile,
        [Parameter(Mandatory)][bool]$RequiresAdmin,
        [string]$ResultFile
    )

    $argument = if ($PSBoundParameters.ContainsKey('ResultFile')) {
        Get-SpawnNewActionArgument -ScriptPath $ScriptPath -ContextFile $ContextFile -ResultFile $ResultFile
    }
    else {
        Get-SpawnNewActionArgument -ScriptPath $ScriptPath -ContextFile $ContextFile
    }

    $parameter = @{
        FilePath     = (Get-SpawnNewPowerShellPath)
        ArgumentList = $argument
        PassThru     = $true
        WindowStyle  = 'Hidden'
    }
    if ($RequiresAdmin) { $parameter['Verb'] = 'RunAs' }

    try {
        return (Start-Process @parameter)
    }
    catch [System.ComponentModel.Win32Exception] {
        # Abgelehnte Rechteabfrage. Es wurde nichts gestartet.
        return $null
    }
}

function Request-SpawnNewCancel {
    <#
    .SYNOPSIS
    Fordert den Abbruch an, indem die Abbruchdatei des Laufs angelegt wird.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    [System.IO.File]::WriteAllText($Run.CancelFile, '', (New-Object System.Text.UTF8Encoding $false))
}

function Test-SpawnNewCancelRequested {
    <#
    .SYNOPSIS
    Prueft, ob fuer diesen Lauf ein Abbruch angefordert wurde.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)]$Run)

    return [System.IO.File]::Exists($Run.CancelFile)
}

function Read-SpawnNewProgress {
    <#
    .SYNOPSIS
    Liest neue Fortschrittszeilen ab einer Leseposition.
    .DESCRIPTION
    Es werden nur vollstaendige Zeilen ausgewertet. Die neue Leseposition
    liegt hinter dem letzten Zeilenumbruch, damit eine halb geschriebene
    Zeile beim naechsten Aufruf vollstaendig gelesen wird.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$Offset
    )

    $empty = [pscustomobject]@{ Entry = @(); Offset = $Offset }
    if (-not [System.IO.File]::Exists($Path)) { return $empty }

    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -le $Offset) { return $empty }

        [void]$stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
        $buffer = New-Object byte[] ($stream.Length - $Offset)
        $read   = $stream.Read($buffer, 0, $buffer.Length)
    }
    finally {
        $stream.Dispose()
    }

    $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
    $cut  = $text.LastIndexOf("`n")
    if ($cut -lt 0) { return $empty }

    $complete = $text.Substring(0, $cut + 1)
    $entries  = New-Object System.Collections.ArrayList

    foreach ($line in $complete.Split("`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) { continue }

        $entry = ConvertTo-SpawnNewProgressEntry -Line $trimmed
        if ($null -ne $entry) { [void]$entries.Add($entry) }
    }

    $consumed = [System.Text.Encoding]::UTF8.GetByteCount($complete)
    return [pscustomobject]@{ Entry = $entries.ToArray(); Offset = ($Offset + $consumed) }
}

function ConvertTo-SpawnNewProgressEntry {
    <#
    .SYNOPSIS
    Wandelt eine Fortschrittszeile in einen Eintrag. Liefert $null, wenn die
    Zeile keine gueltige JSON ist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line)

    try { $raw = ConvertFrom-Json -InputObject $Line }
    catch { return $null }

    $type = 'info'
    if (Test-SpawnNewProperty $raw 'type') { $type = [string]$raw.type }
    if ($script:ProgressTypes -notcontains $type) { $type = 'info' }

    $text = ''
    if (Test-SpawnNewProperty $raw 'text') { $text = [string]$raw.text }

    $percent = -1
    if (Test-SpawnNewProperty $raw 'percent') {
        $parsed = 0
        if ([int]::TryParse([string]$raw.percent, [ref]$parsed)) {
            $percent = [System.Math]::Max(0, [System.Math]::Min(100, $parsed))
        }
    }

    $kind = ''
    if (Test-SpawnNewProperty $raw 'kind') { $kind = [string]$raw.kind }

    $path = ''
    if (Test-SpawnNewProperty $raw 'path') { $path = [string]$raw.path }

    return [pscustomobject]@{
        Type    = $type
        Text    = $text
        Percent = $percent
        Kind    = $kind
        Path    = $path
    }
}

function Read-SpawnNewResult {
    <#
    .SYNOPSIS
    Liest die Ergebnisdatei nach docs/Aktionsvertrag.md Abschnitt 4. Liefert
    $null, wenn sie fehlt oder unbrauchbar ist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    if (-not [System.IO.File]::Exists($Run.ResultFile)) { return $null }

    try { $raw = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($Run.ResultFile)) }
    catch { return $null }

    $status = ''
    if (Test-SpawnNewProperty $raw 'status') { $status = ([string]$raw.status).ToLowerInvariant() }
    if ($script:ResultStates -notcontains $status) { return $null }

    $message = ''
    if (Test-SpawnNewProperty $raw 'message') { $message = [string]$raw.message }

    $created = @()
    if (Test-SpawnNewProperty $raw 'created') { $created = @(ConvertTo-SpawnNewResource -Entry $raw.created) }

    $failure = $null
    if ((Test-SpawnNewProperty $raw 'error') -and $null -ne $raw.error) {
        $failure = [pscustomobject]@{
            Step    = (Get-SpawnNewErrorField -Raw $raw.error -Name 'step')
            Reason  = (Get-SpawnNewErrorField -Raw $raw.error -Name 'reason')
            Details = (Get-SpawnNewErrorField -Raw $raw.error -Name 'details')
        }
    }

    return [pscustomobject]@{
        Status  = $status
        Message = $message
        Created = $created
        Error   = $failure
    }
}

function Get-SpawnNewErrorField {
    <#
    .SYNOPSIS
    Einzelfeld aus dem Fehlerblock der Ergebnisdatei.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowNull()]$Raw,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-SpawnNewProperty $Raw $Name)) { return '' }
    return [string]$Raw.$Name
}

function ConvertTo-SpawnNewResource {
    <#
    .SYNOPSIS
    Normalisiert die Liste erstellter Ressourcen.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][AllowNull()]$Entry)

    $resources = New-Object System.Collections.ArrayList

    foreach ($item in @($Entry)) {
        $path = ''
        if (Test-SpawnNewProperty $item 'path') { $path = [string]$item.path }
        if ($path.Length -eq 0) { continue }

        $kind = 'file'
        if (Test-SpawnNewProperty $item 'kind') { $kind = [string]$item.kind }

        [void]$resources.Add([pscustomobject]@{ Kind = $kind; Path = $path })
    }

    return [object[]]$resources.ToArray()
}

function Get-SpawnNewRunStatus {
    <#
    .SYNOPSIS
    Fuehrt Rueckgabewert, Ergebnisdatei und Fortschritt zu einem Status zusammen.
    .DESCRIPTION
    Die Ergebnisdatei gilt vor dem Rueckgabewert. Fehlt sie, lautet der Status
    'unknown'; eine Prozessbeendigung wird nie als Erfolg dargestellt.
    Abschnitt 9 verlangt diese Unterscheidung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][AllowNull()]$Result,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Progress
    )

    $fromProgress = @(
        $Progress |
            Where-Object { $_.Type -eq 'created' } |
            ForEach-Object { [pscustomobject]@{ Kind = $_.Kind; Path = $_.Path } }
    )

    if ($null -eq $Result) {
        $message = 'Die Aktion hat kein Ergebnis hinterlassen. Der Zustand ist unbekannt.'
        if ($fromProgress.Count -gt 0) {
            $message += ' Laut Fortschritt wurden bereits ' + $fromProgress.Count + ' Ressource(n) erstellt.'
        }
        return [pscustomobject]@{
            Status   = 'unknown'
            Message  = $message
            Created  = $fromProgress
            Error    = $null
            Note     = ''
            ExitCode = $ExitCode
        }
    }

    $note = ''
    if ($script:ExitStates.ContainsKey($ExitCode) -and $script:ExitStates[$ExitCode] -ne $Result.Status) {
        if (-not ($ExitCode -eq 0 -and $Result.Status -eq 'nochange')) {
            $note = 'Rückgabewert ' + $ExitCode + ' und Ergebnisdatei weichen ab; die Ergebnisdatei gilt.'
        }
    }
    elseif (-not $script:ExitStates.ContainsKey($ExitCode)) {
        $note = 'Unbekannter Rückgabewert ' + $ExitCode + '; die Ergebnisdatei gilt.'
    }

    $created = $Result.Created
    if ($created.Count -eq 0) { $created = $fromProgress }

    return [pscustomobject]@{
        Status   = $Result.Status
        Message  = $Result.Message
        Created  = $created
        Error    = $Result.Error
        Note     = $note
        ExitCode = $ExitCode
    }
}

function Test-SpawnNewCleanupOffer {
    <#
    .SYNOPSIS
    Prueft, ob fuer diesen Lauf ein Aufraeumen angeboten werden darf.
    .DESCRIPTION
    Nur bei Teilergebnis, Abbruch, Fehler oder unbekanntem Zustand, nur wenn
    die Aktion ein Aufraeumskript nennt und nur wenn ueberhaupt etwas erstellt
    wurde. Abschnitt 9 erlaubt kein Aufraeumen ohne diese Voraussetzungen.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)]$Status
    )

    if ($Action.Cleanup.Length -eq 0) { return $false }
    if (@('partial', 'cancelled', 'failed', 'unknown') -notcontains $Status.Status) { return $false }
    return ($Status.Created.Count -gt 0)
}

Export-ModuleMember -Function Get-SpawnNewPowerShellPath, Get-SpawnNewRun, Write-SpawnNewContextFile, Get-SpawnNewActionArgument, Invoke-SpawnNewActionProcess, Request-SpawnNewCancel, Test-SpawnNewCancelRequested, Read-SpawnNewProgress, ConvertTo-SpawnNewProgressEntry, Read-SpawnNewResult, Get-SpawnNewErrorField, ConvertTo-SpawnNewResource, Get-SpawnNewRunStatus, Test-SpawnNewCleanupOffer
