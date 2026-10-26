# SpawnNew.Catalog.ps1
# Version 1.0 | Menuekatalog als JSON fuer die Explorer-Erweiterung.
# Zweck  : Quellen auflosen und die Menuedaten ausgeben. Liest ausschliesslich
#          Metadaten und fuehrt keine Aktion aus, damit das Oeffnen des
#          Kontextmenues kein Aktionsskript startet.
# Input  : -OutputFile Zieldatei; ohne Angabe geht die Ausgabe nach stdout.
#          -AppDirectory abweichendes Programmverzeichnis zum Pruefen.
# Output : JSON mit Aktionen und Diagnosen, UTF-8 ohne BOM.
#          Rueckgabewert 0, auch wenn einzelne Quellen fehlerhaft sind.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1, SpawnNew.Catalog.psm1,
#          SpawnNew.Resolve.psm1.

[CmdletBinding()]
param(
    [string]$OutputFile,
    [string]$AppDirectory = $PSScriptRoot,
    [string[]]$LayerPath
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')  -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Catalog.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Resolve.psm1') -ErrorAction Stop

$parameter = @{ AppDirectory = $AppDirectory }
if ($LayerPath) { $parameter['LayerPath'] = $LayerPath }

$config  = Get-SpawnNewConfig @parameter
$catalog = Get-SpawnNewCatalog -Config $config

$actions = @(
    $catalog.Actions | ForEach-Object {
        [pscustomobject]@{
            id            = $_.Id
            title         = $_.Title
            category      = $_.Category
            icon          = $_.Icon
            requiresAdmin = $_.RequiresAdmin
            sourceName    = $_.SourceName
            sourcePath    = $_.SourcePath
            stale         = $_.Stale
        }
    }
)

$diagnostics = @(
    $catalog.Diagnostics | ForEach-Object {
        [pscustomobject]@{
            severity = $_.Severity
            area     = $_.Area
            path     = $_.Path
            message  = $_.Message
        }
    }
)

$install = @{ Id = 'spawnnew.install'; Title = 'SpawnNew installieren'; Command = $config.Install }
$update  = @{ Id = 'spawnnew.update';  Title = 'SpawnNew aktualisieren'; Command = $config.Update }

$commands = @()
foreach ($entry in @($install, $update)) {
    if ($null -eq $entry.Command) { continue }

    $commands += [pscustomobject]@{
        id            = $entry.Id
        title         = $entry.Title
        command       = $entry.Command.Command
        requiresAdmin = $entry.Command.RequiresAdmin
    }
}

$payload = [pscustomobject]@{
    schemaVersion = 1
    generatedUtc  = [System.DateTime]::UtcNow.ToString('o')
    actions       = $actions
    commands      = $commands
    diagnostics   = $diagnostics
}

$json = ConvertTo-Json -InputObject $payload -Depth 6

if ($OutputFile) {
    $directory = Split-Path -Parent $OutputFile
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    [System.IO.File]::WriteAllText($OutputFile, $json, (New-Object System.Text.UTF8Encoding $false))
}
else {
    Write-Output $json
}

exit 0
