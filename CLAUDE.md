# CLAUDE.md

Leitfaden für die Arbeit an diesem Repository. Kurz halten, Fakten prüfen, nichts raten.

## Was das ist

LoxBerry-Plugin (Plugin-Interface **2.0**), das **Homebridge** + **homebridge-config-ui-x**
auf einem LoxBerry (Raspberry Pi / Debian bookworm, i. d. R. arm64) installiert und als
systemd-Dienst betreibt. Homebridge läuft in einem **isolierten Node.js**, nicht im System-Node.

Kein Anwendungscode im klassischen Sinn – das Plugin besteht aus **Bash-Installationsskripten**,
einem CGI-Webfrontend (Perl/`index.cgi`) und HTML-Templates.

## Ablauf der Installation/Updates (wichtig!)

LoxBerry-Hook-Reihenfolge bei einem **Update**:
`preroot` (root) → `preupgrade` (loxberry) → **alte Plugin-Ordner werden gelöscht** →
`preinstall` → Dateien kopieren → `postupgrade` → `postinstall` → `postroot` (root).

Daraus folgt die zentrale Design-Entscheidung: Der Config-Ordner wird beim Update gelöscht,
**bevor** `postroot` läuft. Deshalb:

- **`preroot.sh`** (root, vor dem Löschen, bei Install *und* Update):
  1. Homebridge stoppen (`systemctl stop homebridge.service`) + Port **8082** freigeben
     (Fallback `fuser`/`ss`/`lsof`, sanft dann SIGKILL).
  2. Config sichern nach `data/system/tmp/homebridge_config_backup/backup_<ts>` (rotiert, letzte 5).
- **`postroot.sh`** (root, nach dem Löschen), 5 Schritte:
  1. Config aus dem preroot-Backup wiederherstellen.
  2. Homebridge-/Node-Version ermitteln (via `curl` an die npm-Registry; Node-Major aus `engines.node`, Fallback 22).
  3. Isoliertes Node.js in die **persistente Runtime** einrichten (nur bei anderer Version neu).
  4. Homebridge + config-ui-x installieren/aktualisieren (**Skip**, wenn Node unverändert *und* beide aktuell).
  5. `hb-service` registrieren (immer uninstall+install, damit die Unit auf das isolierte Node zeigt).
- **`uninstall/uninstall`** (root): Dienst + Unit entfernen, Config-Backups + persistente Runtime löschen.

**Das System-Node wird NICHT angefasst** (kein Entfernen, kein apt-Install). Homebridge nutzt
ausschließlich das isolierte Node der persistenten Runtime.

## Feste Pfade / Invarianten

- Config/Pairings: **`/opt/loxberry/config/plugins/homebridge`** (`$LBPCONFIG/$PDIR`) – historisch fest,
  wird bei Updates gelöscht → Backup/Restore über preroot/postroot.
- Persistente Runtime: **`/opt/loxberry/data/system/homebridge_runtime`** (`nodejs/` + `npm-global/`) –
  liegt außerhalb der Plugin-Ordner, überlebt Updates, muss vom `uninstall` selbst gelöscht werden.
- Config-Backups: `data/system/tmp/homebridge_config_backup/`.
- systemd-Unit: **`homebridge.service`**, UI-Port **8082**, User **loxberry**.

Alles unter `data/system/` überlebt Updates; Plugin-Ordner (`config/plugins/…`, `data/plugins/…`, `bin/plugins/…`) werden bei jedem Update gelöscht.

## Kompatibilität mit Altinstallationen (nicht zerschießen!)

Das alte Plugin (vor 2026, Commit `a77a16e`) nutzte **System-Node** (`n stable`, `/usr/local/...`),
aber denselben `hb-service`-Aufruf: gleiche Unit, gleicher Storage-Pfad, Port 8082, User loxberry.

**Wichtig:** Das System-Node in `/usr/local/bin` wird **nicht** entfernt – LoxBerry 4 (Debian
trixie) bringt selbst ein Node dort mit, das andere Komponenten brauchen. (Eine frühere Version
des Plugins hat es fälschlich als „Fremdinstallation" gelöscht – das ist raus.) Homebridge läuft
nur im isolierten Node. Beim Übergang alt→neu registriert Schritt 5 den Dienst **immer neu**
(uninstall + install unter isoliertem Node), damit die alte Unit nicht mehr auf ein fremdes Node zeigt.

## Konventionen / Fallstricke

- **Zeilenenden: nur LF.** `.gitattributes` erzwingt das. `.sh` mit CRLF brechen auf Linux.
- `postroot.sh` läuft mit **`set -e`** – Command-Substitutions/`wait` entsprechend absichern
  (`VAR=0; cmd || VAR=$?`), sonst bricht das Skript unbeabsichtigt ab.
- Versionsabfragen per **`curl` an `registry.npmjs.org`**, *nicht* `npm view` – das Debian-`npm`-apt-Paket
  zieht ~349 Pakete nach und darf **nicht** installiert werden.
- npm-Install läuft non-TTY → **Heartbeat** (alle 15 s) + eigenes Logfile in der Runtime, sonst wirkt es „hängt".
- Kommentare/Log-Ausgaben auf Deutsch (Ziel: der/die Betreiber:in liest das LoxBerry-Log).
- Hook-Skripte werden von Interface 2.0 **automatisch am Dateinamen erkannt** – kein `plugin.cfg`-Eintrag nötig.

## Testen / Deployen

- Syntax: `bash -n preroot.sh postroot.sh uninstall/uninstall` (Repo liegt unter Windows/Git-Bash).
- Echte Prüfung nur auf einem LoxBerry: Plugin-Zip bauen/hochladen und das LoxBerry-Installationslog lesen
  (Schritte 1–6). Kein lokaler Ersatz dafür.
- `plugin.cfg`: `VERSION` hochziehen bei Releases; `RELEASECFG`/`PRERELEASECFG` steuern das Autoupdate.
