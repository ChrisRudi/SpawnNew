# Install-SpawnNew.ps1
# Version 1.0 | Installiert, aktualisiert und entfernt SpawnNew.
# Zweck  : Programmdateien in das Installationsverzeichnis kopieren und das
#          Kontextmenue registrieren. Benutzerdaten bleiben unberuehrt.
# Input  : -Scope CurrentUser oder AllUsers; -Uninstall entfernt.
# Output : Bericht auf stdout. Rueckgabewert 1 bei fehlenden Rechten oder
#          fehlenden Quelldateien.
# Deps   : Windows PowerShell 5.1. Muss aus einem Quellverzeichnis mit den
#          Unterordnern Host und Actions laufen.

[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers')][string]$Scope = 'CurrentUser',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$appDirectory = if ($Scope -eq 'AllUsers') {
    Join-Path $env:ProgramFiles 'SpawnNew\App'
}
else {
    Join-Path $env:LOCALAPPDATA 'SpawnNew\App'
}

$dataDirectory = Join-Path $env:LOCALAPPDATA 'SpawnNew'

if ($Scope -eq 'AllUsers') {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output 'Fuer -Scope AllUsers sind Administratorrechte noetig. Bitte PowerShell als Administrator starten.'
        exit 1
    }
}

Import-Module (Join-Path $PSScriptRoot 'Host\SpawnNew.Register.psm1') -ErrorAction Stop
$root = Get-SpawnNewRegistryRoot -Scope $Scope

if ($Uninstall) {
    Remove-SpawnNewRegistration -Root $root
    Write-Output ('Menueregistrierung entfernt: ' + (Get-SpawnNewMenuKey -Root $root))

    if (Test-Path -LiteralPath $appDirectory) {
        Remove-Item -LiteralPath $appDirectory -Recurse -Force
        Write-Output ('Programmdateien entfernt: ' + $appDirectory)
    }

    Write-Output ''
    Write-Output 'Erhalten bleiben:'
    foreach ($name in @('spawnnew.settings.json', 'Actions', 'Cache', 'Secrets', 'Logs')) {
        $path = Join-Path $dataDirectory $name
        if (Test-Path -LiteralPath $path) { Write-Output ('  ' + $path) }
    }
    exit 0
}

$hostSource    = Join-Path $PSScriptRoot 'Host'
$actionSource  = Join-Path $PSScriptRoot 'Actions'
$configSource  = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\spawnnew.settings.default.json'

foreach ($path in @($hostSource, $actionSource, $configSource)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Output ('Quelldatei oder Quellordner fehlt: ' + $path)
        exit 1
    }
}

$actionTarget = Join-Path $appDirectory 'Actions'
[void](New-Item -ItemType Directory -Path $actionTarget -Force)

Copy-Item -Path (Join-Path $hostSource '*') -Destination $appDirectory -Recurse -Force
Copy-Item -Path (Join-Path $actionSource '*') -Destination $actionTarget -Recurse -Force
Copy-Item -Path $configSource -Destination $appDirectory -Force
Write-Output ('Programmdateien installiert: ' + $appDirectory)

Import-Module (Join-Path $appDirectory 'SpawnNew.Config.psm1')  -Force -ErrorAction Stop
Import-Module (Join-Path $appDirectory 'SpawnNew.Catalog.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $appDirectory 'SpawnNew.Resolve.psm1') -Force -ErrorAction Stop

$config  = Get-SpawnNewConfig -AppDirectory $appDirectory
$catalog = Get-SpawnNewCatalog -Config $config

# Erst entfernen, dann frisch schreiben: so verschwinden Eintraege von
# Aktionen, die es nicht mehr gibt, und Reste aelterer Fassungen.
Remove-SpawnNewRegistration -Root $root

$entries = Get-SpawnNewRegistryEntry -Action $catalog.Actions -AppDirectory $appDirectory -Root $root
Set-SpawnNewRegistration -Entry $entries

Write-Output ''
Write-Output ('Kontextmenue registriert: ' + (Get-SpawnNewMenuKey -Root $root))
Write-Output ('Aktionen im Menue: ' + @($catalog.Actions).Count)
foreach ($action in $catalog.Actions) {
    Write-Output ('  ' + $action.Title + '  [' + $action.Id + ']  aus ' + $action.SourceName)
}

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

Write-Output 'Fertig. Rechtsklick in den leeren Bereich eines Ordners, dann SpawnNew.'
Write-Output 'Unter Windows 11 zuerst "Weitere Optionen anzeigen".'
exit 0
