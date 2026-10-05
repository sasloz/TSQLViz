# Charts und Textlayout (`0.1.0-s5a`)

`dist/install.sql` installiert Core und Charts gemeinsam in einer Transaktion.
Alternativ zuerst `dist/install-core.sql`, danach `dist/install-charts.sql` ausführen.
Die vorhandene Version `0.1.0-s2` wird ohne Austausch der bestehenden `_v1`-Typen
aktualisiert. Andere ältere Versionen benötigen eine eigene Migration.

## Kontext ab S5a

Alle Charts ergänzen `@Context viz.Context_v1 READONLY` und `@ItemLabels viz.ItemLabel_v1 READONLY`. Bubble ergänzt `@View='detail'`. Die [vollständigen Verträge](../../docs/data-contracts.md) erklären Pflichtfelder, statische Detailseiten und Fehler. Maximal acht Bubble-Detailzeilen; Überblick bis 200 Marken. Der Kontextbereich erweitert die Scene unterhalb des Plots; `@Height` bleibt die Höhe des Plots. Texte behalten Größe 18 und werden vollständig umgebrochen.

Die nachfolgenden Minimalaufrufe und `@ShowIds` bleiben verwendbar, liefern alleine aber keine vollständige Erklärung und Einzelzuordnung. Neue Ansichten sollen wie die [vollständigen Beispiele](../../examples/synthetic/03-workload.sql) Kontext und Kennzeichen mitliefern. Die [Validierungsübersicht](../../docs/validation.md) beschreibt die noch offenen Lesbarkeitsprobleme.

## Aufrufe

Alle Charts geben genau `Scene_v1` zurück. `@Data` ist READONLY. Gemeinsame Optionen:
`@Title nvarchar(max)`, `@Subtitle nvarchar(max)=NULL`, `@Width float=1000`,
`@Height float=600`. Die fachlichen Textlimits bleiben 100/200 Zeichen; der breite
SQL-Parametertyp erlaubt eine Prüfung vor Trunkierung.

| Prozedur | Dataset | Weitere Optionen und Defaults |
|---|---|---|
| `viz.BarChart` | `CategoryValue_v1` | `@ValueLabel=N'Value'`, `@ValueFormat='number'`, `@ValueMin=NULL`, `@ValueMax=NULL` |
| `viz.LineChart` | `XY_v1` | `@XKind='number'`, `@XLabel=N'X'`, `@YLabel=N'Y'`, `@XFormat='number'`, `@YFormat='number'`, `@XMin/@XMax/@YMin/@YMax=NULL` |
| `viz.BubbleChart` | `XY_v1` | `@XLabel=N'X'`, `@YLabel=N'Y'`, `@SizeLabel=N'Size'`, `@XFormat/@YFormat/@SizeFormat='number'`, `@XScale/@YScale='linear'`, `@XMin/@XMax/@YMin/@YMax=NULL`, `@SizeMode='area'`, `@ShowIds=0` |

Achsentitel werden als `nvarchar(max)` angenommen und auf 60 Zeichen begrenzt.
Domains und Canvasgrößen sind `float`, Formate `varchar(24)`, Skalen/Modi
`varchar(12)`, `@ShowIds` ist `bit`. Standardtitel: `Bar chart`, `Line chart`,
`Bubble chart`.

Bar zeichnet positive und negative Rechtecke ab 0 und markiert beobachtete Nullen
mit einem Kreuz plus `0`. NULL erzeugt einen sichtbaren Fehlend-Zähler. Die erste
Kategorie steht oben. Maximal 20 Kategorien einschließlich fehlender Werte.

Line verbindet die Punktreihenfolge je Serie; NULL-Y unterbricht sie. Wiederholtes
X ist zulässig, sinkendes X nicht. Einzelpunkte erscheinen als Kreis. Linien werden
um 0,8 Canvas-Einheiten verbreitert. Teilstücke enthalten zunächst höchstens 128
aufeinanderfolgende Vertices; zu große Shapes werden weiter geteilt. Benachbarte
Teilstücke teilen einen Endpunkt, jede Beobachtung bleibt erhalten. Endlabels
werden um höchstens 96 Einheiten verschoben, mit mindestens 24 Einheiten Abstand.
Bei nicht lösbaren Kollisionen folgt `51000`.

Zeitachsen verlangen `@XKind='time', @XFormat='utc-time'`. X enthält ganzzahlige
UTC-Millisekunden seit 2000-01-01. Der Achsentitel nennt UTC und den Datumsbereich;
bei Tageswechsel zeigen Ticks Monat/Tag und Uhrzeit, bei Subsekunden Millisekunden.

Bubble verwendet `r=24*sqrt(SizeValue/Maximum)`. Gleiche Werte ergeben gleiche
Fläche. Die Legende zeigt Maximum, Viertel und Sechzehntel. Nullgröße ist ein Kreuz,
fehlende Größe wird gezählt. Scatter (`@SizeMode='constant'`) verwendet Radius 4
und ignoriert SizeValue vollständig. Positive Logachsen verwenden Basis 10.
Maximal 200 sichtbare Beobachtungen; große Bubbles werden zuerst ausgegeben.
Im alten Modus ohne Kontext tragen bei mehreren Serien Legende und Marks dieselben Seriennummern.
`@ShowIds=1` beschriftet höchstens die zehn größten Marks; zu wenig Platz oder
überlappende ID-Texte ergeben einen Layoutfehler.

## Komposition

```sql
DECLARE @Data viz.CategoryValue_v1, @Scene viz.Scene_v1;
INSERT @Data VALUES(N'a',N'a',N'Example',1,N'value',N'Value',1,7,NULL);
INSERT @Scene EXEC viz.BarChart @Data=@Data;
INSERT @Scene VALUES(30,999,N'own:point','mark',NULL,NULL,N'Own point',viz.Point(900,450));
EXEC viz.RenderScene @Scene=@Scene;
```

Es gibt kein internes `INSERT EXEC`, keine globalen Temp-Tabellen und keine
Quellabfragen. Eigene ElementKeys müssen mit den vorhandenen Keys konfliktfrei
sein. Öffentliche Helfer und Charts sind mit `viz_user` ausführbar.

## Text und Layouthelfer

Der gemeinsame Font verwendet etwas mehr Zeichenabstand: bei Größe 18/24 rund 7 % mehr Laufweite,
bei sehr kleiner Schrift einen Mindestabstand zwischen den verbreiterten Strichen. `Text`, `MeasureText`,
`FitText` und `TextRows` verwenden dafür denselben internen Helfer `TextAdvance`.
Die Layouthelfer berücksichtigen die größere Breite automatisch. [Prüfstand und bekannte Grenzen](../../docs/validation.md).

| Helfer | Vertrag |
|---|---|
| `MeasureText(text,size)` | Width, Height, DisplayText, WasSubstituted; Größe 6..40, inklusive 0,75 Strichrand je Seite |
| `Text(text,x,y,size,rotation)` | Verbreiterte Original-Strokes; Radiant um die linke untere Basis; leerer Text → NULL |
| `TextRows(text,x,y,size,rotation)` | ChunkOrder, Characters, Shape; normalerweise 24 Zeichen je Teil, adaptiv innerhalb 32.000 Bytes |
| `FitText(text,size,width,maxCharacters)` | Gezeichneter Text mit `...` bei Platzmangel; vollständige Quelle separat in Label erhalten |
| `FormatNumber(value,format,decimals)` | `number`, `compact`, `integer`, `percent`, `duration-ms`, `bytes-iec`; 0..6 Stellen, ohne überflüssige Nullen |
| `FormatTime(epoch,format)` | `utc-time`, `utc-date`, `utc-datetime`; UTC ohne Zeitzonenheuristik |
| `Canvas(width,height)` | Eine ungefüllte Rahmenlinie im Scene-Schema |
| `AxisTicks(min,max,start,end,scale,format)` | TickOrder, Position, Label; lineare/Log-/UTC-Ticks; bei `duration-ms` und `bytes-iec` Ticks auf Uhr- bzw. Zweierpotenzschritten; bis sechs Dezimalstellen für eindeutige Zahlenlabels |
| `AxisBottom(ticks,start,end,cross,gridEnd,prefix)` | Scene-Zeilen für X-Achse, Tickstriche, Grid und verbreiterte Ticktexte |
| `AxisLeft(ticks,start,end,cross,gridEnd,prefix)` | Entsprechender Y-Achsenhelfer |

`ticks` ist `viz.Tick_v1`: `TickOrder int PRIMARY KEY`, `Position float`,
`Label nvarchar(400)`, alle NOT NULL. Positionen sind bereits gemappte
Canvas-Koordinaten und müssen in TickOrder strikt steigen. 2..12 Ticks sind
zulässig. `start/end/cross/gridEnd` sind float, `prefix` ist nvarchar(100).
Ein eindeutiger Prefix verhindert ElementKey-Kollisionen zwischen Achsen.
Achsen behalten erste und letzte Labels und dünnen innere Labels aus. Können
zwei Randlabels nicht passen, liefert der TVF keine Zeilen; Charts melden `51000`.

Direkte Texthelfer akzeptieren bis 1.200 UTF-16-Codeeinheiten, damit Expansionen
eines 400-Zeichen-Labels nicht abgeschnitten werden. Leerzeichen behalten Vorschub.
Textmessung liefert eine konservative Box; leere Eingabe hat Breite/Höhe 0.
Ungültige Skalarargumente ergeben NULL, ungültige TVF-Argumente keine Zeilen.
Unbekannte Unicode-Codepoints werden einzeln ersetzt. Die 83 sichtbaren Glyphen
sind im [Originalatlas](../core/text/font-data.sql) selbst entworfen; Leerzeichen
benötigt keinen Datensatz.

Line reserviert rechts 190
Einheiten für Endlabels. Bubble reserviert oben 225 für zwei Serienzeilen und
Größenlegende; Scatter 160. Canvas/Plot-Mindestmaße und Labelboxen werden geprüft.
Es gibt keine automatische Verkleinerung, Auswahl von Top-N oder Datenreduktion.

## Build, Prüfung und Deinstallation

```powershell
./tools/build.ps1
./tools/build-charts.ps1
./tools/test-charts.ps1 -Performance
./tools/test-charts.ps1 -Image mcr.microsoft.com/mssql/server:2017-latest -CompatibilityLevel 140
```

Der Runner verwendet vorhandene Docker-Images und räumt ausschließlich seinen
eigenen Laborcontainer auf. Ein übergebener `-RunId` bleibt für SSMS geöffnet.
SQL-Nachweise und SSMS-Sichtbefunde werden getrennt dokumentiert.

Zum Entfernen zuerst `dist/uninstall-charts.sql`, danach bei Bedarf
`dist/uninstall-core.sql` ausführen. Fremde SQL-Abhängigkeiten verhindern die
Deinstallation. Quelltabellen und Datenbank bleiben erhalten.
