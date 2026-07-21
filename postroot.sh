#!/bin/bash
# Shell script which is executed by bash *BEFORE* installation is started
# (*BEFORE* preinstall and *BEFORE* preupdate). Use with caution and remember,
# that all systems may be different!
#
# Exit code must be 0 if executed successfull.
# Exit code 1 gives a warning but continues installation.
# Exit code 2 cancels installation.
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# Will be executed as user "root".
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# You can use all vars from /etc/environment in this script.
#
# We add 5 additional arguments when executing this script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>
#
# For logging, print to STDOUT. You can use the following tags for showing
# different colorized information during plugin installation:
#
# <OK> This was ok!"
# <INFO> This is just for your information."
# <WARNING> This is a warning!"
# <ERROR> This is an error!"
# <FAIL> This is a fail!"

# To use important variables from command line use the following code:
COMMAND=$0    # Zero argument is shell command
PTEMPDIR=$1   # First argument is temp folder during install
PSHNAME=$2    # Second argument is Plugin-Name for scipts etc.
PDIR=$3       # Third argument is Plugin installation folder
PVERSION=$4   # Forth argument is Plugin version
LBHOMEDIR=$5  # Comes from /etc/environment now. Fifth argument is
              # Base folder of LoxBerry
PTEMPPATH=$6  # Sixth argument is full temp path during install (see also $1)

# Combine them with /etc/environment
PCGI=$LBPCGI/$PDIR
PHTML=$LBPHTML/$PDIR
PTEMPL=$LBPTEMPL/$PDIR
PDATA=$LBPDATA/$PDIR
PLOG=$LBPLOG/$PDIR # Note! This is stored on a Ramdisk now!
PCONFIG=$LBPCONFIG/$PDIR
PSBIN=$LBPSBIN/$PDIR
PBIN=$LBPBIN/$PDIR

#. $LBHOMEDIR/libs/bashlib/loxberry_log.sh
#PACKAGE=${PSHNAME}
#NAME=preroot_install
#FILENAME=${LBPLOG}/${PSHNAME}/preroot_install.log
#APPEND=1
#STDERR=1

echo "<INFO> Installation as root user started."

# --------------------------------------------------------------------------
# Build-Tools sicherstellen (g++/make/python3). Das betrifft NUR den
# Compiler, nicht Node.js oder npm selbst - unabhaengig von der installierten
# Node-Version kann es sein, dass fuer ein natives npm-Modul auf einer
# bestimmten Architektur (z.B. arm64) kein Prebuild-Binary existiert. npm
# faellt dann automatisch auf Kompilieren aus dem Quellcode zurueck; ohne
# Compiler wuerde die Installation in so einem Fall unnoetig scheitern,
# obwohl sie mit Compiler funktioniert haette. Laeuft ausschliesslich ueber
# apt-get und veraendert Node/npm nicht.
# --------------------------------------------------------------------------
if ! command -v g++ >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "<INFO> Build-Tools (build-essential, python3) fehlen - werden ueber apt-get installiert..."
    apt-get update -qq
    apt-get install -y --no-install-recommends build-essential python3 python3-dev
    if [ $? -ne 0 ]; then
        echo "<WARNING> Installation der Build-Tools ueber apt-get fehlgeschlagen. Kompilieren nativer npm-Module koennte scheitern."
    else
        echo "<OK> Build-Tools erfolgreich installiert."
    fi
else
    echo "<OK> Build-Tools bereits vorhanden."
fi

npm cache clean -f

# --------------------------------------------------------------------------
# WICHTIG: LoxBerry verwaltet Node.js/npm bereits selbst (systemweit ueber
# apt/Debian). Andere Plugins koennten davon abhaengen. Dieses Skript fuegt
# daher KEINE Fremdquelle hinzu (kein "n", kein NodeSource-Setup-Skript) -
# Node.js darf aber ueber die bereits konfigurierten apt-Quellen aktualisiert
# werden, weil das exakt die Version ist, die eine frische LoxBerry-
# Installation zum jetzigen Zeitpunkt ohnehin bekommen wuerde (siehe oben).
#
# Strategie:
#   1. Node.js ggf. ueber die vorhandenen apt-Quellen aktualisieren (oben
#      bereits erledigt).
#   2. Neueste, ueber "*" abgefragte Versionen von homebridge und
#      homebridge-config-ui-x pruefen: welche davon ist mit der (ggf. gerade
#      aktualisierten) Node.js-Version kompatibel (engines.node)? Es wird
#      jeweils die NEUESTE kompatible Version ermittelt (das kann bereits
#      "latest" sein).
#   3. Diese ermittelten Versionen werden fixiert installiert
#      (z.B. homebridge-config-ui-x@4.5.0), NICHT einfach "latest".
#   4. Wird fuer eines der beiden Pakete GAR KEINE kompatible Version
#      gefunden, wird die Installation sauber abgebrochen (exit 2).
# --------------------------------------------------------------------------

CURRENT_NODE_FULL=$(node -v 2>/dev/null | sed 's/^v//')
if [ -z "$CURRENT_NODE_FULL" ]; then
    echo "<ERROR> Konnte die installierte Node.js-Version nicht ermitteln (ist Node.js ueberhaupt installiert?)."
    exit 2
fi
CURRENT_NPM_FULL=$(npm -v 2>/dev/null)
echo "<INFO> Installierte Version: Node.js v$CURRENT_NODE_FULL / npm v$CURRENT_NPM_FULL."

# --------------------------------------------------------------------------
# Ueber die bereits konfigurierten apt-Quellen (Debian Trixie selbst - KEINE
# NodeSource-Fremdquelle wird hinzugefuegt) pruefen, ob eine neuere
# Node.js-Paketversion als Candidate verfuegbar ist, und diese ggf.
# installieren. Das ist kein "fremdes" Erzwingen einer Version: Es ist genau
# die Version, die eine frische LoxBerry-Installation zum jetzigen Zeitpunkt
# ohnehin bekommen wuerde. npm wird dabei automatisch als Teil des
# nodejs-Pakets mitaktualisiert.
# --------------------------------------------------------------------------
echo "<INFO> Pruefe ueber die bereits konfigurierten apt-Quellen, ob eine neuere Node.js-Paketversion verfuegbar ist..."
apt-get update -qq
NODEJS_INSTALLED=$(apt-cache policy nodejs 2>/dev/null | awk '/Installed:/ {print $2}')
NODEJS_CANDIDATE=$(apt-cache policy nodejs 2>/dev/null | awk '/Candidate:/ {print $2}')
if [ -n "$NODEJS_CANDIDATE" ] && [ "$NODEJS_CANDIDATE" != "(none)" ] && [ "$NODEJS_CANDIDATE" != "$NODEJS_INSTALLED" ]; then
    echo "<INFO> Neuere Node.js-Paketversion aus den konfigurierten apt-Quellen verfuegbar: $NODEJS_CANDIDATE (installiert: ${NODEJS_INSTALLED:-unbekannt}). Wird installiert..."
    apt-get install -y nodejs
    if [ $? -ne 0 ]; then
        echo "<WARNING> Aktualisierung von nodejs ueber apt-get fehlgeschlagen. Es wird mit der bisherigen Version v$CURRENT_NODE_FULL weitergemacht."
    else
        CURRENT_NODE_FULL=$(node -v 2>/dev/null | sed 's/^v//')
        CURRENT_NPM_FULL=$(npm -v 2>/dev/null)
        echo "<OK> Node.js aktualisiert auf v$CURRENT_NODE_FULL (npm v$CURRENT_NPM_FULL)."
    fi
else
    echo "<OK> Ueber die konfigurierten apt-Quellen ist keine neuere Node.js-Paketversion verfuegbar - installierte Version ist bereits aktuell."
fi

# Sucht unter allen veroeffentlichten Versionen von Paket $1 die NEUESTE,
# deren engines.node-Range mit $CURRENT_NODE_FULL kompatibel ist. Gibt die
# Versionsnummer auf stdout aus, oder nichts, wenn keine passt.
find_compatible_version() {
    local PKG="$1"
    node -e '
        const { execSync } = require("child_process");
        const pkg = process.argv[1];
        const current = process.argv[2];

        function parseVer(v) {
            const m = String(v).trim().match(/(\d+)\.(\d+)\.(\d+)/);
            if (!m) return null;
            return [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)];
        }
        function cmp(a, b) {
            for (let i = 0; i < 3; i++) { if (a[i] !== b[i]) return a[i] - b[i]; }
            return 0;
        }
        // Einfacher, aber fuer uebliche engines.node-Angaben
        // (^x.y.z, >=x.y.z, >x.y.z, <=x.y.z, <x.y.z, =x.y.z, x.y.z, oder mit
        // "||" verknuepfte Alternativen) ausreichender Range-Check. Deckt
        // keine vollstaendige Semver-Grammatik (z.B. "1.x", Hyphen-Ranges) ab.
        function satisfies(current, range) {
            if (!range) return true; // keine Angabe -> keine Einschraenkung
            const cur = parseVer(current);
            if (!cur) return false;
            const alts = String(range).split("||").map(s => s.trim()).filter(Boolean);
            return alts.some(alt => {
                const m = alt.match(/^(\^|>=|>|<=|<|=)?\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
                if (!m) return false;
                const op = m[1] || "=";
                const maj = parseInt(m[2], 10);
                const min = m[3] !== undefined ? parseInt(m[3], 10) : 0;
                const pat = m[4] !== undefined ? parseInt(m[4], 10) : 0;
                const base = [maj, min, pat];
                switch (op) {
                    case "^": return cur[0] === maj && cmp(cur, base) >= 0;
                    case ">=": return cmp(cur, base) >= 0;
                    case ">": return cmp(cur, base) > 0;
                    case "<=": return cmp(cur, base) <= 0;
                    case "<": return cmp(cur, base) < 0;
                    case "=": return cur[0] === maj
                        && (m[3] === undefined || cur[1] === min)
                        && (m[4] === undefined || cur[2] === pat);
                    default: return false;
                }
            });
        }

        let raw;
        try {
            // "*" fragt engines.node fuer ALLE veroeffentlichten Versionen in
            // einem Rutsch ab, statt jede Version einzeln nachzufragen.
            raw = execSync(`npm view ${pkg}@"*" engines.node --json`, { encoding: "utf8" });
        } catch (e) {
            process.exit(0); // nichts ausgeben -> Aufrufer wertet als "keine gefunden"
        }
        let data;
        try { data = JSON.parse(raw); } catch (e) { process.exit(0); }

        let map = (data && typeof data === "object" && !Array.isArray(data)) ? data : {};
        const versions = Object.keys(map);
        if (versions.length === 0) process.exit(0);

        versions.sort((a, b) => {
            const pa = parseVer(a), pb = parseVer(b);
            if (!pa || !pb) return 0;
            return cmp(pb, pa); // absteigend, neueste zuerst
        });

        for (const v of versions) {
            const range = Array.isArray(map[v]) ? map[v][0] : map[v];
            if (satisfies(current, range)) {
                console.log(v);
                process.exit(0);
            }
        }
        process.exit(0);
    ' "$PKG" "$CURRENT_NODE_FULL"
}

echo "<INFO> Suche neueste zu Node.js v$CURRENT_NODE_FULL kompatible Version von homebridge-config-ui-x..."
UI_VERSION=$(find_compatible_version "homebridge-config-ui-x")

echo "<INFO> Suche neueste zu Node.js v$CURRENT_NODE_FULL kompatible Version von homebridge..."
HB_VERSION=$(find_compatible_version "homebridge")

if [ -z "$UI_VERSION" ] || [ -z "$HB_VERSION" ]; then
    echo "<ERROR> Es wurde keine mit der installierten Node.js-Version v$CURRENT_NODE_FULL kompatible Version gefunden:"
    [ -z "$HB_VERSION" ] && echo "<ERROR>   - homebridge: keine passende Version gefunden"
    [ -z "$UI_VERSION" ] && echo "<ERROR>   - homebridge-config-ui-x: keine passende Version gefunden"
    echo "<ERROR> Auch die ueber die konfigurierten apt-Quellen verfuegbare Node.js-Version reicht nicht aus. Eine Fremdquelle (NodeSource) wird bewusst NICHT hinzugefuegt."
    echo "<ERROR> Installation wird abgebrochen."
    exit 2
fi

LATEST_UI_VERSION=$(npm view homebridge-config-ui-x version 2>/dev/null)
LATEST_HB_VERSION=$(npm view homebridge version 2>/dev/null)

if [ "$UI_VERSION" != "$LATEST_UI_VERSION" ]; then
    echo "<WARNING> Installierte Node.js-Version ist zu alt fuer das aktuelle homebridge-config-ui-x (${LATEST_UI_VERSION:-unbekannt})."
    echo "<WARNING> Installiere stattdessen die neueste dazu kompatible Version: homebridge-config-ui-x@$UI_VERSION"
else
    echo "<OK> Node.js v$CURRENT_NODE_FULL ist mit der aktuellen Version homebridge-config-ui-x@$UI_VERSION kompatibel."
fi

if [ "$HB_VERSION" != "$LATEST_HB_VERSION" ]; then
    echo "<WARNING> Installierte Node.js-Version ist zu alt fuer das aktuelle homebridge (${LATEST_HB_VERSION:-unbekannt})."
    echo "<WARNING> Installiere stattdessen die neueste dazu kompatible Version: homebridge@$HB_VERSION"
else
    echo "<OK> Node.js v$CURRENT_NODE_FULL ist mit der aktuellen Version homebridge@$HB_VERSION kompatibel."
fi

# Hinweis (Restrisiko): homebridge-config-ui-x@$UI_VERSION kann intern eine
# eigene Mindestanforderung an die homebridge-Version haben. Das wird hier
# nicht automatisch erzwungen, sondern nur zur Information ausgegeben.
UI_REQUIRES_HB=$(npm view "homebridge-config-ui-x@$UI_VERSION" peerDependencies.homebridge 2>/dev/null)
if [ -n "$UI_REQUIRES_HB" ]; then
    echo "<INFO> homebridge-config-ui-x@$UI_VERSION gibt als benoetigte homebridge-Version an: $UI_REQUIRES_HB (bitte ggf. manuell mit homebridge@$HB_VERSION abgleichen)."
fi

echo "<INFO> homebridge@$HB_VERSION und homebridge-config-ui-x@$UI_VERSION werden installiert."
npm install -g --unsafe-perm homebridge@$HB_VERSION homebridge-config-ui-x@$UI_VERSION
if [ $? -ne 0 ]; then
    echo "<ERROR> npm-Installation von homebridge@$HB_VERSION / homebridge-config-ui-x@$UI_VERSION fehlgeschlagen. Siehe npm-Log oben."
    exit 2
fi

# Homebridge starten und als Dienst einrichten
echo "<INFO> Dienst fuer homebridge einrichten und homebridge starten"
hb-service -U $5/config/plugins/homebridge --user loxberry --port 8082 install
if [ $? -ne 0 ]; then
    echo "<ERROR> Einrichtung des homebridge-Dienstes (hb-service install) fehlgeschlagen."
    exit 2
fi

exit 0