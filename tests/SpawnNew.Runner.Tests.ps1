# tests/SpawnNew.Runner.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Runner.psm1.
# Zweck  : Kontextdatei, Argumentuebergabe, Fortschritt, Ergebnis, Status und
#          Aufraeumangebot nach docs/Aktionsvertrag.md. Deckt Abnahme 9 und 15.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

function Get-TestActionObject {
    param([string]$Cleanup = '')

    return [pscustomobject]@{
        Id              = 'spawnnew.gitproject'
        ActionDirectory = 'C:\Quelle\Git Projekt'
        Cleanup         = $Cleanup
    }
}

function Add-TestProgress {
    param([string]$Path, [string[]]$Line)

    $text = ''
    if (Test-Path -LiteralPath $Path) { $text = [System.IO.File]::ReadAllText($Path) }
    foreach ($entry in $Line) { $text += $entry + "`r`n" }
    [void](Add-SpawnNewTestFile -Path $Path -Content $text)
}

function Get-TestStatus {
    param([int]$ExitCode, $Result, $Progress = @())

    return (Get-SpawnNewRunStatus -ExitCode $ExitCode -Result $Result -Progress @($Progress))
}

Add-SpawnNewTest 'Laufverzeichnis und Vertragsdateien werden benannt' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work

    Confirm-SpawnNewCondition -Label 'Verzeichnis da' -Condition (Test-Path -LiteralPath $run.Directory -PathType Container)
    Confirm-SpawnNewValue -Label 'Kontext' -Actual (Split-Path -Leaf $run.ContextFile) -Expected 'context.json'
    Confirm-SpawnNewValue -Label 'Fortschritt' -Actual (Split-Path -Leaf $run.ProgressFile) -Expected 'progress.jsonl'
    Confirm-SpawnNewValue -Label 'Ergebnis' -Actual (Split-Path -Leaf $run.ResultFile) -Expected 'result.json'
    Confirm-SpawnNewValue -Label 'Abbruch' -Actual (Split-Path -Leaf $run.CancelFile) -Expected 'cancel.flag'
}

Add-SpawnNewTest 'Kontextdatei enthaelt alle Felder des Vertrags' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work
    [void](Write-SpawnNewContextFile -Run $run -Action (Get-TestActionObject) -ExplorerPath 'D:\Büro' -TargetPath 'D:\Büro\Neues Projekt' -TargetExisted $true -ConflictPolicy 'rename' -Value @{ name = 'Neues Projekt'; gitignore = 'VisualStudio' })

    $context = ConvertFrom-Json ([System.IO.File]::ReadAllText($run.ContextFile))

    Confirm-SpawnNewValue -Label 'schemaVersion' -Actual $context.schemaVersion -Expected 1
    Confirm-SpawnNewValue -Label 'actionId' -Actual $context.actionId -Expected 'spawnnew.gitproject'
    Confirm-SpawnNewValue -Label 'actionDirectory' -Actual $context.actionDirectory -Expected 'C:\Quelle\Git Projekt'
    Confirm-SpawnNewValue -Label 'explorerPath' -Actual $context.explorerPath -Expected 'D:\Büro'
    Confirm-SpawnNewValue -Label 'targetPath' -Actual $context.targetPath -Expected 'D:\Büro\Neues Projekt'
    Confirm-SpawnNewValue -Label 'targetExisted' -Actual $context.targetExisted -Expected $true
    Confirm-SpawnNewValue -Label 'conflictPolicy' -Actual $context.conflictPolicy -Expected 'rename'
    Confirm-SpawnNewValue -Label 'fields.name' -Actual $context.fields.name -Expected 'Neues Projekt'
    Confirm-SpawnNewValue -Label 'fields.gitignore' -Actual $context.fields.gitignore -Expected 'VisualStudio'
    Confirm-SpawnNewValue -Label 'progressFile' -Actual $context.progressFile -Expected $run.ProgressFile
    Confirm-SpawnNewValue -Label 'resultFile' -Actual $context.resultFile -Expected $run.ResultFile
    Confirm-SpawnNewValue -Label 'cancelFile' -Actual $context.cancelFile -Expected $run.CancelFile
}

Add-SpawnNewTest 'Kontextdatei ist UTF-8 ohne BOM' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work
    [void](Write-SpawnNewContextFile -Run $run -Action (Get-TestActionObject) -ExplorerPath 'D:\x' -TargetPath 'D:\x\y' -TargetExisted $false -ConflictPolicy 'fail' -Value @{})

    $bytes = [System.IO.File]::ReadAllBytes($run.ContextFile)
    Confirm-SpawnNewCondition -Label 'kein BOM' -Condition (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
}

Add-SpawnNewTest 'Argumente werden als Feld uebergeben, nicht als Befehlszeile' {
    $argument = @(Get-SpawnNewActionArgument -ScriptPath 'C:\Quelle\Git Projekt\Invoke-SpawnAction.ps1' -ContextFile 'C:\Temp\sn 1\context.json')

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $argument.Count -Expected 8
    Confirm-SpawnNewValue -Label 'NoProfile' -Actual $argument[0] -Expected '-NoProfile'
    Confirm-SpawnNewValue -Label 'NonInteractive' -Actual $argument[1] -Expected '-NonInteractive'
    Confirm-SpawnNewValue -Label 'File' -Actual $argument[4] -Expected '-File'
    Confirm-SpawnNewValue -Label 'Skript als eigenes Element' -Actual $argument[5] -Expected 'C:\Quelle\Git Projekt\Invoke-SpawnAction.ps1'
    Confirm-SpawnNewValue -Label 'ContextFile' -Actual $argument[6] -Expected '-ContextFile'
    Confirm-SpawnNewValue -Label 'Kontext als eigenes Element' -Actual $argument[7] -Expected 'C:\Temp\sn 1\context.json'
}

Add-SpawnNewTest 'Aufraeumskript erhaelt zusaetzlich die Ergebnisdatei' {
    $argument = @(Get-SpawnNewActionArgument -ScriptPath 'C:\A\Clear-Action.ps1' -ContextFile 'C:\T\context.json' -ResultFile 'C:\T\result.json')

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $argument.Count -Expected 10
    Confirm-SpawnNewValue -Label 'ResultFile' -Actual $argument[8] -Expected '-ResultFile'
    Confirm-SpawnNewValue -Label 'Pfad' -Actual $argument[9] -Expected 'C:\T\result.json'
}

Add-SpawnNewTest 'Abbruch wird angefordert und erkannt' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work

    Confirm-SpawnNewValue -Label 'vorher' -Actual (Test-SpawnNewCancelRequested -Run $run) -Expected $false
    Request-SpawnNewCancel -Run $run
    Confirm-SpawnNewValue -Label 'nachher' -Actual (Test-SpawnNewCancelRequested -Run $run) -Expected $true
}

Add-SpawnNewTest 'Fortschritt wird ab der Leseposition gelesen' {
    $Work = Get-SpawnNewTestDirectory
    $file = Join-Path $Work 'progress.jsonl'
    Add-TestProgress -Path $file -Line @('{"type":"step","text":"Ordner anlegen","percent":10}')

    $first = Read-SpawnNewProgress -Path $file -Offset 0
    Confirm-SpawnNewValue -Label 'erste Runde' -Actual $first.Entry.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Typ' -Actual $first.Entry[0].Type -Expected 'step'
    Confirm-SpawnNewValue -Label 'Text' -Actual $first.Entry[0].Text -Expected 'Ordner anlegen'
    Confirm-SpawnNewValue -Label 'Anteil' -Actual $first.Entry[0].Percent -Expected 10

    $leer = Read-SpawnNewProgress -Path $file -Offset $first.Offset
    Confirm-SpawnNewValue -Label 'nichts Neues' -Actual $leer.Entry.Count -Expected 0

    Add-TestProgress -Path $file -Line @('{"type":"created","kind":"folder","path":"D:\\Büro\\Neu"}')
    $second = Read-SpawnNewProgress -Path $file -Offset $first.Offset
    Confirm-SpawnNewValue -Label 'zweite Runde' -Actual $second.Entry.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Art' -Actual $second.Entry[0].Kind -Expected 'folder'
    Confirm-SpawnNewValue -Label 'Pfad mit Umlaut' -Actual $second.Entry[0].Path -Expected 'D:\Büro\Neu'
}

Add-SpawnNewTest 'Halb geschriebene Zeile wird erst vollstaendig gelesen' {
    $Work = Get-SpawnNewTestDirectory
    $file = Join-Path $Work 'progress.jsonl'
    [void](Add-SpawnNewTestFile -Path $file -Content '{"type":"info","text":"halb')

    $first = Read-SpawnNewProgress -Path $file -Offset 0
    Confirm-SpawnNewValue -Label 'noch nichts' -Actual $first.Entry.Count -Expected 0
    Confirm-SpawnNewValue -Label 'Position unveraendert' -Actual $first.Offset -Expected 0

    [void](Add-SpawnNewTestFile -Path $file -Content "{`"type`":`"info`",`"text`":`"ganz`"}`r`n")
    $second = Read-SpawnNewProgress -Path $file -Offset 0
    Confirm-SpawnNewValue -Label 'jetzt da' -Actual $second.Entry.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Text' -Actual $second.Entry[0].Text -Expected 'ganz'
}

Add-SpawnNewTest 'Fehlende Fortschrittsdatei liefert nichts' {
    $Work = Get-SpawnNewTestDirectory
    $result = Read-SpawnNewProgress -Path (Join-Path $Work 'gibtesnicht.jsonl') -Offset 0

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $result.Entry.Count -Expected 0
    Confirm-SpawnNewValue -Label 'Position' -Actual $result.Offset -Expected 0
}

Add-SpawnNewTest 'Unbrauchbare Fortschrittszeilen werden uebersprungen' {
    $Work = Get-SpawnNewTestDirectory
    $file = Join-Path $Work 'progress.jsonl'
    Add-TestProgress -Path $file -Line @(
        '{"type":"info","text":"gut"}',
        'kein JSON',
        '{"type":"farbe","text":"unbekannter Typ"}',
        '{"type":"step","text":"zu hoch","percent":500}',
        '{"type":"step","text":"zu tief","percent":-20}')

    $entries = @((Read-SpawnNewProgress -Path $file -Offset 0).Entry)

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $entries.Count -Expected 4
    Confirm-SpawnNewValue -Label 'unbekannter Typ wird info' -Actual $entries[1].Type -Expected 'info'
    Confirm-SpawnNewValue -Label 'oben geklemmt' -Actual $entries[2].Percent -Expected 100
    Confirm-SpawnNewValue -Label 'unten geklemmt' -Actual $entries[3].Percent -Expected 0
}

Add-SpawnNewTest 'Ergebnisdatei wird gelesen und normalisiert' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work
    [void](Add-SpawnNewTestFile -Path $run.ResultFile -Content @'
{ "schemaVersion": 1, "status": "SUCCESS", "message": "Repository angelegt.",
  "created": [ { "kind": "folder", "path": "D:\\Büro\\Neu" }, { "path": "D:\\Büro\\Neu\\README.md" } ],
  "error": null }
'@)
    $result = Read-SpawnNewResult -Run $run

    Confirm-SpawnNewValue -Label 'Status klein' -Actual $result.Status -Expected 'success'
    Confirm-SpawnNewValue -Label 'Meldung' -Actual $result.Message -Expected 'Repository angelegt.'
    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $result.Created.Count -Expected 2
    Confirm-SpawnNewValue -Label 'Art' -Actual $result.Created[0].Kind -Expected 'folder'
    Confirm-SpawnNewValue -Label 'Art Vorgabe' -Actual $result.Created[1].Kind -Expected 'file'
    Confirm-SpawnNewValue -Label 'Fehler leer' -Actual $result.Error -Expected $null
}

Add-SpawnNewTest 'Fehlerblock der Ergebnisdatei wird uebernommen' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work
    [void](Add-SpawnNewTestFile -Path $run.ResultFile -Content @'
{ "status": "failed", "error": { "step": "Git initialisieren", "reason": "git.exe nicht gefunden" } }
'@)
    $result = Read-SpawnNewResult -Run $run

    Confirm-SpawnNewValue -Label 'Status' -Actual $result.Status -Expected 'failed'
    Confirm-SpawnNewValue -Label 'Schritt' -Actual $result.Error.Step -Expected 'Git initialisieren'
    Confirm-SpawnNewValue -Label 'Grund' -Actual $result.Error.Reason -Expected 'git.exe nicht gefunden'
    Confirm-SpawnNewValue -Label 'Details leer' -Actual $result.Error.Details -Expected ''
}

Add-SpawnNewTest 'Unbrauchbare Ergebnisdatei gilt als nicht vorhanden' {
    $Work = Get-SpawnNewTestDirectory
    $run = Get-SpawnNewRun -Root $Work

    Confirm-SpawnNewValue -Label 'fehlt' -Actual (Read-SpawnNewResult -Run $run) -Expected $null

    [void](Add-SpawnNewTestFile -Path $run.ResultFile -Content '{ "status": "success"')
    Confirm-SpawnNewValue -Label 'kaputte JSON' -Actual (Read-SpawnNewResult -Run $run) -Expected $null

    [void](Add-SpawnNewTestFile -Path $run.ResultFile -Content '{ "status": "fertig" }')
    Confirm-SpawnNewValue -Label 'fremder Status' -Actual (Read-SpawnNewResult -Run $run) -Expected $null

    [void](Add-SpawnNewTestFile -Path $run.ResultFile -Content '{ "message": "ohne Status" }')
    Confirm-SpawnNewValue -Label 'ohne Status' -Actual (Read-SpawnNewResult -Run $run) -Expected $null
}

Add-SpawnNewTest 'Fehlende Ergebnisdatei ergibt den Status unknown' {
    $progress = @([pscustomobject]@{ Type = 'created'; Kind = 'folder'; Path = 'D:\Neu'; Text = ''; Percent = -1 })
    $status = Get-TestStatus -ExitCode 0 -Result $null -Progress $progress

    Confirm-SpawnNewValue -Label 'Status' -Actual $status.Status -Expected 'unknown'
    Confirm-SpawnNewValue -Label 'Ressourcen aus Fortschritt' -Actual $status.Created.Count -Expected 1
    Confirm-SpawnNewValue -Label 'Pfad' -Actual $status.Created[0].Path -Expected 'D:\Neu'
    Confirm-SpawnNewMatch -Label 'Meldung' -Actual $status.Message -Pattern 'unbekannt'
}

Add-SpawnNewTest 'Die Ergebnisdatei gilt vor dem Rueckgabewert' {
    $result = [pscustomobject]@{ Status = 'partial'; Message = 'halb'; Created = @(); Error = $null }
    $status = Get-TestStatus -ExitCode 0 -Result $result

    Confirm-SpawnNewValue -Label 'Status' -Actual $status.Status -Expected 'partial'
    Confirm-SpawnNewMatch -Label 'Hinweis' -Actual $status.Note -Pattern 'weichen ab'
}

Add-SpawnNewTest 'Rueckgabewert 0 mit nochange ergibt keinen Hinweis' {
    $result = [pscustomobject]@{ Status = 'nochange'; Message = ''; Created = @(); Error = $null }

    Confirm-SpawnNewValue -Label 'Hinweis' -Actual (Get-TestStatus -ExitCode 0 -Result $result).Note -Expected ''
}

Add-SpawnNewTest 'Unbekannter Rueckgabewert wird vermerkt' {
    $result = [pscustomobject]@{ Status = 'success'; Message = ''; Created = @(); Error = $null }

    Confirm-SpawnNewMatch -Label 'Hinweis' -Actual (Get-TestStatus -ExitCode 42 -Result $result).Note -Pattern 'Unbekannter Rückgabewert 42'
}

Add-SpawnNewTest 'Leere Ressourcenliste wird aus dem Fortschritt ergaenzt' {
    $result   = [pscustomobject]@{ Status = 'failed'; Message = ''; Created = @(); Error = $null }
    $progress = @([pscustomobject]@{ Type = 'created'; Kind = 'file'; Path = 'D:\a.txt'; Text = ''; Percent = -1 })

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual (Get-TestStatus -ExitCode 1 -Result $result -Progress $progress).Created.Count -Expected 1
}

Add-SpawnNewTest 'Aufraeumen wird nur unter den festgelegten Bedingungen angeboten' {
    $mit  = Get-TestActionObject -Cleanup 'C:\A\Clear-Action.ps1'
    $ohne = Get-TestActionObject
    $etwas = [pscustomobject]@{ Status = 'partial'; Created = @([pscustomobject]@{ Kind = 'folder'; Path = 'D:\x' }) }
    $nichts = [pscustomobject]@{ Status = 'partial'; Created = @() }
    $erfolg = [pscustomobject]@{ Status = 'success'; Created = @([pscustomobject]@{ Kind = 'folder'; Path = 'D:\x' }) }

    Confirm-SpawnNewValue -Label 'Teilergebnis mit Skript' -Actual (Test-SpawnNewCleanupOffer -Action $mit -Status $etwas) -Expected $true
    Confirm-SpawnNewValue -Label 'ohne Skript' -Actual (Test-SpawnNewCleanupOffer -Action $ohne -Status $etwas) -Expected $false
    Confirm-SpawnNewValue -Label 'nichts erstellt' -Actual (Test-SpawnNewCleanupOffer -Action $mit -Status $nichts) -Expected $false
    Confirm-SpawnNewValue -Label 'Erfolg' -Actual (Test-SpawnNewCleanupOffer -Action $mit -Status $erfolg) -Expected $false

    foreach ($state in @('cancelled', 'failed', 'unknown')) {
        $status = [pscustomobject]@{ Status = $state; Created = @([pscustomobject]@{ Kind = 'folder'; Path = 'D:\x' }) }
        Confirm-SpawnNewValue -Label "Status '$state'" -Actual (Test-SpawnNewCleanupOffer -Action $mit -Status $status) -Expected $true
    }
}

Add-SpawnNewTest 'Pfad der Laufzeit zeigt auf Windows PowerShell 5.1' {
    $env:SystemRoot = 'C:\Windows'

    Confirm-SpawnNewValue -Label 'Pfad' -Actual (Get-SpawnNewPowerShellPath) -Expected 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
}
