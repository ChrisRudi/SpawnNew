# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 14: Eigene Aktion.
# Zweck  : Grundgeruest einer neuen Aktion mit Skript, JSON-Beschreibung und
#          Kurzdokumentation anlegen, standardmaessig im persoenlichen
#          Aktionsverzeichnis.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: name, id, beschreibung.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, SpawnNew.Action.psm1 im Programmverzeichnis.

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
    $target = [string]$context.targetPath
    $name = Get-SpawnNewActionField -Name 'name'
    $id = Get-SpawnNewActionField -Name 'id'
    $beschreibung = Get-SpawnNewActionField -Name 'beschreibung'
    if ($beschreibung.Length -eq 0) { $beschreibung = 'Eigene Aktion ' + $name + '.' }

    $value = @{ name = $name; id = $id; beschreibung = $beschreibung; datum = (Get-Date -Format 'dd.MM.yyyy') }

    Write-SpawnNewActionStep -Text 'Aktionsordner anlegen' -Percent 10
    New-SpawnNewActionFolder -Path $target

    # Die Beschreibung entsteht als Objekt und wird serialisiert, damit
    # Anfuehrungszeichen oder Rueckstriche im Namen keine ungueltige JSON
    # ergeben.
    Write-SpawnNewActionStep -Text 'action.json anlegen' -Percent 35
    $description = [ordered]@{
        schemaVersion  = 1
        id             = $id
        title          = $name
        category       = ''
        entryPoint     = 'Invoke-SpawnAction.ps1'
        requiresAdmin  = $false
        supportsCancel = $false
        targetKind     = 'folder'
        fields         = @([ordered]@{ name = 'name'; label = 'Name'; type = 'text'; required = $true })
        plannedSteps   = @('Zielordner anlegen', 'Notiz.md anlegen')
    }
    $json = ConvertTo-Json -InputObject ([pscustomobject]$description) -Depth 5
    [void](Write-SpawnNewActionText -NoBom -Path (Join-Path $target 'action.json') -Text ($json + "`r`n"))

    Write-SpawnNewActionStep -Text 'Invoke-SpawnAction.ps1 anlegen' -Percent 60
    $skriptWert = $value.Clone()
    $skriptWert['beschreibung'] = ($beschreibung -split "`r?`n")[0]
    [void](Write-SpawnNewActionText -Path (Join-Path $target 'Invoke-SpawnAction.ps1') -Text (Expand-Template -File 'Invoke-SpawnAction.ps1.vorlage' -Value $skriptWert))

    Write-SpawnNewActionStep -Text 'README.md anlegen' -Percent 85
    [void](Write-SpawnNewActionText -Path (Join-Path $target 'README.md') -Text (Expand-Template -File 'README.md' -Value $value))

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    Write-SpawnNewActionNote -Text 'Die Aktion erscheint nach dem nächsten Aufruf eines SpawnNew-Eintrags im Menü.'
    exit (Complete-SpawnNewAction -Message ('Eigene Aktion ' + $name + ' (' + $id + ') angelegt.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
