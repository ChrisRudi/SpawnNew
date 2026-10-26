# tests/SpawnNew.Test.Tests.ps1
# Version 1.0 | Prueft den Testlaeufer selbst.
# Zweck  : Sichert zu, dass Arbeitsverzeichnis, Modulimport und Zusicherungen
#          so arbeiten, wie die uebrigen Testdateien es voraussetzen.

Import-SpawnNewHostModule -Name 'Config'

Add-SpawnNewTest 'Arbeitsverzeichnis ist leer und vorhanden' {
    $Work = Get-SpawnNewTestDirectory
    Confirm-SpawnNewCondition -Label 'Ordner da' -Condition (Test-Path -LiteralPath $Work -PathType Container)
    Confirm-SpawnNewValue -Label 'leer' -Actual @(Get-ChildItem -LiteralPath $Work).Count -Expected 0
}

Add-SpawnNewTest 'Hostmodul ist in der Testsitzung geladen' {
    Confirm-SpawnNewValue -Label 'Pfadschluessel' -Actual (Get-SpawnNewPathKey -Path 'C:\Test\') -Expected 'c:\test'
}

Add-SpawnNewTest 'LOCALAPPDATA zeigt in das Arbeitsverzeichnis' {
    $Work = Get-SpawnNewTestDirectory
    Confirm-SpawnNewValue -Label 'LOCALAPPDATA' -Actual $env:LOCALAPPDATA -Expected $Work
}

Add-SpawnNewTest 'Confirm-SpawnNewValue meldet eine Abweichung' {
    $thrown = $false
    try { Confirm-SpawnNewValue -Label 'Beispiel' -Actual 1 -Expected 2 }
    catch { $thrown = $true }
    Confirm-SpawnNewCondition -Label 'Abweichung erkannt' -Condition $thrown
}

Add-SpawnNewTest 'Confirm-SpawnNewCondition meldet eine falsche Bedingung' {
    $thrown = $false
    try { Confirm-SpawnNewCondition -Label 'Beispiel' -Condition $false }
    catch { $thrown = $true }
    Confirm-SpawnNewCondition -Label 'Bedingung erkannt' -Condition $thrown
}
