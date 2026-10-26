<!-- README.md | Version 1.1 | 26.10.2026 -->

# SpawnNew

Explorer-Kontextmenue fuer vorbereitete Arbeitsumgebungen unter Windows 10
und Windows 11. Anforderungen und Abnahmekriterien stehen in
[`SpawnNew.md`](SpawnNew.md).

## Stand

| Umsetzungsschritt (`SpawnNew.md` Abschnitt 13) | Stand |
|---|---|
| 1. Dateinamen, Konfiguration, IDs, Prioritaet, Schnittstellenvertrag | fertig, siehe `docs/` |
| 2. Explorer-Prototyp Windows 10 und 11 | offen |
| 3. Quellen, Prioritaet, IDs, Nachladen, Cache, Beschreibungspruefung | fertig und geprueft |
| 4. Formular, Zusammenfassung, PowerShell-Start | fertig; WinForms noch nicht auf Windows erprobt |
| 5. Fortschritt, Fehler, Rechte, Aufraeumen | fertig; WinForms noch nicht auf Windows erprobt |
| 6. Sieben mitgelieferte Aktionen | offen |
| 7. Installation, Aktualisierung, Konfiguration, Deinstallation | offen |
| 8. Menueeintraege fuer Installation und Aktualisierung | Katalogausgabe fertig, Registrierung offen |
| 9. Abnahme auf Windows 10 und 11 | offen |

## Aufbau

| Pfad | Inhalt |
|---|---|
| `SpawnNew.md` | Konzept und Anforderungen |
| `docs/Dateiliste.md` | festgelegte Dateinamen, Ablage, Konfigurationsschichten, ID-Regeln, Beschreibungsformat |
| `docs/Aktionsvertrag.md` | Vertrag zwischen Ausfuehrungsprozess und Aktionsskript |
| `config/` | mitgelieferte Standardkonfiguration |
| `src/Host/` | Ausfuehrungsprozess, Windows PowerShell 5.1 |
| `src/Explorer/` | native Explorer-Erweiterung, C++ |
| `src/Actions/` | mitgelieferte Aktionen |
| `tests/` | Tests zu den Bausteinen des Ausfuehrungsprozesses |
| `tools/` | Pruefwerkzeuge, nicht Teil der Installation |

## Einstiegspunkte

| Datei | Aufruf |
|---|---|
| `src/Host/SpawnNew.Catalog.ps1` | Menuekatalog als JSON fuer die Explorer-Erweiterung |
| `src/Host/SpawnNew.Host.ps1` | Abwicklung einer gewaehlten Aktion |

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\Host\SpawnNew.Catalog.ps1 -OutputFile %TEMP%\spawnnew-katalog.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\Host\SpawnNew.Host.ps1 -ActionId spawnnew.gitproject -ExplorerPath D:\Projekte
```

## Pruefen

Der Code laeuft unter Windows PowerShell 5.1. Geprueft wird mit PowerShell 7
und PSScriptAnalyzer, der die 5.1-Kompatibilitaet mitprueft
(`PSUseCompatibleSyntax`, `PSUseCompatibleCommands`).

```
pwsh -NoProfile -File tools/Install-DevTools.ps1
pwsh -NoProfile -File tools/Invoke-Lint.ps1
pwsh -NoProfile -File tools/Invoke-Test.ps1
```

`Invoke-Lint.ps1` endet mit Rueckgabewert 1, sobald Befunde ab Stufe
`Warning` auftreten; `-Severity Information` zeigt auch Hinweise. Der
vollstaendige Lauf dauert einige Minuten, weil PSScriptAnalyzer das
Kompatibilitaetsprofil je Pfad neu laedt.

`Invoke-Test.ps1` endet mit Rueckgabewert 1 bei mindestens einem Fehler.
`-Filter` grenzt auf einzelne Testfaelle ein, `-Path` auf einzelne Dateien.

`SpawnNew.Form.psm1` und `SpawnNew.Progress.psm1` laden WinForms und sind nur
auf Windows ausfuehrbar. Die Regeln dahinter liegen in `SpawnNew.Input.psm1`
und `SpawnNew.Target.psm1` und sind dort geprueft.

## Bauen

Die Explorer-Erweiterung aus `src/Explorer/` ist eine x64-DLL und braucht
Visual Studio mit dem Windows SDK. Sie ist noch nicht umgesetzt.
