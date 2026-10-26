# SpawnNew.Form.psm1
# Version 1.0 | Einheitliche Dialoge des Ausfuehrungsprozesses.
# Zweck  : Eingabeformular, Konfliktfrage, Zusammenfassung und Meldungen als
#          WinForms-Fenster. Die Regeln dahinter stehen in SpawnNew.Input.psm1
#          und SpawnNew.Target.psm1; hier wird nur dargestellt.
# Input  : Katalogeintrag, normalisierte Felder, Basisverzeichnis.
# Output : Benutzerentscheidung und Eingabewerte.
# Deps   : Windows PowerShell 5.1, System.Windows.Forms, System.Drawing,
#          SpawnNew.Input.psm1, SpawnNew.Target.psm1.

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Input.psm1')
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Target.psm1')

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:LabelWidth   = 150
$script:ControlWidth = 380
$script:RowHeight    = 30
$script:Margin       = 12

function Get-SpawnNewDialog {
    <#
    .SYNOPSIS
    Grundfenster mit einheitlicher Gestaltung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = $Title
    $form.ClientSize      = New-Object System.Drawing.Size($Width, $Height)
    $form.FormBorderStyle = 'FixedDialog'
    $form.StartPosition   = 'CenterScreen'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)
    return $form
}

function Get-SpawnNewLabel {
    <#
    .SYNOPSIS
    Beschriftung links neben einem Eingabefeld.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Top
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text      = $Text
    $label.Left      = $script:Margin
    $label.Top       = $Top + 3
    $label.Width     = $script:LabelWidth
    $label.AutoSize  = $false
    return $label
}

function Get-SpawnNewFieldControl {
    <#
    .SYNOPSIS
    Eingabefeld passend zum Feldtyp, vorbelegt mit der Vorgabe der Aktion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Field,
        [Parameter(Mandatory)][int]$Top
    )

    $default = Get-SpawnNewFieldDefault -Field $Field
    $left    = $script:Margin + $script:LabelWidth

    switch ($Field.Type) {
        'bool' {
            $control = New-Object System.Windows.Forms.CheckBox
            $control.Checked = ($default -eq 'true' -or $default -eq 'True')
            $control.Text    = ''
            $control.Width   = 20
        }
        'choice' {
            $control = New-Object System.Windows.Forms.ComboBox
            $control.DropDownStyle = 'DropDownList'
            foreach ($choice in $Field.Choices) { [void]$control.Items.Add($choice) }
            $control.SelectedItem = $default
            $control.Width = $script:ControlWidth
        }
        'multiline' {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Multiline = $true
            $control.Height    = 60
            $control.Text      = $default
            $control.Width     = $script:ControlWidth
        }
        default {
            $control = New-Object System.Windows.Forms.TextBox
            $control.Text  = $default
            $control.Width = $script:ControlWidth
        }
    }

    $control.Left = $left
    $control.Top  = $Top
    $control.Tag  = $Field.Name
    return $control
}

function Get-SpawnNewControlValue {
    <#
    .SYNOPSIS
    Liest den Wert eines Eingabefeldes als Zeichenkette.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Control)

    if ($Control -is [System.Windows.Forms.CheckBox]) { return $Control.Checked.ToString() }
    if ($Control -is [System.Windows.Forms.ComboBox]) {
        if ($null -eq $Control.SelectedItem) { return '' }
        return [string]$Control.SelectedItem
    }
    return [string]$Control.Text
}

function Show-SpawnNewActionForm {
    <#
    .SYNOPSIS
    Eingabeformular einer Aktion mit aenderbarem Zielpfad.
    .DESCRIPTION
    Abbrechen fuehrt keine fachliche Aenderung aus. Erst nach fehlerfreier
    Pruefung liefert die Funktion Confirmed = $true.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Field,
        [Parameter(Mandatory)][string]$BasePath
    )

    $abort = [pscustomobject]@{ Confirmed = $false; BasePath = $BasePath; Value = @{} }
    $rows  = $script:Margin

    $form = Get-SpawnNewDialog -Title ('SpawnNew - ' + $Action.Title) -Width 580 -Height 200

    $pathLabel = Get-SpawnNewLabel -Text 'Zielordner' -Top $rows
    $pathBox   = New-Object System.Windows.Forms.TextBox
    $pathBox.Left  = $script:Margin + $script:LabelWidth
    $pathBox.Top   = $rows
    $pathBox.Width = $script:ControlWidth - 90
    $pathBox.Text  = $BasePath

    $browse = New-Object System.Windows.Forms.Button
    $browse.Text  = 'Wählen'
    $browse.Left  = $pathBox.Left + $pathBox.Width + 8
    $browse.Top   = $rows - 1
    $browse.Width = 82
    $onBrowse = {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.SelectedPath = $pathBox.Text
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $pathBox.Text = $dialog.SelectedPath
        }
        $dialog.Dispose()
    }
    $browse.Add_Click($onBrowse.GetNewClosure())

    $form.Controls.AddRange(@($pathLabel, $pathBox, $browse))
    $rows += $script:RowHeight

    $controls = @{}
    foreach ($entry in $Field) {
        $label   = Get-SpawnNewLabel -Text $entry.Label -Top $rows
        $control = Get-SpawnNewFieldControl -Field $entry -Top $rows
        $form.Controls.AddRange(@($label, $control))
        $controls[$entry.Name] = $control
        $rows += [System.Math]::Max($script:RowHeight, $control.Height + 6)
    }

    $hint = New-Object System.Windows.Forms.Label
    $hint.Left      = $script:Margin
    $hint.Top       = $rows + 4
    $hint.Width     = $script:Margin + $script:LabelWidth + $script:ControlWidth
    $hint.Height    = 34
    $hint.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($hint)
    $rows += 44

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text   = 'Weiter'
    $ok.Width  = 110
    $ok.Left   = $script:Margin + $script:LabelWidth + $script:ControlWidth - 228
    $ok.Top    = $rows

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text         = 'Abbrechen'
    $cancel.Width        = 110
    $cancel.Left         = $ok.Left + 118
    $cancel.Top          = $rows
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $result = [pscustomobject]@{ Confirmed = $false; BasePath = $BasePath; Value = @{} }

    $onAccept = {
        $raw = @{}
        foreach ($name in $controls.Keys) { $raw[$name] = Get-SpawnNewControlValue -Control $controls[$name] }

        $pathCheck = Test-SpawnNewBasePath -Path $pathBox.Text
        if (-not $pathCheck.Valid) {
            $hint.Text = $pathCheck.Message
            return
        }

        $check = Test-SpawnNewFieldValueSet -Field $Field -Value $raw
        if (-not $check.Valid) {
            $hint.Text = ($check.Errors -join "`r`n")
            return
        }

        $result.Confirmed = $true
        $result.BasePath  = $pathCheck.Value
        $result.Value     = $check.Value
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    }
    $ok.Add_Click($onAccept.GetNewClosure())

    $form.Controls.AddRange(@($ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.ClientSize   = New-Object System.Drawing.Size(580, ($rows + 40))

    $shown = $form.ShowDialog()
    $form.Dispose()

    if ($shown -ne [System.Windows.Forms.DialogResult]::OK) { return $abort }
    return $result
}

function Show-SpawnNewTextDialog {
    <#
    .SYNOPSIS
    Fenster mit festem Text und zwei Schaltflaechen.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$AcceptText,
        [Parameter(Mandatory)][string]$CancelText
    )

    $form = Get-SpawnNewDialog -Title $Title -Width 580 -Height 420

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline  = $true
    $box.ReadOnly   = $true
    $box.ScrollBars = 'Vertical'
    $box.Left       = $script:Margin
    $box.Top        = $script:Margin
    $box.Width      = 556
    $box.Height     = 330
    $box.Font       = New-Object System.Drawing.Font('Consolas', 9)
    $box.Text       = $Text

    $accept = New-Object System.Windows.Forms.Button
    $accept.Text         = $AcceptText
    $accept.Width        = 130
    $accept.Left         = 304
    $accept.Top          = 358
    $accept.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text         = $CancelText
    $cancel.Width        = 130
    $cancel.Left         = 442
    $cancel.Top          = 358
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($box, $accept, $cancel))
    $form.AcceptButton = $accept
    $form.CancelButton = $cancel

    $shown = $form.ShowDialog()
    $form.Dispose()
    return ($shown -eq [System.Windows.Forms.DialogResult]::OK)
}

function Show-SpawnNewSummary {
    <#
    .SYNOPSIS
    Zusammenfassung vor dem Start. Erst 'Erstellen' startet die Aktion.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Text)

    return (Show-SpawnNewTextDialog -Title 'SpawnNew - Zusammenfassung' -Text $Text -AcceptText 'Erstellen' -CancelText 'Abbrechen')
}

function Show-SpawnNewConflictChoice {
    <#
    .SYNOPSIS
    Auswahl bei vorhandenem Zielnamen nach SpawnNew.md Abschnitt 7.
    .DESCRIPTION
    Liefert 'cancel', 'rename' oder 'use'. 'use' ist keine Erlaubnis zum
    Ueberschreiben vorhandener Dateien.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$FreeName
    )

    $form = Get-SpawnNewDialog -Title 'SpawnNew - Ziel vorhanden' -Width 520 -Height 170

    $label = New-Object System.Windows.Forms.Label
    $label.Left   = $script:Margin
    $label.Top    = $script:Margin
    $label.Width  = 496
    $label.Height = 60
    $label.Text   = "Das Ziel ist bereits vorhanden:`r`n$TargetPath`r`n`r`nVorhandene Dateien werden nicht überschrieben."

    $state = [pscustomobject]@{ Choice = 'cancel' }

    $rename = New-Object System.Windows.Forms.Button
    $rename.Text  = ('"' + $FreeName + '" verwenden')
    $rename.Left  = $script:Margin
    $rename.Top   = 96
    $rename.Width = 200
    $onRename = {
        $state.Choice = 'rename'
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    }
    $rename.Add_Click($onRename.GetNewClosure())

    $use = New-Object System.Windows.Forms.Button
    $use.Text  = 'Vorhandenen Ordner verwenden'
    $use.Left  = $script:Margin + 208
    $use.Top   = 96
    $use.Width = 200
    $onUse = {
        $state.Choice = 'use'
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    }
    $use.Add_Click($onUse.GetNewClosure())

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text         = 'Abbrechen'
    $cancel.Left         = $script:Margin + 416
    $cancel.Top          = 96
    $cancel.Width        = 80
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($label, $rename, $use, $cancel))
    $form.CancelButton = $cancel

    [void]$form.ShowDialog()
    $form.Dispose()
    return $state.Choice
}

function Show-SpawnNewMessage {
    <#
    .SYNOPSIS
    Meldung mit einer Schaltflaeche.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information'
    )

    $buttons = [System.Windows.Forms.MessageBoxButtons]::OK
    $symbol  = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [void][System.Windows.Forms.MessageBox]::Show($Text, ('SpawnNew - ' + $Title), $buttons, $symbol)
}

function Show-SpawnNewConfirmation {
    <#
    .SYNOPSIS
    Rueckfrage mit Ja und Nein.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Text
    )

    $buttons = [System.Windows.Forms.MessageBoxButtons]::YesNo
    $symbol  = [System.Windows.Forms.MessageBoxIcon]::Question
    $answer  = [System.Windows.Forms.MessageBox]::Show($Text, ('SpawnNew - ' + $Title), $buttons, $symbol)

    return ($answer -eq [System.Windows.Forms.DialogResult]::Yes)
}

Export-ModuleMember -Function Get-SpawnNewDialog, Get-SpawnNewLabel, Get-SpawnNewFieldControl, Get-SpawnNewControlValue, Show-SpawnNewActionForm, Show-SpawnNewTextDialog, Show-SpawnNewSummary, Show-SpawnNewConflictChoice, Show-SpawnNewMessage, Show-SpawnNewConfirmation
