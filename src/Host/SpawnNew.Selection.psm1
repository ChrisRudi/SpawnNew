# SpawnNew.Selection.psm1
# Version 1.0 | Mehrfachauswahl im Explorer zu einem Lauf zusammenfassen.
# Zweck  : Bei mehreren markierten Dateien startet der Explorer den Host
#          einmal je Datei. Der erste Prozess sammelt die Pfade der anderen
#          ein, bis eine kurze Zeit keine neuen mehr kommen; die anderen
#          geben ihren Pfad ab und enden still. So erscheint ein Formular
#          fuer die ganze Auswahl.
# Input  : Aktions-ID und Pfad der angeklickten Datei.
# Output : Die gesammelten Pfade fuer den ersten Prozess, $null fuer alle
#          anderen.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')

function Get-SpawnNewSelectionKey {
    <#
    .SYNOPSIS
    Kurzer, fuer Datei- und Mutexnamen taugender Schluessel einer Aktions-ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ActionId)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ActionId.ToLowerInvariant())) }
    finally { $sha.Dispose() }
    return (-join ($hash[0..7] | ForEach-Object { $_.ToString('x2') }))
}

function Add-SpawnNewSelection {
    <#
    .SYNOPSIS
    Gibt einen Pfad in die Sammlung. Liefert fuer den sammelnden Prozess
    alle Pfade, fuer alle anderen $null.
    .DESCRIPTION
    Wer die Sammeldatei anlegt, sammelt. Er wartet, bis die Datei
    QuietMilliseconds lang nicht mehr waechst, hoechstens MaxMilliseconds,
    liest dann alle Pfade und loescht die Datei. Eine Sammeldatei, die
    aelter als 30 Sekunden ist, stammt von einem abgebrochenen Lauf und wird
    verworfen. Ein Mutex schuetzt Anhaengen und Einlesen.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$Path,
        [int]$QuietMilliseconds = 900,
        [int]$MaxMilliseconds = 8000,
        [string]$Directory = (Join-Path (Get-SpawnNewLocalDirectory) 'Selection')
    )

    $key  = Get-SpawnNewSelectionKey -ActionId $ActionId
    $file = Join-Path $Directory ($key + '.txt')
    if (-not [System.IO.Directory]::Exists($Directory)) { [void][System.IO.Directory]::CreateDirectory($Directory) }

    $mutex = New-Object System.Threading.Mutex($false, ('Local\SpawnNew.Selection.' + $key))
    try {
        $first = $false
        try { [void]$mutex.WaitOne() } catch [System.Threading.AbandonedMutexException] { Write-Verbose 'Verlassener Mutex uebernommen.' }
        try {
            $exists = [System.IO.File]::Exists($file)
            if ($exists -and ([System.DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($file)).TotalSeconds -gt 30) {
                [System.IO.File]::Delete($file)
                $exists = $false
            }
            [System.IO.File]::AppendAllText($file, $Path + "`r`n", (New-Object System.Text.UTF8Encoding $false))
            $first = -not $exists
        }
        finally {
            $mutex.ReleaseMutex()
        }

        if (-not $first) { return $null }

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $length = -1L
        $stable = [System.Diagnostics.Stopwatch]::StartNew()
        while ($stable.ElapsedMilliseconds -lt $QuietMilliseconds -and $watch.ElapsedMilliseconds -lt $MaxMilliseconds) {
            Start-Sleep -Milliseconds 100
            $current = (New-Object System.IO.FileInfo($file)).Length
            if ($current -ne $length) { $length = $current; $stable.Restart() }
        }

        try { [void]$mutex.WaitOne() } catch [System.Threading.AbandonedMutexException] { Write-Verbose 'Verlassener Mutex uebernommen.' }
        try {
            $lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)
            [System.IO.File]::Delete($file)
        }
        finally {
            $mutex.ReleaseMutex()
        }

        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        return [string[]]@($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $seen.Add($_) })
    }
    finally {
        $mutex.Dispose()
    }
}

Export-ModuleMember -Function Get-SpawnNewSelectionKey, Add-SpawnNewSelection
