# SpawnNew.Diagnose.ps1
# Version 1.1 | Zeigt, warum das Kontextmenue leer bleibt.
# Zweck  : Konfigurationsschichten, Quellen, Zeitverhalten, Katalog,
#          Diagnosen und die tatsaechlichen Registrierungseintraege ausgeben.
# Input  : -AppDirectory abweichendes Programmverzeichnis.
# Output : Bericht auf stdout. Aendert nichts.
# Deps   : Windows PowerShell 5.1, die Module in diesem Verzeichnis.

[CmdletBinding()]
param([string]$AppDirectory = '')

$ErrorActionPreference = 'Stop'

# $PSScriptRoot ist in Windows PowerShell 5.1 bei -File mit CmdletBinding in
# den param()-Vorgaben leer; so startet der Explorer dieses Skript.
if (-not $AppDirectory) { $AppDirectory = $PSScriptRoot }

foreach ($name in @('Config', 'Catalog', 'Resolve', 'Register')) {
    Import-Module (Join-Path $AppDirectory ('SpawnNew.' + $name + '.psm1')) -Force -ErrorAction Stop
}

Write-Output ('Programmverzeichnis : ' + $AppDirectory)
Write-Output ('Datenverzeichnis    : ' + (Get-SpawnNewDataDirectory -AppDirectory $AppDirectory) + $(if (Test-SpawnNewPortable -AppDirectory $AppDirectory) { '  (Cloudordner)' } else { '  (lokal)' }))
Write-Output ('Nur dieser Rechner  : ' + (Get-SpawnNewLocalDirectory))
Write-Output ('PowerShell          : ' + $PSVersionTable.PSVersion.ToString())
Write-Output ('Betriebssystem      : ' + [System.Environment]::OSVersion.VersionString)

Write-Output ''
Write-Output '--- Konfigurationsschichten ---'
foreach ($layer in (Get-SpawnNewConfigLayerPath -AppDirectory $AppDirectory)) {
    $mark = if (Test-Path -LiteralPath $layer) { 'vorhanden' } else { 'fehlt' }
    Write-Output ('  [{0,-9}] {1}' -f $mark, $layer)
}

$config = Get-SpawnNewConfig -AppDirectory $AppDirectory

Write-Output ''
Write-Output ('--- Quellen, Zeitlimit ' + $config.SourceTimeoutMs + ' ms, Tiefe ' + $config.ScanDepth + ' ---')
foreach ($source in $config.Sources) {
    $mark = if ([System.IO.Directory]::Exists($source.Path)) { 'erreichbar' } else { 'fehlt' }
    Write-Output ('  [{0,-10}] {1,4} {2,-8} {3}' -f $mark, $source.Order, $source.Scope, $source.Path)
}

Write-Output ''
Write-Output '--- Zeitverhalten ---'
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$shell = [powershell]::Create()
[void]$shell.AddScript('param($p) Import-Module $p').AddArgument((Join-Path $AppDirectory 'SpawnNew.Catalog.psm1'))
[void]$shell.Invoke()
$shell.Dispose()
$watch.Stop()
Write-Output ('  Runspace und Modulimport : ' + $watch.ElapsedMilliseconds + ' ms')
if ($watch.ElapsedMilliseconds -ge $config.SourceTimeoutMs) {
    Write-Output '  Hinweis: laenger als das Zeitlimit. Der Import darf nicht mitgezaehlt werden.'
}

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$catalog = Get-SpawnNewCatalog -Config $config
$watch.Stop()
Write-Output ('  Katalog vollstaendig     : ' + $watch.ElapsedMilliseconds + ' ms')

Write-Output ''
Write-Output ('--- Katalog: ' + @($catalog.Actions).Count + ' Aktion(en) ---')
foreach ($action in $catalog.Actions) {
    Write-Output ('  ' + $action.Id + '  |  ' + $action.Title + '  |  ' + $action.SourceName + '  |  veraltet=' + $action.Stale)
}

Write-Output ''
Write-Output ('--- Diagnosen: ' + @($catalog.Diagnostics).Count + ' ---')
foreach ($entry in $catalog.Diagnostics) {
    Write-Output ('  [' + $entry.Severity + '] ' + $entry.Message)
    if ($entry.Path) { Write-Output ('            ' + $entry.Path) }
}

Write-Output ''
Write-Output '--- Registrierung ---'
foreach ($scope in @('CurrentUser', 'AllUsers')) {
    $menu = Get-SpawnNewMenuKey -Root (Get-SpawnNewRegistryRoot -Scope $scope)

    if (-not (Test-Path -LiteralPath $menu -ErrorAction SilentlyContinue)) {
        Write-Output ('  ' + $scope + ': nicht registriert (' + $menu + ')')
        continue
    }

    Write-Output ('  ' + $scope + ': ' + $menu)
    $sub = Join-Path $menu 'shell'

    if (-not (Test-Path -LiteralPath $sub -ErrorAction SilentlyContinue)) {
        Write-Output '    Kein shell-Unterschluessel. Das Untermenue bleibt leer.'
        continue
    }

    $keys = @(Get-ChildItem -LiteralPath $sub)
    Write-Output ('    ' + $keys.Count + ' Eintrag/Eintraege')

    foreach ($key in $keys) {
        Write-Output ('    ' + $key.PSChildName)
        Write-Output ('      MUIVerb : ' + $key.GetValue('MUIVerb'))

        $commandKey = Get-Item -LiteralPath (Join-Path $key.PSPath 'command') -ErrorAction SilentlyContinue
        if ($null -eq $commandKey) {
            Write-Output '      Befehl  : kein command-Unterschluessel'
            continue
        }

        # GetValue('') liest den unbenannten Standardwert. Nur den liest die
        # Shell. Ein Wert, der woertlich '(default)' heisst, ist ein Rest der
        # Fassung, die New-ItemProperty dafuer verwendet hat.
        Write-Output ('      Befehl  : ' + $commandKey.GetValue(''))
        if ($commandKey.GetValueNames() -contains '(default)') {
            Write-Output '      ACHTUNG : Wert namens (default) vorhanden. Den liest die Shell nicht.'
        }
    }

    $menuKey = Get-Item -LiteralPath $menu
    if ($menuKey.GetValueNames() -contains '(default)') {
        Write-Output '    ACHTUNG: Menueschluessel hat einen Wert namens (default). Rest einer aelteren Fassung.'
    }
}

Write-Output ''
$hostScript = Join-Path $AppDirectory 'SpawnNew.Host.ps1'
$mark = if (Test-Path -LiteralPath $hostScript) { 'vorhanden' } else { 'FEHLT' }
Write-Output ('Ausfuehrungsprozess : [' + $mark + '] ' + $hostScript)
