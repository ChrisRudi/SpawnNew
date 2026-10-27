# SpawnNew.Menu.ps1
# Version 1.0 | Kontextmenue auf diesem Rechner einrichten oder entfernen.
# Zweck  : Fuer eine Installation im Cloudordner (OneDrive, Google Drive)
#          auf jedem weiteren Rechner das Menue registrieren, ohne Dateien zu
#          kopieren. Das Menue zeigt auf genau dieses Programmverzeichnis,
#          also auf den Pfad des Cloudordners auf diesem Rechner.
# Input  : -Remove entfernt das Menue; -Scope AllUsers braucht
#          Administratorrechte.
# Output : Bericht auf stdout. Rueckgabewert 1, wenn keine Aktion gefunden
#          wurde oder Rechte fehlen.
# Deps   : Windows PowerShell 5.1, die Module in diesem Verzeichnis.

[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers')][string]$Scope = 'CurrentUser',
    [switch]$Remove,
    [string]$AppDirectory = ''
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot ist in Windows PowerShell 5.1 bei -File mit CmdletBinding in
# den param()-Vorgaben leer.
if (-not $AppDirectory) { $AppDirectory = $PSScriptRoot }

foreach ($name in @('Config', 'Catalog', 'Resolve', 'Register')) {
    Import-Module (Join-Path $AppDirectory ('SpawnNew.' + $name + '.psm1')) -ErrorAction Stop
}

if ($Scope -eq 'AllUsers') {
    $principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output 'Fuer -Scope AllUsers sind Administratorrechte noetig.'
        exit 1
    }
}

$root = Get-SpawnNewRegistryRoot -Scope $Scope

if ($Remove) {
    Remove-SpawnNewRegistration -Root $root
    Write-Output ('Menue auf diesem Rechner entfernt. Die Dateien bleiben: ' + $AppDirectory)
    exit 0
}

$config  = Get-SpawnNewConfig -AppDirectory $AppDirectory
$catalog = Get-SpawnNewCatalog -Config $config

$previous = Get-SpawnNewRegisteredAppDirectory -Root $root
if ($previous -and (Get-SpawnNewPathKey -Path $previous) -ne (Get-SpawnNewPathKey -Path $AppDirectory)) {
    Write-Output ('Bisher zeigte das Menue auf: ' + $previous)
}

Remove-SpawnNewRegistration -Root $root
Set-SpawnNewRegistration -Entry (Get-SpawnNewRegistryEntry -Action $catalog.Actions -AppDirectory $AppDirectory -Root $root -Command (Get-SpawnNewMenuCommand -Config $config))

Write-Output ('Programmverzeichnis: ' + $AppDirectory)
Write-Output ('Datenverzeichnis:    ' + (Get-SpawnNewDataDirectory -AppDirectory $AppDirectory))
Write-Output ('Aktionen im Menue:   ' + @($catalog.Actions).Count)

if (@($catalog.Actions).Count -eq 0) {
    Write-Output 'ACHTUNG: keine Aktion gefunden. Ist der Cloudordner vollstaendig synchronisiert?'
    exit 1
}

Write-Output 'Fertig. Rechtsklick in den leeren Bereich eines Ordners, dann SpawnNew.'
Write-Output 'Geheimnisse (API-Schluessel) sind rechnergebunden und unter "SpawnNew konfigurieren" je Rechner einmal zu speichern.'
exit 0
