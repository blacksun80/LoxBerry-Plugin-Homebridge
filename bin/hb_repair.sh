#!/bin/bash
# bin/hb_repair.sh
#
# Raeumt Node/npm-Reste auf und stellt bei Bedarf das System-Node wieder her.
# Wird als root ueber sudo aus dem Webfrontend aufgerufen.
#
# Aufruf:
#   hb_repair.sh check            # nur pruefen und berichten (kein root noetig)
#   hb_repair.sh repair [logfile] # aufraeumen + System-Node reparieren (root)
#
# Fasst die Homebridge-Config/Pairings NICHT an.

MODE="${1:-check}"

LOGDIR="REPLACELBPLOGDIR"
LOGFILE="${2:-$LOGDIR/hb_repair_$(date +%Y%m%d_%H%M%S).log}"

RUNTIME_DIR="REPLACELBPDATADIR/homebridge_runtime"
NPM_GLOBAL="$RUNTIME_DIR/npm-global"
CONFIG_DIR="REPLACELBPCONFIGDIR"
SERVICE_UNIT="/etc/systemd/system/homebridge.service"

NODESOURCE_KEYRING="/usr/share/keyrings/nodesource.gpg"
NODESOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"

# ============================================================
# Hilfsfunktionen
# ============================================================

# Debian-Codename und Versions-ID ermitteln.
detect_system() {
    CODENAME=""
    VERSION_ID_LOCAL=""
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        CODENAME="${VERSION_CODENAME:-}"
        VERSION_ID_LOCAL="${VERSION_ID:-}"
    fi
}

# Passende Node-Major-Version pro Debian-Codename.
# PLATZHALTER fuer bookworm/trixie - wird nach dem LB4-Frischinstall-Check gefuellt.
nodesource_major() {
    case "$1" in
        buster)   echo 12 ;;
        bullseye) echo 18 ;;
        bookworm) echo "" ;;   # PLATZHALTER (Debian 12 / LB4)
        trixie)   echo "" ;;   # PLATZHALTER (Debian 13 / LB4)
        *)        echo "" ;;
    esac
}

# Zustand des System-Node: ok | broken | missing.
system_node_state() {
    if command -v node >/dev/null 2>&1 && node -v >/dev/null 2>&1 \
       && command -v npm >/dev/null 2>&1 && npm -v >/dev/null 2>&1; then
        echo "ok"
    elif command -v node >/dev/null 2>&1 || command -v npm >/dev/null 2>&1; then
        echo "broken"
    else
        echo "missing"
    fi
}

# Prueft, ob unter /usr/local eine Fremd-Node-Installation liegt.
foreign_node_present() {
    [ -e /usr/local/bin/node ] || [ -e /usr/local/bin/npm ] || [ -d /usr/local/lib/node_modules ]
}

# ============================================================
# Pruefen (check)
# ============================================================

do_check() {
    detect_system

    echo "============================================================"
    echo "Pruefung Node/npm"
    echo "============================================================"
    echo "Debian-Codename:   ${CODENAME:-unbekannt} (Version ${VERSION_ID_LOCAL:-?})"
    echo "System-Node-Zustand: $(system_node_state)"

    echo "--- gefundene node/npm-Pfade ---"
    which -a node 2>/dev/null || echo "(node nicht gefunden)"
    which -a npm 2>/dev/null || echo "(npm nicht gefunden)"

    echo "--- Versionen (falls aufloesbar) ---"
    echo "node: $(node -v 2>/dev/null || echo n/a)"
    echo "npm:  $(npm -v 2>/dev/null || echo n/a)"

    echo "--- apt-Paket nodejs/npm ---"
    dpkg -l 2>/dev/null | grep -iE '^ii +(nodejs|npm) ' || echo "(kein apt-Paket)"

    echo "--- Fremd-Node unter /usr/local ---"
    if foreign_node_present; then
        ls -la /usr/local/bin/node /usr/local/bin/npm 2>/dev/null
        ls -1 /usr/local/lib/node_modules 2>/dev/null
    else
        echo "(keine)"
    fi

    echo "--- NodeSource-Source-Listen ---"
    grep -rniE 'nodesource' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || echo "(keine)"

    echo "--- isolierte Homebridge-Runtime ---"
    if [ -x "$RUNTIME_DIR/nodejs/bin/node" ]; then
        echo "vorhanden: $("$RUNTIME_DIR/nodejs/bin/node" -v 2>/dev/null)"
    else
        echo "(nicht vorhanden)"
    fi
}

# ============================================================
# Reparatur-Bausteine (repair)
# ============================================================

# Homebridge-Dienst stoppen und systemd-Unit entfernen.
stop_service() {
    echo "--- Dienst stoppen + Unit entfernen ---"
    systemctl stop homebridge.service 2>/dev/null || true
    local hb_service="$NPM_GLOBAL/bin/hb-service"
    if [ -x "$hb_service" ]; then
        export PATH="$RUNTIME_DIR/nodejs/bin:$NPM_GLOBAL/bin:$PATH"
        "$hb_service" uninstall || true
    fi
    if [ -f "$SERVICE_UNIT" ]; then
        systemctl disable --now homebridge.service 2>/dev/null || true
        rm -f "$SERVICE_UNIT"
        systemctl daemon-reload 2>/dev/null || true
    fi
}

# Isolierte Runtime loeschen (das Plugin baut sie beim Reinstall neu auf).
delete_runtime() {
    echo "--- Isolierte Runtime loeschen ---"
    if [ -d "$RUNTIME_DIR" ]; then
        rm -rf "$RUNTIME_DIR"
        echo "geloescht: $RUNTIME_DIR"
    else
        echo "(keine Runtime vorhanden)"
    fi
}

# Globale Homebridge-Reste unter /usr/local entfernen.
# node/npm unter /usr/local bleiben unangetastet (auf LB4 LoxBerrys eigenes Node).
clean_usr_local() {
    echo "--- Globale Homebridge-Reste unter /usr/local entfernen ---"
    for d in /usr/local/lib/node_modules/homebridge /usr/local/lib/node_modules/homebridge-config-ui-x; do
        [ -d "$d" ] && rm -rf "$d" && echo "entfernt: $d"
    done
    for b in /usr/local/bin/homebridge /usr/local/bin/hb-service; do
        if [ -e "$b" ] || [ -L "$b" ]; then
            rm -f "$b"
            echo "entfernt: $b"
        fi
    done
    echo "--- tote Symlinks in /usr/local/bin ---"
    find /usr/local/bin -maxdepth 1 -xtype l -print -delete 2>/dev/null || echo "(keine)"
}

# NodeSource-GPG-Key (neu) holen - gegen fehlende/abgelaufene Keys.
refresh_nodesource_key() {
    echo "--- NodeSource-GPG-Key aktualisieren ---"
    mkdir -p "$(dirname "$NODESOURCE_KEYRING")"
    if curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
         | gpg --dearmor -o "$NODESOURCE_KEYRING" 2>/dev/null; then
        chmod 0644 "$NODESOURCE_KEYRING"
        echo "Key aktualisiert: $NODESOURCE_KEYRING"
    else
        echo "<WARNING> NodeSource-Key konnte nicht geladen werden."
    fi
}

# NodeSource-Source-Liste pruefen und bei fehlendem/falschem Eintrag schreiben.
ensure_nodesource_repo() {
    local major="$1"
    echo "--- NodeSource-Source-Liste (node ${major}) pruefen ---"
    local want="deb [signed-by=$NODESOURCE_KEYRING] https://deb.nodesource.com/node_${major}.x nodistro main"
    if [ -f "$NODESOURCE_LIST" ] && grep -qF "node_${major}.x" "$NODESOURCE_LIST"; then
        echo "Eintrag bereits korrekt."
    else
        echo "$want" > "$NODESOURCE_LIST"
        echo "geschrieben: $want"
    fi
}

# System-Node ueber apt (NodeSource) neu installieren.
reinstall_system_node() {
    echo "--- System-Node via apt (NodeSource) installieren ---"
    apt-get update || echo "<WARNING> apt-get update mit Fehlern."
    if apt-get install -y nodejs; then
        echo "Ergebnis: node=$(node -v 2>/dev/null || echo n/a), npm=$(npm -v 2>/dev/null || echo n/a)"
    else
        echo "<WARNING> apt-get install nodejs fehlgeschlagen."
    fi
}

# System-Node nur anzeigen und ggf. warnen - nicht anfassen.
repair_system_node() {
    echo "--- System-Node pruefen (nur Anzeige) ---"
    local state
    state=$(system_node_state)
    echo "System-Node-Zustand: $state"
    if [ "$state" != "ok" ]; then
        echo "<WARNING> System-Node defekt/fehlt - wird NICHT angefasst (LoxBerry-Sache)."
    fi
    # Versionsabhaengige Node-Wiederherstellung (refresh_nodesource_key /
    # ensure_nodesource_repo / reinstall_system_node) ist bewusst noch nicht
    # aktiv - erst nach Verifikation des Node-Modells pro LB-Version.
}

do_repair() {
    detect_system
    echo "############################################################"
    echo "# hb_repair - REPARATUR gestartet ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "############################################################"

    echo ""
    echo "=== Ausgangslage ==="
    do_check

    echo ""
    echo "=== Aufraeumen ==="
    stop_service
    delete_runtime
    clean_usr_local

    echo ""
    echo "=== System-Node ==="
    repair_system_node

    echo ""
    echo "############################################################"
    echo "# Fertig."
    echo "# 1. LoxBerry NEU STARTEN (raeumt tote Symlinks/Reste endgueltig ab)."
    echo "# 2. Danach das Homebridge-Plugin NEU INSTALLIEREN - es baut die"
    echo "#    isolierte Runtime frisch auf. Config/Pairings bleiben erhalten."
    echo "############################################################"
}

# ============================================================
# Ablauf
# ============================================================

mkdir -p "$LOGDIR" 2>/dev/null

# Reparatur zusaetzlich in ein downloadbares Logfile schreiben.
if [ "$MODE" = "repair" ]; then
    exec > >(tee -a "$LOGFILE") 2>&1
fi

case "$MODE" in
    check)
        do_check
        ;;
    repair)
        if [ "$(id -u)" -ne 0 ]; then
            echo "FEHLER: 'repair' muss als root laufen."
            exit 1
        fi
        do_repair
        chown loxberry:loxberry "$LOGFILE" 2>/dev/null || true
        echo ""
        echo "LOGFILE: $LOGFILE"
        ;;
    *)
        echo "Aufruf: hb_repair.sh check | repair [logfile]"
        exit 1
        ;;
esac

exit 0
