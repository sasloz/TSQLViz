# Lokale Nachweise

`tools/lab.ps1 Start` erzeugt pro Lauf ein Verzeichnis mit einem Manifest ohne Passwort.
`Test` ergänzt SQL-Logs und `sql-tests.json`. Screenshots und `capabilities.md` werden
beim SSMS-Test in demselben Verzeichnis abgelegt. Laufartefakte sind standardmäßig
von Git ausgenommen; eine kuratierte Zusammenfassung gehört nach `tests/visual/`.

`passed` bei SQL bestätigt keine sichtbare Darstellung. Die visuelle Abnahme wird
separat mit SSMS-Build, Fenstergröße, Skalierung und Fixture dokumentiert.

S5 verwendet `tools/test-frk.ps1` und speichert `frk-tests.json`, ausgeführte SQL-Dateien,
kompakte Scene-Messwerte, Orakel und Source-Hashes. `-RealCapture` lädt die gepinnte FRK-Datei
in das ignorierte Laufverzeichnis. `tools/save-frk-evidence.ps1 -RunId ...` prüft Runtime-Hashes
und kopiert Testlogs/Metadaten nach `tests/evidence/s5`, ohne den Upstream-Code mitzukopieren.

Der S5-Runner verwendet standardmäßig `System.Data.SqlClient` über `tools/lab-sql-client.ps1`.
`frk-client.json` hält die Clientwahl fest; ältere Läufe ohne diese Datei verwendeten den Container-`sqlcmd`.
`-SqlClient sqlcmd` aktiviert diesen Pfad ausdrücklich. Der .NET-Runner erwartet kompakte Resultsets;
Scene-Ausgaben werden im Test in einem TVP erfasst und als Messwerte ausgegeben. SSMS erhält weiterhin
das vollständige Scene-Resultset aus den unveränderten Beispielen.
