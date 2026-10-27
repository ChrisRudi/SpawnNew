<!-- README.md | Version 1.5 | 26.10.2026 -->

# SpawnNew

Explorer-Kontextmenue fuer vorbereitete Arbeitsumgebungen unter Windows 10
und Windows 11. Anforderungen und Abnahmekriterien stehen in
[`SpawnNew.md`](SpawnNew.md).

## Installieren und testen

### Im Cloudordner (empfohlen)

SpawnNew laeuft komplett aus OneDrive, Google Drive oder einem anderen
synchronisierten Ordner: Programmdateien, eigene Aktionen, eigene Vorlagen
und Einstellungen liegen dort und gelten auf allen Rechnern. Eine Zeile in
einer PowerShell-Sitzung, ohne Administratorrechte:

```
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $zip = "$env:TEMP\spawnnew.zip"; $dir = "$env:TEMP\spawnnew"; Invoke-WebRequest 'https://github.com/ChrisRudi/SpawnNew/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; Expand-Archive $zip $dir -Force; & "$dir\SpawnNew-main\src\Install-SpawnNew.ps1" -Path "$env:OneDrive\SpawnNew"
```

Fuer Google Drive am Ende statt dessen etwa `-Path "G:\Meine Ablage\SpawnNew"`.

Auf jedem weiteren Rechner genuegt danach ein Doppelklick auf
**SpawnNew einrichten.cmd** im Cloudordner; das traegt nur das Menue ein.
**SpawnNew auf diesem Rechner entfernen.cmd** nimmt es wieder heraus.

| Liegt im Cloudordner, auf allen Rechnern gleich | Bleibt auf jedem Rechner lokal |
|---|---|
| `App\` Programmdateien | Menueeintrag in der Registrierung |
| `Actions\` eigene Aktionen | Geheimnisse (API-Schluessel), an Benutzer und Rechner gebunden |
| `Vorlagen\` eigene Dokumentvorlagen | Cache und Protokolle unter `%LOCALAPPDATA%\SpawnNew` |
| `spawnnew.settings.json` Einstellungen, KI-Endpunkte | |

Fuer OneDrive den Ordner per Rechtsklick auf **Immer auf diesem Geraet
behalten** stellen, sonst laedt das erste Oeffnen des Menues die Dateien
erst herunter. Ein Update ueber **SpawnNew aktualisieren** oder den
Einzeiler bleibt im Cloudordner und gilt damit fuer alle Rechner.

### Lokal in einer PowerShell-Sitzung

Nur fuer diesen Rechner, unter `%LOCALAPPDATA%\SpawnNew`:

```
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $zip = "$env:TEMP\spawnnew.zip"; $dir = "$env:TEMP\spawnnew"; Invoke-WebRequest 'https://github.com/ChrisRudi/SpawnNew/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; Expand-Archive $zip $dir -Force; & "$dir\SpawnNew-main\src\Install-SpawnNew.ps1" -Scope CurrentUser
```

Entfernen, Benutzerdaten bleiben erhalten. Bei einer Installation im
Cloudordner entfernt das nur das Menue auf diesem Rechner; mit
`-RemoveFiles` auch die Programmdateien fuer alle Rechner:

```
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $zip = "$env:TEMP\spawnnew.zip"; $dir = "$env:TEMP\spawnnew"; Invoke-WebRequest 'https://github.com/ChrisRudi/SpawnNew/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; Expand-Archive $zip $dir -Force; & "$dir\SpawnNew-main\src\Install-SpawnNew.ps1" -Scope CurrentUser -Uninstall
```

### In cmd.exe, im Ausfuehren-Dialog oder in einer Verknuepfung

Hier wird `powershell.exe` selbst gestartet. Diese Fassung **nicht** in eine
schon laufende PowerShell-Sitzung einfuegen: die aeussere Sitzung wuerde
`$zip` und `$dir` vorher durch leere Werte ersetzen.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $zip = Join-Path $env:TEMP 'spawnnew.zip'; $dir = Join-Path $env:TEMP 'spawnnew'; Invoke-WebRequest -Uri 'https://github.com/ChrisRudi/SpawnNew/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }; Expand-Archive -Path $zip -DestinationPath $dir -Force; & (Join-Path $dir 'SpawnNew-main\src\Install-SpawnNew.ps1') -Scope CurrentUser }"
```

Diese Fassung steht auch in `config/spawnnew.settings.default.json` unter
`install` und `update`; die Menueeintraege **SpawnNew aktualisieren** und
**SpawnNew installieren** fuehren sie nach Bestaetigung aus.

### Aus einem lokalen Klon

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-SpawnNew.ps1 -Path "$env:OneDrive\SpawnNew"
```

Ohne `-Path` installiert der Installer dorthin, wo SpawnNew bisher lag:
in den Cloudordner, wenn das Menue schon auf einen zeigt, sonst lokal.

### Hinweise

Nach der Installation Rechtsklick in den leeren Bereich eines Ordners, dann
**SpawnNew**. Unter Windows 11 zuerst **Weitere Optionen anzeigen** — die
direkte Anzeige in der ersten Menueebene verlangt `IExplorerCommand` und ist
noch offen.

Erneutes Ausfuehren desselben Einzeilers wirkt als Aktualisierung: die
Programmdateien unter `App` werden vollstaendig ersetzt, Einstellungen,
persoenliche Aktionen, eigene Vorlagen, Geheimnisse, Cache und Protokolle
bleiben erhalten. `-Scope AllUsers` installiert fuer alle Benutzer und
braucht Administratorrechte; der Einzeiler oben gilt nur fuer `CurrentUser`.

Der Installer darf unter Windows PowerShell 5.1 oder unter PowerShell 7
laufen. Die Aktionen selbst startet SpawnNew immer mit `powershell.exe`,
also mit Windows PowerShell 5.1.

## Das Menue

| Eintrag | Ergebnis |
|---|---|
| Datei zusammenfassen | je markierter Textdatei eine Zusammenfassung als Entwurf daneben (KI); auch per Rechtsklick auf eine oder mehrere Dateien |
| Eigene Aktion | Grundgeruest einer neuen Aktion im persoenlichen Aktionsordner |
| Fehleranalyse | Analysedokument mit Ordnern fuer Logs, Screenshots, Loesungsnachweis |
| Git-Projekt | lokales Repository mit `.gitignore`, README, optional erstem Commit |
| Ordner dokumentieren | `README.Entwurf.md` aus Dateiliste und Auszuegen (KI); auch per Rechtsklick auf einen Ordner |
| Ordnerstruktur | Unterordner nach Vorlage, auch mit NTFS-Rechten |
| Ordnerstruktur aus Beschreibung | Struktur vom Sprachmodell, angelegt erst nach Bestaetigung (KI) |
| PowerShell-Werkzeug | Skript mit Kopf, Konfiguration und README |
| Projekt abschließen | Abschlussvermerk, SHA-256-Manifest, optional ZIP und Archiv; auch per Rechtsklick auf einen Ordner |
| Sitzung | Tagesordnung, Protokoll, Beschlussliste in Markdown oder Word |
| Werkstättenprotokoll | Protokollvorlage in Markdown oder Word, Bilder- und Messdatenordner |
| — | |
| SpawnNew konfigurieren | Uebersicht, Einstellungen, Geheimnisse, Endpunkttest, Menue neu einlesen |
| SpawnNew aktualisieren | Einzeiler anzeigen, bestaetigen, ausfuehren, Ergebnis zeigen |
| SpawnNew installieren | dasselbe mit dem Installationseinzeiler |

Das volle Menue erscheint per Rechtsklick in den leeren Bereich eines Ordners.
Rechtsklick auf markierte Dateien zeigt unter **SpawnNew** nur **Datei
zusammenfassen**, Rechtsklick auf einen Ordner **Ordner dokumentieren** und
**Projekt abschließen**, jeweils fuer genau das Angeklickte. Bei mehreren
markierten Dateien oeffnet sich ein Formular fuer alle; Windows zeigt einen
solchen Eintrag fuer hoechstens 15 markierte Dateien.

Jede Aktion zeigt erst ein Formular, dann eine Zusammenfassung mit Ziel,
Eingaben und geplanten Schritten; angelegt wird erst nach **Erstellen**.
Vorhandene Dateien werden nie still ueberschrieben.

### KI-Aktionen einrichten

Die Aktionen mit (KI) und die optionalen Entwuerfe in Werkstättenprotokoll,
Fehleranalyse und Sitzung brauchen einen OpenAI-kompatiblen Endpunkt.
Vorgabe ist ein lokales Ollama unter `http://localhost:11434/v1` mit dem
Modell `llama3.2`; dabei verlaesst kein Inhalt den Rechner.

1. Ollama oder LM Studio starten und ein Modell laden.
2. **SpawnNew konfigurieren > Einstellungen bearbeiten**, unter `llm` einen
   Endpunkt eintragen, etwa
   `{ "name": "Lokal", "baseUrl": "http://localhost:1234/v1", "model": "<Modell>" }`.
3. Fuer einen Webdienst zusaetzlich `"secret": "web"` angeben und den
   Schluessel unter **Geheimnis speichern** mit dem Namen `web` ablegen.
4. **KI-Endpunkte testen**.

Ohne erreichbaren Endpunkt melden die KI-Aktionen das vor dem Formular und
legen nichts an. Einzelheiten: [`docs/KI-Anbindung.md`](docs/KI-Anbindung.md).

### Eigene Vorlagen

Eine Datei `Vorlagen\<Aktions-ID>\<Name>.md` oder
`.docx` im Datenverzeichnis (Cloudordner oder `%LOCALAPPDATA%\SpawnNew`) ersetzt die mitgelieferte Vorlage, etwa
`...\Vorlagen\spawnnew.workshoplog\Protokoll.docx`. Platzhalter wie
`{{klasse}}`, `{{thema}}` oder `{{datumText}}` werden auch im Inhalt einer
`.docx` ersetzt; Word ist dafuer nicht noetig. **SpawnNew konfigurieren >
Vorlagenordner oeffnen** fuehrt dorthin.

### Wenn etwas fehlt

```
& "$env:OneDrive\SpawnNew\App\SpawnNew.Diagnose.ps1"
```

Zeigt Konfigurationsschichten, Quellen und ihre Erreichbarkeit, das
Zeitverhalten der Quellenerkennung, den aufgeloesten Katalog, alle Diagnosen
und die tatsaechlich geschriebenen Registrierungseintraege samt Befehlszeile.
Aendert nichts. Fehler beim Start einer Aktion stehen in
`%LOCALAPPDATA%\SpawnNew\Logs\host.log`, bei den Verwaltungsbefehlen in
`command.log`.

### Was ein Test von Hand zeigen soll

1. **SpawnNew** erscheint im Kontextmenue mit elf Aktionen, darunter durch
   eine Trennlinie abgesetzt die drei Verwaltungsbefehle.
2. **Ordnerstruktur**: Formular mit Zielordner, Name, Strukturvorlage und
   Zweck; ein leerer oder ungueltiger Name wird abgewiesen; **Abbrechen**
   legt nichts an; ein zweiter Lauf mit gleichem Namen fragt nach.
3. **Ordnerstruktur** mit Vorlage "Projekt mit vertraulichem Ordner": unter
   Eigenschaften > Sicherheit von `09 Vertraulich` stehen nur der eigene
   Benutzer, SYSTEM und Administratoren, ohne Vererbung.
4. **Werkstättenprotokoll** in Word: der Ordner heisst `Datum Klasse Thema`,
   `Protokoll.docx` oeffnet sich in Word mit Tabelle und Ueberschriften.
5. **Projekt abschließen** mit ZIP: `ABSCHLUSS.md`, `MANIFEST-SHA256.txt`
   und das ZIP neben dem Ordner entstehen; ein zweiter Lauf aendert nichts.
6. **Eigene Aktion**: nach dem naechsten Aufruf eines SpawnNew-Eintrags steht
   die neue Aktion im Menue.
7. **SpawnNew konfigurieren**: Uebersicht zeigt Schichten, Quellen und
   Endpunkte; ein gespeichertes Geheimnis erscheint nur mit Namen.
8. **SpawnNew aktualisieren**: Befehl, Ziel und Rechte erscheinen vor der
   Ausfuehrung; danach Rueckgabewert und Ausgabe.
9. Mit laufendem lokalem Modell: **Ordnerstruktur aus Beschreibung** zeigt
   den Vorschlag in der Zusammenfassung; **Abbrechen** legt nichts an.

## Stand

| Umsetzungsschritt (`SpawnNew.md` Abschnitt 14) | Stand |
|---|---|
| 1. Dateinamen, Konfiguration, IDs, Prioritaet, Schnittstellenvertrag | fertig |
| 2. Explorer-Prototyp: direkte Anzeige unter Windows 11 per `IExplorerCommand` | offen |
| 3. Quellen, Prioritaet, IDs, Nachladen, Cache, Beschreibungspruefung | fertig und geprueft |
| 4. Formular, Zusammenfassung, PowerShell-Start | fertig; Ablauf geprueft, Fenster von Hand noch nicht erprobt |
| 5. Fortschritt, Fehler, Rechte, Aufraeumen | fertig; Fenster von Hand noch nicht erprobt |
| 6. Dokumenterzeugung mit Platzhaltern in Markdown und `.docx` | fertig und geprueft |
| 7. KI-Anbindung Stufe 1, lokaler Endpunkt | fertig, gegen Testserver geprueft |
| 8. KI-Anbindung Stufe 2, Webendpunkt mit verschluesseltem Schluessel | fertig und geprueft |
| 9. NTFS-Rechte aus der Vorlage | fertig und geprueft |
| 10. Elf mitgelieferte Aktionen | fertig, 11 von 11 |
| 11. Installation, Aktualisierung, Konfigurationszugriff, Deinstallation | fertig in der Registrierungsstufe |
| 12. Menueeintraege fuer Installation und Aktualisierung | fertig |
| 13. Abnahme auf Windows 10 und 11 | offen |

Die Menueregistrierung laeuft vorerst ueber die Registrierungsdatenbank
(`Directory\Background\shell`). Sie entsteht bei der Installation und wird
bei jedem Aufruf eines SpawnNew-Eintrags mit dem Katalog abgeglichen.
Nachladen beim Oeffnen des Menues und die erste Menueebene unter Windows 11
kommen mit der DLL aus Schritt 2.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `SpawnNew.md` | Konzept und Anforderungen |
| `docs/Dateiliste.md` | Dateinamen, Ablage, Konfigurationsschichten, ID-Regeln, Beschreibungsformat, Vorlagen, Registrierungsaufbau |
| `docs/Aktionsvertrag.md` | Vertrag zwischen Ausfuehrungsprozess und Aktionsskript, Vorschlagsskript, Hilfsmodul |
| `docs/KI-Anbindung.md` | Endpunkte, Geheimnisse, Entwuerfe und Vorschlaege |
| `config/` | mitgelieferte Standardkonfiguration |
| `src/Install-SpawnNew.ps1` | Installation, Aktualisierung, Deinstallation |
| `src/Host/` | Ausfuehrungsprozess und Verwaltungsbefehle, Windows PowerShell 5.1 |
| `src/Explorer/` | native Explorer-Erweiterung, C++, noch nicht angelegt |
| `src/Actions/` | die elf mitgelieferten Aktionen |
| `tests/` | Tests zu Bausteinen, Aktionen und Host |
| `tools/` | Pruefwerkzeuge, nicht Teil der Installation |

## Pruefen

Der Code laeuft unter Windows PowerShell 5.1 und wird dort geprueft:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-Lint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-Test.ps1
```

PSScriptAnalyzer prueft dabei die 5.1-Kompatibilitaet mit
(`PSUseCompatibleSyntax`, `PSUseCompatibleCommands`). Fehlt er,
richtet `pwsh -NoProfile -File tools/Install-DevTools.ps1` ihn ein.

`Invoke-Lint.ps1` endet mit Rueckgabewert 1 ab Stufe `Warning`;
`-Severity Information` zeigt auch Hinweise. Der Lauf dauert einige Minuten.

`Invoke-Test.ps1` endet mit Rueckgabewert 1 bei mindestens einem Fehler.
`-Filter` grenzt auf einzelne Testfaelle ein, `-Path` auf eine Datei. Die
Tests brauchen Windows: sie pruefen Registrierung (in einem eigenen
Testschluessel), NTFS-Rechte, DPAPI und die Aktionen in eigenen Prozessen.
Sprachmodelle ersetzt ein Testserver auf 127.0.0.1. Den Host prueft
`SpawnNew.HostFlow.Tests.ps1` als Ganzes; nur die Fenster sind dort durch
Stellvertreter ersetzt, die vorgegebene Antworten liefern.

## Bauen

Die Explorer-Erweiterung aus `src/Explorer/` ist eine x64-DLL und braucht
Visual Studio mit dem Windows SDK. Sie ist noch nicht umgesetzt.
