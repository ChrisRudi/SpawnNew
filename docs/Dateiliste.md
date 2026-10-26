<!-- docs/Dateiliste.md | Version 1.0 | 26.10.2026 -->

# Dateiliste und Festlegungen

Umsetzungsschritt 1 aus `SpawnNew.md` Abschnitt 13. Diese Dateinamen sind
festgelegt und werden bei Aenderungen beibehalten (Entwicklungsregel 11).

## 1. Verzeichnisaufbau im Repository

```
SpawnNew.md                             Konzept und Anforderungen
README.md                               Kurzuebersicht, Build, Lint
docs/Dateiliste.md                      diese Datei
docs/Aktionsvertrag.md                  Ausfuehrungsvertrag der PowerShell-Aktionen
config/spawnnew.settings.default.json   mitgelieferte Standardkonfiguration
src/Install-SpawnNew.ps1                Installation, Aktualisierung, Deinstallation
src/Host/                               Ausfuehrungsprozess, Windows PowerShell 5.1
src/Explorer/                           native Explorer-Erweiterung, C++
src/Actions/                            die sieben mitgelieferten Aktionen
tools/                                  Entwicklungswerkzeuge, nicht Teil der Installation
```

## 2. Ausfuehrungsprozess (`src/Host/`)

| Datei | Zweck |
|---|---|
| `SpawnNew.Host.ps1` | Einstiegspunkt. Nimmt Aktions-ID, Quelle und Explorer-Pfad, fuehrt Formular, Zusammenfassung, Start und Fortschritt aus |
| `SpawnNew.Config.psm1` | Konfigurationsschichten laden, Umgebungsvariablen aufloesen, Quellenliste normalisieren |
| `SpawnNew.Catalog.psm1` | Quellen abtasten, Aktions-IDs bilden, Beschreibungen pruefen |
| `SpawnNew.Resolve.psm1` | Quellen mit Zeitlimit abtasten, Metadaten-Cache, Prioritaet aufloesen, Nachpruefung vor der Ausfuehrung |
| `SpawnNew.Input.psm1` | Formularfelder normalisieren, Vorbelegungen, Eingaben pruefen. Ohne WinForms, damit pruefbar |
| `SpawnNew.Target.psm1` | Namen und Zielpfade pruefen, Zielart, Zielzustand, freier Name, Voraussetzungen, Zusammenfassungstext. Ohne WinForms |
| `SpawnNew.Form.psm1` | Eingabeformular, Konfliktfrage, Zusammenfassung und Meldungen als WinForms-Fenster |
| `SpawnNew.Progress.psm1` | Fortschrittsfenster, Abbruchanforderung, Abschlussbericht |
| `SpawnNew.Runner.psm1` | Laufverzeichnis, Kontextdatei, Argumente, Prozessstart, Fortschritt lesen, Ergebnis und Status |
| `SpawnNew.Document.psm1` | Erzeugung von Markdown- und `.docx`-Dateien ohne Word-Automatisierung |
| `SpawnNew.Register.psm1` | Registrierungseintraege des Kontextmenues aus dem Katalog bilden, schreiben und entfernen |
| `SpawnNew.Llm.psm1` | OpenAI-kompatibler Client fuer lokale und Webendpunkte, geplant |
| `SpawnNew.Secret.psm1` | Geheimnisse benutzer- und rechnergebunden speichern und lesen, geplant |
| `SpawnNew.Catalog.ps1` | Konsolen-Einstiegspunkt: schreibt den aufgeloesten Katalog als JSON fuer die Explorer-Erweiterung |
| `SpawnNew.Diagnose.ps1` | Konsolen-Einstiegspunkt: Schichten, Quellen, Zeitverhalten, Katalog, Diagnosen und Registrierung anzeigen |

## 3. Explorer-Erweiterung (`src/Explorer/`)

| Datei | Zweck |
|---|---|
| `SpawnNew.Explorer.vcxproj` | Projektdatei, DLL fuer x64 |
| `dllmain.cpp` | DLL-Einstiegspunkt, Registrierung der Klassenfabrik |
| `ClassFactory.h`, `ClassFactory.cpp` | `IClassFactory` fuer den COM-Server |
| `SpawnNewCommand.h`, `SpawnNewCommand.cpp` | `IExplorerCommand` und `IEnumExplorerCommand`, Windows 11 |
| `LegacyContextMenu.h`, `LegacyContextMenu.cpp` | `IContextMenu3` und `IShellExtInit`, Windows 10 |
| `ActionCatalog.h`, `ActionCatalog.cpp` | Liest die Katalog-JSON. Liest ausschliesslich Metadaten, fuehrt nichts aus |
| `SpawnNew.Explorer.def` | Exportliste des COM-Servers |
| `resource.h`, `SpawnNew.Explorer.rc` | Symbole und Versionsressource |

## 4. Mitgelieferte Aktionen (`src/Actions/`)

Je Aktion ein Ordner mit `action.json` und `Invoke-SpawnAction.ps1`.

| Ordner | Aktions-ID | Nr. in Abschnitt 4 |
|---|---|---|
| `Ordnerstruktur` | `spawnnew.folderstructure` | 1 |
| `GitProjekt` | `spawnnew.gitproject` | 2 |
| `PowerShellWerkzeug` | `spawnnew.pstool` | 3 |
| `Werkstattprotokoll` | `spawnnew.workshoplog` | 7 |
| `Fehleranalyse` | `spawnnew.incident` | 10 |
| `Sitzung` | `spawnnew.meeting` | 11 |
| `EigeneAktion` | `spawnnew.customaction` | 14 |
| `ProjektAbschliessen` | `spawnnew.closeout` | 15 |
| `StrukturAusBeschreibung` | `spawnnew.structurefromtext` | 17 |
| `DateiZusammenfassen` | `spawnnew.summarizefile` | 18 |
| `OrdnerDokumentieren` | `spawnnew.documentfolder` | 19 |

## 5. Werkzeuge (`tools/`)

| Datei | Zweck |
|---|---|
| `Install-DevTools.ps1` | Richtet PowerShell 7 und PSScriptAnalyzer fuer die Pruefung ein |
| `Invoke-Lint.ps1` | PSScriptAnalyzer gegen das Windows-PowerShell-5.1-Profil |
| `PSScriptAnalyzerSettings.psd1` | Regelsatz und Zielprofil |
| `SpawnNew.Test.psm1` | Minimaler Testlaeufer: Testfaelle anmelden, Zusicherungen, Arbeitsverzeichnis je Fall |
| `Invoke-Test.ps1` | Fuehrt `tests/*.Tests.ps1` aus |

Kein externes Testframework: die PowerShell Gallery ist nicht in jeder
Umgebung erreichbar, Pester 5 liegt nicht als Release-Paket auf github.com,
und Windows PowerShell 5.1 bringt nur das syntaktisch inkompatible Pester 3.4
mit. Der Laeufer kommt ohne Installationsschritt.

## 5a. Tests (`tests/`)

Je geprueftem Baustein eine Datei `<Baustein>.Tests.ps1`. Jeder Testfall
erhaelt ein eigenes leeres Arbeitsverzeichnis; `LOCALAPPDATA` zeigt waehrend
des Falls dorthin, damit Cache und Protokolle den Entwicklerrechner nicht
beschreiben.

| Datei | Prueft |
|---|---|
| `SpawnNew.Test.Tests.ps1` | den Testlaeufer selbst |
| `SpawnNew.Config.Tests.ps1` | Konfigurationsschichten, Quellenpriorietaet, Entdoppelung |
| `SpawnNew.Catalog.Tests.ps1` | Aktionserkennung, Aktions-IDs, Beschreibungspruefung |
| `SpawnNew.Resolve.Tests.ps1` | Prioritaet, Zeitlimit, Cache, Nachpruefung |
| `SpawnNew.Input.Tests.ps1` | Feldnormalisierung und Eingabepruefung |
| `SpawnNew.Target.Tests.ps1` | Namen, Zielpfade, Konflikte, Voraussetzungen, Zusammenfassung |
| `SpawnNew.Runner.Tests.ps1` | Kontextdatei, Argumente, Fortschritt, Ergebnis, Status, Aufraeumangebot |
| `SpawnNew.CatalogCli.Tests.ps1` | die JSON-Ausgabe fuer die Explorer-Erweiterung |

`SpawnNew.Form.psm1` und `SpawnNew.Progress.psm1` laden WinForms und sind
darum nur auf Windows ausfuehrbar. Die Regeln dahinter stehen bewusst in
`SpawnNew.Input.psm1` und `SpawnNew.Target.psm1` und sind dort geprueft.

## 6. Installierte Ablage auf dem Zielsystem

| Zweck | Benutzerinstallation | Systeminstallation |
|---|---|---|
| Programmdateien | `%LOCALAPPDATA%\SpawnNew\App` | `%PROGRAMFILES%\SpawnNew\App` |
| Mitgelieferte Aktionen | `%LOCALAPPDATA%\SpawnNew\App\Actions` | `%PROGRAMFILES%\SpawnNew\App\Actions` |
| Standardkonfiguration | `%LOCALAPPDATA%\SpawnNew\App\spawnnew.settings.default.json` | `%PROGRAMFILES%\SpawnNew\App\spawnnew.settings.default.json` |
| Benutzerkonfiguration | `%LOCALAPPDATA%\SpawnNew\spawnnew.settings.json` | dieselbe Datei je Benutzer |
| Maschinenkonfiguration | entfaellt | `%PROGRAMDATA%\SpawnNew\spawnnew.settings.json` |
| Persoenliche Aktionen | `%LOCALAPPDATA%\SpawnNew\Actions` | dieselbe Datei je Benutzer |
| Metadaten-Cache | `%LOCALAPPDATA%\SpawnNew\Cache` | dieselbe Datei je Benutzer |
| Geheimnisse | `%LOCALAPPDATA%\SpawnNew\Secrets` | dieselbe Datei je Benutzer |
| Diagnoseprotokoll | `%LOCALAPPDATA%\SpawnNew\Logs` | dieselbe Datei je Benutzer |

Programmdateien und Benutzerdaten liegen getrennt. Ein Update schreibt
ausschliesslich unter `App`. Deinstallation entfernt `App` und die
Menuregistrierung; `Actions`, `Cache`, `Logs` und
`spawnnew.settings.json` bleiben erhalten.

## 7. Konfigurationsschichten

Reihenfolge der Auswertung:

1. `%LOCALAPPDATA%\SpawnNew\spawnnew.settings.json`
2. `%PROGRAMDATA%\SpawnNew\spawnnew.settings.json`
3. `<Programmdateien>\spawnnew.settings.default.json`

Einzelwerte wie `sourceTimeoutMs` stammen aus der ersten Schicht, die sie
definiert. Die Listen `sources` werden ueber alle Schichten verbunden und
anhand des normalisierten Pfades entdoppelt; der erste Treffer gewinnt. So
kann eine Benutzerkonfiguration eine Quelle ergaenzen, ohne die
mitgelieferten Quellen zu wiederholen.

## 8. Ergaenzungen am Beschreibungsformat

Ueber den Entwurf in `SpawnNew.md` Abschnitt 5 hinaus wertet die Umsetzung
diese Angaben in `action.json` aus:

| Angabe | Werte | Vorgabe | Zweck |
|---|---|---|---|
| `supportsCancel` | `true`, `false` | `false` | Die Aktion prueft die Abbruchdatei zwischen Schritten |
| `allowsOverwrite` | `true`, `false` | `false` | Ueberschreiben darf nach Bestaetigung angeboten werden |
| `targetKind` | `folder`, `inPlace` | `folder` | `folder` bildet den Zielpfad aus Basisverzeichnis und dem Feld `name`; `inPlace` arbeitet im Basisverzeichnis selbst |
| `secrets` | Liste von Namen | leer | Benoetigte Geheimnisse, nur mit Namen, nie mit Wert |
| `permissions` | Liste von Regeln | leer | NTFS-Rechte je Ordner der Vorlage, geplant |

Arten in `prerequisites`: `command` (Get-Command), `module` (Get-Module -ListAvailable),
`file` (relativ zum Aktionsverzeichnis), `endpoint` (HTTP-Erreichbarkeit mit Zeitlimit,
geplant fuer die KI-Anbindung).

Feldtypen in `fields`: `text`, `multiline`, `date`, `choice`, `bool`. Ein
unbekannter Typ gilt als `text` und wird als Diagnose erfasst. Ein Feld ohne
`name` und ein `choice`-Feld ohne `choices` werden uebersprungen. `default`
mit dem Wert `today` belegt ein Datumsfeld mit dem heutigen Tag vor.

## 9. Aktions-ID

Explizite ID aus `action.json`, Feld `id`:

```
^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$
```

Automatisch erzeugte ID fuer Einzelskripte und Aktionsordner ohne
`action.json`:

```
auto:<erste 16 Hexstellen von SHA256(kanonische Quelle + "|" + relativer Pfad, klein geschrieben)>
```

Der Doppelpunkt ist im Muster der expliziten ID nicht erlaubt. Eine
automatisch erzeugte ID kann deshalb keine explizite ID ersetzen, ohne dass
dafuer eine Sonderbehandlung noetig ist. Zwei automatische IDs kollidieren
nur bei identischer Quelle und identischem relativem Pfad, was nicht
auftreten kann.

## 10. Quellenpriorität

Sortierschluessel in dieser Reihenfolge:

1. `order` aufsteigend
2. Ebene: `personal` vor `shared`
3. Index der Konfigurationsschicht
4. Reihenfolge der Deklaration innerhalb der Schicht

Anschliessend gewinnt bei gleicher expliziter ID die zuerst einsortierte
Quelle. Die unterlegene Aktion wird als Diagnose erfasst, nicht angezeigt.

## 11. Aktionserkennung in einer Quelle

Abtasten bis zu drei Ebenen tief ab dem Quellenwurzelverzeichnis.

| Befund | Ergebnis |
|---|---|
| Verzeichnis mit `action.json` | Aktionsordner. Gueltig nur bei lesbarer JSON und vorhandenem `entryPoint` |
| Verzeichnis mit `Invoke-SpawnAction.ps1`, ohne `action.json` | Aktionsordner mit automatischer ID, Titel aus dem Ordnernamen |
| `.ps1`-Datei ausserhalb eines erkannten Aktionsordners | Einzelskript-Aktion mit automatischer ID, Titel aus dem Dateinamen |

In ein erkanntes Aktionsverzeichnis wird nicht weiter abgestiegen. Interne
Hilfsskripte erscheinen dadurch nicht als eigene Menueaktionen.

## 12. Nachpruefung vor der Ausfuehrung

`Test-SpawnNewAction` prueft unmittelbar vor dem Start erneut: Quelle
erreichbar, Beschreibung lesbar und gueltig, Einstiegspunkt vorhanden,
Aktions-ID unveraendert. Ein Eintrag aus dem Metadaten-Cache gilt dabei
immer als nicht geprueft und wird nicht gestartet.

## 13. Registrierung des Kontextmenues

Erste testbare Stufe ohne Compiler, deshalb reine Registrierung statt DLL:

```
<Wurzel>\Directory\Background\shell\SpawnNew
    (Default)   = "SpawnNew"
    SubCommands = ""
<Wurzel>\Directory\Background\shell\SpawnNew\shell\<NN>_<id>
    (Default)   = "<Titel>"
<Wurzel>\Directory\Background\shell\SpawnNew\shell\<NN>_<id>\command
    (Default)   = powershell.exe -NoProfile -WindowStyle Hidden
                  -ExecutionPolicy Bypass -File "<App>\SpawnNew.Host.ps1"
                  -ActionId <id> -ExplorerPath "%V"
```

Wurzel ist `HKCU:\Software\Classes` bei Benutzerinstallation und
`HKLM:\Software\Classes` bei Systeminstallation. `SubCommands` als leere
Zeichenkette plus `shell`-Unterschlüssel erzeugt das Untermenü. Die
Unterschlüssel werden alphabetisch sortiert, darum der Zahlenpräfix.

Diese Stufe zeigt SpawnNew unter Windows 10 in der ersten Menüebene, unter
Windows 11 erst unter "Weitere Optionen anzeigen". Die direkte Anzeige unter
Windows 11 verlangt `IExplorerCommand` und bleibt Umsetzungsschritt 2. Die
Einträge entstehen bei der Installation aus dem Katalog; dynamisches
Nachladen beim Öffnen des Menüs kommt erst mit der DLL.

## 14. Installations- und Aktualisierungseinzeiler

Beide stehen in der Konfiguration unter `install` und `update` und werden vor
der Ausfuehrung vollstaendig angezeigt. Sie sind identisch: die Installation
ist wiederholbar und wirkt beim zweiten Lauf als Aktualisierung.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { ... }"
```

Der Einzeiler laedt das Archiv des main-Branch nach `%TEMP%`, entpackt es und
ruft `src\Install-SpawnNew.ps1` auf. Er setzt anonymen Lesezugriff auf das
Repository voraus. Bei einem privaten Repository ist statt dessen ein Weg
ueber `git clone` oder ein lokales Verzeichnis zu konfigurieren. TLS 1.2 wird ausdruecklich gesetzt, weil
Windows PowerShell 5.1 sonst je nach System eine aeltere Fassung aushandelt.

`Install-SpawnNew.ps1` kopiert `src\Host\*` und `src\Actions` in das
Programmverzeichnis, legt die Standardkonfiguration daneben, loest den Katalog
auf und schreibt daraus die Registrierungseintraege aus Abschnitt 13. Es
schreibt ausschliesslich unter `App` und in die Menuregistrierung.
`-Uninstall` entfernt beides und nennt die erhaltenen Benutzerdaten.

## 15. Encoding

| Dateiart | Encoding |
|---|---|
| `.ps1`, `.psm1`, `.psd1` | UTF-8 mit BOM |
| `.json` | UTF-8 ohne BOM |
| `.md` | UTF-8 ohne BOM |
| `.cpp`, `.h` | ASCII |

Windows PowerShell 5.1 liest Dateien ohne BOM in der ANSI-Codepage des
Systems. Ein BOM macht die Datei unabhaengig von der Codepage eindeutig, was
`SpawnNew.md` Abschnitt 11 ausdruecklich zulaesst und PSScriptAnalyzer ueber
`PSUseBOMForUnicodeEncodedFile` auch verlangt. Von Aktionen erzeugte
Textdateien werden ebenfalls als UTF-8 mit BOM geschrieben.

Die Dateien, die der Ausfuehrungsprozess und die Aktionen untereinander
austauschen (Kontext, Fortschritt, Ergebnis, Cache), sind UTF-8 ohne BOM,
weil `ConvertFrom-Json` sie so ohne Umwege liest.
