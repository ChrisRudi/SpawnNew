# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 3: PowerShell-Werkzeug.
# Zweck  : Ordner mit Skript (Dateiname und Version im Kopf), optionaler
#          JSON-Konfiguration und Kurzdokumentation anlegen.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: name, beschreibung, konfiguration.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1 im Programmverzeichnis,
#          Vorlagen im Unterordner Vorlagen.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ContextFile)

$ErrorActionPreference = 'Stop'

$raw = ConvertFrom-Json ([System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8))
$helper = Join-Path ([string]$raw.appDirectory) 'SpawnNew.Action.psm1'
if (-not ([string]$raw.appDirectory) -or -not [System.IO.File]::Exists($helper)) {
    [System.IO.File]::WriteAllText($raw.resultFile, '{"schemaVersion":1,"status":"failed","message":"Es wurde nichts angelegt.","created":[],"error":{"step":"Vorbereiten","reason":"SpawnNew.Action.psm1 fehlt; SpawnNew bitte neu installieren.","details":""}}')
    exit 1
}
Import-Module $helper
$context = Initialize-SpawnNewAction -ContextFile $ContextFile

function Expand-Template {
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][hashtable]$Value)
    $path = Join-Path (Join-Path $context.actionDirectory 'Vorlagen') $File
    return (Expand-SpawnNewPlaceholder -Text ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)) -Value $Value)
}

try {
    $name = Get-SpawnNewActionField -Name 'name'
    $zweck = (Get-SpawnNewActionField -Name 'beschreibung').Trim()
    $mitKonfiguration = Test-SpawnNewActionFlag -Name 'konfiguration'
    $target = [string]$context.targetPath

    # Kopfzeilen sind einzeilig; Folgezeilen der Beschreibung werden im
    # Kommentar eingerueckt fortgesetzt.
    $kurz = ($zweck -split "`r?`n")[0]
    $zweckKopf = ($zweck -split "`r?`n") -join ("`r`n#          ")
    $konfigurationText = if ($mitKonfiguration) { "Einstellungen stehen in ``$name.config.json`` unter ``settings``. Die Datei ist optional; ohne sie gelten die Vorgaben im Skript." } else { 'Keine Konfigurationsdatei angelegt. Das Skript laeuft mit seinen Vorgaben; eine Datei nach dem Muster aus SpawnNew kann spaeter ergaenzt werden.' }

    $value = @{
        name          = $name
        kurz          = $kurz
        zweck         = $zweck
        datum         = (Get-Date -Format 'dd.MM.yyyy')
        konfiguration = $konfigurationText
    }

    Write-SpawnNewActionStep -Text 'Zielordner anlegen' -Percent 10
    New-SpawnNewActionFolder -Path $target

    Write-SpawnNewActionStep -Text ('Skript ' + $name + '.ps1 anlegen') -Percent 35
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    $skriptWert = $value.Clone()
    $skriptWert['zweck'] = $zweckKopf
    [void](Write-SpawnNewActionText -Path (Join-Path $target ($name + '.ps1')) -Text (Expand-Template -File 'Skript.ps1.vorlage' -Value $skriptWert))

    if ($mitKonfiguration) {
        Write-SpawnNewActionStep -Text 'Konfiguration anlegen' -Percent 60
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
        $jsonWert = @{ name = $name }
        [void](Write-SpawnNewActionText -NoBom -Path (Join-Path $target ($name + '.config.json')) -Text (Expand-Template -File 'Konfiguration.json.vorlage' -Value $jsonWert))
    }

    Write-SpawnNewActionStep -Text 'README.md anlegen' -Percent 80
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    [void](Write-SpawnNewActionText -Path (Join-Path $target 'README.md') -Text (Expand-Template -File 'README.md' -Value $value))

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('PowerShell-Werkzeug ' + $name + ' angelegt.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
