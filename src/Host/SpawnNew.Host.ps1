# SpawnNew.Host.ps1
# Version 1.1 | Ausfuehrungsprozess von SpawnNew.
# Zweck  : Eine vom Kontextmenue gewaehlte Aktion abwickeln: nachpruefen,
#          Voraussetzungen melden, Formular zeigen, Konflikte klaeren,
#          zusammenfassen, starten, Fortschritt zeigen, Aufraeumen anbieten.
# Input  : -ActionId Aktionskennung, -SourcePath Quelle, -ExplorerPath Ordner,
#          aus dem das Kontextmenue geoeffnet wurde.
# Output : Keine Ausgabe auf stdout. Protokoll in
#          %LOCALAPPDATA%\SpawnNew\Logs\host.log. Rueckgabewert 0 bei Erfolg
#          oder bewusstem Abbruch, 1 bei Fehler, 2 bei Teilergebnis, 3 bei
#          unbekanntem Status.
# Deps   : Windows PowerShell 5.1, die Module in diesem Verzeichnis.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ActionId,
    [string]$SourcePath,
    [string]$ExplorerPath = (Get-Location).Path,
    [string]$AppDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# Der Explorer startet diesen Prozess mit verborgenem Fenster. Ohne Protokoll
# waere jeder Fehler vor dem ersten Fenster unsichtbar.
$logDirectory = if ($env:LOCALAPPDATA) {
    Join-Path (Join-Path $env:LOCALAPPDATA 'SpawnNew') 'Logs'
}
else {
    Join-Path ([System.IO.Path]::GetTempPath()) 'SpawnNew'
}
$logFile = Join-Path $logDirectory 'host.log'

function Write-SpawnNewHostLog {
    <#
    .SYNOPSIS
    Haengt eine Zeile an das Protokoll an. Nutzt keine SpawnNew-Module,
    damit auch ein fehlgeschlagener Modulimport protokolliert wird.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    try {
        if (-not [System.IO.Directory]::Exists($logDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($logDirectory)
        }
        $line = ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $Text + "`r`n")
        [System.IO.File]::AppendAllText($logFile, $line, (New-Object System.Text.UTF8Encoding $true))
    }
    catch {
        # Ein nicht schreibbares Protokoll darf die Aktion nicht verhindern.
        Write-Error -Message ('Protokoll nicht schreibbar: ' + $_.Exception.Message) -ErrorAction Continue
    }
}

function Show-SpawnNewHostFailure {
    <#
    .SYNOPSIS
    Zeigt einen Fehler, der vor oder neben den Dialogen aufgetreten ist.
    Scheitert die Anzeige selbst, bleibt das Protokoll als Nachweis.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $full = $Text + "`r`n`r`nEinzelheiten stehen in:`r`n" + $logFile
        [void][System.Windows.Forms.MessageBox]::Show($full, 'SpawnNew - Fehler',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    catch {
        Write-SpawnNewHostLog 'Der Fehler konnte nicht angezeigt werden.'
    }
}

Write-SpawnNewHostLog ('--- Start  ActionId=' + $ActionId + '  ExplorerPath=' + $ExplorerPath)
Write-SpawnNewHostLog ('    AppDirectory=' + $AppDirectory + '  PowerShell=' + $PSVersionTable.PSVersion.ToString())

try {
    foreach ($name in @('Config', 'Catalog', 'Resolve', 'Input', 'Target', 'Runner', 'Form', 'Progress')) {
        Import-Module (Join-Path $AppDirectory ('SpawnNew.' + $name + '.psm1')) -ErrorAction Stop
    }
    Write-SpawnNewHostLog '    Module geladen'

    $exitCodes = @{ success = 0; nochange = 0; cancelled = 0; failed = 1; partial = 2; unknown = 3 }

    function Exit-SpawnNewHost {
        <#
        .SYNOPSIS
        Beendet den Ausfuehrungsprozess mit einer Meldung.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Title,
            [Parameter(Mandatory)][string]$Text,
            [ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information',
            [int]$Code = 0
        )

        Write-SpawnNewHostLog ('    Ende: ' + $Title + ' - ' + $Text)
        Show-SpawnNewMessage -Title $Title -Text $Text -Icon $Icon
        exit $Code
    }

    $config  = Get-SpawnNewConfig -AppDirectory $AppDirectory
    $catalog = Get-SpawnNewCatalog -Config $config
    Write-SpawnNewHostLog ('    Katalog: ' + @($catalog.Actions).Count + ' Aktion(en)')

    $candidates = @($catalog.Actions | Where-Object { $_.Id -eq $ActionId })
    if ($SourcePath) {
        $key = Get-SpawnNewPathKey -Path $SourcePath
        $candidates = @($candidates | Where-Object { (Get-SpawnNewPathKey -Path $_.SourcePath) -eq $key })
    }

    if ($candidates.Count -eq 0) {
        Exit-SpawnNewHost -Title 'Aktion nicht gefunden' -Icon 'Warning' -Code 1 -Text "Die Aktion '$ActionId' ist nicht mehr vorhanden. Bitte das Kontextmenü erneut öffnen."
    }

    $check = Test-SpawnNewAction -Action $candidates[0]
    if (-not $check.Valid) {
        Exit-SpawnNewHost -Title 'Aktion nicht mehr gültig' -Icon 'Warning' -Code 1 -Text ($check.Message + "`r`n`r`nBitte das Kontextmenü erneut öffnen.")
    }

    $action  = $check.Action
    $missing = @(Get-SpawnNewMissingPrerequisite -Action $action)

    if ($missing.Count -gt 0) {
        $lines = @('Für diese Aktion fehlen Voraussetzungen:', '')
        foreach ($entry in $missing) {
            $line = '  ' + $entry.Kind + ': ' + $entry.Name
            if ($entry.Hint.Length -gt 0) { $line += ' - ' + $entry.Hint }
            $lines += $line
        }
        $lines += @('', 'SpawnNew installiert nichts selbst.')

        Exit-SpawnNewHost -Title 'Voraussetzungen fehlen' -Icon 'Warning' -Code 1 -Text ($lines -join "`r`n")
    }

    $diagnostics = New-Object System.Collections.ArrayList
    $fields      = @(Get-SpawnNewFieldList -Action $action -Diagnostics $diagnostics)
    $targetKind  = Get-SpawnNewTargetKind -Action $action -Diagnostics $diagnostics
    $basePath    = Get-SpawnNewBasePath -Action $action -ExplorerPath $ExplorerPath -AppDirectory $AppDirectory
    Write-SpawnNewHostLog ('    Formular: ' + $fields.Count + ' Feld(er), Zielart ' + $targetKind + ', Basis ' + $basePath)

    $form = Show-SpawnNewActionForm -Action $action -Field $fields -BasePath $basePath
    if (-not $form.Confirmed) {
        Write-SpawnNewHostLog '    Ende: im Formular abgebrochen'
        exit 0
    }

    $values = $form.Value
    $name   = ''
    if ($values.ContainsKey('name')) { $name = [string]$values['name'] }

    if ($targetKind -eq 'folder') {
        $nameCheck = Test-SpawnNewName -Name $name
        if (-not $nameCheck.Valid) {
            Exit-SpawnNewHost -Title 'Name nicht verwendbar' -Icon 'Warning' -Code 1 -Text $nameCheck.Message
        }
        $name = $nameCheck.Value
        $values['name'] = $name
    }

    $targetPath    = Join-SpawnNewTargetPath -BasePath $form.BasePath -TargetKind $targetKind -Name $name
    $state         = Get-SpawnNewTargetState -Path $targetPath
    $targetExisted = $false

    if ($state.IsFile) {
        Exit-SpawnNewHost -Title 'Ziel ist eine Datei' -Icon 'Warning' -Code 1 -Text "Am Ziel liegt bereits eine Datei:`r`n$targetPath"
    }

    if ($state.IsFolder -and $targetKind -eq 'folder') {
        $free   = Get-SpawnNewFreeName -BasePath $form.BasePath -Name $name
        $choice = Show-SpawnNewConflictChoice -TargetPath $targetPath -FreeName $free
        Write-SpawnNewHostLog ('    Zielkonflikt: ' + $choice)

        switch ($choice) {
            'rename' {
                $name           = $free
                $values['name'] = $free
                $targetPath     = Join-SpawnNewTargetPath -BasePath $form.BasePath -TargetKind $targetKind -Name $free
            }
            'use' { $targetExisted = $true }
            default { exit 0 }
        }
    }
    elseif ($state.IsFolder) {
        $targetExisted = $true
    }

    # Ueberschreiben nur, wenn die Aktion es beschreibt und der Benutzer es vor
    # dem Start ausdruecklich bestaetigt. Vorgabe bleibt der Abbruch.
    $conflictPolicy = 'fail'
    if ($targetExisted -and -not $state.IsEmpty -and $action.AllowsOverwrite) {
        $hint = 'Vorhandene Dateien überschreiben? Nein bricht bei einem Konflikt ab.'
        $question = "Der Zielordner enthält bereits Dateien:`r`n$targetPath`r`n`r`n" + $hint
        if (Show-SpawnNewConfirmation -Title 'Dateien überschreiben' -Text $question) {
            $conflictPolicy = 'overwrite'
        }
    }

    $summary = Get-SpawnNewSummaryText -Action $action -TargetPath $targetPath -Field $fields -Value $values -ConflictPolicy $conflictPolicy -TargetExisted $targetExisted

    if (-not (Show-SpawnNewSummary -Text $summary)) {
        Write-SpawnNewHostLog '    Ende: in der Zusammenfassung abgebrochen'
        exit 0
    }

    $run = Get-SpawnNewRun
    [void](Write-SpawnNewContextFile -Run $run -Action $action -ExplorerPath $ExplorerPath -TargetPath $targetPath -TargetExisted $targetExisted -ConflictPolicy $conflictPolicy -Value $values)
    Write-SpawnNewHostLog ('    Lauf: ' + $run.Directory + ', Ziel ' + $targetPath)

    $process = Invoke-SpawnNewActionProcess -ScriptPath $action.EntryPoint -ContextFile $run.ContextFile -RequiresAdmin $action.RequiresAdmin

    if ($null -eq $process) {
        Exit-SpawnNewHost -Title 'Rechteabfrage abgelehnt' -Code 0 -Text 'Die Aktion wurde nicht gestartet. Es wurde nichts geändert.'
    }

    $status = Invoke-SpawnNewProgressWindow -Run $run -Action $action -Process $process
    Write-SpawnNewHostLog ('    Ergebnis: ' + $status.Status + ', ' + $status.Created.Count + ' Ressource(n), Rueckgabewert ' + $status.ExitCode)

    if (Test-SpawnNewCleanupOffer -Action $action -Status $status) {
        $hint = 'Die Aktion bietet ein Aufräumen an. Die oben genannten Ressourcen werden entfernt. Jetzt aufräumen?'
        $question = (Get-SpawnNewResultReport -Status $status) + "`r`n`r`n" + $hint

        if (Show-SpawnNewConfirmation -Title 'Aufräumen' -Text $question) {
            $cleanup = Invoke-SpawnNewActionProcess -ScriptPath $action.Cleanup -ContextFile $run.ContextFile -ResultFile $run.ResultFile -RequiresAdmin $action.RequiresAdmin

            if ($null -eq $cleanup) {
                Show-SpawnNewMessage -Title 'Aufräumen' -Icon 'Warning' -Text 'Das Aufräumen wurde nicht gestartet. Die Teilergebnisse bleiben erhalten.'
            }
            else {
                $cleanup.WaitForExit()
                Show-SpawnNewMessage -Title 'Aufräumen' -Text ('Das Aufräumskript endete mit Rückgabewert ' + $cleanup.ExitCode + '.')
            }
        }
    }

    if (@('success', 'partial') -contains $status.Status -and (Test-Path -LiteralPath $targetPath -PathType Container)) {
        if (Show-SpawnNewConfirmation -Title 'Zielordner' -Text ("Zielordner jetzt öffnen?`r`n$targetPath")) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $targetPath
        }
    }

    if ($exitCodes.ContainsKey($status.Status)) { exit $exitCodes[$status.Status] }
    exit 3
}
catch {
    Write-SpawnNewHostLog ('FEHLER: ' + $_.Exception.GetType().FullName)
    Write-SpawnNewHostLog ('        ' + $_.Exception.Message)
    Write-SpawnNewHostLog ('        ' + [string]$_.InvocationInfo.PositionMessage)
    Write-SpawnNewHostLog ('        ' + [string]$_.ScriptStackTrace)
    Show-SpawnNewHostFailure -Text $_.Exception.Message
    exit 1
}
