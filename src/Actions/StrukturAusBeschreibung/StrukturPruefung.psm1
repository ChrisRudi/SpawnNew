# StrukturPruefung.psm1
# Version 1.0 | Hilfsmodul der Aktion 17, keine eigene Menueaktion.
# Zweck  : Ordnerpfade aus einer Modellantwort pruefen und normalisieren:
#          nur relative Pfade, keine verbotenen Zeichen oder Namen, kein
#          Verlassen des Zielordners, begrenzte Tiefe und Anzahl.
# Input  : Rohdaten aus der Modellantwort.
# Output : Sortierte Liste gueltiger relativer Pfade mit '/' als Trenner.
# Deps   : Windows PowerShell 5.1.

Set-StrictMode -Version 2.0

$script:MaxDepth = 6
$script:MaxCount = 150
$script:Invalid  = [char[]]@('<', '>', ':', '"', '|', '?', '*')
$script:Reserved = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')

function Test-StrukturSegment {
    <#
    .SYNOPSIS
    Prueft einen einzelnen Ordnernamen.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Segment)

    if ($Segment.Length -eq 0 -or $Segment.Length -gt 80) { return $false }
    if ($Segment -eq '.' -or $Segment -eq '..') { return $false }
    if ($Segment.IndexOfAny($script:Invalid) -ge 0) { return $false }
    if ($Segment.EndsWith('.') -or $Segment.EndsWith(' ')) { return $false }
    foreach ($char in $Segment.ToCharArray()) { if ([int]$char -lt 32) { return $false } }
    $stem = $Segment.Split('.')[0].ToUpperInvariant()
    return ($script:Reserved -notcontains $stem)
}

function ConvertTo-StrukturListe {
    <#
    .SYNOPSIS
    Liefert die gueltigen Ordnerpfade aus einer Modellantwort.
    .DESCRIPTION
    Akzeptiert ein Feld von Zeichenketten oder ein Objekt mit 'ordner' oder
    'folders'. Uebergeordnete Ordner werden ergaenzt, Doppelte entfernt.
    Ungueltige Eintraege fallen weg und werden gezaehlt.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Data)

    $items = @()
    if ($null -eq $Data) { $items = @() }
    elseif ($Data -is [string]) { $items = @($Data) }
    elseif ($Data -is [System.Collections.IEnumerable]) { $items = @($Data) }
    else {
        foreach ($key in @('ordner', 'folders')) {
            if ($Data.PSObject.Properties.Name -contains $key) { $items = @($Data.$key) }
        }
    }

    $set = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $dropped = 0

    foreach ($item in $items) {
        $text = ([string]$item).Trim().Replace('\', '/').Trim('/')
        $segments = @($text.Split('/') | ForEach-Object { $_.Trim() })
        $ok = $text.Length -gt 0 -and $segments.Count -le $script:MaxDepth
        foreach ($segment in $segments) { if (-not (Test-StrukturSegment -Segment $segment)) { $ok = $false } }
        if (-not $ok) { $dropped++; continue }

        for ($i = 1; $i -le $segments.Count; $i++) { [void]$set.Add(($segments[0..($i - 1)] -join '/')) }
    }

    # Nach Ebenen sortieren: der Trenner zaehlt als kleinstes Zeichen, damit
    # 'A/x' direkt unter 'A' steht und nicht hinter 'A-B'.
    [string[]]$list = @($set)
    [string[]]$keys = @($list | ForEach-Object { $_.ToLowerInvariant().Replace('/', [string][char]1) })
    if ($list.Count -gt 1) { [System.Array]::Sort($keys, $list, [System.StringComparer]::Ordinal) }

    if ($list.Count -gt $script:MaxCount) {
        $dropped += $list.Count - $script:MaxCount
        $list = $list[0..($script:MaxCount - 1)]
    }
    return [pscustomobject]@{ Folders = [string[]]$list; Dropped = $dropped }
}

function Get-StrukturBaum {
    <#
    .SYNOPSIS
    Eingerueckte Darstellung der Ordnerliste.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Folders)

    $lines = foreach ($folder in $Folders) {
        $parts = $folder.Split('/')
        ('  ' * ($parts.Count - 1)) + '- ' + $parts[-1]
    }
    return (@($lines) -join "`r`n")
}

Export-ModuleMember -Function Test-StrukturSegment, ConvertTo-StrukturListe, Get-StrukturBaum
