# KickAssist

Kleines Addon zur Interrupt-Koordination in Mythic+ per Raid-Symbol. Jeder wählt sein Symbol, das Addon kümmert sich um Sync, Chat-Ansage und die passenden Makros.

## Installation

1. Ordner `KickAssist` (nicht einzelne Dateien) nach `World of Warcraft/_retail_/Interface/AddOns/` kopieren.
2. WoW starten bzw. am Charakterauswahlbildschirm unten links bei **AddOns** prüfen, dass "KickAssist" aktiviert ist.

## Einmaliges Setup (pro Charakter)

1. Im Spiel `/ka` eingeben – öffnet das Auswahlfenster.
2. Ein Symbol anklicken (nicht Kreuz/Totenkopf, die sind reserviert).
3. Unten im Fenster erscheinen zwei Icons ("Kick" und "Mark") – mit der Maus anklicken, halten und auf eine Aktionsleiste ziehen.
4. Fertig. Diese beiden Tasten bleiben jetzt bestehen und aktualisieren sich automatisch, auch wenn du später ein anderes Symbol wählst.

**Bequemer Zugang:** Statt `/ka` zu tippen, gibt es auch ein kleines Icon am Minimap-Rand zum Anklicken.

## Nutzung pro Dungeon

1. Vor dem Pull kurz absprechen, wer welches Symbol nimmt (das Fenster zeigt euch unten, wer schon was gewählt hat – bereits vergebene Symbole sind ausgegraut).
2. Dein Symbol per Klick (im Fenster oder Minimap-Icon) wählen. Das postet automatisch "Ich kicke [Symbol]" in den Party-Chat.
3. Im Kampf: Ziel anvisieren → **Mark**-Taste drücken (markiert das Ziel mit deinem Symbol und setzt es gleich als Fokus) → **Kick**-Taste drückt deinen Interrupt-Spell auf Fokus (bzw. aktuelles Ziel, falls kein Fokus gesetzt).
4. Symbol wechseln oder freigeben: einfach neu wählen, oder über den Button "Symbol freigeben" im Fenster. (Das Mark-Makro-Icon zeigt danach noch kurz das alte Symbol an, bis du neu wählst – das ist kein Fehler, nur kosmetisch, siehe unten.)

## Befehle

| Befehl | Wirkung |
|---|---|
| `/ka` | Auswahlfenster öffnen/schließen |
| `/ka <1-6>` | Symbol direkt setzen (1=Stern, 2=Kreis, 3=Diamant, 4=Dreieck, 5=Mond, 6=Quadrat) |
| `/ka clear` | Eigenes Symbol freigeben |
| `/ka minimap` | Minimap-Icon ein-/ausblenden |

## Bekannte Einschränkungen

- Funktioniert nur innerhalb einer Gruppe (Party/Raid) – Sync braucht eine Gruppe.
- Nach "Symbol freigeben" bleibt das Mark-Makro (Icon und Funktion) auf dem zuletzt gewählten Symbol stehen, statt sich zurückzusetzen. Das ist bewusst so und **kein Fehler**: Das Makro wird einfach erst beim nächsten Wählen eines Symbols neu geschrieben. Bis dahin würde das Makro, falls du es trotzdem drückst, noch mit deinem alten Symbol markieren.
- Nach großen WoW-Patches kann eine Fehlermeldung "inkompatibel" auftauchen – dann bei den AddOns die Option "Nicht aktualisierte AddOns laden" aktivieren, bis eine neue Version kommt.
- Eine Interrupt-Zählung (`/ka stats`) wurde ausprobiert, musste aber wieder entfernt werden: Blizzard hat das Mitlesen des Combat-Logs für Addons in diesem Patch gesperrt (Teil der "Midnight"-Einschränkungen gegen kampfrelevante Addon-Funktionen).

## Fragen / Probleme

Bei Fehlern (Chatausgabe in Rot, "Message: ...") einfach den Text an Dober weiterleiten.
