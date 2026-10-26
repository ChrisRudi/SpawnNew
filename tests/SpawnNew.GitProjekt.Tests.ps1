# tests/SpawnNew.GitProjekt.Tests.ps1
# Version 1.0 | Prueft Aktion 2 gegen den Ausfuehrungsvertrag.
# Zweck  : Die Aktion in einem eigenen Prozess starten, wie der
#          Ausfuehrungsprozess es tut, und Repository, Dateien, Commit,
#          Fortschritt, Ergebnis und Rueckgabewert pruefen. Die
#          Git-Konfiguration des Rechners wird dabei ausgeblendet.

Import-SpawnNewHostModule -Name 'Config', 'Runner'

function Get-ActionDirectory {
    $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
    return (Join-Path (Join-Path $src 'Actions') 'GitProjekt')
}

function Invoke-TestAction {
    param(
        [Parameter(Mandatory)]$Work,
        [Parameter(Mandatory)][hashtable]$Value,
        [switch]$NoIdentity,
        [switch]$Cancel
    )

    $action = [pscustomobject]@{ Id = 'spawnnew.gitproject'; ActionDirectory = (Get-ActionDirectory) }
    $run    = Get-SpawnNewRun -Root $Work
    $target = Join-Path $Work $Value['name']

    [void](Write-SpawnNewContextFile -Run $run -Action $action -ExplorerPath $Work -TargetPath $target -TargetExisted $false -ConflictPolicy 'fail' -Value $Value)
    if ($Cancel) { Request-SpawnNewCancel -Run $run }

    # Globale und systemweite Git-Einstellungen ausblenden; die Identitaet
    # kommt nur aus den Umgebungsvariablen dieses Falls.
    $globalConfig = Add-SpawnNewTestFile -Path (Join-Path $Work 'gitconfig') -Content ''
    $variables = @{
        GIT_CONFIG_GLOBAL   = $globalConfig
        GIT_CONFIG_NOSYSTEM = '1'
        GIT_AUTHOR_NAME     = 'Test'
        GIT_AUTHOR_EMAIL    = 'test@example.org'
        GIT_COMMITTER_NAME  = 'Test'
        GIT_COMMITTER_EMAIL = 'test@example.org'
    }
    if ($NoIdentity) {
        foreach ($key in @('GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL')) { $variables[$key] = $null }
    }

    $saved = @{}
    foreach ($key in $variables.Keys) {
        $saved[$key] = [System.Environment]::GetEnvironmentVariable($key)
        [System.Environment]::SetEnvironmentVariable($key, $variables[$key])
    }

    try {
        $shell  = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $output = & $shell -NoProfile -File (Join-Path (Get-ActionDirectory) 'Invoke-SpawnAction.ps1') -ContextFile $run.ContextFile 2>&1
        $code   = $LASTEXITCODE
        $count   = -1
        $tracked = @()
        if ([System.IO.File]::Exists((Join-Path (Join-Path $target '.git') 'HEAD'))) {
            $count   = [int](@(& git -C $target rev-list --all --count) -join '')
            $tracked = @(& git -C $target ls-files)
        }
    }
    finally {
        foreach ($key in $saved.Keys) { [System.Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    }

    return [pscustomobject]@{
        Target   = $target
        ExitCode = $code
        Output   = ($output -join "`r`n")
        Progress = @((Read-SpawnNewProgress -Path $run.ProgressFile -Offset 0).Entry)
        Result   = (Read-SpawnNewResult -Run $run)
        Commits  = $count
        Tracked  = $tracked
    }
}

Add-SpawnNewTest 'Legt Repository, .gitignore, README und ersten Commit an' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Werkzeug'; gitignore = 'PowerShell'; beschreibung = 'Hilfsskripte'; commit = $true }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 0
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewValue -Label 'Commits' -Actual $run.Commits -Expected 1
    Confirm-SpawnNewCondition -Label 'README im Commit' -Condition ($run.Tracked -contains 'README.md')
    Confirm-SpawnNewCondition -Label '.gitignore im Commit' -Condition ($run.Tracked -contains '.gitignore')

    $text = [System.IO.File]::ReadAllText((Join-Path $run.Target 'README.md'))
    Confirm-SpawnNewMatch -Label 'Name im README' -Actual $text -Pattern '# Werkzeug'
    Confirm-SpawnNewMatch -Label 'Beschreibung im README' -Actual $text -Pattern 'Hilfsskripte'

    $ignore = [System.IO.File]::ReadAllText((Join-Path $run.Target '.gitignore'))
    Confirm-SpawnNewMatch -Label 'Vorlage' -Actual $ignore -Pattern 'PowerShell\.gitignore'
}

Add-SpawnNewTest 'Alle erstellten Ressourcen werden gemeldet' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $true }

    $arten = @($run.Result.Created | ForEach-Object { $_.Kind })
    Confirm-SpawnNewValue -Label 'Arten' -Actual ($arten -join ',') -Expected 'folder,repository,file,file'
    Confirm-SpawnNewValue -Label 'Repository' -Actual $run.Result.Created[1].Path -Expected (Join-Path $run.Target '.git')

    $gemeldet = @($run.Progress | Where-Object { $_.Type -eq 'created' })
    Confirm-SpawnNewValue -Label 'Anzahl im Fortschritt' -Actual $gemeldet.Count -Expected 4
}

Add-SpawnNewTest 'Ohne ersten Commit bleibt das Repository leer' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $false }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewValue -Label 'Commits' -Actual $run.Commits -Expected 0
    Confirm-SpawnNewCondition -Label 'README da' -Condition (Test-Path -LiteralPath (Join-Path $run.Target 'README.md') -PathType Leaf)
}

Add-SpawnNewTest 'Vorlage Keine legt keine .gitignore an' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Keine'; beschreibung = ''; commit = $true }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewCondition -Label 'keine .gitignore' -Condition (-not (Test-Path -LiteralPath (Join-Path $run.Target '.gitignore')))
}

Add-SpawnNewTest 'Jede angebotene Vorlage hat eine Datei' {
    $directory = Get-ActionDirectory
    $description = ConvertFrom-Json ([System.IO.File]::ReadAllText((Join-Path $directory 'action.json')))
    $field = $description.fields | Where-Object { $_.name -eq 'gitignore' }

    foreach ($choice in @($field.choices | Where-Object { $_ -ne 'Keine' })) {
        $file = Join-Path (Join-Path $directory 'Gitignore') ($choice + '.gitignore')
        Confirm-SpawnNewCondition -Label ("Vorlage '$choice'") -Condition (Test-Path -LiteralPath $file -PathType Leaf)
    }
}

Add-SpawnNewTest 'Vorhandenes Repository wird nicht angetastet' {
    $Work = Get-SpawnNewTestDirectory
    $target = Join-Path $Work 'Projekt'
    [void](New-Item -ItemType Directory -Path (Join-Path $target '.git') -Force)

    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $true }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 1
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'failed'
    Confirm-SpawnNewMatch -Label 'Ursache' -Actual $run.Result.Error.Reason -Pattern 'bereits ein Git-Repository'
    Confirm-SpawnNewCondition -Label 'kein README' -Condition (-not (Test-Path -LiteralPath (Join-Path $target 'README.md')))
}

Add-SpawnNewTest 'Fehlende Git-Identitaet bricht vor jeder Aenderung ab' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $true } -NoIdentity

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 1
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'failed'
    Confirm-SpawnNewMatch -Label 'Ursache' -Actual $run.Result.Error.Reason -Pattern 'user\.name'
    Confirm-SpawnNewCondition -Label 'nichts angelegt' -Condition (-not (Test-Path -LiteralPath $run.Target))
}

Add-SpawnNewTest 'Ohne Commit braucht es keine Git-Identitaet' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $false } -NoIdentity

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
}

Add-SpawnNewTest 'Vorhandene README wird nicht ueberschrieben' {
    $Work = Get-SpawnNewTestDirectory
    $target = Join-Path $Work 'Projekt'
    [void](Add-SpawnNewTestFile -Path (Join-Path $target 'README.md') -Content 'HANDGESCHRIEBEN')

    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $true }

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 2
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'partial'
    Confirm-SpawnNewValue -Label 'README unveraendert' -Actual ([System.IO.File]::ReadAllText((Join-Path $target 'README.md'))) -Expected 'HANDGESCHRIEBEN'
    Confirm-SpawnNewValue -Label 'Commits' -Actual $run.Commits -Expected 1

    $warnung = @($run.Progress | Where-Object { $_.Type -eq 'warn' })
    Confirm-SpawnNewValue -Label 'Warnung' -Actual $warnung.Count -Expected 1
}

Add-SpawnNewTest 'Angeforderter Abbruch wird vor dem Repository beachtet' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $true } -Cancel

    Confirm-SpawnNewValue -Label 'Rueckgabewert' -Actual $run.ExitCode -Expected 3
    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'cancelled'
    Confirm-SpawnNewCondition -Label 'Zielordner bleibt' -Condition (Test-Path -LiteralPath $run.Target -PathType Container)
    Confirm-SpawnNewCondition -Label 'kein Repository' -Condition (-not (Test-Path -LiteralPath (Join-Path $run.Target '.git')))
}

Add-SpawnNewTest 'Umlaute und Leerzeichen im Zielpfad funktionieren' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Prüfung Übergabe'; gitignore = 'Allgemein'; beschreibung = 'Größe prüfen'; commit = $true }

    Confirm-SpawnNewValue -Label 'Status' -Actual $run.Result.Status -Expected 'success'
    Confirm-SpawnNewValue -Label 'Commits' -Actual $run.Commits -Expected 1

    $text = [System.IO.File]::ReadAllText((Join-Path $run.Target 'README.md'))
    Confirm-SpawnNewMatch -Label 'Umlaut im README' -Actual $text -Pattern 'Größe prüfen'
}

Add-SpawnNewTest 'Die Aktion schreibt nichts auf stdout' {
    $Work = Get-SpawnNewTestDirectory
    $run = Invoke-TestAction -Work $Work -Value @{ name = 'Projekt'; gitignore = 'Allgemein'; beschreibung = ''; commit = $true }

    Confirm-SpawnNewValue -Label 'Ausgabe' -Actual $run.Output -Expected ''
}
