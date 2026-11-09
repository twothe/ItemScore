# ItemScore für WoW Forever

Stand: 5.0.0, Interface 16001. Release-Paket lokal vorbereitet. Im Spiel bestätigt: Suche beendet sich, nachgeladene Dungeon-Items erscheinen und Vergleichstooltips verursachen den gemeldeten Fehler nicht mehr. Die vollständige Prüfliste unten bleibt für weitere Abnahmetests erhalten; nicht alle Punkte wurden im Spiel bestätigt.

## Änderungen

- Die Mindestgrenze von 5 Score-Punkten entfällt. Die Slot-Suche sortiert auch Items mit Score 0 oder negativem Score. Tooltips zeigen die Werte aktivierter Profile ebenfalls ohne positive Mindestgrenze.
- LootCollector, beide alten AtlasLoot-Anbindungen, Ascension-Itemabfragen, Ersatz-IDs, Worldforged-, Mythic-/Ascended- und Erweiterungsfilter wurden entfernt.
- AtlasLoot Forever liefert den Katalog. Quellen lassen sich einzeln oder gemeinsam unter `/itemscore` → Loot Sources wählen.
- Item-Attribute kommen ausschließlich aus `C_Item`. Ein unbekanntes Item wird nicht durch ein vermeintlich ähnliches Item ersetzt.
- Einstellungen und Tooltips verwenden die Forever-Schnittstellen von Blizzard.

Vorhandene Profile, Gewichte und Profilfilter bleiben erhalten. Alte Quelleneinstellungen werden durch eine definierte Auswahl der weiterhin gültigen Felder ersetzt; alte Kataloge werden verworfen. Die neuen Quellenauswahlen beginnen aktiviert. Die maximale Gegenstandsstufe zum Anlegen bleibt ein optionaler Filter (0 bis 60).

## Nachladen und Score 0

Die alte Abfrage wartete pauschal 1,5 Sekunden und fragte bei bekanntem Namen, aber fehlenden Attributen, nicht erneut an. Jetzt werden fehlende Daten mit `C_Item.RequestLoadItemDataByID` angefordert. `ITEM_DATA_LOAD_RESULT` und `GET_ITEM_INFO_RECEIVED` sowie die Kontrolle noch laufender Anfragen erkennen nachgeladene Daten.

Pro Item erfolgen höchstens zwei Anfragen innerhalb einer Runde, mit acht Sekunden Wartezeit je Anfrage. Pro 0,1 Sekunden werden höchstens 40 Anfragen gestartet. Nach fünf Minuten kann eine erneute Suche eine neue Runde anstoßen. Ein Neuladen der Oberfläche setzt diese sitzungsbezogenen Grenzen zurück. Späte erfolgreiche Ladeereignisse werden auch nach einem Timeout verarbeitet.

Die offene Suche wird nach Abschluss laufender Abfragen erneut ausgewertet; Ladeereignisse werden dabei zusammengefasst. Auch die zwischengespeicherten Scores angelegter Items werden ungültig. Ein fehlender Wert bleibt bis zur Verfügbarkeit 0. Eine vorhandene, leere Attributtabelle ist dagegen ein gültiges Ergebnis und löst keine Nachladeschleife aus.

Erfolgreich gelesene Namen, Slots und Attribute werden für die laufende Sitzung in ItemScore aufbewahrt. Die Clientdiagnose zeigte bei Ragefire erfolgreiche Ladeereignisse und vollständige Daten, die bei der späteren Suche wieder aus dem Client-Cache fehlten. Suche, Bewertung und Slotprüfung verwenden deshalb gemeinsame Lesezugriffe mit Sitzungsspeicher. Neue Clientdaten haben Vorrang; unbekannte Daten werden nicht ergänzt. Vollständige Itemstrings bleiben getrennt, damit Varianten keine Attribute des Basisitems übernehmen. `/reload` leert diesen Sitzungsspeicher.

Ohne Namen und Slot kann ein Item noch keiner Slot-Liste zugeordnet werden. Es bleibt im Katalog und wird nach dem Laden aufgenommen. Ist die Identität bereits vorhanden, fehlen aber Attribute, kann es mit Score 0 erscheinen. Blizzard unterscheidet über diese Schnittstelle nicht zuverlässig zwischen noch nicht veröffentlichten, ungültigen und vorübergehend nicht verfügbaren IDs. Deshalb werden keine IDs dauerhaft ausgeschlossen. Ein vorläufiger Score 0 ist kein Beleg für die tatsächliche Qualität eines Items.

## Adapter und Datenfluss

`ItemScoreSourceAtlasLoot.lua` ist die einzige Datei, die das AtlasLoot-Datenformat kennt. Ihr Vertrag:

- `IsAvailable`, `GetVersion` und `GetIdentity` beschreiben den verfügbaren Anbieter und seine Datenversion.
- `Scan(disabledSources, emitChoice, emitItem, checkpoint)` liefert Quellenauswahlen sowie Item-IDs mit Fundorten. `checkpoint` ermöglicht die Verteilung über mehrere Frames.
- Quellen haben stabile Schlüssel aus Modul- und Inhaltskennung. Übersetzte Namen sind reine Anzeige.
- Die aktuelle Implementierung verwendet `Loader:GetLootModuleList`, `ItemDB:GetModuleList` und `ItemDB:GetItemTable`.
- Item-, Rezept- und Set-Einträge werden getrennt behandelt. Fraktionsvarianten, numerische Tabellenverweise, ergänzte Tabellen und verlinkte Boss-Tabellen werden aufgelöst. Ein Rezept liefert sein hergestelltes Item; eine Set-ID liefert die zugehörigen Item-IDs.
- Unerwartete Formate erzeugen eine sichtbare Fehlermeldung. Es wird kein unvollständiger Import als gültiger Katalog veröffentlicht.

`ItemScoreSources.lua` verwaltet Auswahl, Migration und den vollständigen Austausch des Katalogs. Die Gültigkeit hängt von Adapterrevision, AtlasLoot-/Modulversionen, aktiven Modulen, Sprache, Fraktion und Quellenauswahl ab. Änderungen während eines Imports verwerfen dessen Zwischenergebnis. In Kämpfen wird der Import pausiert beziehungsweise bis zum Kampfende zurückgestellt.

Bei AtlasLoot-Änderungen zuerst den Adapter und seine Integrationstests anpassen. Die Adapterrevision bei Änderungen am Importer erhöhen; die Cache-Schemaversion nur bei Änderungen des gespeicherten Formats erhöhen. Item-Attribute und Scores werden nicht im Quellenkatalog gespeichert.

## Prüfung

Entwicklungsabhängigkeit: Python mit `lupa` (Lua-5.1-Laufzeit). Im ItemScore-Verzeichnis:

```powershell
python -m pip install lupa
python tests/run.py
```

Alternativ nimmt `--atlasloot-root` den Pfad des AddOns-Verzeichnisses entgegen. Die Tests laden die echten ItemScore-Dateien und die installierte AtlasLoot-Datenbank. WoW-Client- und reine Darstellungsschnittstellen werden simuliert; die Import-, Bewertungs- und Suchlogik stammt aus dem produktiven Code.

Geprüft wurden:

- Lua-5.1-Syntax und Laden aller TOC-Dateien;
- Scores unter 5, 0 und negative Werte in der Slot-Suche;
- fehlende Namen und Attribute, Ladeerfolg, Fehlschlag, Timeout, späte Erfolge und erneute Anfragen nach Ablauf der Wartefrist;
- Neubewertung angelegter Ausrüstung nach dem Laden;
- Profilübernahme, Entfernen alter Quellenfelder und Cache-Neuaufbau;
- atomare Veröffentlichung, Änderungen während eines Imports, Quellenauswahl und Zurückstellung im Kampf;
- Konstruktion der Einstellungsseiten im simulierten Client und lokalisierte Rüstungs-/Waffenfilter über die Client-API;
- AtlasLoot Forever v1.3.4: 5.572 eindeutige Item-IDs, 7.401 Fundortzuordnungen und 99 auswählbare Quellen in der Alliance-/Classic-Phase-6-Testumgebung;
- zusätzliche Vertragsfälle für Fraktionsersetzungen, Sets, Rezepte, Verweise, Erweiterungsfilter und nicht unterstützte Schemaänderungen.

Die absichtlich erzeugte Meldung `test schema change` gehört zur Prüfung eines fehlgeschlagenen Imports.

## Freigabe im Spiel

1. `/reload`, danach `/itemscore`: bestehende Profile und Gewichte kontrollieren; ein Profil bearbeiten, hinzufügen und löschen. Nach erneutem `/reload` Speicherung prüfen.
2. Loot Sources öffnen, Katalog aktualisieren, eine Quelle ausschalten und wieder einschalten. `/is status` darf danach keinen Importfehler melden.
3. Mit `/is` einen Slot und ein Profil wählen. Einen bekannten Gegenstand manuell anhand seiner Attribute nachrechnen; ein Profil ohne Gewichte muss Score-0-Ergebnisse zeigen.
4. Bei einer noch nicht im Client-Cache vorhandenen, aber verfügbaren ID prüfen, dass die Ergebnisse nach dem Laden ohne erneuten Klick aktualisiert werden. Eine weiterhin nicht verfügbare ID darf keine Dauerschleife verursachen.
5. Suche mit angelegten Items vergleichen, Shift-Vergleichstooltips, Fenstergröße und Quellenauswahl prüfen. Einen im Kampf angeforderten Import nach Kampfende kontrollieren.
6. Vor Veröffentlichung die verbleibenden Abnahmetests durchführen. Das vorbereitete Paket wurde nicht veröffentlicht.

## Grenzen der Bewertung

„Max Lvl“ filtert ausschließlich das vom Client gemeldete benötigte Charakterlevel zum Anlegen, nicht das Itemlevel oder die Erhältlichkeit. Items ohne eigene Levelanforderung passieren diesen Filter auch dann, wenn sie aus hochstufigen Quests stammen. Quest-, Ruf- und Zugangsvoraussetzungen werden nicht abgeleitet.


Die Suche ermittelt die besten Einzelitems gemäß den eingetragenen linearen Gewichten. Sie ist kein vollständiger Ausrüstungs- oder Kampfsimulator: Procs, Setboni, Treffergrenzen, Unique-Equip-Kombinationen und Wechselwirkungen zwischen Slots werden nicht optimiert. Die bisherige Halbierung des Scores von Zweihandwaffen bleibt erhalten. Die Slot-Suche zeigt bis zu 20 Ergebnisse; die Upgrade-Ansicht bis zu sechs pro Slot und nur Verbesserungen gegenüber der angelegten Ausrüstung. Armor-/Klassen- und Profilfilter ersetzen keine vollständige Prüfung aller erlernbaren Waffenfertigkeiten.

Die automatisierten Tests belegen keine echte WoW-Darstellung und keine serverseitige Verfügbarkeit der gelisteten Items.

## Referenzen

- [Blizzards Item-API im Forever-UI-Quellcode](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)
- [Blizzards Tooltip-Verarbeitung im Forever-UI-Quellcode](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)
- [Blizzards Settings-Registrierung im Forever-UI-Quellcode](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua)
- Installierte AtlasLoot-Quellen: `AtlasLootClassic/ItemDB/ItemDB.lua`, `Loader.lua`, `Constants.lua`, `Data/Profession.lua`, `Data/ItemSet.lua` und die fünf Lootmodule.
