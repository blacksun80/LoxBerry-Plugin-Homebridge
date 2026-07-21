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
# Fix: Build-Tools sicherstellen (g++/make/python3 werden von node-gyp
# benoetigt, sobald fuer ein natives npm-Modul kein Prebuild-Binary
# existiert - das ist bei sehr neuen Node-Versionen auf arm64 haeufig der
# Fall und war die Ursache fuer den bisherigen Installationsabbruch).
# --------------------------------------------------------------------------
if ! command -v g++ >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "<INFO> Build-Tools (build-essential, python3) fehlen - werden installiert..."
    apt-get update -qq
    apt-get install -y --no-install-recommends build-essential python3 python3-dev
    if [ $? -ne 0 ]; then
        echo "<ERROR> Installation der Build-Tools fehlgeschlagen. Kompilieren nativer npm-Module wird evtl. scheitern."
    else
        echo "<OK> Build-Tools erfolgreich installiert."
    fi
else
    echo "<OK> Build-Tools bereits vorhanden."
fi

npm cache clean -f

# --------------------------------------------------------------------------
# Fix: LoxBerry installiert und verwaltet Node.js bereits selbst - systemweit
# ueber apt und die NodeSource-Paketquelle (/etc/apt/sources.list.d/nodesource.list),
# siehe LoxBerry-Kernupdate (update_v2.0.0.pl). Ein zusaetzlicher Versions-
# manager wie "n" installiert eine ZWEITE, parallele Node-Installation unter
# /usr/local/bin, die mit der apt-verwalteten unter /usr/bin um den PATH
# konkurriert. Das ist ein bekanntes Problem in der LoxBerry-Community -
# je nach PATH-Reihenfolge meldet "node -v" dann etwas anderes als
# "nodejs -v", und LoxBerry-Updates koennen die apt-Version jederzeit
# zuruecksetzen, waehrend die "n"-Version bestehen bleibt oder umgekehrt.
#
# Deshalb wird hier NICHT "n" verwendet, sondern - falls ueberhaupt noetig -
# genau derselbe Mechanismus wie im LoxBerry-Kern selbst: Die NodeSource-
# apt-Quelle wird auf die benoetigte Major-Version gesetzt und "nodejs"
# per apt installiert/aktualisiert. Damit bleibt es eine einzige, konsistente
# Node-Installation, die sich wie der Rest des Systems verhaelt.
# --------------------------------------------------------------------------
NODE_FALLBACK_VERSION=22

echo "<INFO> Ermittle unterstuetzte Node.js-Version von homebridge-config-ui-x..."
ENGINES_RAW=$(npm view homebridge-config-ui-x engines.node 2>/dev/null)

# Alle unterstuetzten Major-Versionen (nicht nur die aelteste) fuer den
# Abgleich mit der bereits installierten LoxBerry-System-Version.
SUPPORTED_VERSIONS=$(echo "$ENGINES_RAW" \
    | tr '|' '\n' \
    | sed -E 's/[^0-9]*([0-9]+).*/\1/' \
    | grep -E '^[0-9]+$' \
    | awk '$1 % 2 == 0' \
    | sort -n)

OLDEST_SUPPORTED=$(echo "$SUPPORTED_VERSIONS" | head -1)

if [ -z "$OLDEST_SUPPORTED" ]; then
    echo "<WARNING> Konnte unterstuetzte Node-Version nicht ermitteln, verwende Fallback v$NODE_FALLBACK_VERSION."
    SUPPORTED_VERSIONS=$NODE_FALLBACK_VERSION
    OLDEST_SUPPORTED=$NODE_FALLBACK_VERSION
fi

CURRENT_MAJOR=""
if command -v node >/dev/null 2>&1; then
    CURRENT_MAJOR=$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')
fi

if [ -n "$CURRENT_MAJOR" ] && echo "$SUPPORTED_VERSIONS" | grep -qx "$CURRENT_MAJOR"; then
    # Bereits von LoxBerry (oder einem anderen Plugin) installierte Version
    # erfuellt die Anforderung bereits - nichts tun, System nicht anfassen.
    echo "<OK> System-Node.js v$CURRENT_MAJOR erfuellt die Anforderungen bereits - keine Aenderung noetig."
else
    NODE_TARGET_VERSION=$OLDEST_SUPPORTED
    echo "<WARNING> System-Node.js (${CURRENT_MAJOR:-nicht gefunden}) erfuellt die Anforderungen nicht."
    echo "<INFO> Aktualisiere ueber die NodeSource-apt-Quelle auf Node.js v$NODE_TARGET_VERSION (wie im LoxBerry-Kernupdate)."
    echo "<WARNING> Das betrifft alle Node.js-basierten Plugins/Dienste auf diesem LoxBerry, nicht nur Homebridge!"
    curl -fsSL https://deb.nodesource.com/setup_${NODE_TARGET_VERSION}.x | bash -
    apt-get update -qq
    apt-get install -y nodejs
    if [ $? -ne 0 ]; then
        echo "<ERROR> Aktualisierung von Node.js ueber apt fehlgeschlagen (apt-get-Fehler)."
        exit 1
    fi

    # --------------------------------------------------------------------
    # Fix: apt "erzwingt" die Zielversion nicht garantiert - schlaegt das
    # NodeSource-Setup-Skript still fehl (Netzwerk, Repo noch nicht bereit
    # fuer diese arm64-Version, apt-Hold, etc.), installiert apt-get einfach
    # die zuvor konfigurierte Version weiter, ohne einen Fehler zu werfen.
    # Deshalb hier explizit nachpruefen, ob tatsaechlich die gewuenschte
    # Major-Version installiert wurde, bevor mit npm weitergemacht wird -
    # sonst wiederholt sich der urspruengliche Fehler nur unbemerkt.
    # --------------------------------------------------------------------
    INSTALLED_MAJOR=$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')
    if [ "$INSTALLED_MAJOR" != "$NODE_TARGET_VERSION" ]; then
        echo "<ERROR> Nach der Aktualisierung meldet 'node -v' Major-Version ${INSTALLED_MAJOR:-keine} statt der erwarteten v$NODE_TARGET_VERSION."
        echo "<ERROR> NodeSource-Repo evtl. noch nicht verfuegbar fuer diese Architektur/Version, oder apt-Hold aktiv. Installation wird abgebrochen."
        exit 1
    fi
    echo "<OK> Node.js $(node -v) erfolgreich installiert."
fi

# Homebridge / Homebridge Config UI installieren
echo "<INFO> homebridge und homebridge-config-ui-x wird installiert."
npm install -g --unsafe-perm homebridge homebridge-config-ui-x
if [ $? -ne 0 ]; then
    echo "<ERROR> npm-Installation von homebridge/homebridge-config-ui-x fehlgeschlagen. Siehe npm-Log oben."
    exit 1
fi

# Homebridge starten und als Dienst einrichten
echo "<INFO> Dienst fuer homebridge einrichten und homebridge starten"
hb-service -U $5/config/plugins/homebridge --user loxberry --port 8082 install

exit 0