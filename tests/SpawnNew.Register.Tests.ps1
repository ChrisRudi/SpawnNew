# tests/SpawnNew.Register.Tests.ps1
# Version 1.0 | Prueft SpawnNew.Register.psm1.
# Zweck  : Die Registrierungseintraege als Daten. Der Schreibzugriff selbst
#          ist nur auf Windows pruefbar und hier nicht abgedeckt.

Import-SpawnNewHostModule -Name 'Register'

function Get-TestEntry {
    param([object[]]$Action = @(), [string]$Scope = 'CurrentUser')

    $root = Get-SpawnNewRegistryRoot -Scope $Scope
    return @(Get-SpawnNewRegistryEntry -Action $Action -AppDirectory 'C:\App' -Root $root)
}

function Get-TestAction {
    param([string]$Id, [string]$Title)

    return [pscustomobject]@{ Id = $Id; Title = $Title }
}

Add-SpawnNewTest 'Wurzel haengt am Installationsumfang' {
    Confirm-SpawnNewValue -Label 'Benutzer' -Actual (Get-SpawnNewRegistryRoot -Scope 'CurrentUser') -Expected 'HKCU:\Software\Classes'
    Confirm-SpawnNewValue -Label 'System' -Actual (Get-SpawnNewRegistryRoot -Scope 'AllUsers') -Expected 'HKLM:\Software\Classes'
}

Add-SpawnNewTest 'Menueschluessel liegt unter Directory Background shell' {
    $key = Get-SpawnNewMenuKey -Root 'HKCU:\Software\Classes'

    Confirm-SpawnNewMatch -Label 'Pfad' -Actual $key -Pattern 'Directory.Background.shell.SpawnNew$'
}

Add-SpawnNewTest 'Untermenue entsteht aus MUIVerb und leerem SubCommands' {
    $entries = Get-TestEntry

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $entries.Count -Expected 2
    Confirm-SpawnNewValue -Label 'Anzeigename ueber MUIVerb' -Actual $entries[0].Name -Expected 'MUIVerb'
    Confirm-SpawnNewValue -Label 'Name' -Actual $entries[0].Value -Expected 'SpawnNew'
    Confirm-SpawnNewValue -Label 'SubCommands' -Actual $entries[1].Name -Expected 'SubCommands'
    Confirm-SpawnNewValue -Label 'leer' -Actual $entries[1].Value -Expected ''
}

Add-SpawnNewTest 'Nur die Befehlszeile ist ein unbenannter Standardwert' {
    $entries = Get-TestEntry -Action @((Get-TestAction -Id 'spawnnew.folderstructure' -Title 'Ordnerstruktur'))

    $standard = @($entries | Where-Object { $_.Kind -eq 'default' })
    Confirm-SpawnNewValue -Label 'Anzahl Standardwerte' -Actual $standard.Count -Expected 1
    Confirm-SpawnNewMatch -Label 'liegt unter command' -Actual $standard[0].Path -Pattern 'command$'
    Confirm-SpawnNewMatch -Label 'ist die Befehlszeile' -Actual $standard[0].Value -Pattern 'SpawnNew\.Host\.ps1'

    $benannt = @($entries | Where-Object { $_.Kind -eq 'value' })
    Confirm-SpawnNewValue -Label 'Anzahl benannte Werte' -Actual $benannt.Count -Expected 3
    Confirm-SpawnNewValue -Label 'kein Wert heisst (default)' -Actual @($benannt | Where-Object { $_.Name -eq '(default)' }).Count -Expected 0
}

Add-SpawnNewTest 'Je Aktion entstehen Titel und Befehl' {
    $entries = Get-TestEntry -Action @((Get-TestAction -Id 'spawnnew.folderstructure' -Title 'Ordnerstruktur'))

    Confirm-SpawnNewValue -Label 'Anzahl' -Actual $entries.Count -Expected 4
    Confirm-SpawnNewValue -Label 'Titel ueber MUIVerb' -Actual $entries[2].Name -Expected 'MUIVerb'
    Confirm-SpawnNewValue -Label 'Titel' -Actual $entries[2].Value -Expected 'Ordnerstruktur'
    Confirm-SpawnNewMatch -Label 'Schluessel' -Actual $entries[2].Path -Pattern 'shell.01_spawnnew\.folderstructure$'
    Confirm-SpawnNewMatch -Label 'Befehlsschluessel' -Actual $entries[3].Path -Pattern 'command$'
}

Add-SpawnNewTest 'Befehl uebergibt Skript, Aktions-ID und Explorer-Pfad in Anfuehrungszeichen' {
    $command = Get-SpawnNewActionCommand -AppDirectory 'C:\Program Files\SpawnNew\App' -ActionId 'spawnnew.gitproject'

    Confirm-SpawnNewMatch -Label 'Laufzeit' -Actual $command -Pattern '^powershell\.exe -NoProfile'
    Confirm-SpawnNewMatch -Label 'kein Profil, kein Dialog' -Actual $command -Pattern '-WindowStyle Hidden -ExecutionPolicy Bypass'
    Confirm-SpawnNewMatch -Label 'Skript mit Leerzeichen' -Actual $command -Pattern '-File "C:\\Program Files\\SpawnNew\\App\\SpawnNew\.Host\.ps1"'
    Confirm-SpawnNewMatch -Label 'Aktions-ID' -Actual $command -Pattern '-ActionId "spawnnew\.gitproject"'
    Confirm-SpawnNewMatch -Label 'Explorer-Pfad' -Actual $command -Pattern '-ExplorerPath "%V"$'
}

Add-SpawnNewTest 'Aktionen stehen nach Titel sortiert, der Zahlenpraefix haelt die Reihenfolge' {
    $actions = @(
        (Get-TestAction -Id 'spawnnew.zebra' -Title 'Zebra'),
        (Get-TestAction -Id 'spawnnew.alpha' -Title 'Alpha')
    )
    $entries = Get-TestEntry -Action $actions

    Confirm-SpawnNewMatch -Label 'erste' -Actual $entries[2].Path -Pattern '01_spawnnew\.alpha$'
    Confirm-SpawnNewMatch -Label 'zweite' -Actual $entries[4].Path -Pattern '02_spawnnew\.zebra$'
}

Add-SpawnNewTest 'Automatisch erzeugte ID ergibt einen zulaessigen Schluesselnamen' {
    $name = Get-SpawnNewKeyName -Index 3 -Id 'auto:4d5d771484317363'

    Confirm-SpawnNewValue -Label 'Schluesselname' -Actual $name -Expected '03_auto_4d5d771484317363'
}

Add-SpawnNewTest 'Die Aktions-ID selbst bleibt im Befehl unveraendert' {
    $entries = Get-TestEntry -Action @((Get-TestAction -Id 'auto:4d5d771484317363' -Title 'Mein Werkzeug'))

    Confirm-SpawnNewMatch -Label 'ID im Befehl' -Actual $entries[3].Value -Pattern '-ActionId "auto:4d5d771484317363"'
}

Add-SpawnNewTest 'Verwaltungsbefehle folgen mit Trennlinie auf die Aktionen' {
    $root = 'HKCU:\Software\Classes'
    $command = @(Get-SpawnNewMenuCommand -Config ([pscustomobject]@{ Install = 'x'; Update = 'y' }))
    $entries = @(Get-SpawnNewRegistryEntry -Action @([pscustomobject]@{ Id = 'spawnnew.a'; Title = 'A' }) -AppDirectory 'C:\App' -Root $root -Command $command)

    $titles = @($entries | Where-Object { $_.Name -eq 'MUIVerb' } | ForEach-Object { $_.Value })
    Confirm-SpawnNewValue -Label 'Reihenfolge' -Actual ($titles -join '|') -Expected 'SpawnNew|A|SpawnNew konfigurieren|SpawnNew aktualisieren|SpawnNew installieren'

    $flags = @($entries | Where-Object { $_.Kind -eq 'dword' })
    Confirm-SpawnNewValue -Label 'eine Trennlinie' -Actual $flags.Count -Expected 1
    Confirm-SpawnNewMatch -Label 'vor Konfigurieren' -Actual $flags[0].Path -Pattern 'zz1_spawnnew\.configure$'

    $line = ($entries | Where-Object { $_.Path -match 'zz2_spawnnew\.update\\command$' }).Value
    Confirm-SpawnNewMatch -Label 'Befehl' -Actual $line -Pattern '"C:\\App\\SpawnNew\.Command\.ps1" -Command update$'
}

Add-SpawnNewTest 'Ohne Einzeiler gibt es nur Konfigurieren' {
    $command = @(Get-SpawnNewMenuCommand -Config ([pscustomobject]@{ Install = $null; Update = $null }))
    Confirm-SpawnNewValue -Label 'Befehle' -Actual (($command | ForEach-Object { $_.Name }) -join ',') -Expected 'configure'
}

Add-SpawnNewTest 'Installationsumfang folgt aus dem Programmverzeichnis' {
    Confirm-SpawnNewValue -Label 'Benutzer' -Actual (Get-SpawnNewInstallScope -AppDirectory (Join-Path $env:LOCALAPPDATA 'SpawnNew\App')) -Expected 'CurrentUser'
    Confirm-SpawnNewValue -Label 'System' -Actual (Get-SpawnNewInstallScope -AppDirectory 'C:\Program Files\SpawnNew\App') -Expected 'AllUsers'
}

Add-SpawnNewTest 'Abgleich schreibt nur bei Abweichung und entfernt Altlasten' {
    $root = 'HKCU:\Software\SpawnNewTest\' + [guid]::NewGuid().ToString('N')
    try {
        $one = @(Get-SpawnNewRegistryEntry -Action @([pscustomobject]@{ Id = 'spawnnew.a'; Title = 'A' }) -AppDirectory 'C:\App' -Root $root -Command @(Get-SpawnNewMenuCommand -Config ([pscustomobject]@{ Install = $null; Update = $null })))

        Confirm-SpawnNewValue -Label 'erst schreiben' -Actual (Sync-SpawnNewRegistration -Entry $one -Root $root) -Expected $true
        Confirm-SpawnNewValue -Label 'dann aktuell' -Actual (Sync-SpawnNewRegistration -Entry $one -Root $root) -Expected $false
        Confirm-SpawnNewValue -Label 'Trennlinie gesetzt' -Actual ((Get-Item -LiteralPath ((Get-SpawnNewMenuKey -Root $root) + '\shell\zz1_spawnnew.configure')).GetValue('CommandFlags')) -Expected 32

        $two = @(Get-SpawnNewRegistryEntry -Action @([pscustomobject]@{ Id = 'spawnnew.b'; Title = 'B' }) -AppDirectory 'C:\App' -Root $root)
        Confirm-SpawnNewValue -Label 'Abweichung' -Actual (Sync-SpawnNewRegistration -Entry $two -Root $root) -Expected $true

        $keys = @(Get-ChildItem -LiteralPath ((Get-SpawnNewMenuKey -Root $root) + '\shell') | ForEach-Object { $_.PSChildName })
        Confirm-SpawnNewValue -Label 'nur neue Eintraege' -Actual ($keys -join ',') -Expected '01_spawnnew.b'
    }
    finally {
        Remove-Item -LiteralPath (Split-Path -Parent $root) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Add-SpawnNewTest 'Programmverzeichnis wird aus der Befehlszeile gelesen' {
    $line = Get-SpawnNewActionCommand -AppDirectory 'G:\Meine Ablage\SpawnNew\App' -ActionId 'spawnnew.a'
    Confirm-SpawnNewValue -Label 'Aktion' -Actual (ConvertFrom-SpawnNewCommandLine -Line $line) -Expected 'G:\Meine Ablage\SpawnNew\App'

    $line = Get-SpawnNewManagementCommand -AppDirectory 'C:\Users\x\OneDrive\SpawnNew\App' -Name 'configure'
    Confirm-SpawnNewValue -Label 'Befehl' -Actual (ConvertFrom-SpawnNewCommandLine -Line $line) -Expected 'C:\Users\x\OneDrive\SpawnNew\App'
    Confirm-SpawnNewValue -Label 'fremd' -Actual (ConvertFrom-SpawnNewCommandLine -Line 'notepad.exe "%1"') -Expected ''
}

Add-SpawnNewTest 'Cloudordner gilt als Benutzerinstallation' {
    Confirm-SpawnNewValue -Label 'OneDrive' -Actual (Get-SpawnNewInstallScope -AppDirectory 'C:\Users\x\OneDrive\SpawnNew\App') -Expected 'CurrentUser'
    Confirm-SpawnNewValue -Label 'Google Drive' -Actual (Get-SpawnNewInstallScope -AppDirectory 'G:\Meine Ablage\SpawnNew\App') -Expected 'CurrentUser'
}

Add-SpawnNewTest 'Registriertes Programmverzeichnis wird aus der Registrierung gelesen' {
    $root = 'HKCU:\Software\SpawnNewTest\' + [guid]::NewGuid().ToString('N')
    try {
        Confirm-SpawnNewValue -Label 'leer' -Actual (Get-SpawnNewRegisteredAppDirectory -Root $root) -Expected ''
        Set-SpawnNewRegistration -Entry @(Get-SpawnNewRegistryEntry -Action @([pscustomobject]@{ Id = 'spawnnew.a'; Title = 'A' }) -AppDirectory 'D:\Cloud\SpawnNew\App' -Root $root)
        Confirm-SpawnNewValue -Label 'gelesen' -Actual (Get-SpawnNewRegisteredAppDirectory -Root $root) -Expected 'D:\Cloud\SpawnNew\App'
    }
    finally {
        Remove-Item -LiteralPath (Split-Path -Parent $root) -Recurse -Force -ErrorAction SilentlyContinue
    }
}
