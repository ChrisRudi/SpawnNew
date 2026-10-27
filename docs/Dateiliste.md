<!-- docs/Dateiliste.md | Version 1.2 | 26.10.2026 -->

# Dateiliste und Festlegungen

Umsetzungsschritt 1 aus `SpawnNew.md` Abschnitt 14. Diese Dateinamen sind
festgelegt und werden bei Aenderungen beibehalten (Entwicklungsregel 2 in
`SpawnNew.md` Abschnitt 12).

## 1. Verzeichnisaufbau im Repository

```
SpawnNew.md                             Konzept und Anforderungen
README.md                               Kurzuebersicht, Installation, Pruefen
docs/Dateiliste.md                      diese Datei
docs/Aktionsvertrag.md                  Ausfuehrungsvertrag der PowerShell-Aktionen
docs/KI-Anbindung.md                    Endpunkte, Geheimnisse, Bestaetigung der Modellausgabe
config/spawnnew.settings.default.json   mitgelieferte Standardkonfiguration
src/Install-SpawnNew.ps1                Installation, Aktualisierung, Deinstallation
src/Host/                               Ausfuehrungsprozess, Windows PowerShell 5.1
src/Explorer/                           native Explorer-Erweiterung, C++, noch nicht angelegt
src/Actions/                            die elf mitgelieferten Aktionen
tests/                                  Tests je Baustein, nicht Teil der Installation
tools/                                  Entwicklungswerkzeuge, nicht Teil der Installation
```

## 2. Ausfuehrungsprozess (`src/Host/`)

| Datei | Zweck |
|---|---|
| `SpawnNew.Host.ps1` | Einstiegspunkt einer Aktion. Nimmt Aktions-ID und Explorer-Pfad, fuehrt Nachpruefung, Formular, Vorschlag, Zusammenfassung, Start und Fortschritt aus |
| `SpawnNew.Command.ps1` | Einstiegspunkt der Verwaltungsbefehle `configure`, `update`, `install` |
| `SpawnNew.Catalog.ps1` | Konsolen-Einstiegspunkt: schreibt den aufgeloesten Katalog als JSON fuer die Explorer-Erweiterung |
| `SpawnNew.Diagnose.ps1` | Konsolen-Einstiegspunkt: Schichten, Quellen, Zeitverhalten, Katalog, Diagnosen und Registrierung anzeigen |
| `SpawnNew.Config.psm1` | Konfigurationsschichten laden, Umgebungsvariablen aufloesen, Quellen und KI-Endpunkte normalisieren |
| `SpawnNew.Catalog.psm1` | Quellen abtasten, Aktions-IDs bilden, Beschreibungen pruefen |
| `SpawnNew.Resolve.psm1` | Quellen mit Zeitlimit abtasten, Metadaten-Cache, Prioritaet aufloesen, Nachpruefung vor der Ausfuehrung |
| `SpawnNew.Input.psm1` | Formularfelder normalisieren, Vorbelegungen, Eingaben pruefen. Ohne WinForms |
| `SpawnNew.Target.psm1` | Namen, Namensvorlage, Zielpfade, Zielzustand, freier Name, Voraussetzungen, Zusammenfassungstext. Ohne WinForms |
| `SpawnNew.Runner.psm1` | Laufverzeichnis, Kontextdatei, Prozessstart, Fortschritt, Ergebnis, Vorschlag, Status |
| `SpawnNew.Register.psm1` | Registrierungseintraege des Kontextmenues bilden, abgleichen, schreiben und entfernen |
| `SpawnNew.Document.psm1` | Markdown- und `.docx`-Dateien aus Vorlagen mit Platzhaltern, ohne Word-Automatisierung |
| `SpawnNew.Llm.psm1` | OpenAI-kompatibler Client fuer lokale und Webendpunkte |
| `SpawnNew.Secret.psm1` | Geheimnisse benutzer- und rechnergebunden speichern und lesen |
| `SpawnNew.Settings.psm1` | Verwaltungsbefehle ohne Fenster: Uebersicht, Benutzerkonfiguration, Menueabgleich, Einzeiler |
| `SpawnNew.Action.psm1` | Hilfen fuer Aktionsskripte: Kontext, Fortschritt, Ergebnis, Dateien ohne Ueberschreiben, Dokumente, Entwuerfe |
| `SpawnNew.Form.psm1` | Eingabeformular, Konfliktfrage, Zusammenfassung und Meldungen als WinForms-Fenster |
| `SpawnNew.Progress.psm1` | Fortschrittsfenster, Abbruchanforderung, Abschlussbericht |
| `SpawnNew.SettingsForm.psm1` | Konfigurationsfenster, Geheimniseingabe, Wartefenster |

Die Regeln liegen in Modulen ohne Fensterdarstellung und sind dort geprueft.
`Form`, `Progress` und `SettingsForm` stellen nur dar.

## 3. Explorer-Erweiterung (`src/Explorer/`)

Festgelegt, noch nicht angelegt (Umsetzungsschritt 2).

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

Je Aktion ein Ordner mit `action.json` und `Invoke-SpawnAction.ps1`, dazu
bei Bedarf `Vorlagen/` und Hilfsdateien. Alle elf sind vorhanden.

| Ordner | Aktions-ID | Nr. | Weitere Dateien |
|---|---|---|---|
| `Ordnerstruktur` | `spawnnew.folderstructure` | 1 | `Vorlagen.json` mit Unterordnern und NTFS-Rechten |
| `GitProjekt` | `spawnnew.gitproject` | 2 | `Gitignore/<Vorlage>.gitignore` |
| `PowerShellWerkzeug` | `spawnnew.pstool` | 3 | `Vorlagen/Skript.ps1.vorlage`, `Konfiguration.json.vorlage`, `README.md` |
| `Werkstattprotokoll` | `spawnnew.workshoplog` | 7 | `Vorlagen/Protokoll.md` |
| `Fehleranalyse` | `spawnnew.incident` | 10 | `Vorlagen/Fehleranalyse.md` |
| `Sitzung` | `spawnnew.meeting` | 11 | `Vorlagen/Tagesordnung.md`, `Protokoll.md`, `Beschlussliste.md` |
| `EigeneAktion` | `spawnnew.customaction` | 14 | `Vorlagen/Invoke-SpawnAction.ps1.vorlage`, `README.md` |
| `ProjektAbschliessen` | `spawnnew.closeout` | 15 | |
| `StrukturAusBeschreibung` | `spawnnew.structurefromtext` | 17 | `Get-SpawnProposal.ps1`, `StrukturPruefung.psm1` |
| `DateiZusammenfassen` | `spawnnew.summarizefile` | 18 | |
| `OrdnerDokumentieren` | `spawnnew.documentfolder` | 19 | |

Die Aktionen 1 und 2 sind eigenstaendig. Die uebrigen nutzen
`SpawnNew.Action.psm1` aus dem Programmverzeichnis, das ihnen die
Kontextdatei unter `appDirectory` nennt. Code-Vorlagen enden auf `.vorlage`,
damit Lint und Katalog sie nicht als Skripte behandeln.

### Dokumentvorlagen

Vorlagen sind Markdown mit Platzhaltern `{{name}}`. `SpawnNew.Document.psm1`
sucht in dieser Reihenfolge:

1. `%LOCALAPPDATA%\SpawnNew\Vorlagen\<Aktions-ID>\<Name>.docx` (nur fuer Word)
2. `%LOCALAPPDATA%\SpawnNew\Vorlagen\<Aktions-ID>\<Name>.md`
3. `<Aktionsordner>\Vorlagen\<Name>.docx` (nur fuer Word)
4. `<Aktionsordner>\Vorlagen\<Name>.md`

Eine Markdown-Vorlage wird fuer Word in ein `.docx` umgewandelt
(Ueberschriften, Aufzaehlungen, Kontrollkaestchen, Tabellen, Fettdruck). In
einer eigenen `.docx`-Vorlage werden die Platzhalter in Text, Kopf- und
Fusszeilen ersetzt, auch wenn Word einen Platzhalter auf mehrere Laeufe
verteilt hat. Unbekannte Platzhalter bleiben sichtbar stehen.

### NTFS-Rechte in `Vorlagen.json`

Ein Vorlageneintrag ist ein Ordnername oder ein Objekt:

```json
{ "pfad": "09 Vertraulich",
  "rechte": { "vererbungTrennen": true,
              "regeln": [ { "identitaet": "*S-1-5-18", "recht": "FullControl" } ] } }
```

`identitaet` ist `AKTUELLER_BENUTZER`, eine SID mit fuehrendem `*` oder ein
Kontoname; SIDs sind sprachunabhaengig. `recht` ist ein Wert von
`FileSystemRights`, `typ` optional `Allow` oder `Deny`. Bei getrennter
Vererbung behaelt der aktuelle Benutzer immer Vollzugriff. Die Rechte gelten
fuer Unterordner und Dateien.

## 5. Werkzeuge (`tools/`)

| Datei | Zweck |
|---|---|
| `Install-DevTools.ps1` | Richtet PowerShell 7 und PSScriptAnalyzer fuer die Pruefung ein |
| `Invoke-Lint.ps1` | PSScriptAnalyzer gegen das Windows-PowerShell-5.1-Profil |
| `PSScriptAnalyzerSettings.psd1` | Regelsatz und Zielprofil |
| `SpawnNew.Test.psm1` | Minimaler Testlaeufer: Testfaelle, Zusicherungen, Arbeitsverzeichnis je Fall, Aktionsstart, Testserver fuer Sprachmodelle |
| `Invoke-Test.ps1` | Fuehrt `tests/*.Tests.ps1` aus |

Kein externes Testframework: die PowerShell Gallery ist nicht in jeder
Umgebung erreichbar, Pester 5 liegt nicht als Release-Paket auf github.com,
und Windows PowerShell 5.1 bringt nur das syntaktisch inkompatible Pester 3.4
mit. Der Laeufer kommt ohne Installationsschritt.

## 5a. Tests (`tests/`)

Jeder Testfall erhaelt ein eigenes leeres Arbeitsverzeichnis;
`LOCALAPPDATA` zeigt waehrend des Falls dorthin, damit Cache, Protokolle,
Geheimnisse und eigene Vorlagen den Entwicklerrechner nicht beschreiben.

| Datei | Prueft |
|---|---|
| `SpawnNew.Test.Tests.ps1` | den Testlaeufer selbst |
| `SpawnNew.Config.Tests.ps1` | Konfigurationsschichten, Quellenprioritaet, Entdoppelung |
| `SpawnNew.Catalog.Tests.ps1` | Aktionserkennung, Aktions-IDs, Beschreibungspruefung |
| `SpawnNew.CatalogCli.Tests.ps1` | die JSON-Ausgabe fuer die Explorer-Erweiterung |
| `SpawnNew.Resolve.Tests.ps1` | Prioritaet, Zeitlimit, Cache, Nachpruefung |
| `SpawnNew.Input.Tests.ps1` | Feldnormalisierung, Eingabepruefung, Datei- und Endpunktfelder |
| `SpawnNew.Target.Tests.ps1` | Namen, Namensvorlage, Zielpfade, Konflikte, Voraussetzungen, Zusammenfassung |
| `SpawnNew.Runner.Tests.ps1` | Kontextdatei, Argumente, Fortschritt, Ergebnis, Vorschlag, Status, Aufraeumangebot |
| `SpawnNew.Register.Tests.ps1` | Registrierungseintraege, Verwaltungsbefehle, Abgleich in einem Testschluessel |
| `SpawnNew.Secret.Tests.ps1` | Verschluesselung, Ablage, Fehlerfaelle der Geheimnisse |
| `SpawnNew.Llm.Tests.ps1` | KI-Endpunkte, Chat, Schluessel nur im Kopf, Fehler, Zeitlimit, JSON aus Antworten |
| `SpawnNew.Document.Tests.ps1` | Platzhalter, Vorlagensuche, Markdown, `.docx` aus Markdown und aus Vorlage |
| `SpawnNew.Settings.Tests.ps1` | Uebersicht, Benutzerkonfiguration, Einzeiler, Laden der Fenstermodule |
| `SpawnNew.Ordnerstruktur.Tests.ps1` | Aktion 1 samt NTFS-Rechten |
| `SpawnNew.GitProjekt.Tests.ps1` | Aktion 2 mit echtem `git`, Rechnerkonfiguration ausgeblendet |
| `SpawnNew.PowerShellWerkzeug.Tests.ps1` | Aktion 3; das erzeugte Skript parst und laeuft |
| `SpawnNew.Dokumentaktionen.Tests.ps1` | Aktionen 7, 10 und 11 mit Markdown, Word, eigenen Vorlagen und Entwuerfen |
| `SpawnNew.EigeneAktion.Tests.ps1` | Aktion 14; das Grundgeruest wird erkannt und laeuft |
| `SpawnNew.ProjektAbschliessen.Tests.ps1` | Aktion 15 mit Manifest, ZIP, Verschieben und Vorpruefungen |
| `SpawnNew.KiAktionen.Tests.ps1` | Aktionen 17 bis 19 gegen einen Testserver |
| `SpawnNew.HostFlow.Tests.ps1` | den Host als Ganzes; nur die Fenster sind durch Stellvertreter ersetzt |

Die Tests laufen unter Windows PowerShell 5.1 auf Windows. Registrierung,
NTFS-Rechte, DPAPI und WinForms setzen Windows voraus. Pfade, die in
JSON-Texte eingesetzt werden, gehen ueber `ConvertTo-SpawnNewJsonText`.
Der Testserver fuer Sprachmodelle ist ein TcpListener auf 127.0.0.1 und
braucht keine Rechte.

## 6. Installierte Ablage auf dem Zielsystem

| Zweck | Benutzerinstallation | Systeminstallation |
|---|---|---|
| Programmdateien | `%LOCALAPPDATA%\SpawnNew\App` | `%PROGRAMFILES%\SpawnNew\App` |
| Mitgelieferte Aktionen | `%LOCALAPPDATA%\SpawnNew\App\Actions` | `%PROGRAMFILES%\SpawnNew\App\Actions` |
| Standardkonfiguration | `%LOCALAPPDATA%\SpawnNew\App\spawnnew.settings.default.json` | `%PROGRAMFILES%\SpawnNew\App\spawnnew.settings.default.json` |
| Benutzerkonfiguration | `%LOCALAPPDATA%\SpawnNew\spawnnew.settings.json` | dieselbe Datei je Benutzer |
| Maschinenkonfiguration | entfaellt | `%PROGRAMDATA%\SpawnNew\spawnnew.settings.json` |
| Persoenliche Aktionen | `%LOCALAPPDATA%\SpawnNew\Actions` | dieselbe Datei je Benutzer |
| Eigene Dokumentvorlagen | `%LOCALAPPDATA%\SpawnNew\Vorlagen\<Aktions-ID>` | dieselbe Datei je Benutzer |
| Metadaten-Cache | `%LOCALAPPDATA%\SpawnNew\Cache` | dieselbe Datei je Benutzer |
| Geheimnisse | `%LOCALAPPDATA%\SpawnNew\Secrets` | dieselbe Datei je Benutzer |
| Protokolle | `%LOCALAPPDATA%\SpawnNew\Logs\host.log`, `command.log` | dieselbe Datei je Benutzer |

Programmdateien und Benutzerdaten liegen getrennt. Ein Update schreibt
ausschliesslich unter `App`. Deinstallation entfernt `App` und die
Menueregistrierung; alle Benutzerdaten bleiben erhalten.

## 7. Konfigurationsschichten

Reihenfolge der Auswertung:

1. `%LOCALAPPDATA%\SpawnNew\spawnnew.settings.json`
2. `%PROGRAMDATA%\SpawnNew\spawnnew.settings.json`
3. `<Programmdateien>\spawnnew.settings.default.json`

Einzelwerte wie `sourceTimeoutMs` und `llm.defaultEndpoint` stammen aus der
ersten Schicht, die sie definiert. Die Listen `sources` und
`llm.endpoints` werden ueber alle Schichten verbunden; Quellen werden
anhand des Pfades, Endpunkte anhand des Namens entdoppelt, der erste Treffer
gewinnt. So ergaenzt oder ersetzt eine Benutzerkonfiguration einzelne
Eintraege, ohne die mitgelieferten zu wiederholen. Die KI-Angaben stehen in
`docs/KI-Anbindung.md`.

## 8. Ergaenzungen am Beschreibungsformat

Ueber den Entwurf in `SpawnNew.md` Abschnitt 5 hinaus wertet die Umsetzung
diese Angaben in `action.json` aus:

| Angabe | Werte | Vorgabe | Zweck |
|---|---|---|---|
| `supportsCancel` | `true`, `false` | `false` | Die Aktion prueft die Abbruchdatei zwischen Schritten |
| `allowsOverwrite` | `true`, `false` | `false` | Ueberschreiben darf nach Bestaetigung angeboten werden |
| `targetKind` | `folder`, `inPlace` | `folder` | `folder` bildet den Zielpfad aus Basisverzeichnis und Ordnername; `inPlace` arbeitet im Basisverzeichnis selbst |
| `nameTemplate` | Text mit `{{feld}}` | leer | Ordnername aus Feldern, wenn es kein Feld `name` gibt; verbotene Zeichen werden `-` |
| `proposal` | relativer Pfad | leer | Vorschlagsskript, das vor der Zusammenfassung laeuft (`docs/Aktionsvertrag.md` Abschnitt 12) |
| `secrets` | Liste von Namen | leer | Benoetigte Geheimnisse, nur mit Namen, nie mit Wert; fehlende gelten als fehlende Voraussetzung |

Arten in `prerequisites`: `command` (Get-Command), `module` (Get-Module
-ListAvailable), `file` (relativ zum Aktionsverzeichnis), `secret`
(gespeichertes Geheimnis), `endpoint` (voreingestellter KI-Endpunkt
konfiguriert, Geheimnis vorhanden, `GET models` innerhalb von 3 s
erfolgreich). Diese Pruefung laeuft erst nach Auswahl der Aktion, nie beim
Oeffnen des Menues.

Feldtypen in `fields`: `text`, `multiline`, `date`, `choice`, `bool`,
`file` (vorhandene Datei, vollstaendiger Pfad, Auswahl ueber einen
Dateidialog) und `endpoint` (Auswahl unter den konfigurierten KI-Endpunkten,
vorbelegt mit dem voreingestellten). Ein unbekannter Typ gilt als `text`
und wird als Diagnose erfasst. Ein Feld ohne `name` und ein `choice`-Feld
ohne `choices` werden uebersprungen. `default` mit dem Wert `today` belegt
ein Datumsfeld mit dem heutigen Tag vor. `pattern` und `message` pruefen
Textfelder mit einem regulaeren Ausdruck.

`permissions` aus `SpawnNew.md` Abschnitt 5 ist ueber `Vorlagen.json` der
Aktion 1 umgesetzt (Abschnitt 4), weil die Rechte zur Strukturvorlage
gehoeren und nicht zur Aktion.

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
| Verzeichnis mit `action.json` | Aktionsordner. Gueltig nur bei lesbarer JSON, vorhandenem `entryPoint` und, falls angegeben, vorhandenem `proposal` |
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
    MUIVerb      = "SpawnNew"
    SubCommands  = ""
<Wurzel>\...\SpawnNew\shell\<NN>_<id>
    MUIVerb      = "<Titel>"
<Wurzel>\...\SpawnNew\shell\<NN>_<id>\command
    <Standard>   = powershell.exe -NoProfile -WindowStyle Hidden
                   -ExecutionPolicy Bypass -File "<App>\SpawnNew.Host.ps1"
                   -ActionId "<id>" -ExplorerPath "%V"
<Wurzel>\...\SpawnNew\shell\zz<N>_spawnnew.<befehl>
    MUIVerb      = "SpawnNew konfigurieren" | "... aktualisieren" | "... installieren"
    CommandFlags = 0x20 (nur beim ersten: Trennlinie davor)
<Wurzel>\...\SpawnNew\shell\zz<N>_spawnnew.<befehl>\command
    <Standard>   = powershell.exe ... -File "<App>\SpawnNew.Command.ps1" -Command <befehl>
```

Anzeigetexte stehen in `MUIVerb`, also in benannten Werten. Unbenannter
Standardwert ist nur die Befehlszeile. `New-ItemProperty -Name '(default)'`
legt einen Wert an, der woertlich `(default)` heisst, und den liest die
Shell nicht. Der Standardwert eines Schluessels wird mit
`Set-Item -LiteralPath <Schluessel> -Value <Text>` geschrieben.

Eine Neuregistrierung entfernt zuerst den gesamten `SpawnNew`-Schluessel und
schreibt dann frisch. Wurzel ist `HKCU:\Software\Classes` bei
Benutzerinstallation und `HKLM:\Software\Classes` bei Systeminstallation.
Die Unterschluessel werden alphabetisch sortiert, darum der Zahlenpraefix
der Aktionen und `zz` vor den Verwaltungsbefehlen.

Bis zur DLL entsteht das Menue nicht beim Oeffnen. Der Ausfuehrungsprozess
gleicht es darum bei jedem Aufruf mit dem Katalog ab und schreibt es bei
einer Abweichung neu; eine neue persoenliche Aktion erscheint so nach dem
naechsten Aufruf eines SpawnNew-Eintrags, sofort ueber **SpawnNew
konfigurieren > Menue neu einlesen**. Das gilt fuer Benutzerinstallationen;
eine Systeminstallation braucht dafuer Administratorrechte.

Diese Stufe zeigt SpawnNew unter Windows 10 in der ersten Menueebene, unter
Windows 11 erst unter "Weitere Optionen anzeigen". Die direkte Anzeige unter
Windows 11 verlangt `IExplorerCommand` und bleibt Umsetzungsschritt 2.

## 14. Installations- und Aktualisierungseinzeiler

Beide stehen in der Konfiguration unter `install` und `update`. Sie sind
identisch: die Installation ist wiederholbar und wirkt beim zweiten Lauf als
Aktualisierung.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { ... }"
```

Der Einzeiler laedt das Archiv des main-Branch nach `%TEMP%`, entpackt es und
ruft `src\Install-SpawnNew.ps1` auf. Er setzt anonymen Lesezugriff auf das
Repository voraus. TLS 1.2 wird ausdruecklich gesetzt, weil Windows
PowerShell 5.1 sonst je nach System eine aeltere Fassung aushandelt.

Die Menueeintraege **SpawnNew aktualisieren** und **SpawnNew installieren**
zeigen den vollstaendigen Befehl, das Ziel und die Rechte und fuehren ihn
erst nach "Ausfuehren" aus. `cmd.exe /d /s /c "(<Befehl>) > <Protokoll> 2>&1"`
startet ihn verborgen; danach erscheinen Befehl, Rueckgabewert und Ausgabe.
Bei `requiresAdmin: true` fragt Windows vorher nach Rechten.

`Install-SpawnNew.ps1` leert `App`, kopiert `src\Host\*` und `src\Actions`
hinein, legt die Standardkonfiguration daneben, loest den Katalog auf und
schreibt daraus die Registrierung aus Abschnitt 13. Es schreibt
ausschliesslich unter `App` und in die Menueregistrierung. `-Uninstall`
entfernt beides und nennt die erhaltenen Benutzerdaten.

## 15. Encoding

| Dateiart | Encoding |
|---|---|
| `.ps1`, `.psm1`, `.psd1` | UTF-8 mit BOM |
| `.json` | UTF-8 ohne BOM |
| `.md`, `.vorlage`, `.gitignore` | UTF-8 ohne BOM |
| `.cpp`, `.h` | ASCII |

Windows PowerShell 5.1 liest Dateien ohne BOM in der ANSI-Codepage des
Systems. Ein BOM macht die Datei unabhaengig von der Codepage eindeutig, was
`SpawnNew.md` Abschnitt 12 ausdruecklich zulaesst und PSScriptAnalyzer ueber
`PSUseBOMForUnicodeEncodedFile` auch verlangt. Von Aktionen erzeugte
Textdateien werden als UTF-8 mit BOM geschrieben, JSON ohne BOM.

Die Dateien, die der Ausfuehrungsprozess und die Aktionen untereinander
austauschen (Kontext, Fortschritt, Ergebnis, Vorschlag, Cache), sind UTF-8
ohne BOM, weil `ConvertFrom-Json` sie so ohne Umwege liest.

## 16. Windows PowerShell 5.1: zwei Fallen

`$PSScriptRoot` ist in den `param()`-Vorgaben eines Skripts mit
`[CmdletBinding()]` leer, wenn es mit `-File` startet, also genau so, wie
der Explorer es startet. Einstiegspunkte setzen ihre Vorgaben darum erst im
Skriptkoerper.

Eine Closure aus `GetNewClosure()` in einem Modul sieht die in dieses Modul
importierten Funktionen nicht. Fensterereignisse, die Modulfunktionen
aufrufen, verwenden darum keine Closure oder verlassen sich darauf, dass der
Einstiegspunkt die Module global importiert hat.
