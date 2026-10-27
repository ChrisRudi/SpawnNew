# tests/SpawnNew.Selection.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Selection.psm1.
# Zweck  : Mehrere gleichzeitig gestartete Prozesse, wie der Explorer sie
#          bei mehreren markierten Dateien startet, ergeben genau einen
#          Sammler mit allen Pfaden.

Import-SpawnNewHostModule -Name 'Config', 'Selection'

Add-SpawnNewTest 'Einzelne Datei ergibt eine Auswahl mit einem Pfad' {
    $directory = Join-Path (Get-SpawnNewTestDirectory) 'Sel'
    $result = @(Add-SpawnNewSelection -ActionId 'spawnnew.test' -Path 'C:\a.txt' -QuietMilliseconds 200 -Directory $directory)

    Confirm-SpawnNewValue -Label 'Pfade' -Actual ($result -join '|') -Expected 'C:\a.txt'
    Confirm-SpawnNewCondition -Label 'Sammeldatei entfernt' -Condition (@(Get-ChildItem -LiteralPath $directory).Count -eq 0)
}

Add-SpawnNewTest 'Gleichzeitige Prozesse ergeben genau einen Sammler mit allen Pfaden' {
    $Work = Get-SpawnNewTestDirectory
    $directory = Join-Path $Work 'Sel'
    $hostDir = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'Host'
    $probe = Add-SpawnNewTestFile -Path (Join-Path $Work 'probe.ps1') -Content (@(
            'param($HostDir, $Directory, $File, $Out)',
            'Import-Module (Join-Path $HostDir ''SpawnNew.Selection.psm1'')',
            '$r = Add-SpawnNewSelection -ActionId ''spawnnew.multi'' -Path $File -QuietMilliseconds 1500 -Directory $Directory',
            '$text = if ($null -eq $r) { ''-'' } else { @($r) -join ''|'' }',
            '[System.IO.File]::WriteAllText($Out, $text)'
        ) -join "`r`n")

    $shell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $processes = foreach ($name in @('eins.txt', 'zwei.txt', 'drei.txt')) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $probe + '" -HostDir "' + $hostDir + '" -Directory "' + $directory + '" -File "C:\Daten\' + $name + '" -Out "' + (Join-Path $Work ($name + '.out')) + '"'
        Start-Process -FilePath $shell -ArgumentList $arguments -PassThru -WindowStyle Hidden
    }
    foreach ($process in $processes) { [void]$process.WaitForExit(30000) }

    $outputs = @('eins.txt', 'zwei.txt', 'drei.txt' | ForEach-Object { [System.IO.File]::ReadAllText((Join-Path $Work ($_ + '.out'))) })
    $collectors = @($outputs | Where-Object { $_ -ne '-' })

    Confirm-SpawnNewValue -Label 'ein Sammler' -Actual $collectors.Count -Expected 1
    Confirm-SpawnNewValue -Label 'alle Pfade' -Actual (@($collectors[0].Split('|') | Sort-Object) -join '|') -Expected 'C:\Daten\drei.txt|C:\Daten\eins.txt|C:\Daten\zwei.txt'
}

Add-SpawnNewTest 'Liegengebliebene Sammeldatei wird verworfen' {
    $directory = Join-Path (Get-SpawnNewTestDirectory) 'Sel'
    $stale = Add-SpawnNewTestFile -Path (Join-Path $directory ((Get-SpawnNewSelectionKey -ActionId 'spawnnew.alt') + '.txt')) -Content "C:\alt.txt`r`n"
    [System.IO.File]::SetLastWriteTimeUtc($stale, [System.DateTime]::UtcNow.AddMinutes(-5))

    $result = @(Add-SpawnNewSelection -ActionId 'spawnnew.alt' -Path 'C:\neu.txt' -QuietMilliseconds 200 -Directory $directory)
    Confirm-SpawnNewValue -Label 'nur neu' -Actual ($result -join '|') -Expected 'C:\neu.txt'
}

Add-SpawnNewTest 'Doppelte Pfade erscheinen einmal' {
    $directory = Join-Path (Get-SpawnNewTestDirectory) 'Sel'
    [void](Add-SpawnNewTestFile -Path (Join-Path $directory ((Get-SpawnNewSelectionKey -ActionId 'spawnnew.d') + '.txt')) -Content "C:\x.txt`r`nc:\X.TXT`r`n")
    # Die vorhandene, frische Datei macht diesen Aufruf zum Mitlaeufer.
    Confirm-SpawnNewValue -Label 'Mitlaeufer' -Actual (Add-SpawnNewSelection -ActionId 'spawnnew.d' -Path 'C:\y.txt' -QuietMilliseconds 200 -Directory $directory) -Expected $null
}
