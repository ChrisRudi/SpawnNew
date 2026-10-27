# Invoke-SpawnAction.ps1
# Version 1.0 | Aktion 15: Projekt abschliessen.
# Zweck  : Im vorhandenen Ordner Abschlussvermerk und SHA-256-Manifest
#          anlegen, optional ein ZIP-Archiv erstellen und den Ordner in ein
#          Archivverzeichnis verschieben. Alle Konflikte werden vor der
#          ersten Aenderung geprueft.
# Input  : -ContextFile Kontextdatei nach docs/Aktionsvertrag.md Abschnitt 2.
#          Felder: vermerk, zip, verschieben, archiv.
# Output : Fortschritt, Ergebnis und Rueckgabewert nach dem Vertrag.
# Deps   : Windows PowerShell 5.1, System.IO.Compression.FileSystem,
#          SpawnNew.Action.psm1 im Programmverzeichnis.

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
Add-Type -AssemblyName System.IO.Compression.FileSystem
$context = Initialize-SpawnNewAction -ContextFile $ContextFile

$manifestName = 'MANIFEST-SHA256.txt'
$closingName  = 'ABSCHLUSS.md'

function Get-RelativePath {
    param([string]$Root, [string]$Path)
    return $Path.Substring($Root.TrimEnd('\').Length + 1)
}

function Get-ProjectFile {
    param([string]$Root)
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object -Property FullName)
}

function Test-Inside {
    param([string]$Parent, [string]$Child)
    $prefix = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $full = [System.IO.Path]::GetFullPath($Child).TrimEnd('\') + '\'
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Copy-Verified {
    # Kopiert den Ordner und prueft jede Datei gegen das Manifest. Erst wenn
    # alles stimmt, wird die Quelle geloescht.
    param([string]$Source, [string]$Destination, [hashtable]$Hashes)

    [void][System.IO.Directory]::CreateDirectory($Destination)
    Add-SpawnNewActionResource -Kind 'folder' -Path $Destination

    foreach ($directory in @(Get-ChildItem -LiteralPath $Source -Recurse -Directory -Force)) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $Destination (Get-RelativePath -Root $Source -Path $directory.FullName)))
    }
    foreach ($file in (Get-ProjectFile -Root $Source)) {
        $relative = Get-RelativePath -Root $Source -Path $file.FullName
        $copy = Join-Path $Destination $relative
        [System.IO.File]::Copy($file.FullName, $copy, $false)
        if ($Hashes.ContainsKey($relative) -and (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $Hashes[$relative]) {
            throw "Prüfsumme der Kopie stimmt nicht: $relative. Die Quelle bleibt unverändert erhalten."
        }
    }
    Remove-Item -LiteralPath $Source -Recurse -Force
}

try {
    $target      = [string]$context.targetPath
    $folderName  = Split-Path -Leaf $target
    $parent      = Split-Path -Parent $target
    $vermerk     = (Get-SpawnNewActionField -Name 'vermerk').Trim()
    $mitZip      = Test-SpawnNewActionFlag -Name 'zip'
    $verschieben = Test-SpawnNewActionFlag -Name 'verschieben'
    $archiv      = (Get-SpawnNewActionField -Name 'archiv').Trim().TrimEnd('\')

    Write-SpawnNewActionStep -Text 'Voraussetzungen pruefen' -Percent 5

    if (-not [System.IO.Directory]::Exists($target)) { exit (Complete-SpawnNewActionFailed -Reason "Der Ordner ist nicht vorhanden: $target") }
    foreach ($name in @($closingName, $manifestName)) {
        if ([System.IO.File]::Exists((Join-Path $target $name))) {
            exit (Complete-SpawnNewActionFailed -Reason "$name ist bereits vorhanden; das Projekt wurde schon abgeschlossen. Nichts wurde geändert.")
        }
    }
    if ($verschieben -and $archiv.Length -eq 0) { exit (Complete-SpawnNewActionFailed -Reason 'Zum Verschieben wird ein Archivverzeichnis gebraucht.') }
    if ($archiv.Length -gt 0) {
        if (-not [System.IO.Path]::IsPathRooted($archiv)) { exit (Complete-SpawnNewActionFailed -Reason "Das Archivverzeichnis braucht einen vollständigen Pfad: $archiv") }
        if (Test-Inside -Parent $target -Child $archiv) { exit (Complete-SpawnNewActionFailed -Reason 'Das Archivverzeichnis darf nicht im abzuschließenden Ordner liegen.') }
    }

    $zipPath = ''
    if ($mitZip) {
        $zipDirectory = if ($archiv.Length -gt 0) { $archiv } else { $parent }
        $zipPath = Join-Path $zipDirectory ($folderName + '.zip')
        if ([System.IO.File]::Exists($zipPath)) { exit (Complete-SpawnNewActionFailed -Reason "Das ZIP-Archiv ist bereits vorhanden: $zipPath") }
    }

    $destination = ''
    if ($verschieben) {
        $destination = Join-Path $archiv $folderName
        if (Test-Path -LiteralPath $destination) { exit (Complete-SpawnNewActionFailed -Reason "Im Archivverzeichnis gibt es bereits: $destination") }
    }

    $files = Get-ProjectFile -Root $target
    $bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)

    Write-SpawnNewActionStep -Text 'Abschlussvermerk anlegen' -Percent 15
    if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
    if ($vermerk.Length -eq 0) { $vermerk = '(kein Vermerk)' }
    $closing = @(
        ('# Projektabschluss: ' + $folderName),
        '',
        ('Abgeschlossen am ' + (Get-Date -Format 'dd.MM.yyyy HH:mm') + ' von ' + [System.Environment]::UserName + '.'),
        '',
        '## Vermerk',
        '',
        $vermerk,
        '',
        '## Umfang',
        '',
        ('- ' + $files.Count + ' Dateien, ' + ('{0:N1}' -f ($bytes / 1MB)) + ' MB'),
        ('- Prüfsummen: ' + $manifestName)
    ) -join "`r`n"
    [void](Write-SpawnNewActionText -Path (Join-Path $target $closingName) -Text ($closing + "`r`n"))

    Write-SpawnNewActionStep -Text 'Manifest mit SHA-256 je Datei anlegen' -Percent 30
    $hashes = @{}
    $lines  = New-Object System.Collections.ArrayList
    [void]$lines.Add('# ' + $manifestName + ' - ' + $folderName + ', erstellt ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    [void]$lines.Add('# SHA256  Bytes  Pfad')
    $index = 0
    foreach ($file in (Get-ProjectFile -Root $target)) {
        $index++
        if ($index % 200 -eq 0 -and (Test-SpawnNewActionCancel)) { exit (Complete-SpawnNewActionCancelled) }
        $relative = Get-RelativePath -Root $target -Path $file.FullName
        if ($relative -eq $manifestName) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $hashes[$relative] = $hash
        [void]$lines.Add($hash + '  ' + $file.Length + '  ' + $relative)
    }
    [void](Write-SpawnNewActionText -Path (Join-Path $target $manifestName) -Text (($lines.ToArray() -join "`r`n") + "`r`n"))
    Write-SpawnNewActionNote -Text ($hashes.Count.ToString() + ' Dateien im Manifest.')

    if ($mitZip) {
        Write-SpawnNewActionStep -Text 'ZIP-Archiv erstellen' -Percent 55
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $zipPath))
        [System.IO.Compression.ZipFile]::CreateFromDirectory($target, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        Add-SpawnNewActionResource -Kind 'file' -Path $zipPath
    }

    if ($verschieben) {
        Write-SpawnNewActionStep -Text 'In das Archivverzeichnis verschieben' -Percent 75
        if (Test-SpawnNewActionCancel) { exit (Complete-SpawnNewActionCancelled) }
        [void][System.IO.Directory]::CreateDirectory($archiv)

        $sameVolume = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($target)) -eq [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($archiv))
        if ($sameVolume) {
            [System.IO.Directory]::Move($target, $destination)
            Add-SpawnNewActionResource -Kind 'folder' -Path $destination
        }
        else {
            Write-SpawnNewActionNote -Text 'Anderes Laufwerk: kopieren, jede Datei prüfen, dann die Quelle löschen.'
            Copy-Verified -Source $target -Destination $destination -Hashes $hashes
        }
        Write-SpawnNewActionNote -Text ('Verschoben nach ' + $destination)
    }

    Write-SpawnNewActionStep -Text 'Fertig' -Percent 100
    exit (Complete-SpawnNewAction -Message ('Projekt ' + $folderName + ' abgeschlossen.'))
}
catch {
    exit (Complete-SpawnNewActionFailed -Reason $_.Exception.Message -Details ([string]$_.ScriptStackTrace))
}
