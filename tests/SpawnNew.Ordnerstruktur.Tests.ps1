# tests/SpawnNew.Ordnerstruktur.Tests.ps1
# Version 1.0 | Prueft Aktion 1 gegen den Ausfuehrungsvertrag.
# Zweck  : Die Aktion in einem eigenen Prozess starten, wie der
#          Ausfuehrungsprozess es tut, und Kontextdatei, Fortschritt,
#          Ergebnis und Rueckgabewert als Ganzes pruefen.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

function Get-ActionPath {
    $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    return (Join-Path (Join-Path (Join-Path $src 'Actions') 'Ordnerstruktur') 'Invoke-SpawnAction.ps1')
}

function Get-ActionDirectory {
    return (Split-Path -Parent (Get-ActionPath))
}

function Invoke-TestAction {
    param(
        [Parameter(Mandatory)]$Work,
        [Parameter(Mandatory)][hashtable]$Value,
        [string]$ConflictPolicy = 'fail',
        [switch]$Cancel
    )

    $action = [pscustomobject]@{
        Id              = 'spawnnew.folderstructure'
        ActionDirectory = (Get-ActionDirectory)
    }

    $run    = Get-SpawnNewRun -Root $Work
    $target = Join-Path $Work $Value['name']

    [void](Write-SpawnNewContextFile -Run $run -Action $action -ExplorerPath $Work -TargetPath $target -TargetExisted $false -ConflictPolicy $ConflictPolicy -Value $Value)
    if ($Cancel) { Request-SpawnNewCancel -Run $run }

    $shell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $output = & $shell -NoProfile -File (Get-ActionPath) -ContextFile $run.ContextFile 2>&1
    $code = $LASTEXITCODE

    return [pscustomobject]@{
        Run        = $run
        Target     = $target
        ExitCode   = $code
        Output     = ($output -join "`r`n")
        Progress   = @((Read-SpawnNewProgress -Path $run.ProgressFile -Offset 0).Entry)
        Result     = (Read-SpawnNewResult -Run $run)
    }
}

Add-SpawnNewTest 'Vorlage Projekt legt Ordner, Unterordner und README an' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Neues Projekt'; vorlage = 'Projekt'; zweck = 'Abschlusspruefung' }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'

    foreach ($ordner in @('01 Planung', '02 Umsetzung', '03 Dokumentation', '04 Abgabe')) {
        Confirm-SpawnNewCondition -Label ("Ordner '$ordner'") -Condition (Test-Path -LiteralPath (Join-Path $run.Target $ordner) -PathType Container)
    }

    $readme = Join-Path $run.Target 'README.md'
    Confirm-SpawnNewCondition -Label 'README da' -Condition (Test-Path -LiteralPath $readme -PathType Leaf)

    $text = [System.IO.File]::ReadAllText($readme)
    Confirm-SpawnNewMatch -Label 'Name im README' -Actual $text -Pattern '# Neues Projekt'
    Confirm-SpawnNewMatch -Label 'Zweck im README' -Actual $text -Pattern 'Abschlusspruefung'
    Confirm-SpawnNewMatch -Label 'Ordner im README' -Actual $text -Pattern '01 Planung'
}

Add-SpawnNewTest 'Alle erstellten Ressourcen werden gemeldet' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Minimal'; zweck = '' }

    Confirm-SpawnNewValue -Label 'Anzahl im Ergebnis' -Actual $run.Result.Created.Count -Expected 3
    Confirm-SpawnNewValue -Label 'Zielordner zuerst' -Actual $run.Result.Created[0].Path -Expected $run.Target
    Confirm-SpawnNewValue -Label 'Art' -Actual $run.Result.Created[2].Kind -Expected 'file'

    $gemeldet = @($run.Progress | Where-Object { $_.Type -eq 'created' })
    Confirm-SpawnNewValue -Label 'Anzahl im Fortschritt' -Actual $gemeldet.Count -Expected 3
}

Add-SpawnNewTest 'Fortschritt meldet Schritte mit Anteil' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Minimal'; zweck = '' }

    $schritte = @($run.Progress | Where-Object { $_.Type -eq 'step' })
    Confirm-SpawnNewCondition -Label 'mehrere Schritte' -Condition ($schritte.Count -ge 3)
    Confirm-SpawnNewValue -Label 'letzter Anteil' -Actual $schritte[-1].Percent -Expected 100
}

Add-SpawnNewTest 'Leerer Zweck erscheint als Hinweis im README' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Minimal'; zweck = '' }
    $text = [System.IO.File]::ReadAllText((Join-Path $run.Target 'README.md'))

    Confirm-SpawnNewMatch -Label 'Hinweis' -Actual $text -Pattern 'kein Zweck angegeben'
}

Add-SpawnNewTest 'Vorhandene README wird nicht ueberschrieben' {
    $Work = Get-SpawnNewTestDirectory
    $target = Join-Path $Work 'Projekt'
    [void](Add-SpawnNewTestFile -Path (Join-Path $target 'README.md') -Content 'HANDGESCHRIEBEN')

    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Minimal'; zweck = '' }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 2
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'partial'
    Confirm-SpawnNewValue -Label 'README unveraendert' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'README.md'))) -Expected 'HANDGESCHRIEBEN'

    $warnung = @($run.Progress | Where-Object { $_.Type -eq 'warn' })
    Confirm-SpawnNewValue -Label 'Warnung' -Actual $warnung.Count -Expected 1
}

Add-SpawnNewTest 'Angeforderter Abbruch wird beachtet' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Projekt'; zweck = '' } -Cancel

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 3
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'cancelled'
    Confirm-SpawnNewCondition -Label 'Zielordner bleibt' -Condition (Test-Path -LiteralPath $run.Target -PathType Container)
    Confirm-SpawnNewCondition -Label 'kein README' -Condition (-not (Test-Path -LiteralPath (Join-Path $run.Target 'README.md')))
}

Add-SpawnNewTest 'Unbekannte Strukturvorlage meldet einen Fehler mit Schritt und Ursache' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Gibtesnicht'; zweck = '' }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 2
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'partial'
    Confirm-SpawnNewValue -Label 'Schritt' -Actual $run.Result.Error.Step -Expected 'Vorlage lesen'
    Confirm-SpawnNewMatch -Label 'Ursache' -Actual $run.Result.Error.Reason -Pattern 'Gibtesnicht'
}

Add-SpawnNewTest 'Umlaute und Leerzeichen im Zielpfad funktionieren' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Büro Übergabe'; vorlage = 'Minimal'; zweck = 'Größe prüfen' }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'Ordner da' -Condition (Test-Path -LiteralPath $run.Target -PathType Container)

    $text = [System.IO.File]::ReadAllText((Join-Path $run.Target 'README.md'))
    Confirm-SpawnNewMatch -Label 'Umlaut im README' -Actual $text -Pattern 'Größe prüfen'
}

Add-SpawnNewTest 'Die Aktion schreibt nichts auf stdout' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; vorlage = 'Minimal'; zweck = '' }

    Confirm-SpawnNewValue -Label 'Ausgabe' -Actual $run.Output -Expected ''
}
