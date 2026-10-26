# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 2: Git-Projekt.
# Zweck  : Zielordner anlegen, ein lokales Git-Repository initialisieren,
#          .gitignore aus einer Vorlage und README.md schreiben und optional
#          den ersten Commit anlegen. Kein Remote, keine Veroeffentlichung.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: name, gitignore, beschreibung, commit.
# Output : Fortschritt in progressFile, Ergebnis in resultFile.
#          Rueckgabewert nach Abschnitt 5 des Vertrags.
# Deps   : Windows PowerShell 5.1, git.exe im Pfad, Vorlagen im Unterordner
#          Gitignore des Aktionsverzeichnisses.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ContextFile)

$ErrorActionPreference = 'Stop'

$utf8    = New-Object System.Text.UTF8Encoding $false
$context = ConvertFrom-Json ([System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8))
$created = New-Object System.Collections.ArrayList
$state   = [pscustomobject]@{ Step = 'Voraussetzungen pruefen'; Skipped = 0 }

function Write-ProgressLine {
    param([Parameter(Mandatory)][hashtable]$Entry)

    $line = (ConvertTo-Json -InputObject ([pscustomobject]$Entry) -Compress) + "`r`n"
    [System.IO.File]::AppendAllText($context.progressFile, $line, $utf8)
}

function Write-Step {
    param([string]$Text, [int]$Percent)

    $state.Step = $Text
    Write-ProgressLine -Entry @{ type = 'step'; text = $Text; percent = $Percent }
}

function Add-Created {
    param([string]$Kind, [string]$Path)

    [void]$created.Add([pscustomobject]@{ kind = $Kind; path = $Path })
    Write-ProgressLine -Entry @{ type = 'created'; kind = $Kind; path = $Path }
}

function Write-Result {
    param([string]$Status, [string]$Message, $Failure = $null)

    $result = [pscustomobject]@{
        schemaVersion = 1
        status        = $Status
        message       = $Message
        created       = $created.ToArray()
        error         = $Failure
    }
    $json = ConvertTo-Json -InputObject $result -Depth 5
    [System.IO.File]::WriteAllText($context.resultFile, $json, $utf8)
}

function Exit-Failed {
    param([string]$Reason, [string]$Details = '')

    $failure = [pscustomobject]@{ step = $state.Step; reason = $Reason; details = $Details }
    Write-Result -Status 'failed' -Message 'Es wurde nichts angelegt.' -Failure $failure
    exit 1
}

function Exit-IfCancelled {
    if (-not [System.IO.File]::Exists($context.cancelFile)) { return }

    Write-Result -Status 'cancelled' -Message ('Abbruch vor dem Schritt "' + $state.Step + '".')
    exit 3
}

function Invoke-Git {
    <#
    .SYNOPSIS
    Ruft git auf und liefert Rueckgabewert und Ausgabe.
    .DESCRIPTION
    git schreibt Hinweise auch bei Erfolg nach stderr. Unter Windows
    PowerShell 5.1 wuerde das mit ErrorActionPreference Stop als Fehler
    gelten; massgeblich ist deshalb allein der Rueckgabewert.
    #>
    param([Parameter(Mandatory)][string[]]$Argument)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @Argument 2>&1 | ForEach-Object { [string]$_ })
        $code   = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    return [pscustomobject]@{ ExitCode = $code; Text = ($output -join "`r`n") }
}

function Invoke-GitChecked {
    param([Parameter(Mandatory)][string[]]$Argument)

    $call = Invoke-Git -Argument $Argument
    if ($call.ExitCode -ne 0) {
        throw ('git ' + $Argument[2] + ' endete mit Rueckgabewert ' + $call.ExitCode + ': ' + $call.Text)
    }
}

function Write-TextFile {
    <#
    .SYNOPSIS
    Schreibt eine Datei, ausser sie ist vorhanden und Ueberschreiben ist
    nicht bestaetigt. Dann bleibt sie unberuehrt und es gibt eine Warnung.
    #>
    param([string]$Path, [string]$Name, [scriptblock]$Writer)

    if ([System.IO.File]::Exists($Path) -and $context.conflictPolicy -ne 'overwrite') {
        Write-ProgressLine -Entry @{ type = 'warn'; text = ($Name + ' ist vorhanden und wird nicht angetastet.') }
        $state.Skipped++
        return
    }

    & $Writer
    Add-Created -Kind 'file' -Path $Path
}

$target     = [string]$context.targetPath
$name       = [string]$context.fields.name
$vorlage    = [string]$context.fields.gitignore
$commit     = [bool]$context.fields.commit
$repository = Join-Path $target '.git'

try {
    Write-Step -Text 'Voraussetzungen pruefen' -Percent 5

    if (Test-Path -LiteralPath $repository) {
        Exit-Failed -Reason 'Im Zielordner liegt bereits ein Git-Repository.' -Details $repository
    }

    $vorlageDatei = ''
    if ($vorlage.Length -gt 0 -and $vorlage -ne 'Keine') {
        $vorlageDatei = Join-Path (Join-Path $context.actionDirectory 'Gitignore') ($vorlage + '.gitignore')
        if (-not [System.IO.File]::Exists($vorlageDatei)) {
            Exit-Failed -Reason ("Die Gitignore-Vorlage '$vorlage' fehlt.") -Details $vorlageDatei
        }
    }

    # Ohne Namen und E-Mail scheitert der Commit erst am Ende. Darum vorher
    # pruefen; SpawnNew richtet die Identitaet nicht selbst ein.
    if ($commit) {
        foreach ($ident in @('GIT_AUTHOR_IDENT', 'GIT_COMMITTER_IDENT')) {
            if ((Invoke-Git -Argument @('var', $ident)).ExitCode -ne 0) {
                $hinweis = @(
                    'git config --global user.name "Vorname Nachname"',
                    'git config --global user.email "name@example.org"'
                ) -join "`r`n"
                Exit-Failed -Reason 'Git kennt keinen Namen und keine E-Mail fuer Commits (user.name, user.email). Entweder einmal einrichten oder ohne ersten Commit anlegen.' -Details $hinweis
            }
        }
    }

    Write-Step -Text 'Zielordner anlegen' -Percent 15
    if (-not [System.IO.Directory]::Exists($target)) {
        [void](New-Item -ItemType Directory -Path $target -Force)
        Add-Created -Kind 'folder' -Path $target
    }

    Write-Step -Text 'Repository initialisieren' -Percent 30
    Exit-IfCancelled
    Invoke-GitChecked -Argument @('-C', $target, 'init', '--quiet')
    Add-Created -Kind 'repository' -Path $repository

    if ($vorlageDatei.Length -gt 0) {
        Write-Step -Text ('.gitignore aus Vorlage ' + $vorlage + ' anlegen') -Percent 50
        Exit-IfCancelled
        $gitignore = Join-Path $target '.gitignore'
        Write-TextFile -Path $gitignore -Name '.gitignore' -Writer { [System.IO.File]::Copy($vorlageDatei, $gitignore, $true) }
    }

    Write-Step -Text 'README.md anlegen' -Percent 70
    Exit-IfCancelled

    $beschreibung = [string]$context.fields.beschreibung
    if ($beschreibung.Length -eq 0) { $beschreibung = '(keine Beschreibung angegeben)' }

    $zeilen = @(
        ('# ' + $name),
        '',
        $beschreibung,
        '',
        ('Angelegt am ' + (Get-Date -Format 'dd.MM.yyyy') + ' mit SpawnNew.')
    )
    if ($vorlageDatei.Length -gt 0) { $zeilen += @('', ('Gitignore-Vorlage: ' + $vorlage)) }

    $readme = Join-Path $target 'README.md'
    $text   = ($zeilen -join "`r`n") + "`r`n"
    Write-TextFile -Path $readme -Name 'README.md' -Writer { [System.IO.File]::WriteAllText($readme, $text, (New-Object System.Text.UTF8Encoding $true)) }

    if ($commit) {
        Write-Step -Text 'Ersten Commit anlegen' -Percent 85
        Exit-IfCancelled
        Invoke-GitChecked -Argument @('-C', $target, 'add', '--all')

        $offen = Invoke-Git -Argument @('-C', $target, 'status', '--porcelain')
        if ($offen.Text.Trim().Length -eq 0) {
            Write-ProgressLine -Entry @{ type = 'warn'; text = 'Keine Dateien fuer einen Commit vorhanden; der erste Commit entfaellt.' }
            $state.Skipped++
        }
        else {
            Invoke-GitChecked -Argument @('-C', $target, 'commit', '--quiet', '-m', 'Projekt mit SpawnNew angelegt')
            Write-ProgressLine -Entry @{ type = 'info'; text = 'Erster Commit angelegt.' }
        }
    }

    Write-Step -Text 'Fertig' -Percent 100

    if ($state.Skipped -gt 0) {
        Write-Result -Status 'partial' -Message 'Repository angelegt; vorhandene Dateien blieben unveraendert.'
        exit 2
    }

    Write-Result -Status 'success' -Message ('Git-Projekt ' + $name + ' angelegt.')
    exit 0
}
catch {
    $failure = [pscustomobject]@{
        step    = $state.Step
        reason  = $_.Exception.Message
        details = ([string]$_.ScriptStackTrace)
    }
    $status = if ($created.Count -gt 0) { 'partial' } else { 'failed' }
    Write-Result -Status $status -Message 'Die Aktion wurde nicht vollstaendig ausgefuehrt.' -Failure $failure
    if ($status -eq 'partial') { exit 2 }
    exit 1
}
