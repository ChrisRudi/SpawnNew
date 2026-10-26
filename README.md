<!-- README.md | Version 1.2 | 26.10.2026 -->

# SpawnNew

Explorer-Kontextmenue fuer vorbereitete Arbeitsumgebungen unter Windows 10
und Windows 11. Anforderungen und Abnahmekriterien stehen in
[`SpawnNew.md`](SpawnNew.md).

## Installieren und testen

Das Repository ist **privat**. Der Einzeiler, der das Archiv aus dem Netz
laedt, braucht anonymen Lesezugriff und laeuft darum erst, wenn das
Repository oeffentlich ist. Fuer den Test bis dahin die beiden folgenden Wege.

### Aus einem Klon, ein Befehl

Braucht Git fuer Windows. Beim ersten Mal fragt der Git Credential Manager
nach der Anmeldung.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $dir = Join-Path $env:TEMP 'spawnnew'; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; git clone --depth 1 https://github.com/ChrisRudi/SpawnNew $dir; & (Join-Path $dir 'src\Install-SpawnNew.ps1') -Scope CurrentUser }"
```

### Aus einem lokalen Ordner

Repository auf die Testmaschine kopieren, dann im Projektordner:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-SpawnNew.ps1 -Scope CurrentUser
```

Entfernen, Benutzerdaten bleiben erhalten:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-SpawnNew.ps1 -Scope CurrentUser -Uninstall
```

`-Scope AllUsers` installiert fuer alle Benutzer und braucht
Administratorrechte. Erneutes Ausfuehren wirkt als Aktualisierung.

### Aus dem Netz, sobald das Repository oeffentlich ist

Dieser Einzeiler steht auch in `config/spawnnew.settings.default.json` unter
`install` und `update` und wird spaeter aus dem Menue angeboten.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $zip = Join-Path $env:TEMP 'spawnnew.zip'; $dir = Join-Path $env:TEMP 'spawnnew'; Invoke-WebRequest -Uri 'https://github.com/ChrisRudi/SpawnNew/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; Expand-Archive -Path $zip -DestinationPath $dir -Force; & (Join-Path $dir 'SpawnNew-main\src\Install-SpawnNew.ps1') -Scope CurrentUser }"
```

Entfernen:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $zip = Join-Path $env:TEMP 'spawnnew.zip'; $dir = Join-Path $env:TEMP 'spawnnew'; Invoke-WebRequest -Uri 'https://github.com/ChrisRudi/SpawnNew/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; Expand-Archive -Path $zip -DestinationPath $dir -Force; & (Join-Path $dir 'SpawnNew-main\src\Install-SpawnNew.ps1') -Scope CurrentUser -Uninstall }"
```

Danach Rechtsklick in den leeren Bereich eines Ordners, dann **SpawnNew**.
Unter Windows 11 zuerst **Weitere Optionen anzeigen** — die direkte Anzeige
in der ersten Menueebene verlangt `IExplorerCommand` und ist noch offen.

### Was der erste Test zeigen soll

1. **SpawnNew** erscheint im Kontextmenue, darunter **Ordnerstruktur**.
2. Ein Klick oeffnet das Formular mit Zielordner, Name, Strukturvorlage und Zweck.
3. Ein leerer Name oder ein Name mit `\ / : * ? " < > |` wird abgewiesen.
4. Die Zusammenfassung nennt Ziel, Eingaben und die drei geplanten Schritte.
5. **Abbrechen** legt nichts an.
6. **Erstellen** zeigt das Fortschrittsfenster und danach den Status.
7. Ein zweiter Lauf mit gleichem Namen fragt: abbrechen, umbenennen, vorhandenen Ordner verwenden.
8. Eine selbst geschriebene `README.md` im Ziel wird nicht ueberschrieben; der Status lautet dann `partial`.

## Stand

| Umsetzungsschritt (`SpawnNew.md` Abschnitt 14) | Stand |
|---|---|
| 1. Dateinamen, Konfiguration, IDs, Prioritaet, Schnittstellenvertrag | fertig |
| 2. Explorer-Prototyp: direkte Anzeige unter Windows 11 per `IExplorerCommand` | offen |
| 3. Quellen, Prioritaet, IDs, Nachladen, Cache, Beschreibungspruefung | fertig und geprueft |
| 4. Formular, Zusammenfassung, PowerShell-Start | fertig; WinForms erst auf Windows erprobbar |
| 5. Fortschritt, Fehler, Rechte, Aufraeumen | fertig; WinForms erst auf Windows erprobbar |
| 6. Dokumenterzeugung mit Platzhaltern in Markdown und `.docx` | offen |
| 7. KI-Anbindung Stufe 1, lokaler Endpunkt | offen |
| 8. KI-Anbindung Stufe 2, Webendpunkt mit verschluesseltem Schluessel | offen |
| 9. NTFS-Rechte aus der Vorlage | offen |
| 10. Elf mitgelieferte Aktionen | 1 von 11 |
| 11. Installation, Aktualisierung, Deinstallation | fertig in der Registrierungsstufe |
| 12. Menueeintraege fuer Installation und Aktualisierung | Katalogausgabe fertig, Registrierung offen |
| 13. Abnahme auf Windows 10 und 11 | offen |

Die Menueregistrierung laeuft vorerst ueber die Registrierungsdatenbank
(`Directory\Background\shell`) und entsteht bei der Installation aus dem
Katalog. Dynamisches Nachladen beim Oeffnen des Menues und die erste
Menueebene unter Windows 11 kommen mit der DLL aus Schritt 2.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `SpawnNew.md` | Konzept und Anforderungen |
| `docs/Dateiliste.md` | Dateinamen, Ablage, Konfigurationsschichten, ID-Regeln, Beschreibungsformat, Registrierungsaufbau |
| `docs/Aktionsvertrag.md` | Vertrag zwischen Ausfuehrungsprozess und Aktionsskript |
| `config/` | mitgelieferte Standardkonfiguration |
| `src/Install-SpawnNew.ps1` | Installation, Aktualisierung, Deinstallation |
| `src/Host/` | Ausfuehrungsprozess, Windows PowerShell 5.1 |
| `src/Explorer/` | native Explorer-Erweiterung, C++, noch leer |
| `src/Actions/` | mitgelieferte Aktionen |
| `tests/` | Tests zu den Bausteinen und zum Ausfuehrungsvertrag |
| `tools/` | Pruefwerkzeuge, nicht Teil der Installation |

## Pruefen

Der Code laeuft unter Windows PowerShell 5.1. Geprueft wird mit PowerShell 7
und PSScriptAnalyzer, der die 5.1-Kompatibilitaet mitprueft
(`PSUseCompatibleSyntax`, `PSUseCompatibleCommands`).

```
pwsh -NoProfile -File tools/Install-DevTools.ps1
pwsh -NoProfile -File tools/Invoke-Lint.ps1
pwsh -NoProfile -File tools/Invoke-Test.ps1
```

`Invoke-Lint.ps1` endet mit Rueckgabewert 1 ab Stufe `Warning`;
`-Severity Information` zeigt auch Hinweise. Der Lauf dauert einige Minuten,
weil PSScriptAnalyzer das Kompatibilitaetsprofil je Pfad neu laedt.

`Invoke-Test.ps1` endet mit Rueckgabewert 1 bei mindestens einem Fehler.
`-Filter` grenzt auf einzelne Testfaelle ein, `-Path` auf einzelne Dateien.

`SpawnNew.Form.psm1` und `SpawnNew.Progress.psm1` laden WinForms und sind nur
auf Windows ausfuehrbar; `SpawnNew.Register.psm1` schreibt in die
Registrierungsdatenbank. Die Regeln dahinter liegen in `SpawnNew.Input.psm1`,
`SpawnNew.Target.psm1` und den reinen Funktionen von `SpawnNew.Register.psm1`
und sind dort geprueft.

## Bauen

Die Explorer-Erweiterung aus `src/Explorer/` ist eine x64-DLL und braucht
Visual Studio mit dem Windows SDK. Sie ist noch nicht umgesetzt.
