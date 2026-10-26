# SpawnNew.Progress.psm1
# Version 1.0 | Fortschrittsfenster des Ausfuehrungsprozesses.
# Zweck  : Fortschritt der laufenden Aktion anzeigen, Abbruch anfordern und
#          am Ende Status, Meldung, Fehlerdetails und erstellte Ressourcen
#          zeigen. Unterscheidet Erfolg, Teilergebnis, Abbruch, Fehler und
#          unbekannten Zustand nach SpawnNew.md Abschnitt 10.
# Input  : Laufobjekt, Katalogeintrag, gestarteter Prozess.
# Output : Statusobjekt aus Get-SpawnNewRunStatus.
# Deps   : Windows PowerShell 5.1, System.Windows.Forms, System.Drawing,
#          SpawnNew.Runner.psm1.

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module (Join-Path $PSScriptRoot 'SpawnNew.Runner.psm1')

$script:PollMilliseconds = 250

$script:StatusText = @{
    success   = 'Erfolgreich erstellt.'
    partial   = 'Teilweise erstellt. Die unten genannten Ressourcen bleiben erhalten.'
    nochange  = 'Keine Änderungen.'
    cancelled = 'Abgebrochen. Die unten genannten Ressourcen bleiben erhalten.'
    failed    = 'Fehlgeschlagen.'
    unknown   = 'Status unbekannt. Es ist nicht gesichert, was erstellt wurde.'
}

function Get-SpawnNewStatusText {
    <#
    .SYNOPSIS
    Klartext zu einem Status.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Status)

    if ($script:StatusText.ContainsKey($Status)) { return $script:StatusText[$Status] }
    return $script:StatusText['unknown']
}

function Get-SpawnNewResultReport {
    <#
    .SYNOPSIS
    Abschlusstext mit Status, Meldung, Fehlerdetails und Ressourcenliste.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Status)

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('')
    [void]$lines.Add('--- ' + (Get-SpawnNewStatusText -Status $Status.Status) + ' ---')

    if ($Status.Message.Length -gt 0) { [void]$lines.Add($Status.Message) }
    if ($Status.Note.Length -gt 0)    { [void]$lines.Add($Status.Note) }

    if ($null -ne $Status.Error) {
        [void]$lines.Add('Schritt: ' + $Status.Error.Step)
        [void]$lines.Add('Ursache: ' + $Status.Error.Reason)
        if ($Status.Error.Details.Length -gt 0) {
            [void]$lines.Add('Details: ' + $Status.Error.Details)
        }
    }

    if ($Status.Created.Count -gt 0) {
        [void]$lines.Add('Erstellt:')
        foreach ($resource in $Status.Created) {
            [void]$lines.Add('  [' + $resource.Kind + '] ' + $resource.Path)
        }
    }

    return ($lines.ToArray() -join "`r`n")
}

function Invoke-SpawnNewProgressWindow {
    <#
    .SYNOPSIS
    Zeigt den Fortschritt und liefert den Endstatus.
    .DESCRIPTION
    Unterstuetzt die Aktion den Abbruch, wird die Abbruchdatei angelegt.
    Andernfalls wird der Abbruch nur als angefordert angezeigt; der Prozess
    wird nie von aussen beendet, damit eine Beendigung nicht als gelungenes
    Zuruecksetzen erscheint.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)]$Action,
        [Parameter(Mandatory)]$Process
    )

    $state = [pscustomobject]@{
        Offset   = [long]0
        Progress = (New-Object System.Collections.ArrayList)
        Status   = $null
        Done     = $false
        Process  = $Process
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = 'SpawnNew - ' + $Action.Title
    $form.ClientSize      = New-Object System.Drawing.Size(640, 420)
    $form.FormBorderStyle = 'FixedDialog'
    $form.StartPosition   = 'CenterScreen'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.ControlBox      = $false
    $form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

    $step = New-Object System.Windows.Forms.Label
    $step.Left  = 12
    $step.Top   = 12
    $step.Width = 616
    $step.Text  = 'Aktion wird gestartet.'

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Left  = 12
    $bar.Top   = 36
    $bar.Width = 616
    $bar.Style = 'Marquee'

    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline  = $true
    $log.ReadOnly   = $true
    $log.ScrollBars = 'Vertical'
    $log.Left       = 12
    $log.Top        = 70
    $log.Width      = 616
    $log.Height     = 300
    $log.Font       = New-Object System.Drawing.Font('Consolas', 9)

    $button = New-Object System.Windows.Forms.Button
    $button.Text  = 'Abbrechen'
    $button.Left  = 518
    $button.Top   = 382
    $button.Width = 110

    $form.Controls.AddRange(@($step, $bar, $log, $button))

    $append = {
        param($Text)
        $log.AppendText($Text + "`r`n")
    }

    $onButton = {
        if ($state.Done) {
            $form.Close()
            return
        }

        $button.Enabled = $false
        if ($Action.SupportsCancel) {
            Request-SpawnNewCancel -Run $Run
            & $append 'Abbruch angefordert. Die Aktion beendet sich beim nächsten Schritt.'
        }
        else {
            Request-SpawnNewCancel -Run $Run
            & $append 'Abbruch angefordert. Diese Aktion unterstützt keinen Abbruch; es wird auf das Ende des Vorgangs gewartet.'
        }
    }
    $button.Add_Click($onButton.GetNewClosure())

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $script:PollMilliseconds

    $onTick = {
        $read = Read-SpawnNewProgress -Path $Run.ProgressFile -Offset $state.Offset
        $state.Offset = $read.Offset

        foreach ($entry in $read.Entry) {
            [void]$state.Progress.Add($entry)

            switch ($entry.Type) {
                'step' {
                    $step.Text = $entry.Text
                    & $append ('* ' + $entry.Text)
                    if ($entry.Percent -ge 0) {
                        $bar.Style = 'Continuous'
                        $bar.Value = $entry.Percent
                    }
                }
                'created' { & $append ('  + ' + $entry.Kind + ': ' + $entry.Path) }
                'warn'    { & $append ('  ! ' + $entry.Text) }
                default   { & $append ('  ' + $entry.Text) }
            }
        }

        if (-not $state.Process.HasExited) { return }

        $timer.Stop()

        $result = Read-SpawnNewResult -Run $Run
        $status = Get-SpawnNewRunStatus -ExitCode $state.Process.ExitCode -Result $result -Progress $state.Progress.ToArray()

        $state.Status = $status
        $state.Done   = $true

        $bar.Style = 'Continuous'
        $bar.Value = 100
        $step.Text = Get-SpawnNewStatusText -Status $status.Status
        & $append (Get-SpawnNewResultReport -Status $status)

        $button.Text    = 'Schließen'
        $button.Enabled = $true
    }
    $timer.Add_Tick($onTick.GetNewClosure())

    $onShown = { $timer.Start() }
    $form.Add_Shown($onShown.GetNewClosure())

    [void]$form.ShowDialog()
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()

    if ($null -ne $state.Status) { return $state.Status }

    # Das Fenster wurde geschlossen, bevor der Prozess endete.
    return (Get-SpawnNewRunStatus -ExitCode -1 -Result (Read-SpawnNewResult -Run $Run) -Progress $state.Progress.ToArray())
}

Export-ModuleMember -Function Get-SpawnNewStatusText, Get-SpawnNewResultReport, Invoke-SpawnNewProgressWindow
