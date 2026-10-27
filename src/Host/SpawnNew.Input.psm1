# SpawnNew.Input.psm1
# Version 1.1 | Formularfelder normalisieren und pruefen.
# Zweck  : Felder aus action.json in eine einheitliche Form bringen,
#          Vorbelegungen bestimmen und Eingaben pruefen. Enthaelt keine
#          Fensterdarstellung, damit die Regeln ohne WinForms pruefbar bleiben.
# Input  : Katalogeintrag aus SpawnNew.Catalog.psm1, Eingabewerte.
# Output : Normalisierte Felder und Pruefergebnisse.
# Deps   : Windows PowerShell 5.1, SpawnNew.Config.psm1.

Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Config.psm1')

$script:FieldTypes = @('text', 'multiline', 'date', 'choice', 'bool', 'file', 'endpoint')

function Get-SpawnNewCheckResult {
    <#
    .SYNOPSIS
    Einheitliches Pruefergebnis aus Gueltigkeit, Meldung und Wert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Valid,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Value
    )

    return [pscustomobject]@{ Valid = $Valid; Message = $Message; Value = $Value }
}

function Get-SpawnNewStringOrDefault {
    <#
    .SYNOPSIS
    Zeichenkette aus einem JSON-Objekt, sonst die Vorgabe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Default
    )

    if (-not (Test-SpawnNewProperty $InputObject $Name)) { return $Default }

    $value = [string]$InputObject.$Name
    if ($value.Length -eq 0) { return $Default }
    return $value
}

function Get-SpawnNewBoolOrDefault {
    <#
    .SYNOPSIS
    Wahrheitswert aus einem JSON-Objekt, sonst die Vorgabe.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Default
    )

    if (-not (Test-SpawnNewProperty $InputObject $Name)) { return $Default }
    return [bool]$InputObject.$Name
}

function ConvertTo-SpawnNewField {
    <#
    .SYNOPSIS
    Normalisiert einen Feldeintrag aus action.json. Liefert $null, wenn der
    Eintrag unbrauchbar ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Entry,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $name = ''
    if (Test-SpawnNewProperty $Entry 'name') { $name = ([string]$Entry.name).Trim() }

    if ($name.Length -eq 0) {
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' -Area 'action' `
            -Path $Path -Message "Feld $Index hat keinen Namen und wird übersprungen."
        return $null
    }

    $type = 'text'
    if (Test-SpawnNewProperty $Entry 'type') { $type = ([string]$Entry.type).Trim() }

    if ($script:FieldTypes -notcontains $type) {
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' -Area 'action' `
            -Path $Path -Message "Feld '$name' hat den unbekannten Typ '$type'; es gilt 'text'."
        $type = 'text'
    }

    $choices = @()
    if (Test-SpawnNewProperty $Entry 'choices') { $choices = @($Entry.choices | ForEach-Object { [string]$_ }) }

    if ($type -eq 'choice' -and $choices.Count -eq 0) {
        Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'error' -Area 'action' `
            -Path $Path -Message "Auswahlfeld '$name' hat keine Auswahlwerte und wird übersprungen."
        return $null
    }

    return [pscustomobject]@{
        Name     = $name
        Label    = (Get-SpawnNewStringOrDefault -InputObject $Entry -Name 'label' -Default $name)
        Type     = $type
        Required = (Get-SpawnNewBoolOrDefault -InputObject $Entry -Name 'required' -Default $false)
        Default  = (Get-SpawnNewStringOrDefault -InputObject $Entry -Name 'default' -Default '')
        Choices  = $choices
        Multiple = (Get-SpawnNewBoolOrDefault -InputObject $Entry -Name 'multiple' -Default $false)
        Pattern  = (Get-SpawnNewStringOrDefault -InputObject $Entry -Name 'pattern' -Default '')
        Message  = (Get-SpawnNewStringOrDefault -InputObject $Entry -Name 'message' -Default '')
    }
}

function Get-SpawnNewFieldList {
    <#
    .SYNOPSIS
    Normalisiert alle Felder einer Aktion.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Diagnostics
    )

    $fields = New-Object System.Collections.ArrayList
    $seen   = @{}
    $index  = 0

    foreach ($entry in @($Action.Fields)) {
        $field = ConvertTo-SpawnNewField -Entry $entry -Index $index -Path $Action.DescriptionPath -Diagnostics $Diagnostics
        $index++
        if ($null -eq $field) { continue }

        $key = $field.Name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            Add-SpawnNewDiagnostic -Diagnostics $Diagnostics -Severity 'warning' -Area 'action' `
                -Path $Action.DescriptionPath -Message "Feld '$($field.Name)' ist mehrfach deklariert; der erste Eintrag gilt."
            continue
        }

        $seen[$key] = $true
        [void]$fields.Add($field)
    }

    return [object[]]$fields.ToArray()
}

function Get-SpawnNewFieldDefault {
    <#
    .SYNOPSIS
    Vorbelegung eines Feldes. 'today' in einem Datumsfeld wird zum heutigen
    Datum nach ISO 8601.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Field)

    if ($Field.Type -eq 'date' -and $Field.Default -eq 'today') {
        return [System.DateTime]::Today.ToString('yyyy-MM-dd')
    }

    if (($Field.Type -eq 'choice' -or $Field.Type -eq 'endpoint') -and $Field.Default.Length -eq 0) {
        if (@($Field.Choices).Count -eq 0) { return '' }
        return @($Field.Choices)[0]
    }

    return $Field.Default
}

function Set-SpawnNewEndpointChoice {
    <#
    .SYNOPSIS
    Fuellt Felder vom Typ 'endpoint' mit den konfigurierten KI-Endpunkten.
    .DESCRIPTION
    Die Auswahl steht nicht in action.json, sondern in der Konfiguration.
    Der voreingestellte Endpunkt wird Vorbelegung.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Field,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Default
    )

    foreach ($entry in $Field) {
        if ($entry.Type -ne 'endpoint') { continue }
        if (-not $PSCmdlet.ShouldProcess($entry.Name, 'Endpunkte eintragen')) { continue }

        $entry.Choices = $Name
        if ($entry.Default.Length -eq 0 -or $Name -notcontains $entry.Default) {
            $entry.Default = if ($Name -contains $Default) { $Default } else { '' }
        }
    }
}

function Test-SpawnNewFieldValue {
    <#
    .SYNOPSIS
    Prueft einen einzelnen Eingabewert und liefert ihn normalisiert zurueck.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Field,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Value
    )

    $text = ''
    if ($null -ne $Value) { $text = ([string]$Value).Trim() }

    if ($text.Length -eq 0) {
        if ($Field.Required) {
            return (Get-SpawnNewCheckResult -Valid $false -Message "$($Field.Label): Eingabe fehlt." -Value '')
        }
        return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value '')
    }

    switch ($Field.Type) {
        'bool' {
            $parsed = $false
            if (-not [bool]::TryParse($text, [ref]$parsed)) {
                return (Get-SpawnNewCheckResult -Valid $false -Message "$($Field.Label): nur Ja oder Nein möglich." -Value $text)
            }
            return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $parsed)
        }
        'date' {
            $parsed = [System.DateTime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::None
            $culture = [System.Globalization.CultureInfo]::GetCultureInfo('de-DE')
            if ([System.DateTime]::TryParse($text, $culture, $styles, [ref]$parsed)) {
                return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $parsed.ToString('yyyy-MM-dd'))
            }
            return (Get-SpawnNewCheckResult -Valid $false -Message "$($Field.Label): kein gültiges Datum." -Value $text)
        }
        { $_ -eq 'choice' -or $_ -eq 'endpoint' } {
            if ($Field.Choices -contains $text) {
                return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $text)
            }
            if (@($Field.Choices).Count -eq 0) {
                return (Get-SpawnNewCheckResult -Valid $false -Message "$($Field.Label): es ist kein KI-Endpunkt konfiguriert." -Value $text)
            }
            $list = $Field.Choices -join ', '
            return (Get-SpawnNewCheckResult -Valid $false -Message "$($Field.Label): nur $list möglich." -Value $text)
        }
        'file' {
            # Mehrere Dateien stehen je Zeile; der Wert wird dann ein Feld.
            $multiple = (Test-SpawnNewProperty $Field 'Multiple') -and [bool]$Field.Multiple
            $items = if ($multiple) { @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @($text) }
            $files = New-Object System.Collections.ArrayList

            foreach ($item in $items) {
                $full = $item
                try { $full = [System.IO.Path]::GetFullPath($item) } catch { $full = $item }
                if (-not ([System.IO.Path]::IsPathRooted($item) -and [System.IO.File]::Exists($full))) {
                    return (Get-SpawnNewCheckResult -Valid $false -Message "$($Field.Label): die Datei ist nicht vorhanden: $item" -Value $text)
                }
                [void]$files.Add($full)
            }

            if ($multiple) { return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value ([string[]]$files.ToArray())) }
            return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $files[0])
        }
    }

    if ($Field.Pattern.Length -gt 0 -and $text -notmatch $Field.Pattern) {
        $message = $Field.Message
        if ($message.Length -eq 0) { $message = "$($Field.Label): Eingabe entspricht nicht dem erwarteten Muster." }
        return (Get-SpawnNewCheckResult -Valid $false -Message $message -Value $text)
    }

    return (Get-SpawnNewCheckResult -Valid $true -Message '' -Value $text)
}

function Test-SpawnNewFieldValueSet {
    <#
    .SYNOPSIS
    Prueft alle Eingaben eines Formulars.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Field,
        [Parameter(Mandatory)][hashtable]$Value
    )

    $errors = New-Object System.Collections.ArrayList
    $result = @{}

    foreach ($entry in $Field) {
        $raw = $null
        if ($Value.ContainsKey($entry.Name)) { $raw = $Value[$entry.Name] }

        $check = Test-SpawnNewFieldValue -Field $entry -Value $raw
        if ($check.Valid) { $result[$entry.Name] = $check.Value }
        else { [void]$errors.Add($check.Message) }
    }

    return [pscustomobject]@{
        Valid  = ($errors.Count -eq 0)
        Errors = $errors.ToArray()
        Value  = $result
    }
}

Export-ModuleMember -Function Get-SpawnNewCheckResult, Get-SpawnNewStringOrDefault, Get-SpawnNewBoolOrDefault, ConvertTo-SpawnNewField, Get-SpawnNewFieldList, Get-SpawnNewFieldDefault, Set-SpawnNewEndpointChoice, Test-SpawnNewFieldValue, Test-SpawnNewFieldValueSet
