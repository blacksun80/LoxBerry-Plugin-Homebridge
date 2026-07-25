#!/bin/bash
# check_node_update.sh
#
# Prueft, ob eine neue, mit Homebridge + Config UI X + allen installierten
# Homebridge-Plugins gemeinsam kompatible Node-Version verfuegbar ist. Nur
# Lesezugriffe (Registry-Abfragen, lokale package.json-Dateien), kein sudo.
#
# Ausgabe (auf stdout, key=value):
#   CURRENT=<installierte Node-Version oder leer>
#   RECOMMENDED=<empfohlene Node-Version>
#   UPDATE_AVAILABLE=0|1
#   LIMITING=<Pakete, die die Auswahl einschraenken; "(!)" = Konflikt ignoriert>
#   MODULES=<name>:<node-engines-range>;<name>:<node-engines-range>;... (fuer die GUI)

PDIR="homebridge"
LBPDATA="${LBPDATA:-${LBHOMEDIR:-/opt/loxberry}/data/plugins}"
HB_RUNTIME_DIR="$LBPDATA/$PDIR/homebridge_runtime"
HB_NPM_GLOBAL="$HB_RUNTIME_DIR/npm-global"

CURRENT_LOCAL_VERSION=""
[ -x "$HB_RUNTIME_DIR/nodejs/bin/node" ] && CURRENT_LOCAL_VERSION=$("$HB_RUNTIME_DIR/nodejs/bin/node" -v 2>/dev/null)

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) NODE_ARCH="arm64" ;;
    armv7l)  NODE_ARCH="armv7l" ;;
    x86_64)  NODE_ARCH="x64" ;;
    *)       echo "CURRENT=$CURRENT_LOCAL_VERSION"; echo "UPDATE_AVAILABLE=0"; exit 0 ;;
esac

HB_UI_MANIFEST=$(curl -fsSL https://registry.npmjs.org/homebridge-config-ui-x/latest 2>/dev/null || echo "")
HB_MANIFEST=$(curl -fsSL https://registry.npmjs.org/homebridge/latest 2>/dev/null || echo "")
REQUIRED_RANGE_UI=$(printf '%s' "$HB_UI_MANIFEST" | grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' | head -1)
REQUIRED_RANGE_HB=$(printf '%s' "$HB_MANIFEST" | grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' | head -1)

if [ -z "$REQUIRED_RANGE_UI" ] || [ -z "$REQUIRED_RANGE_HB" ]; then
    echo "CURRENT=$CURRENT_LOCAL_VERSION"
    echo "UPDATE_AVAILABLE=0"
    exit 0
fi

MAJORS=$(echo "$REQUIRED_RANGE_UI" | grep -oP '\^\K[0-9]+' | sort -nu)
LIMITING="homebridge-config-ui-x"
MODULES="homebridge-config-ui-x:${REQUIRED_RANGE_UI};homebridge:${REQUIRED_RANGE_HB}"

# Schneidet $MAJORS mit den Majors eines weiteren Pakets. Kein Ueberlappung
# gefunden = Konflikt, wird nur vermerkt (Paket als "(!)" markiert), $MAJORS
# bleibt unangetastet - ein einzelnes zu eng deklariertes Plugin soll nicht
# die ganze Empfehlung auf "nichts passt" kippen.
apply_constraint() {
    local label="$1" other="$2" common before
    [ -z "$other" ] && return
    before="$MAJORS"
    common=$(echo "$MAJORS" | grep -Fxf <(echo "$other") 2>/dev/null)
    if [ -z "$common" ]; then
        LIMITING="$LIMITING, ${label}(!)"
        return
    fi
    MAJORS="$common"
    [ "$before" != "$MAJORS" ] && LIMITING="$LIMITING, $label"
}

apply_constraint "homebridge" "$(echo "$REQUIRED_RANGE_HB" | grep -oP '\^\K[0-9]+' | sort -nu)"

# Alle zusaetzlich installierten Plugins beruecksichtigen (eigene package.json,
# keine Registry-Abfrage noetig - wir pruefen die tatsaechlich installierte Version).
if [ -d "$HB_NPM_GLOBAL/lib/node_modules" ]; then
    for pkg_dir in "$HB_NPM_GLOBAL/lib/node_modules"/*/; do
        pkg_name=$(basename "$pkg_dir")
        case "$pkg_name" in
            homebridge|homebridge-config-ui-x|npm|corepack|.bin) continue ;;
        esac
        pkg_json="$pkg_dir/package.json"
        [ -f "$pkg_json" ] || continue
        plugin_range=$(grep -oP '"engines"\s*:\s*\{[^}]*?"node"\s*:\s*"\K[^"]+' "$pkg_json" | head -1)
        if [ -z "$plugin_range" ]; then
            # Kein engines.node hinterlegt - trotzdem auflisten (leerer
            # Bereich), nur nicht in die Versions-Einschraenkung einbeziehen.
            MODULES="${MODULES};${pkg_name}:"
            continue
        fi
        MODULES="${MODULES};${pkg_name}:${plugin_range}"
        apply_constraint "$pkg_name" "$(echo "$plugin_range" | grep -oP '\^\K[0-9]+' | sort -nu)"
    done
fi

CANDIDATE_MAJORS=$(echo "$MAJORS" | sort -rn)
if [ -z "$CANDIDATE_MAJORS" ]; then
    echo "CURRENT=$CURRENT_LOCAL_VERSION"
    echo "UPDATE_AVAILABLE=0"
    echo "MODULES=$MODULES"
    exit 0
fi

NODE_INDEX=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null || echo "")
RECOMMENDED=""
for CANDIDATE in $CANDIDATE_MAJORS; do
    FULL=$(printf '%s' "$NODE_INDEX" | grep -oP "\"version\":\"v${CANDIDATE}\.[0-9]+\.[0-9]+\"" | head -1 | grep -oP 'v[0-9.]+')
    [ -z "$FULL" ] && continue
    DL_URL="https://nodejs.org/dist/${FULL}/node-${FULL}-linux-${NODE_ARCH}.tar.xz"
    if curl -fsSL --connect-timeout 15 -o /dev/null -I "$DL_URL" 2>/dev/null; then
        RECOMMENDED=$FULL
        break
    fi
done

echo "CURRENT=$CURRENT_LOCAL_VERSION"
echo "RECOMMENDED=$RECOMMENDED"
if [ -n "$RECOMMENDED" ] && [ "$RECOMMENDED" != "$CURRENT_LOCAL_VERSION" ]; then
    echo "UPDATE_AVAILABLE=1"
    echo "LIMITING=$LIMITING"
else
    echo "UPDATE_AVAILABLE=0"
fi
echo "MODULES=$MODULES"
exit 0
