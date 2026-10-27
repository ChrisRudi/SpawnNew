# Install-SpawnNew.ps1
# Version 1.3 | Installiert, aktualisiert und entfernt SpawnNew.
# Zweck  : Programmdateien in das Installationsverzeichnis kopieren und das
#          Kontextmenue registrieren. Mit -Path liegt alles in einem
#          Cloudordner (OneDrive, Google Drive): Programmdateien, eigene
#          Aktionen, eigene Vorlagen und Einstellungen. Ein erneuter Lauf
#          ersetzt die Programmdateien vollstaendig und bleibt am bisherigen
#          Ort. Benutzerdaten bleiben unberuehrt.
# Input  : -Scope CurrentUser oder AllUsers; -Path Cloudordner;
#          -Uninstall entfernt das Menue, bei lokaler Installation auch die
#          Programmdateien; -RemoveFiles entfernt sie auch im Cloudordner.
# Output : Bericht auf stdout. Rueckgabewert 1 bei fehlenden Rechten,
#          fehlenden Quelldateien oder fremdem Inhalt im Zielordner.
# Deps   : Windows PowerShell 5.1. Muss aus einem Quellverzeichnis mit den
#          Unterordnern Host und Actions laufen.

[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers')][string]$Scope = 'CurrentUser',
    [string]$Path = '',
    [switch]$Uninstall,
    [switch]$RemoveFiles
)

$ErrorActionPreference = 'Stop'

if ($Scope -eq 'AllUsers') {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output 'Fuer -Scope AllUsers sind Administratorrechte noetig. Bitte PowerShell als Administrator starten.'
        exit 1
    }
}

Import-Module (Join-Path $PSScriptRoot 'Host\SpawnNew.Config.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'Host\SpawnNew.Register.psm1') -ErrorAction Stop
$root = Get-SpawnNewRegistryRoot -Scope $Scope

# Ort bestimmen: ausdruecklich per -Path, sonst der Cloudordner einer
# bestehenden Installation, sonst der lokale Standard. So bleibt ein Update
# ueber den Einzeiler dort, wo SpawnNew bisher lag.
$baseDirectory = ''
if ($Path) {
    $baseDirectory = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}
else {
    $registered = Get-SpawnNewRegisteredAppDirectory -Root $root
    if ($registered -and (Test-SpawnNewPortable -AppDirectory $registered)) {
        $baseDirectory = Split-Path -Parent $registered
        Write-Output ('Bisherige Installation im Cloudordner: ' + $baseDirectory)
    }
}

$portable = [bool]$baseDirectory
$appDirectory = if ($portable) {
    Join-Path $baseDirectory 'App'
}
elseif ($Scope -eq 'AllUsers') {
    Join-Path $env:ProgramFiles 'SpawnNew\App'
}
else {
    Join-Path $env:LOCALAPPDATA 'SpawnNew\App'
}

$setupName  = 'SpawnNew einrichten.cmd'
$removeName = 'SpawnNew auf diesem Rechner entfernen.cmd'

if ($Uninstall) {
    Remove-SpawnNewRegistration -Root $root
    Write-Output ('Menueregistrierung auf diesem Rechner entfernt: ' + (Get-SpawnNewMenuKey -Root $root))

    if ($portable -and -not $RemoveFiles) {
        Write-Output ''
        Write-Output 'Die Programmdateien im Cloudordner bleiben, andere Rechner nutzen sie:'
        Write-Output ('  ' + $appDirectory)
        Write-Output 'Mit -RemoveFiles werden sie fuer alle Rechner entfernt.'
        exit 0
    }

    if (Test-Path -LiteralPath $appDirectory) {
        Remove-Item -LiteralPath $appDirectory -Recurse -Force
        Write-Output ('Programmdateien entfernt: ' + $appDirectory)
    }
    if ($portable) {
        foreach ($name in @($setupName, $removeName)) {
            $file = Join-Path $baseDirectory $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
    }

    Write-Output ''
    Write-Output 'Erhalten bleiben:'
    $dataDirectory = if ($portable) { $baseDirectory } else { Join-Path $env:LOCALAPPDATA 'SpawnNew' }
    foreach ($entry in @(
            (Join-Path $dataDirectory 'spawnnew.settings.json'),
            (Join-Path $dataDirectory 'Actions'),
            (Join-Path $dataDirectory 'Vorlagen'),
            (Join-Path (Get-SpawnNewLocalDirectory) 'Secrets'),
            (Join-Path (Get-SpawnNewLocalDirectory) 'Cache'),
            (Join-Path (Get-SpawnNewLocalDirectory) 'Logs'))) {
        if (Test-Path -LiteralPath $entry) { Write-Output ('  ' + $entry) }
    }
    exit 0
}

$hostSource    = Join-Path $PSScriptRoot 'Host'
$actionSource  = Join-Path $PSScriptRoot 'Actions'
$configSource  = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\spawnnew.settings.default.json'

foreach ($source in @($hostSource, $actionSource, $configSource)) {
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Output ('Quelldatei oder Quellordner fehlt: ' + $source)
        exit 1
    }
}

# Erst leeren, dann kopieren: Copy-Item ueberschreibt nur, entfernt aber
# nichts. Eine in der neuen Fassung gestrichene Aktion bliebe sonst liegen
# und erschiene weiter im Menue. Geleert wird nur ein App-Ordner, der
# erkennbar SpawnNew enthaelt; fremde Inhalte bleiben unangetastet.
if (Test-Path -LiteralPath $appDirectory) {
    $ours = Test-Path -LiteralPath (Join-Path $appDirectory 'SpawnNew.Host.ps1')
    $empty = @(Get-ChildItem -LiteralPath $appDirectory -Force).Count -eq 0
    if (-not $ours -and -not $empty) {
        Write-Output ('Im Zielordner liegt ein App-Ordner, der nicht zu SpawnNew gehoert: ' + $appDirectory)
        Write-Output 'Es wurde nichts geaendert. Bitte einen anderen Ordner fuer -Path waehlen.'
        exit 1
    }
    Remove-Item -LiteralPath $appDirectory -Recurse -Force
    Write-Output ('Vorherige Programmdateien entfernt: ' + $appDirectory)
}

$actionTarget = Join-Path $appDirectory 'Actions'
[void](New-Item -ItemType Directory -Path $actionTarget -Force)

Copy-Item -Path (Join-Path $hostSource '*') -Destination $appDirectory -Recurse -Force
Copy-Item -Path (Join-Path $actionSource '*') -Destination $actionTarget -Recurse -Force
Copy-Item -Path $configSource -Destination $appDirectory -Force
Write-Output ('Programmdateien installiert: ' + $appDirectory)

$ascii = New-Object System.Text.ASCIIEncoding
if ($portable) {
    # Die Markierung nennt das Datenverzeichnis relativ zum
    # Programmverzeichnis; jeder Rechner findet so seinen eigenen Pfad des
    # Cloudordners.
    $marker = '{ "schemaVersion": 1, "comment": "SpawnNew im Cloudordner: Einstellungen, Actions und Vorlagen liegen eine Ebene hoeher.", "dataDirectory": ".." }'
    [System.IO.File]::WriteAllText((Join-Path $appDirectory 'spawnnew.portable.json'), $marker + "`r`n", (New-Object System.Text.UTF8Encoding $false))

    foreach ($folder in @('Actions', 'Vorlagen')) { [void](New-Item -ItemType Directory -Path (Join-Path $baseDirectory $folder) -Force) }

    $setup = @(
        '@echo off',
        'rem SpawnNew einrichten.cmd - Kontextmenue auf diesem Rechner einrichten.',
        'rem Die Dateien bleiben im Cloudordner; eingetragen wird nur das Menue.',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\SpawnNew.Menu.ps1"',
        'echo.',
        'pause'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $baseDirectory $setupName), $setup + "`r`n", $ascii)

    $remove = @(
        '@echo off',
        'rem Entfernt nur das Menue auf diesem Rechner. Der Cloudordner bleibt.',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0App\SpawnNew.Menu.ps1" -Remove',
        'echo.',
        'pause'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $baseDirectory $removeName), $remove + "`r`n", $ascii)
}

Import-Module (Join-Path $appDirectory 'SpawnNew.Config.psm1')  -Force -ErrorAction Stop
Import-Module (Join-Path $appDirectory 'SpawnNew.Catalog.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $appDirectory 'SpawnNew.Resolve.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $appDirectory 'SpawnNew.Register.psm1') -Force -ErrorAction Stop

$config  = Get-SpawnNewConfig -AppDirectory $appDirectory
$catalog = Get-SpawnNewCatalog -Config $config

# Erst entfernen, dann frisch schreiben: so verschwinden Eintraege von
# Aktionen, die es nicht mehr gibt, und Reste aelterer Fassungen.
Remove-SpawnNewRegistration -Root $root

$commands = Get-SpawnNewMenuCommand -Config $config
$entries  = Get-SpawnNewRegistryEntry -Action $catalog.Actions -AppDirectory $appDirectory -Root $root -Command $commands
Set-SpawnNewRegistration -Entry $entries

Write-Output ''
Write-Output ('Kontextmenue registriert: ' + (Get-SpawnNewMenuKey -Root $root))
Write-Output ('Datenverzeichnis: ' + (Get-SpawnNewDataDirectory -AppDirectory $appDirectory))
Write-Output ('Aktionen im Menue: ' + @($catalog.Actions).Count)
foreach ($action in $catalog.Actions) {
    Write-Output ('  ' + $action.Title + '  [' + $action.Id + ']  aus ' + $action.SourceName)
}
Write-Output ('Verwaltungsbefehle: ' + (($commands | ForEach-Object { $_.Title }) -join ', '))

$problems = @($catalog.Diagnostics | Where-Object { $_.Severity -ne 'info' })
if ($problems.Count -gt 0) {
    Write-Output ''
    Write-Output 'Hinweise:'
    foreach ($entry in $problems) { Write-Output ('  [' + $entry.Severity + '] ' + $entry.Message) }
}

Write-Output ''

if (@($catalog.Actions).Count -eq 0) {
    Write-Output 'ACHTUNG: Es wurde keine Aktion registriert. Das Untermenue SpawnNew erscheint,'
    Write-Output 'bleibt aber leer. Die Hinweise oben nennen den Grund. Zur Eingrenzung:'
    Write-Output ('  & "' + (Join-Path $appDirectory 'SpawnNew.Diagnose.ps1') + '"')
    exit 1
}

if ($portable) {
    Write-Output ('Auf jedem weiteren Rechner einmal "' + $setupName + '" im Ordner')
    Write-Output ('  ' + $baseDirectory)
    Write-Output 'ausfuehren. Geheimnisse sind rechnergebunden und dort neu zu speichern.'
    Write-Output 'Fuer OneDrive empfohlen: Ordner per Rechtsklick "Immer auf diesem Geraet behalten".'
    Write-Output ''
}

Write-Output 'Fertig. Rechtsklick in den leeren Bereich eines Ordners, dann SpawnNew.'
Write-Output 'Unter Windows 11 zuerst "Weitere Optionen anzeigen".'
exit 0
