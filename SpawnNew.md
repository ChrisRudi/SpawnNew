<!-- SpawnNew.md | Version 1.3 | 26.10.2026 -->

# SpawnNew

Konzept und Anforderungen, Version 1.3 vom 26.10.2026.
Status: Ausführungsprozess und Katalogauflösung umgesetzt und geprüft;
Explorer-Erweiterung, mitgelieferte Aktionen und Installation offen.

## 1. Ziel

SpawnNew erzeugt über das Windows-Explorer-Kontextmenü vorbereitete Arbeitsumgebungen. Eine Aktion kann Ordner und Dokumente anlegen, ein Git-Repository initialisieren, ein abgeschlossenes Projekt archivieren, ein Sprachmodell um einen Entwurf bitten oder später auch eine virtuelle Maschine erstellen.

Die Explorer-Anbindung ist unabhängig von PowerToys. Neue Aktionen werden aus konfigurierten Verzeichnissen geladen und über Windows PowerShell 5.1 umgesetzt. Neue oder geänderte Aktionen erfordern keinen Neubau der Explorer-Erweiterung.

## 2. Festgelegte Entscheidungen

| Bereich | Festlegung |
|---|---|
| Einstieg | Ausschließlich über das Explorer-Kontextmenü |
| Darstellung | SpawnNew als Untermenü mit direkt auswählbaren Aktionen |
| Betriebssysteme | Windows 10 und Windows 11; Ziel ist die direkte Anzeige im ersten Kontextmenü. Die technische Umsetzung wird je Betriebssystem getrennt registriert und abgenommen |
| Aktionen | Genau elf mitgelieferte Startaktionen; zusätzlich beliebig viele benutzerdefinierte Aktionen aus konfigurierten Quellen |
| Quellen | Mehrere frei konfigurierbare Verzeichnisse, lokal, OneDrive oder Netzwerkfreigabe |
| Quellenpriorität | Explizite Reihenfolge aller Quellen. Bei gleicher Aktions-ID gewinnt die zuerst konfigurierte Quelle. Persönliche Quellen werden standardmäßig vor gemeinsamen Quellen eingeordnet, können aber durch eine explizite Reihenfolge anders priorisiert werden |
| Aktions-ID | Nur eine explizit deklarierte, identische Aktions-ID darf eine andere Aktion ersetzen. Automatisch erzeugte IDs dürfen keine andere Aktion überschreiben |
| Zielpfad | Aktionsstandard im Dialog änderbar; ohne eigenen Standard gilt der Explorer-Ordner |
| Eingaben | Einheitliche Formulare; eigene Dialoge einer Aktion sind nur zulässig, wenn sie denselben Eingabe-, Zusammenfassungs- und Abbruchvertrag einhalten |
| Rechte | Standardmäßig normale Benutzerrechte. Administratorrechte nur bei `requiresAdmin: true`; die Rechteanforderung gilt ausschließlich für die fachliche Ausführung |
| PowerShell | Windows PowerShell 5.1 als einzige unterstützte Laufzeit |
| Beschreibung | Skripte allein nutzbar; optionale JSON-Dateien für zusätzliche Angaben |
| Namenskonflikte | Abbrechen, anderen Namen wählen oder vorhandenen Ordner verwenden |
| Dateikonflikte | Keine stillen Überschreibungen. Für jede betroffene Datei muss die Aktion abbrechen, einen neuen Namen verwenden oder eine ausdrücklich bestätigte Überschreibungsregel anwenden |
| Ausgabe | Fortschrittsfenster, Fehlerdetails und optionales Öffnen des Zielordners |
| Kategorien | Optional; Aktionen können direkt unter SpawnNew oder in Kategorien stehen |
| Teilfehler | Optionale Aufräumfunktion je Aktion; ohne diese bleiben erstellte Teile erhalten |
| Installation | Wahlweise für aktuellen Benutzer oder alle Benutzer |
| Nachladen | Änderungen werden beim nächsten Öffnen des Kontextmenüs berücksichtigt. Bereits geöffnete Menüs werden nicht aktualisiert |
| Quellenfehler | Fehlerhafte oder nicht erreichbare Quellen werden protokolliert, blockieren aber weder andere Quellen noch den Explorer dauerhaft |
| Dokumente | Markdown oder Word-kompatible `.docx`-Dateien auswählbar; eigene Vorlagendateien möglich. Platzhalter werden auch im Inhalt einer `.docx` ersetzt, ohne Word-Automatisierung |
| Ordnerrechte | Eine Vorlage darf NTFS-Rechte je Ordner deklarieren. Ein Kopieren über den Explorer verliert eigene Rechte und erbt die des Elternordners; die Umsetzung muss die deklarierten Rechte darum selbst setzen |
| KI-Anbindung | Optional. Ein OpenAI-kompatibler Endpunkt, lokal oder im Web. Lokal ist die Vorgabe |
| KI-Ausgabe | Nicht deterministisch. Sie wird nie ohne ausdrückliche Bestätigung in eine Datei geschrieben |
| Geheimnisse | API-Schlüssel stehen nie in der Kontextdatei, im Fortschritt, im Protokoll oder in der Zusammenfassung. Getrennter Speicher, benutzer- und rechnergebunden |
| Vor dem Start | Zusammenfassung von Zielpfad, Eingaben und geplanten Schritten; danach ausdrücklich „Erstellen“ |
| Voraussetzungen | Fehlende Voraussetzungen verständlich anzeigen; keine automatische Installation |
| Konfiguration | Quellen, Prioritäten, Endpunkte und Installationsoptionen werden über eine separate Konfigurationsoberfläche oder eine dokumentierte Konfigurationsdatei verwaltet; diese Verwaltung ist keine fachliche Aktion |
| Einzeiler | Einzeilige Befehle für Installation und Aktualisierung stehen zusätzlich als Menüeinträge zur Verfügung |

Die elf mitgelieferten Startaktionen sind die Einträge 1, 2, 3, 7, 10, 11, 14, 15, 17, 18 und 19 in Abschnitt 4. Die Nummern sind stabile fachliche Kennungen und werden nicht als fortlaufende Anzahl interpretiert.

## 3. Bedienablauf

1. Im Hintergrund eines Explorer-Ordners rechts klicken.
2. SpawnNew öffnen und eine Aktion auswählen.
3. SpawnNew liest Beschreibung und prüft Voraussetzungen.
4. Das Formular zeigt Vorgaben sowie den änderbaren Zielpfad.
5. Der Benutzer ergänzt beispielsweise Projektname, Klasse, Thema oder Datum.
6. Eine Zusammenfassung zeigt Zielpfad, Eingaben und geplante Schritte. Bei Aktionen, die einen Vorschlag erzeugen lassen, steht der Vorschlag hier.
7. „Erstellen“ startet die Aktion. Falls deklariert, erfolgt dabei die Windows-Abfrage für Administratorrechte.
8. Das Fortschrittsfenster zeigt den Ablauf und das Ergebnis.
9. Optional wird der Zielordner geöffnet.

Zusätzlich stehen im SpawnNew-Untermenü folgende Verwaltungsbefehle zur Verfügung:

- SpawnNew installieren: Führt den konfigurierten Einzeiler für die Installation aus.
- SpawnNew aktualisieren: Führt den konfigurierten Einzeiler für die Aktualisierung aus.

Die Einzeiler werden nicht automatisch ausgeführt. Vor der Ausführung werden Befehl, Ziel und erforderliche Rechte angezeigt und ausdrücklich bestätigt. Die Befehle dürfen nur die SpawnNew-Installation beziehungsweise deren Programmdateien aktualisieren. Persönliche Aktionen, Quellen und Konfiguration dürfen nicht überschrieben werden.

Abbrechen vor „Erstellen“ darf keine fachlichen Änderungen durchführen. Das Öffnen des Menüs darf keine Aktionsskripte ausführen und keinen Netzzugriff auslösen.

Bei eigenen Aktionsdialogen gelten dieselben Anforderungen an Eingaben, Vorprüfung, Zusammenfassung, Rechteabfrage und Abbruch. Das Formular ist Teil des aufgerufenen Ablaufs, kein eigenständiger Aktionsstarter.

## 4. Mitgelieferte Aktionen der ersten Version

Die erste Version enthält genau elf mitgelieferte Aktionen:

| Nr. | Aktion | Eingaben und Ergebnis |
|---|---|---|
| 1 | Ordnerstruktur | Name, Zielpfad, Strukturvorlage; Unterordner und vorbereitete Dateien. Deklariert die Vorlage NTFS-Rechte, werden sie gesetzt |
| 2 | Git-Projekt | Name, Zielpfad, passende Gitignore-Vorlage; lokales Repository mit README und optionalem ersten Commit. Das reine Initialisieren deckt auch TortoiseGit ab; der Mehrwert liegt in Vorlage, README und erstem Commit in einem Schritt |
| 3 | PowerShell-Werkzeug | Name, Zielpfad, Beschreibung; Skript mit Dateiname und Version im Kopf, Konfiguration und Kurzdokumentation |
| 7 | Werkstättenprotokoll | Klasse, Thema, Datum, Ausgabeformat, optional Entwurf erzeugen; Protokollvorlage sowie Bilder- und Messdatenordner |
| 10 | Fehleranalyse | Titel, Umgebung, Datum, optional Entwurf erzeugen; Fehlerbeschreibung, Reproduktionsschritte, Logs, Screenshots und Lösungsnachweis |
| 11 | Sitzung | Gremium, Thema, Datum, Ausgabeformat, optional Entwurf erzeugen; Tagesordnung, Unterlagen, Protokoll und Beschlussliste |
| 14 | Eigene Aktion | Name und Aktions-ID; dokumentiertes Grundgerüst mit Skript und optionaler JSON-Beschreibung |
| 15 | Projekt abschließen | Arbeitet im vorhandenen Ordner. Abschlussvermerk, Dateimanifest mit SHA-256 je Datei, optional ZIP und Verschieben in ein Archivverzeichnis |
| 17 | Ordnerstruktur aus Beschreibung | Freitextbeschreibung, Zielpfad; ein Sprachmodell schlägt die Struktur vor, der Vorschlag erscheint in der Zusammenfassung und wird erst nach „Erstellen“ angelegt |
| 18 | Datei zusammenfassen | Beliebige Textdatei, Modell; Zusammenfassung als Entwurfsdatei neben der Quelle |
| 19 | Ordner dokumentieren | Zielordner, Modell; `README.md` als Entwurf aus Dateiliste und erkennbarem Zweck |

Hyper-V, Webprojekte und weitere Aktionen bleiben Erweiterungsmöglichkeiten. Sie sind nicht Bestandteil der elf mitgelieferten Aktionen. Git-Projekte werden lokal erstellt; Remote-Erstellung und Veröffentlichung gehören nicht zum Standardablauf.

## 5. Aktionsformat

### Einzelnes Skript

Ein PowerShell-Skript in einer konfigurierten Aktionsquelle genügt. Ohne Beschreibung bestimmt der Dateiname den sichtbaren Namen. Die Aktion verwendet Windows PowerShell 5.1 und normale Benutzerrechte.

Für ein einzelnes Skript wird die Aktions-ID deterministisch aus der kanonischen Quelle und dem relativen Pfad gebildet. Diese automatisch erzeugte ID darf keine andere Aktion ersetzen. Ein bewusstes Überschreiben zwischen persönlichen und gemeinsamen Quellen ist nur mit einer explizit angegebenen Aktions-ID zulässig.

### Aktionsordner

Ein Aktionsordner bündelt Einstiegsskript, optionale JSON-Beschreibung, Vorlagendateien, Ressourcen und Kurzdokumentation. Die Erkennung erfolgt ausschließlich über eine eindeutige Beschreibung oder ein festgelegtes Einstiegsskript, damit interne Hilfsskripte nicht als zusätzliche Menüaktionen erscheinen.

Ein Aktionsordner wird nur dann als Aktion erkannt, wenn sein Einstiegspunkt vorhanden und die Beschreibung syntaktisch gültig ist. Ungültige oder unvollständige Aktionsordner werden nicht ausgeführt und als Diagnose erfasst.

### Angaben der Beschreibung

| Angabe | Zweck |
|---|---|
| `schemaVersion` | Version des Beschreibungsformats |
| `id` | Feste, von Anzeigename und Pfad unabhängige Aktions-ID |
| `title` | Sichtbarer Menüname |
| `category` | Optionale Menükategorie |
| `icon` | Optionales lokales Symbol |
| `entryPoint` | Relativer Pfad zum Einstiegsskript |
| `requiresAdmin` | Deklarierter Bedarf an Administratorrechten |
| `supportsCancel` | Die Aktion prüft die Abbruchdatei zwischen Schritten |
| `allowsOverwrite` | Überschreiben darf nach Bestätigung angeboten werden |
| `targetKind` | `folder` bildet den Zielpfad aus Basisverzeichnis und Name; `inPlace` arbeitet im Basisverzeichnis selbst |
| `defaultTarget` | Optionaler Standardzielpfad |
| `fields` | Beschriebene Formularfelder mit Vorgaben und Prüfung |
| `secrets` | Benötigte Geheimnisse, nur mit Namen, nie mit Wert |
| `permissions` | Optionale NTFS-Rechte je Ordner der Vorlage |
| `prerequisites` | Benötigte Programme, Module, Dateien oder erreichbare Endpunkte |
| `plannedSteps` | Für die Zusammenfassung geeignete Schrittbeschreibung |
| `cleanup` | Optionaler relativer Einstiegspunkt für das Aufräumen nach Teilfehlern |

Die genauen Werte, Vorgaben und Feldtypen stehen in `docs/Dateiliste.md` Abschnitt 8, der Ausführungsvertrag in `docs/Aktionsvertrag.md`, die KI-Anbindung in `docs/KI-Anbindung.md`.

`requiresAdmin: true` darf nicht allein aus einer Beschreibung zu einer erhöhten Ausführung führen, wenn die Aktion die Rechte nicht tatsächlich benötigt. Die Anwendung zeigt die deklarierte Rechteanforderung vor dem Start an und fordert erhöhte Rechte erst nach ausdrücklicher Bestätigung an.

## 6. Quellen und dynamisches Nachladen

- Mehrere Quellen sind gleichzeitig aktiv und als persönlich oder gemeinsam gekennzeichnet.
- Jede Quelle besitzt eine eindeutige, vom Benutzer festgelegte Prioritätsnummer oder Position.
- Die effektive Reihenfolge wird zuerst nach dieser expliziten Reihenfolge und bei Gleichstand nach der Ebene bestimmt: persönliche Quellen vor gemeinsamen Quellen.
- Bei gleicher expliziter Aktions-ID wird ausschließlich die Aktion aus der zuerst priorisierten Quelle angezeigt.
- Eine Aktion ohne explizite ID kann keine Aktion mit expliziter ID ersetzen.
- Gleiche Anzeigenamen mit unterschiedlichen IDs bleiben verschiedene Aktionen und werden bei Bedarf mit Quellenangabe unterscheidbar gemacht.
- Eine ungültige Beschreibung darf andere Aktionen nicht blockieren; der Fehler muss nachvollziehbar sein.
- Nicht erreichbare Netzwerkquellen dürfen das Explorer-Menü nicht auf unbestimmte Zeit blockieren. Für die Erkennung gilt ein begrenztes Zeitlimit.
- Änderungen werden beim nächsten Öffnen des Kontextmenüs eingelesen. Ein begrenzter Metadaten-Cache darf nur verwendet werden, wenn die Quelle nicht rechtzeitig erreichbar ist; zwischengespeicherte Aktionen werden als möglicherweise veraltet behandelt.
- Vor der Ausführung werden Skript, Beschreibung, Quelle und Aktions-ID erneut geprüft, damit veraltete Menüeinträge nicht blind ausgeführt werden.
- Wird eine Aktion zwischen Anzeige und Ausführung entfernt oder geändert, wird sie nicht gestartet; der Benutzer erhält eine verständliche Meldung.

Quellverzeichnisse enthalten ausführbaren Code und werden bewusst konfiguriert. Die Menüerkennung liest ausschließlich Metadaten. Es gibt keinen dauerhaft laufenden PowerShell-Prozess nur zum Beobachten der Quellen.

## 7. Zielpfade und Konflikte

Der Explorer-Pfad wird als Kontext übergeben. Ein Aktionsstandard kann ihn ersetzen; der Benutzer kann das Ziel im Formular ändern. Der bestätigte Pfad wird vor dem Start geprüft und normalisiert.

Bei vorhandenem Zielnamen erscheint die vereinbarte Auswahl: abbrechen, umbenennen oder vorhandenen Ordner verwenden. „Vorhandenen Ordner verwenden“ ist keine pauschale Erlaubnis zum Überschreiben bestehender Dateien.

Dateikonflikte müssen ohne stillen Datenverlust behandelt werden. Standardmäßig bricht die Aktion bei einem Konflikt ab oder verwendet nach ausdrücklicher Bestätigung einen neuen Namen. Überschreiben ist nur zulässig, wenn die Aktion dies ausdrücklich beschreibt, der Benutzer es vor dem Start bestätigen kann und die betroffenen Dateien eindeutig angezeigt werden.

Pfade mit Leerzeichen, Umlauten und UNC-Freigaben müssen funktionieren. Pfadparameter werden als Daten übergeben und nicht in frei zusammengesetzte PowerShell-Befehle eingesetzt.

## 8. Technische Architektur

### Explorer-Erweiterung

Eine schlanke native Erweiterung erzeugt Menüeinträge und übergibt Aktionskennung, Quelle und Explorer-Pfad an den Ausführungsprozess. Sie führt keine fachliche Aktionslogik im Explorer-Prozess aus.

Für Windows 11 wird die Einbindung in das moderne Menü über IExplorerCommand und die dafür erforderliche Paket- oder COM-Registrierung prototypisch geprüft. Windows 10 verwendet den klassischen Kontextmenüpfad. Die direkte Anzeige im ersten Kontextmenü ist für beide Systeme ein Abnahmekriterium. Falls die direkte Anzeige unter einer unterstützten Windows-11-Version technisch nicht zuverlässig möglich ist, muss vor Implementierungsabschluss eine verbindliche Ersatzdarstellung festgelegt werden; eine bloße Anzeige im erweiterten Menü gilt dann nicht automatisch als erfüllt.

### Ausführungsprozess

Ein separater Prozess übernimmt Formular, Vorprüfung, Zusammenfassung, Fortschritt und den Start von Windows PowerShell 5.1. Seine Dialoge erscheinen nur nach Auswahl einer Aktion. Die Eingabe- und Zielregeln liegen getrennt von der Fensterdarstellung, damit sie ohne WinForms prüfbar sind.

### PowerShell-Aktionen

Die Aktionen führen die eigentliche Arbeit aus. SpawnNew übergibt mindestens Explorer-Kontext, bestätigten Zielpfad, Aktionsverzeichnis und Formularwerte über eine Kontextdatei.

Der gemeinsame Vertrag legt fest: Übergabeformat für Kontext und Formularwerte, Ausgabeformat für Fortschritt, Ergebnisstatus, Fehlerformat, Liste der erstellten Ressourcen, Abbruchverhalten, Verhalten bei Prozessbeendigung sowie Aufruf und Einschränkungen der Aufräumfunktion. Er steht in `docs/Aktionsvertrag.md`.

Administratorrechte werden ausschließlich für die angeforderte Ausführung angefordert. Es gibt keinen standardmäßig erhöhten Explorer und keinen dauerhaft erhöhten Hintergrundprozess. Eine abgelehnte Rechteabfrage führt zum Abbruch ohne anschließende fachliche Änderungen.

### Abgrenzung zu PowerToys

Es werden keine PowerToys-Binärdateien geändert. PowerToys-Updates überschreiben daher keine SpawnNew-Komponente. Neue Aktionen benötigen keine Neukompilierung der Explorer-Erweiterung.

## 9. Sprachmodelle und Geheimnisse

### Anbindung

Die KI-Anbindung ist optional. Ohne konfigurierten Endpunkt fehlt den Aktionen 17 bis 19 eine Voraussetzung, sie werden mit verständlicher Meldung nicht gestartet; alle übrigen Aktionen bleiben unberührt.

Angesprochen wird ein OpenAI-kompatibler Endpunkt. Damit sind lokale Laufzeiten wie Ollama und LM Studio sowie Webdienste mit demselben Schnittstellenformat über einen Weg erreichbar. Ein lokaler Endpunkt ist die Vorgabe, weil dabei kein Inhalt den Rechner verlässt; das ist für Protokolle mit Namen, Gremieninhalte und Logdateien die entscheidende Eigenschaft.

Je Endpunkt werden Basis-Adresse, Modellname, Zeitlimit und optional der Name eines Geheimnisses konfiguriert. Die Auswahl des Endpunkts ist Konfiguration, keine fachliche Aktion.

### Bestätigung der Ausgabe

Eine Modellausgabe ist nicht deterministisch und wird nie ohne ausdrückliche Bestätigung in eine Datei geschrieben. Dafür gibt es zwei zugelassene Wege:

- Der Vorschlag wird vor dem Schreiben erzeugt und erscheint in der Zusammenfassung aus Abschnitt 3 Schritt 6. Erst „Erstellen“ legt etwas an. So arbeitet Aktion 17.
- Die Aktion schreibt eine deutlich gekennzeichnete Entwurfsdatei und meldet sie als erstellte Ressource. So arbeiten Aktionen 18 und 19.

Eine Aktion darf eine vorhandene Datei nie mit Modellausgabe überschreiben, auch nicht bei bestätigter Überschreibungsregel.

### Geheimnisse

API-Schlüssel sind Geheimnisse und werden getrennt von Eingaben behandelt:

- Sie stehen nie in der Kontextdatei, im Fortschritt, im Protokoll oder in der Zusammenfassung.
- Sie werden benutzer- und rechnergebunden verschlüsselt im Benutzerdatenbereich abgelegt, getrennt von Programmdateien und Aktionen.
- Die Beschreibung einer Aktion nennt unter `secrets` nur den Namen eines Geheimnisses. Die Aktion holt den Wert selbst zur Laufzeit.
- Ein Formularfeld für ein Geheimnis wird maskiert dargestellt und nicht in die Zusammenfassung übernommen.
- Deinstallation und Aktualisierung löschen oder überschreiben gespeicherte Geheimnisse nicht.

Fehlt ein benötigtes Geheimnis, wird das wie eine fehlende Voraussetzung behandelt: verständliche Meldung, kein Start, keine automatische Einrichtung.

## 10. Fehler, Fortschritt und Aufräumen

- Fehler zeigen betroffenen Schritt, verständliche Ursache und technische Details bei Bedarf.
- Fachliche Ausgaben werden im Fortschrittsfenster gesammelt; vertrauliche Eingaben gehören nicht in Protokolle.
- Die Aktion meldet erstellte Ressourcen, soweit möglich.
- Eine Aufräumfunktion darf nur Ressourcen entfernen, die diese Ausführung selbst erstellt hat.
- Ohne Aufräumfunktion bleiben Teilergebnisse erhalten; die Meldung muss darauf hinweisen.
- Aufräumen ist keine allgemeine Transaktion und garantiert nicht, externe Änderungen vollständig rückgängig zu machen.
- Abbrechen während der Ausführung beendet die Aktion nur, wenn der Ausführungsvertrag dies unterstützt. Andernfalls wird der Abbruch als angefordert angezeigt, bis der Prozess beendet ist.
- Eine Prozessbeendigung darf nicht als erfolgreicher Rollback dargestellt werden.
- Nach einem Abbruch oder Fehler wird eindeutig zwischen „keine Änderungen“, „teilweise erstellt“, „erfolgreich erstellt“ und „Status unbekannt“ unterschieden.
- Ein nicht erreichbarer oder zu langsamer Modellendpunkt ist ein gewöhnlicher Fehler mit Schritt, Ursache und Zeitlimit in der Meldung.

## 11. Installation und Wartung

Installationsumfang: aktueller Benutzer oder alle Benutzer. Eine systemweite Installation benötigt administrative Rechte. Eine Benutzerinstallation darf ohne Administratorrechte erfolgen, sofern die gewählte Registrierungsart dies unterstützt; andernfalls wird die erforderliche Rechteanforderung vor der Installation angezeigt.

Für Installation und Aktualisierung wird jeweils ein konfigurierter Einzeiler bereitgestellt. Beide Befehle sind als eigene Menüeinträge im SpawnNew-Untermenü verfügbar:

- SpawnNew installieren
- SpawnNew aktualisieren

Vor der Ausführung zeigt SpawnNew den vollständigen Einzeiler, das Ziel und die erforderlichen Rechte an. Die Ausführung erfolgt erst nach ausdrücklicher Bestätigung. Einzeiler dürfen keine persönlichen Aktionen, Quellen, Konfigurationen oder Geheimnisse verändern oder löschen. Fehler werden mit dem ausgeführten Befehl, dem Rückgabestatus und verständlichen Details angezeigt.

Konfiguration, persönliche Aktionen und Geheimnisse werden von installierten Programmdateien getrennt. Ein SpawnNew-Update darf diese nicht überschreiben. Deinstallation entfernt die Menüregistrierung und SpawnNew-eigene Programmdateien; benutzereigene Aktionen, Quellen, Konfiguration und Geheimnisse bleiben standardmäßig erhalten. Der Benutzer muss vor der Deinstallation ausdrücklich über verbleibende Daten informiert werden.

Eine Möglichkeit zur Quellen- und Endpunktkonfiguration muss ohne eigenständigen Aktionsstarter erreichbar sein, beispielsweise über einen separaten Konfigurationsbefehl im SpawnNew-Untermenü oder über die installierte Anwendung. Die gewählte Darstellung und ihre Rechteanforderungen werden vor Implementierung festgelegt.

## 12. Entwicklungsregeln

- Minimaler, funktionaler Code; Windows-native APIs bevorzugen.
- Bestehende Dateinamen beibehalten; Implementierungsdateinamen vor dem ersten Code festlegen.
- Jede selbst erstellte Text-/Codedatei beginnt mit einem passenden Kommentar mit Dateiname und Version. Für JSON ein Format ohne Kommentare verwenden und die Version als Metadatum führen; keine ungültige JSON-Syntax einbauen.
- Höchstens 800 Zeilen und 20 kB pro Codedatei.
- Kompatibel mit deutschem Windows und Windows PowerShell 5.1.
- Skripte als UTF-8 mit BOM ausliefern; Austauschdateien zwischen Prozessen als UTF-8 ohne BOM.
- Keine Unicode-Emojis; Umlaute in Texten und Pfaden korrekt unterstützen.
- Dateien bei Änderungen vollständig neu schreiben und Namen beibehalten.
- Bei Fehlerbehebungen nur das konkrete Problem ändern.
- Ausführbare Einstiegspunkte mit Kurzdokumentation ausliefern.
- Aktionsskripte dürfen keine nicht dokumentierten globalen Seiteneffekte ausführen.
- Eingaben und Pfade müssen getrennt von ausführbarem Code übergeben werden.
- Installations- und Aktualisierungseinzeiler müssen dokumentiert, überprüfbar und vor der Ausführung bestätigungspflichtig sein.
- Regeln ohne Fensterdarstellung umsetzen, damit sie ohne WinForms prüfbar sind.
- Jeder Baustein wird zusammen mit seinen Tests geliefert.

## 13. Abnahme

1. SpawnNew erscheint direkt im ersten Kontextmenü unter Windows 10 und Windows 11, sofern die unterstützte Windows-Version die dafür festgelegte Registrierung unterstützt.
2. Neue Skripte und Aktionsordner erscheinen ohne Neubau der Anwendung.
3. Genau elf mitgelieferte Startaktionen funktionieren; zusätzliche benutzerdefinierte Aktionen werden getrennt davon geladen.
4. Persönliche Aktionen ersetzen gemeinsame ausschließlich anhand derselben expliziten ID und gemäß der festgelegten Quellenpriorität.
5. Formulare unterstützen Standardzielpfade, Änderungen und eine abschließende Zusammenfassung.
6. Fehlende Voraussetzungen führen zu einer verständlichen Meldung ohne automatische Installation.
7. Windows PowerShell 5.1 funktioniert standardmäßig und wird für alle Aktionen verwendet.
8. Normale Aktionen lösen keine Rechteabfrage aus; deklarierte erhöhte Aktionen behandeln Zustimmung und Ablehnung korrekt.
9. Bestehende Dateien werden nicht still überschrieben; Fehler und Teilergebnisse sind sichtbar.
10. Nicht erreichbare Quellen blockieren Explorer nicht dauerhaft und überschreiten das festgelegte Zeitlimit nicht.
11. Markdown- und Word-kompatible Ausgabe sowie eigene Dokumentvorlagen funktionieren ohne vorausgesetzte Word-Automatisierung für die reine Dateierzeugung; Platzhalter werden auch im Inhalt einer `.docx` ersetzt.
12. Installieren, Aktualisieren und Deinstallieren erhalten persönliche Aktionen, Konfiguration und Geheimnisse entsprechend den festgelegten Regeln.
13. Die Menüeinträge für Installation und Aktualisierung zeigen den Einzeiler vor der Ausführung an und führen ihn erst nach ausdrücklicher Bestätigung aus.
14. Eine zwischen Menüanzeige und Ausführung geänderte oder entfernte Aktion wird nicht blind ausgeführt.
15. Abbruch, Prozessbeendigung und Aufräumen unterscheiden zuverlässig zwischen keinem Ergebnis, Teilergebnis, Erfolg und unbekanntem Status.
16. Die elf mitgelieferten Aktionen verwenden eindeutige explizite IDs und sind in der Quellenauflösung nicht versehentlich durch automatisch erzeugte IDs ersetzbar.
17. Eine Vorlage mit deklarierten NTFS-Rechten erzeugt die Rechte tatsächlich und erbt sie nicht stillschweigend vom Elternordner.
18. Mit lokalem Endpunkt erzeugt eine KI-Aktion keinen Netzzugriff nach außen.
19. Ein API-Schlüssel erscheint zu keinem Zeitpunkt in Kontextdatei, Fortschritt, Protokoll oder Zusammenfassung.
20. Der Vorschlag von Aktion 17 erscheint in der Zusammenfassung; Abbrechen legt nichts an.
21. Die Aktionen 18 und 19 schreiben nur gekennzeichnete Entwurfsdateien und überschreiben keine vorhandene Datei.
22. Fehlt der konfigurierte Endpunkt oder ein benötigtes Geheimnis, meldet die Anwendung das verständlich und startet nicht; alle übrigen Aktionen bleiben nutzbar.
23. Das Öffnen des Kontextmenüs löst keinen Netzzugriff und keinen Modellaufruf aus.

## 14. Umsetzungsschritte

| Schritt | Inhalt | Stand |
|---|---|---|
| 1 | Dateinamen, Konfigurationsspeicher, Quellenpriorität, Aktions-ID-Regeln, Einzeiler, Schnittstellenverträge festlegen | fertig |
| 2 | Minimalen Explorer-Prototyp auf Windows 10 und 11 prüfen: Menüregistrierung, direkte Anzeige, Pfadübergabe | offen |
| 3 | Aktionsquellen, Prioritätsauflösung, IDs, Nachladen, Cache-Verhalten, Beschreibungsprüfung | fertig und geprüft |
| 4 | Einheitliche Formulare, Zusammenfassung, getrennter PowerShell-Start | fertig; WinForms auf Windows noch nicht erprobt |
| 5 | Fortschritt, Fehlerbehandlung, Rechte, optionale Aufräumfunktion | fertig; WinForms auf Windows noch nicht erprobt |
| 6 | Dokumenterzeugung mit Platzhaltern in Markdown und `.docx` | offen |
| 7 | KI-Anbindung Stufe 1: lokaler OpenAI-kompatibler Endpunkt, Voraussetzungsprüfung, Aktionen 17 bis 19 | offen |
| 8 | KI-Anbindung Stufe 2: Webendpunkt mit verschlüsselt gespeichertem Schlüssel | offen |
| 9 | NTFS-Rechte aus der Vorlage setzen | offen |
| 10 | Elf mitgelieferte Aktionen und Dokumentvorlagen liefern | offen |
| 11 | Installation, Aktualisierung, Konfigurationszugriff, Deinstallation | offen |
| 12 | Menüeinträge für Installation und Aktualisierung mit Bestätigung, Rückgabestatus, Fehleranzeige | offen |
| 13 | Abnahmekriterien auf Windows 10 und 11 mit erreichbaren und nicht erreichbaren Quellen prüfen | offen |

## 15. Name und Marktlage

Der Name SpawnNew ist ein Arbeitsname. Zwei Websuchen zeigten Verwendungen als Funktion, Befehl oder Startparameter, aber kein eindeutig identifiziertes eigenständiges Produkt gleichen Namens. Eine verbindliche Marken- oder Domainfreigabe liegt nicht vor.

Recherche zur Abgrenzung, Stand 26.10.2026. Alle Angaben aus Sekundärquellen; `learn.microsoft.com` war beim Prüfen nicht erreichbar.

| Werkzeug | Deckt ab | Deckt nicht ab |
|---|---|---|
| PowerToys New+ | Datei- und Ordnervorlagen im Kontextmenü, Variablen wie `$YYYY` und Elternordnername im Namen, ein Vorlagenpfad, optional OneDrive | Benutzer nach Werten fragen, Skripte ausführen, mehrere priorisierte Quellen, Platzhalter im Dateiinhalt, NTFS-Rechte. Die Anfrage nach einer Eingabe beim Anlegen wurde mit Verweis auf die Variablen geschlossen |
| DirTemplateExtension | Rechtsklick, Ordner einer Vorlagensammlung als Menüeinträge | Eingaben, Skripte, NTFS-Rechte |
| FolderCrafter | Ordnerbäume aus Textdefinition, Presets | erste Menüebene, Eingabeformular, Skripte |
| TortoiseGit | `Git Create Repository here`, bare oder normal | Gitignore-Vorlage, README, erster Commit in einem Schritt |
| DirCreator | Struktur mit Gruppen und ACLs | Kontextmenü |
| PSCommander | Kontextmenüeinträge, die PowerShell mit dem angeklickten Pfad ausführen | kostenpflichtige Lizenz, kein Quellen- und Vorlagenmodell, kein Formular- und Fortschrittsvertrag |
| Windows 11 AI actions | KI-Aktionen im Explorer für Bilder und einige Dokumenttypen | Copilot+-Hardware, Insider-Kanal, M365- und Copilot-Lizenz nötig; keine eigenen Prompts, kein eigenes Modell, kein Windows 10. Berichten zufolge nimmt Microsoft ab Mitte November 2026 acht dieser Aktionen aus dem Kontextmenü heraus |
| Ollama, LM Studio | lokale Modelle über OpenAI-kompatible Endpunkte | keine Explorer-Integration |
| ContextHelper | eigene Prompts, eigene Schlüssel, lokale Endpunkte | Chrome-Erweiterung, kein Explorer |

Kein gefundenes Werkzeug verbindet Explorer-Kontextmenü, beliebigen Dateityp, eigene Prompts, eigenes Modell lokal oder im Web und Windows 10. Genau diese Verbindung ist die Begründung für SpawnNew; reine Ordner- und Dateivorlagen deckt PowerToys New+ kostenlos ab.

Zur Architektur untersuchte PowerToys-Dateien auf dem veränderlichen main-Branch: Menüaufbau, Klick auf Vorlage, Zielpfad und Kopierablauf, Datei-/Ordnerkopie, Windows-10-Menühandler. Diese Stellen dienen als Architekturbezug. SpawnNew entsteht als eigenständige Erweiterung.
