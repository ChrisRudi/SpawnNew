# SpawnNew.SettingsForm.psm1
# Version 1.0 | Fenster der Verwaltungsbefehle.
# Zweck  : Konfigurationsfenster mit Uebersicht und Schaltflaechen,
#          Eingabe eines Geheimnisses mit verdecktem Feld, Auswahl eines
#          Geheimnisses und ein Wartefenster fuer laufende Einzeiler. Die
#          Regeln dahinter stehen in SpawnNew.Settings.psm1.
# Input  : Programmverzeichnis, laufender Prozess.
# Output : Benutzerentscheidungen.
# Deps   : Windows PowerShell 5.1, System.Windows.Forms, System.Drawing,
#          SpawnNew.Settings.psm1, SpawnNew.Form.psm1.

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Settings.psm1')
Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Form.psm1')

function Show-SpawnNewSecretInput {
    <#
    .SYNOPSIS
    Fragt Name und Wert eines Geheimnisses ab. Der Wert bleibt verdeckt und
    wird als SecureString geliefert. Liefert $null bei Abbruch.
    #>
    [CmdletBinding()]
    param([string]$Name = '')

    $form = Get-SpawnNewDialog -Title 'SpawnNew - Geheimnis speichern' -Width 460 -Height 170

    $nameLabel = Get-SpawnNewLabel -Text 'Name' -Top 14
    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Left = 120; $nameBox.Top = 12; $nameBox.Width = 320; $nameBox.Text = $Name

    $valueLabel = Get-SpawnNewLabel -Text 'Wert' -Top 46
    $valueBox = New-Object System.Windows.Forms.TextBox
    $valueBox.Left = 120; $valueBox.Top = 44; $valueBox.Width = 320; $valueBox.UseSystemPasswordChar = $true

    $hint = New-Object System.Windows.Forms.Label
    $hint.Left = 12; $hint.Top = 76; $hint.Width = 430; $hint.Height = 36
    $hint.Text = 'Der Name gehört als "secret" in den Endpunkt der Konfiguration. Der Wert wird verschlüsselt und nur für diesen Benutzer auf diesem Rechner gespeichert.'

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Speichern'; $ok.Left = 236; $ok.Top = 124; $ok.Width = 100
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Abbrechen'; $cancel.Left = 342; $cancel.Top = 124; $cancel.Width = 100
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($nameLabel, $nameBox, $valueLabel, $valueBox, $hint, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    $result = $null
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $valueBox.Text.Length -gt 0) {
        $secure = New-Object System.Security.SecureString
        foreach ($char in $valueBox.Text.ToCharArray()) { $secure.AppendChar($char) }
        $secure.MakeReadOnly()
        $result = [pscustomobject]@{ Name = $nameBox.Text.Trim(); Value = $secure }
    }
    $valueBox.Text = ''
    $form.Dispose()
    return $result
}

function Show-SpawnNewChoice {
    <#
    .SYNOPSIS
    Auswahl aus einer Liste. Liefert '' bei Abbruch.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Item
    )

    $form = Get-SpawnNewDialog -Title ('SpawnNew - ' + $Title) -Width 360 -Height 100
    $box = New-Object System.Windows.Forms.ComboBox
    $box.DropDownStyle = 'DropDownList'; $box.Left = 12; $box.Top = 12; $box.Width = 336
    foreach ($entry in $Item) { [void]$box.Items.Add($entry) }
    if ($Item.Count -gt 0) { $box.SelectedIndex = 0 }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'; $ok.Left = 142; $ok.Top = 56; $ok.Width = 100
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Abbrechen'; $cancel.Left = 248; $cancel.Top = 56; $cancel.Width = 100
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($box, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    $chosen = ''
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $null -ne $box.SelectedItem) { $chosen = [string]$box.SelectedItem }
    $form.Dispose()
    return $chosen
}

function Show-SpawnNewWaitWindow {
    <#
    .SYNOPSIS
    Zeigt ein Wartefenster, bis der Prozess endet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][string]$Text
    )

    $form = Get-SpawnNewDialog -Title 'SpawnNew' -Width 420 -Height 90
    $form.ControlBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Left = 12; $label.Top = 12; $label.Width = 396; $label.Text = $Text
    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Left = 12; $bar.Top = 44; $bar.Width = 396; $bar.Style = 'Marquee'
    $form.Controls.AddRange(@($label, $bar))

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({ if ($Process.HasExited) { $timer.Stop(); $form.Close() } })
    $form.Add_Shown({ $timer.Start() })

    [void]$form.ShowDialog()
    $timer.Dispose()
    $form.Dispose()
    $Process.WaitForExit()
}

function Show-SpawnNewSettingsDialog {
    <#
    .SYNOPSIS
    Konfigurationsfenster: Uebersicht und alle Verwaltungsschritte, die
    ohne Aktionsstarter erreichbar sein muessen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AppDirectory)

    $form = Get-SpawnNewDialog -Title ('SpawnNew - Konfiguration - ' + $AppDirectory) -Width 760 -Height 520

    $report = New-Object System.Windows.Forms.TextBox
    $report.Multiline = $true; $report.ReadOnly = $true; $report.ScrollBars = 'Both'; $report.WordWrap = $false
    $report.Left = 12; $report.Top = 12; $report.Width = 736; $report.Height = 400
    $report.Font = New-Object System.Drawing.Font('Consolas', 9)
    $form.Controls.Add($report)

    # Bewusst ohne GetNewClosure: eine Closure saehe die in dieses Modul
    # importierten Funktionen nicht. Die Handler laufen waehrend ShowDialog,
    # also solange diese Funktion aktiv ist, und finden $refresh, $report
    # und $AppDirectory ueber den Aufrufstapel.
    $refresh = {
        $config = Get-SpawnNewConfig -AppDirectory $AppDirectory
        $report.Text = Get-SpawnNewSettingsReport -Config $config -AppDirectory $AppDirectory
    }
    & $refresh

    $buttons = @(
        @{ Text = 'Einstellungen bearbeiten'; Action = {
                $path = Initialize-SpawnNewUserSetting
                Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $path + '"') -Wait
                & $refresh
            }
        },
        @{ Text = 'Aktionsordner öffnen'; Action = {
                $path = Join-Path (Get-SpawnNewDataDirectory) 'Actions'
                if (-not [System.IO.Directory]::Exists($path)) { [void][System.IO.Directory]::CreateDirectory($path) }
                Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $path + '"')
            }
        },
        @{ Text = 'Vorlagenordner öffnen'; Action = {
                $path = Join-Path (Get-SpawnNewDataDirectory) 'Vorlagen'
                if (-not [System.IO.Directory]::Exists($path)) { [void][System.IO.Directory]::CreateDirectory($path) }
                Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $path + '"')
            }
        },
        @{ Text = 'Geheimnis speichern'; Action = {
                $entered = Show-SpawnNewSecretInput
                if ($null -eq $entered) { return }
                try {
                    Set-SpawnNewSecret -Name $entered.Name -Value $entered.Value
                    Show-SpawnNewMessage -Title 'Geheimnis' -Text ("Das Geheimnis '" + $entered.Name + "' ist gespeichert.")
                }
                catch { Show-SpawnNewMessage -Title 'Geheimnis' -Icon 'Warning' -Text $_.Exception.Message }
                & $refresh
            }
        },
        @{ Text = 'Geheimnis entfernen'; Action = {
                $names = @(Get-SpawnNewSecretName)
                if ($names.Count -eq 0) { Show-SpawnNewMessage -Title 'Geheimnis' -Text 'Es ist kein Geheimnis gespeichert.'; return }
                $name = Show-SpawnNewChoice -Title 'Geheimnis entfernen' -Item ([string[]]$names)
                if ($name -and (Show-SpawnNewConfirmation -Title 'Geheimnis' -Text ("Das Geheimnis '" + $name + "' entfernen?"))) {
                    Remove-SpawnNewSecret -Name $name
                }
                & $refresh
            }
        },
        @{ Text = 'KI-Endpunkte testen'; Action = {
                $config = Get-SpawnNewConfig -AppDirectory $AppDirectory
                $lines = @()
                foreach ($endpoint in @($config.Llm.Endpoints)) {
                    $check = Test-SpawnNewEndpoint -Endpoint $endpoint
                    $lines += $(if ($check.Reachable) { $endpoint.Name + ': erreichbar' } else { $check.Message })
                }
                if ($lines.Count -eq 0) { $lines = @('Es ist kein KI-Endpunkt konfiguriert.') }
                Show-SpawnNewMessage -Title 'KI-Endpunkte' -Text ($lines -join "`r`n`r`n")
            }
        },
        @{ Text = 'Menü neu einlesen'; Action = {
                $config = Get-SpawnNewConfig -AppDirectory $AppDirectory
                Show-SpawnNewMessage -Title 'Menü' -Text (Update-SpawnNewMenu -Config $config -AppDirectory $AppDirectory).Message
            }
        }
    )

    $left = 12
    $top  = 422
    foreach ($entry in $buttons) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $entry.Text; $button.Left = $left; $button.Top = $top; $button.Width = 178; $button.Height = 28
        # Der Handler steht im Tag der Schaltflaeche; eine Schleifenvariable
        # haette beim Klick den Wert des letzten Durchlaufs.
        $button.Tag = $entry.Action
        $button.Add_Click({ try { & $this.Tag } catch { Show-SpawnNewMessage -Title 'Fehler' -Icon 'Error' -Text $_.Exception.Message } })
        $form.Controls.Add($button)

        $left += 186
        if ($left -gt 600) { $left = 12; $top += 34 }
    }

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Schließen'; $close.Left = 570; $close.Top = 456; $close.Width = 178; $close.Height = 28
    $close.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($close)
    $form.CancelButton = $close

    [void]$form.ShowDialog()
    $form.Dispose()
}

Export-ModuleMember -Function Show-SpawnNewSecretInput, Show-SpawnNewChoice, Show-SpawnNewWaitWindow, Show-SpawnNewSettingsDialog
