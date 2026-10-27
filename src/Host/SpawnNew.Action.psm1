# SpawnNew.Action.psm1
# Version 1.0 | Hilfen fuer Aktionsskripte nach docs/Aktionsvertrag.md.
# Zweck  : Kontext lesen, Fortschritt und Ressourcen melden, Abbruch
#          pruefen, Ergebnisdatei schreiben, Dateien ohne stilles
#          Ueberschreiben anlegen, Dokumente aus Vorlagen erzeugen und
#          Entwuerfe eines Sprachmodells als gekennzeichnete Datei ablegen.
# Input  : -ContextFile des Aktionsskripts.
# Output : Dateien der Aktion; Fortschritt und Ergebnis nach dem Vertrag.
#          Funktionen, die den Lauf beenden, liefern den Rueckgabewert; das
#          Skript ruft damit selbst exit auf.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config/Document/Llm/Secret.psm1.

Set-StrictMode -Version 2.0

foreach ($name in @('Config', 'Secret', 'Llm', 'Document')) {
    Import-Module (Join-Path $PSScriptRoot ('SpawnNew.' + $name + '.psm1'))
}

$script:Utf8   = New-Object System.Text.UTF8Encoding $false
$script:Run    = $null
$script:Codes  = @{ success = 0; nochange = 0; failed = 1; partial = 2; cancelled = 3 }

function Initialize-SpawnNewAction {
    <#
    .SYNOPSIS
    Liest die Kontextdatei und legt den Laufzustand an.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ContextFile)

    $context = ConvertFrom-Json ([System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8))
    $script:Run = [pscustomobject]@{
        Context = $context
        Created = (New-Object System.Collections.ArrayList)
        Step    = 'Vorbereiten'
        Skipped = 0
    }
    return $context
}

function Get-SpawnNewActionField {
    <#
    .SYNOPSIS
    Formularwert als Zeichenkette, leer wenn er fehlt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)

    $fields = $script:Run.Context.fields
    if ($null -eq $fields -or -not ($fields.PSObject.Properties.Name -contains $Name)) { return '' }
    $value = $fields.$Name
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Get-SpawnNewActionList {
    <#
    .SYNOPSIS
    Formularwert als Liste, etwa mehrere markierte Dateien. Ein einzelner
    Wert wird eine Liste mit einem Eintrag.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Name)

    $fields = $script:Run.Context.fields
    if ($null -eq $fields -or -not ($fields.PSObject.Properties.Name -contains $Name)) { return [string[]]@() }
    return [string[]]@($fields.$Name | Where-Object { $null -ne $_ -and ([string]$_).Length -gt 0 } | ForEach-Object { [string]$_ })
}

function Test-SpawnNewActionFlag {
    <#
    .SYNOPSIS
    Formularwert als Wahrheitswert.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)

    $fields = $script:Run.Context.fields
    if ($null -eq $fields -or -not ($fields.PSObject.Properties.Name -contains $Name)) { return $false }
    return [bool]$fields.$Name
}

function Write-SpawnNewActionLine {
    <#
    .SYNOPSIS
    Haengt eine Fortschrittszeile an.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entry)

    $line = (ConvertTo-Json -InputObject ([pscustomobject]$Entry) -Compress) + "`r`n"
    [System.IO.File]::AppendAllText($script:Run.Context.progressFile, $line, $script:Utf8)
}

function Write-SpawnNewActionStep {
    <#
    .SYNOPSIS
    Meldet einen neuen Arbeitsschritt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$Percent = -1
    )

    $script:Run.Step = $Text
    $entry = @{ type = 'step'; text = $Text }
    if ($Percent -ge 0) { $entry['percent'] = $Percent }
    Write-SpawnNewActionLine -Entry $entry
}

function Write-SpawnNewActionNote {
    <#
    .SYNOPSIS
    Meldet eine Hinweis- oder Warnzeile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [switch]$Warning
    )

    if ($Warning) {
        $script:Run.Skipped++
        Write-SpawnNewActionLine -Entry @{ type = 'warn'; text = $Text }
    }
    else {
        Write-SpawnNewActionLine -Entry @{ type = 'info'; text = $Text }
    }
}

function Add-SpawnNewActionResource {
    <#
    .SYNOPSIS
    Meldet eine erstellte Ressource.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('folder', 'file', 'repository')][string]$Kind,
        [Parameter(Mandatory)][string]$Path
    )

    [void]$script:Run.Created.Add([pscustomobject]@{ kind = $Kind; path = $Path })
    Write-SpawnNewActionLine -Entry @{ type = 'created'; kind = $Kind; path = $Path }
}

function Test-SpawnNewActionCancel {
    <#
    .SYNOPSIS
    Prueft, ob der Benutzer den Abbruch angefordert hat.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return [System.IO.File]::Exists($script:Run.Context.cancelFile)
}

function Complete-SpawnNewAction {
    <#
    .SYNOPSIS
    Schreibt die Ergebnisdatei und liefert den Rueckgabewert.
    .DESCRIPTION
    Ohne -Status entscheidet der Lauf: 'partial', wenn etwas uebersprungen
    wurde, sonst 'success'.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [ValidateSet('', 'success', 'partial', 'nochange', 'cancelled', 'failed')][string]$Status = '',
        [Parameter(Mandatory)][string]$Message,
        [string]$Reason = '',
        [string]$Details = ''
    )

    if ($Status -eq '') { $Status = if ($script:Run.Skipped -gt 0) { 'partial' } else { 'success' } }

    $failure = $null
    if ($Reason.Length -gt 0) { $failure = [pscustomobject]@{ step = $script:Run.Step; reason = $Reason; details = $Details } }

    $result = [pscustomobject]@{
        schemaVersion = 1
        status        = $Status
        message       = $Message
        created       = $script:Run.Created.ToArray()
        error         = $failure
    }
    [System.IO.File]::WriteAllText($script:Run.Context.resultFile, (ConvertTo-Json -InputObject $result -Depth 5), $script:Utf8)
    return $script:Codes[$Status]
}

function Complete-SpawnNewActionCancelled {
    <#
    .SYNOPSIS
    Ergebnis fuer einen beachteten Abbruch; liefert den Rueckgabewert.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    return (Complete-SpawnNewAction -Status 'cancelled' -Message ('Abbruch vor dem Schritt "' + $script:Run.Step + '".'))
}

function Complete-SpawnNewActionFailed {
    <#
    .SYNOPSIS
    Ergebnis fuer einen Fehler; 'partial', wenn schon etwas erstellt
    wurde, sonst 'failed'. Liefert den Rueckgabewert.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$Reason,
        [string]$Details = ''
    )

    $status = if ($script:Run.Created.Count -gt 0) { 'partial' } else { 'failed' }
    $message = if ($status -eq 'partial') { 'Die Aktion wurde nicht vollständig ausgeführt; erstellte Teile bleiben erhalten.' } else { 'Es wurde nichts angelegt.' }
    return (Complete-SpawnNewAction -Status $status -Message $message -Reason $Reason -Details $Details)
}

function New-SpawnNewActionFolder {
    <#
    .SYNOPSIS
    Legt einen Ordner an, falls er fehlt, und meldet ihn.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Directory]::Exists($Path)) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Ordner anlegen')) { return }
    [void][System.IO.Directory]::CreateDirectory($Path)
    Add-SpawnNewActionResource -Kind 'folder' -Path $Path
}

function Test-SpawnNewActionWritable {
    <#
    .SYNOPSIS
    Prueft eine Zieldatei gegen die Konfliktregel. Bei vorhandener Datei
    ohne bestaetigtes Ueberschreiben gibt es eine Warnung und $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not [System.IO.File]::Exists($Path)) { return $true }
    if ($script:Run.Context.conflictPolicy -eq 'overwrite') { return $true }

    Write-SpawnNewActionNote -Warning -Text ((Split-Path -Leaf $Path) + ' ist vorhanden und wird nicht angetastet.')
    return $false
}

function Write-SpawnNewActionText {
    <#
    .SYNOPSIS
    Schreibt eine Textdatei als UTF-8 mit BOM, ausser sie ist vorhanden und
    Ueberschreiben ist nicht bestaetigt. Liefert $true, wenn geschrieben.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$NoBom
    )

    if (-not (Test-SpawnNewActionWritable -Path $Path)) { return $false }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Datei schreiben')) { return $false }

    $encoding = New-Object System.Text.UTF8Encoding (-not $NoBom)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
    Add-SpawnNewActionResource -Kind 'file' -Path $Path
    return $true
}

function New-SpawnNewActionDocument {
    <#
    .SYNOPSIS
    Dokument aus einer Vorlage der Aktion, Markdown oder Word. Liefert den
    Pfad oder '' wenn die Datei schon vorhanden war.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('markdown', 'docx')][string]$Format,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][hashtable]$Value
    )

    $context = $script:Run.Context
    $path = Join-Path $Directory ($Name + $(if ($Format -eq 'docx') { '.docx' } else { '.md' }))
    if (-not (Test-SpawnNewActionWritable -Path $path)) { return '' }
    if (-not $PSCmdlet.ShouldProcess($path, 'Dokument erzeugen')) { return '' }

    if ([System.IO.File]::Exists($path)) { Remove-Item -LiteralPath $path -Force }
    [void](New-SpawnNewDocument -ActionId $context.actionId -ActionDirectory $context.actionDirectory -Name $Name -Format $Format -Directory $Directory -Value $Value)
    Add-SpawnNewActionResource -Kind 'file' -Path $path
    return $path
}

function Get-SpawnNewFreeFilePath {
    <#
    .SYNOPSIS
    Freier Dateiname nach dem Muster 'Name (2).ext'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not [System.IO.File]::Exists($Path)) { return $Path }

    $directory = Split-Path -Parent $Path
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)
    for ($i = 2; $i -lt 1000; $i++) {
        $candidate = Join-Path $directory ('{0} ({1}){2}' -f $stem, $i, $extension)
        if (-not [System.IO.File]::Exists($candidate)) { return $candidate }
    }
    throw "Kein freier Dateiname für $Path gefunden."
}

function Assert-SpawnNewActionEndpoint {
    <#
    .SYNOPSIS
    Prueft vor jeder Aenderung, ob ein KI-Endpunkt samt Geheimnis bereitsteht.
    Liefert eine Fehlermeldung oder ''.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $llm = $script:Run.Context.llm
    if ($null -eq $llm) { return 'Es ist kein KI-Endpunkt konfiguriert. Unter "SpawnNew konfigurieren" einrichten oder ohne Entwurf anlegen.' }
    if ([string]$llm.secret -and -not (Test-SpawnNewSecret -Name ([string]$llm.secret))) {
        return ("Für den Endpunkt '" + $llm.name + "' fehlt das Geheimnis '" + $llm.secret + "'. Unter ""SpawnNew konfigurieren"" speichern.")
    }
    return ''
}

function Invoke-SpawnNewActionChat {
    <#
    .SYNOPSIS
    Fragt das Sprachmodell des Kontexts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$System,
        [Parameter(Mandatory)][string]$User
    )

    $llm = $script:Run.Context.llm
    $endpoint = [pscustomobject]@{
        Name           = [string]$llm.name
        BaseUrl        = [string]$llm.baseUrl
        Model          = [string]$llm.model
        TimeoutSeconds = [int]$llm.timeoutSeconds
        Secret         = [string]$llm.secret
    }
    return (Invoke-SpawnNewChat -Endpoint $endpoint -System $System -User $User)
}

function Write-SpawnNewActionDraft {
    <#
    .SYNOPSIS
    Legt Modellausgabe als deutlich gekennzeichnete Entwurfsdatei ab.
    .DESCRIPTION
    Eine vorhandene Datei wird nie ueberschrieben, auch nicht bei
    bestaetigtem Ueberschreiben: der Entwurf bekommt dann einen freien
    Namen. Liefert den geschriebenen Pfad.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text,
        [string]$Source = ''
    )

    $llm  = $script:Run.Context.llm
    $path = Get-SpawnNewFreeFilePath -Path $Path
    if (-not $PSCmdlet.ShouldProcess($path, 'Entwurf schreiben')) { return '' }

    $origin = 'Modell ' + $llm.model + ' über Endpunkt ' + $llm.name
    if ($Source) { $origin += ', Grundlage: ' + $Source }
    $head = @(
        '> **ENTWURF** - automatisch erzeugt am ' + (Get-Date -Format 'dd.MM.yyyy HH:mm') + ' (' + $origin + ').',
        '> Inhalt vor der Verwendung prüfen und diese Kennzeichnung erst danach entfernen.',
        '',
        ''
    ) -join "`r`n"

    [System.IO.File]::WriteAllText($path, $head + $Text.Trim() + "`r`n", (New-Object System.Text.UTF8Encoding $true))
    Add-SpawnNewActionResource -Kind 'file' -Path $path
    return $path
}

function Get-SpawnNewActionFormat {
    <#
    .SYNOPSIS
    Ausgabeformat aus dem Formularfeld 'format': 'Word' wird 'docx'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ((Get-SpawnNewActionField -Name 'format') -eq 'Word') { return 'docx' }
    return 'markdown'
}

Export-ModuleMember -Function Initialize-SpawnNewAction, Get-SpawnNewActionField, Get-SpawnNewActionList, Test-SpawnNewActionFlag, Write-SpawnNewActionStep, Write-SpawnNewActionNote, Add-SpawnNewActionResource, Test-SpawnNewActionCancel, Complete-SpawnNewAction, Complete-SpawnNewActionCancelled, Complete-SpawnNewActionFailed, New-SpawnNewActionFolder, Test-SpawnNewActionWritable, Write-SpawnNewActionText, New-SpawnNewActionDocument, Get-SpawnNewFreeFilePath, Assert-SpawnNewActionEndpoint, Invoke-SpawnNewActionChat, Write-SpawnNewActionDraft, Get-SpawnNewActionFormat, Expand-SpawnNewPlaceholder, Get-SpawnNewDataDirectory, ConvertFrom-SpawnNewModelJson
