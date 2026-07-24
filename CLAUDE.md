# CLAUDE.md

Leitfaden für die Arbeit an diesem Repository. Kurz halten, Fakten prüfen, nichts raten.

## Was das ist

LoxBerry-Plugin (Plugin-Interface **2.0**), das **Homebridge** + **homebridge-config-ui-x**
auf einem LoxBerry (Raspberry Pi / Debian, arm64/armv7/x64) installiert und als systemd-Dienst
betreibt. Homebridge läuft in einem **isolierten Node.js**, nicht im System-Node.

Kein Anwendungscode im klassischen Sinn – das Plugin besteht aus **Bash-Installationsskripten**,
einem CGI-Webfrontend (Perl/`index.cgi`) und HTML-Templates.

## Ablauf der Installation/Updates (wichtig!)

LoxBerry-Hook-Reihenfolge bei einem **Update**:
`preroot` (root) → **alte Plugin-Ordner werden gelöscht** → `preinstall` → Dateien kopieren →
`postinstall` → `postroot` (root).

(Es gibt kein `preupgrade.sh` mehr – die Config-Sicherung läuft komplett in `preroot.sh`, weil
das robuster ist: `preroot` läuft garantiert als root und garantiert vor dem Löschen, bei Install
*und* Update gleichermaßen.)

Daraus folgt die zentrale Design-Entscheidung: Der Config-Ordner wird beim Update gelöscht,
**bevor** `postroot` läuft. Deshalb:

- **`preroot.sh`** (root, vor dem Löschen, bei Install *und* Update), 3 Schritte:
  1. Homebridge stoppen (`systemctl stop homebridge.service`) + Port **8082** freigeben
     (Fallback `fuser`/`ss`/`lsof`, sanft dann SIGKILL).
  2. Config sichern nach `data/system/tmp/homebridge_config_backup/backup_<ts>` (rotiert, letzte 5).
  3. Überbleibsel der **allerersten** Plugin-Version entfernen, falls vorhanden: die hat Homebridge
     + config-ui-x per `npm install -g` systemweit installiert (`/usr/local/lib/node_modules/homebridge`,
     `/usr/local/lib/node_modules/homebridge-config-ui-x`, `/usr/local/bin/homebridge`,
     `/usr/local/bin/hb-service`). Sonst bleibt das als Leiche liegen und Homebridge meldet
     „Multiple instances of Homebridge were found". Rührt **nicht** an System-Node/npm selbst.
- **`postroot.sh`** (root, nach dem Löschen), 5 Schritte:
  1. Config aus dem preroot-Backup wiederherstellen.
  2. Homebridge-/Node-Version ermitteln (via `curl` an die npm-Registry; Node-Major aus `engines.node`, Fallback 22).
  3. Isoliertes Node.js in die **persistente Runtime** einrichten (nur bei anderer Version neu).
  4. Homebridge + config-ui-x installieren/aktualisieren (**Skip**, wenn Node unverändert *und* beide aktuell).
  5. `hb-service` registrieren (immer uninstall+install, **danach zwingend PATH-Fix in der Unit** – siehe unten).
- **`uninstall/uninstall`** (root): Dienst + Unit entfernen, Config-Backups + persistente Runtime löschen.

### Kritisch: `hb-service install` erzeugt eine Unit ohne `Environment=PATH=`

`hb-service ... install` schreibt `/etc/systemd/system/homebridge.service` **ohne eigenes
`Environment=PATH=`**. `ExecStart` ruft die `.js`-Datei direkt auf (`#!/usr/bin/env node`-Shebang) –
die Node-Auflösung passiert dadurch zur **Laufzeit über systemds Standard-PATH**, nicht über
irgendeinen PATH, den `postroot.sh` waihrend der Installation gesetzt hatte.

Auf LoxBerry 4 (Debian trixie) liegt unter `/usr/local/bin/node` ein **eigenes, viel neueres**
System-Node (z. B. v26), das in diesem Standard-PATH **vor** unserer isolierten Runtime gefunden
wird. Folge: Die Config-UI läuft mit der falschen Node-Version, natives `node-pty` (ABI-gebunden,
kompiliert für unser Node 22 beim `npm install`) lässt sich nicht laden
(`Cannot find module '../build/Release/pty.node'`), die Weboberfläche crasht in einer
**Restart-Schleife** (`journalctl` zeigt hochlaufenden „restart counter", ohne erkennbaren Fehler –
der eigentliche Stack-Trace steht nicht im Journal, sondern in
`$HB_STORAGE_DIR/homebridge.log`!). Die reine HAP-Bridge (Homebridge-Kern) läuft davon unbeeindruckt
auf einem eigenen Port weiter – das täuscht im Log Erfolg vor, obwohl Port 8082 nie erreichbar ist.

**Fix** ([postroot.sh](postroot.sh), direkt nach `hb-service ... install`): Die generierte Unit wird
per `sed` um `Environment=PATH=$HB_NODE_DIR/bin:$HB_NPM_GLOBAL/bin:<Standard-PATH>` ergänzt (idempotent
– alte Zeile wird vorher entfernt), dann `daemon-reload` + `restart`. Muss bei **jedem** Lauf erneut
passieren, weil `hb-service install` die Unit jedes Mal neu schreibt (auch bei jedem Plugin-Update).
Scope ist strikt auf diese eine Unit begrenzt (`Environment=` in einer systemd-Unit wirkt nie auf
andere Units/Plugins/Shells).

Debugging-Weg, falls das je wieder auftaucht: `systemctl status homebridge.service` (Restart-Counter?)
→ `journalctl -u homebridge.service -n 100` (zeigt nur „Storage/Config/Log path"-Debug-Zeilen, keinen
Fehler) → **`tail -n 100 $HB_STORAGE_DIR/homebridge.log`** (zeigt den echten Stack-Trace) →
`sudo -u loxberry <isoliertes-node> -v` testen. Journal reicht hier NICHT aus, das eigentliche
Fehlerbild steckt in homebridge.log.

**Das System-Node wird NICHT angefasst** (kein Entfernen, kein apt-Install). Homebridge nutzt
ausschließlich das isolierte Node der persistenten Runtime. (Eine frühere Fassung hat versucht,
„fremdes" Node unter `/usr/local` zu entfernen – das ist raus, weil LoxBerry 4 selbst ein Node
dort ablegen kann, das andere Komponenten brauchen.)

## Feste Pfade / Invarianten

- Config/Pairings: **`/opt/loxberry/config/plugins/homebridge`** (`$LBPCONFIG/$PDIR`) – historisch fest,
  wird bei Updates gelöscht → Backup/Restore über preroot/postroot.
- Persistente Runtime: **`/opt/loxberry/data/system/homebridge_runtime`** (`nodejs/` + `npm-global/`) –
  liegt außerhalb der Plugin-Ordner, überlebt Updates, muss vom `uninstall` selbst gelöscht werden.
- Config-Backups: `data/system/tmp/homebridge_config_backup/`.
- systemd-Unit: **`homebridge.service`**, UI-Port **8082**, User **loxberry**.

Alles unter `data/system/` überlebt Updates; Plugin-Ordner (`config/plugins/…`, `data/plugins/…`,
`bin/plugins/…`) werden bei jedem Update gelöscht.

**Frühe Entwicklungsstände** (nie released) haben die Runtime versehentlich in
`data/plugins/homebridge/nodejs` bzw. `/npm-global` abgelegt – root-eigen, innerhalb eines
Plugin-Ordners. Das führt beim Update zu tausenden „permission denied", weil LoxBerry diesen
Ordner als User `loxberry` löscht. Betrifft nur Testsysteme mit diesem Zwischenstand, kein
Cleanup dafür im Code (bewusst, da nie released – manuell per `rm -rf` auf dem betroffenen
System beheben).

## Kompatibilität mit Altinstallationen (nicht zerschießen!)

Das alte, released Plugin (vor 2026, Commit `a77a16e`) nutzte **System-Node** (`n stable`,
`/usr/local/...`) und installierte Homebridge + config-ui-x systemweit per `npm install -g`,
aber mit demselben `hb-service`-Aufruf: gleiche Unit, gleicher Storage-Pfad, Port 8082, User
loxberry. preroot-Schritt 3 räumt genau diese alte, systemweite npm-Installation weg (siehe oben).

Beim Übergang alt→neu registriert postroot-Schritt 5 den Dienst **immer neu** (uninstall +
install unter isoliertem Node statt nur `restart`), damit die Unit nicht mehr auf ein fremdes/
gelöschtes Node zeigt.

## Konventionen / Fallstricke

- **Zeilenenden: nur LF.** `.gitattributes` erzwingt das. `.sh` mit CRLF brechen auf Linux.
- `postroot.sh` läuft mit **`set -e`** – Command-Substitutions/`wait` entsprechend absichern
  (`VAR=0; cmd || VAR=$?`), sonst bricht das Skript unbeabsichtigt ab.
- Versionsabfragen per **`curl` an `registry.npmjs.org`**, *nicht* `npm view` – das Debian-`npm`-apt-Paket
  zieht ~349 Pakete nach und darf **nicht** installiert werden.
- npm-Install läuft non-TTY → **Heartbeat** (alle 15 s) + eigenes Logfile in der Runtime, sonst wirkt es „hängt".
- **Den alten Storage-Pfad eines bestehenden `homebridge.service` NICHT zu ermitteln versuchen** –
  ein früherer Versuch (grep auf `/etc/default/homebridge` bzw. die `.service`-Datei nach `-U`) war
  je nach hb-service-Version unzuverlässig und wurde ersatzlos gestrichen. Wird auch nicht gebraucht:
  wir registrieren den Dienst ohnehin immer mit dem festen `$HB_STORAGE_DIR` neu.
- **Kommentare beschreiben WAS getan wird, nicht WARUM.** Kurz halten.
- Kommentare/Log-Ausgaben **immer auf Deutsch** – auch wenn Vorlagen oder Fremddateien
  englisch o.ä. sind (Ziel: der/die Betreiber:in liest das LoxBerry-Log).
- Hook-Skripte werden von Interface 2.0 **automatisch am Dateinamen erkannt** – kein `plugin.cfg`-Eintrag nötig.

## Testen / Deployen

- Syntax: `bash -n preroot.sh postroot.sh uninstall/uninstall` (Repo liegt unter Windows/Git-Bash).
- Echte Prüfung nur auf einem LoxBerry: Plugin-Zip bauen/hochladen (oder Tag pushen fürs Autoupdate)
  und das LoxBerry-Installationslog lesen (preroot: Schritte 1–3, postroot: Schritte 1–5). Kein
  lokaler Ersatz dafür.
- Ob Homebridge nach der Installation *tatsächlich* läuft, zeigt das Installationslog nur bedingt
  (`hb-service`-Meldungen sind real, aber kein Langzeit-Health-Check – „Setup complete" kann sich auf
  einen Start beziehen, der Sekunden später crasht). Verifizieren via SSH:
  `systemctl status homebridge.service` (erwartet `active (running)`, **kein** hochlaufender
  „restart counter"), `curl -I http://localhost:8082` (erwartet `200`).
  **`journalctl -u homebridge.service` zeigt bei einem Absturz meist nur Debug-Zeilen (Storage-/
  Config-/Log-Pfad), nicht den eigentlichen Fehler** – der steht in
  `$HB_STORAGE_DIR/homebridge.log` (`tail -n 100 .../homebridge.log`).
- `plugin.cfg`: `[AUTHOR]`-Block (`NAME`+`EMAIL`) und `[PLUGIN]` `NAME`/`FOLDER` sind die **eingefrorene
  Identität** des Plugins (LoxBerry-MD5-Matching) – nie ändern, sonst brechen Updates auf allen
  Installationen. `VERSION` bei Releases hochziehen; `RELEASECFG`/`PRERELEASECFG` steuern das
  Autoupdate und sollten bei einem Release **gemeinsam** hochgezogen werden (sonst zeigt die
  Plugin-Verwaltung einen veralteten „New Pre-Release"-Hinweis an). Das Archiv-Zip wird erst mit
  dem zugehörigen git-Tag (`Homebridge-V<version>`) real – Tag muss vor/mit dem Release existieren.
