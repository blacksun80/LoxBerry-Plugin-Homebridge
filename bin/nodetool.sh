#!/bin/bash
# nodetool.sh
#
# Menuegefuehrtes Diagnose-/Reparatur-Tool fuer System-Node/npm auf einem LoxBerry.
# Eigenstaendig, laeuft NICHT ueber das Plugin-Webfrontend.
#
# Starten (als root, z.B. per Putty):
#   cp nodetool.sh /tmp/            # oder mit scp/WinSCP nach /tmp kopieren
#   chmod +x /tmp/nodetool.sh
#   sudo /tmp/nodetool.sh           # bzw. als root:  /tmp/nodetool.sh
#
# Wissensstand (verifiziert), auf dem die Empfehlungen/Warnungen beruhen:
#   Debian 10 Buster (LB2):   NodeSource node 12  -> /usr/bin/node   (apt)
#   Debian 11 Bullseye (LB3): NodeSource node 18  -> /usr/bin/node   (apt)
#   Debian 12 Bookworm (LB3): DietPi (Software 9) -> /usr/local/bin/node
#   Debian 13 Trixie (LB4):   DietPi (Software 9) -> /usr/local/bin/node
#   -> Buster/Bullseye = NodeSource-apt in /usr/bin; Bookworm/Trixie = DietPi in /usr/local.

if [ "$(id -u)" -ne 0 ]; then
    echo "Bitte als root ausfuehren (sudo $0)."
    exit 1
fi

NODESOURCE_KEYRING="/usr/share/keyrings/nodesource.gpg"
NODESOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"
YARN_KEYRING="/usr/share/keyrings/yarnkey.gpg"

# ============================================================
# System-Erkennung
# ============================================================
detect_system() {
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64) NODE_ARCH="arm64" ;;
        armv7l)  NODE_ARCH="armv7l" ;;
        armv6l)  NODE_ARCH="armv6l" ;;
        x86_64)  NODE_ARCH="x64" ;;
        *)       NODE_ARCH="unbekannt" ;;
    esac

    HW_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    if [ -z "$HW_MODEL" ]; then
        HW_MODEL=$(printf '%s %s' "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" "$(cat /sys/class/dmi/id/product_name 2>/dev/null)")
        HW_MODEL=$(echo "$HW_MODEL" | sed 's/^ *//; s/ *$//')
    fi

    CODENAME=""; PRETTY=""; VERSION_ID_LOCAL=""
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        CODENAME="${VERSION_CODENAME:-}"
        PRETTY="${PRETTY_NAME:-}"
        VERSION_ID_LOCAL="${VERSION_ID:-}"
    fi

    IS_DIETPI=0
    [ -x /boot/dietpi/dietpi-software ] && IS_DIETPI=1
}

# Von LoxBerry vorgesehene NodeSource-Major-Version je Debian-Codename.
# Leer = auf dieser Basis nutzt LoxBerry NICHT NodeSource, sondern DietPi.
recommended_nodesource_major() {
    case "$CODENAME" in
        buster)   echo 12 ;;
        bullseye) echo 18 ;;
        *)        echo "" ;;
    esac
}

# Grobe Plausibilitaet: hat nodejs.org/NodeSource fuer diese Arch ueberhaupt
# einen Build der gewaehlten Major-Version? (armv7l faellt ab node 24 weg.)
nodesource_arch_plausible() {
    local major="$1"
    if [ "$NODE_ARCH" = "armv7l" ] && [ "$major" -ge 24 ] 2>/dev/null; then
        return 1
    fi
    if [ "$NODE_ARCH" = "armv6l" ]; then
        return 1   # offiziell keine armv6l-Node-Builds
    fi
    return 0
}

# ============================================================
# 1) System-Info
# ============================================================
show_system_info() {
    echo "------------------------------------------------------------"
    echo "Geraet:      ${HW_MODEL:-unbekannt}"
    echo "Architektur: $ARCH  (Node-Arch: $NODE_ARCH)"
    echo "OS:          ${PRETTY:-unbekannt} (Codename: ${CODENAME:-?})"
    echo "DietPi:      $( [ "$IS_DIETPI" -eq 1 ] && echo "ja (Node = Software-ID 9)" || echo "nein" )"
    local rec; rec=$(recommended_nodesource_major)
    if [ -n "$rec" ]; then
        echo "LoxBerry-Standard hier: NodeSource node $rec -> /usr/bin/node"
    elif [ "$IS_DIETPI" -eq 1 ]; then
        echo "LoxBerry-Standard hier: DietPi (Software 9) -> /usr/local/bin/node"
    else
        echo "LoxBerry-Standard hier: nicht eindeutig (Codename ${CODENAME:-?})"
    fi
    echo "------------------------------------------------------------"
}

# ============================================================
# 2) Node/npm-Status
# ============================================================
probe_bin() {
    # $1 = Pfad zu einem node/npm-Binary
    local p="$1"
    if [ ! -e "$p" ]; then
        echo "  $p: nicht vorhanden"
        return
    fi
    local real ver owner pkg
    real=$(readlink -f "$p" 2>/dev/null)
    ver=$("$p" -v 2>/dev/null)
    owner=$(stat -c '%U:%G' "$p" 2>/dev/null)
    pkg=$(dpkg -S "$real" 2>/dev/null | cut -d: -f1)
    [ -z "$pkg" ] && pkg="(kein dpkg-Paket)"
    local link=""
    [ -L "$p" ] && link=" -> $real"
    echo "  $p${link}"
    echo "     Version: ${ver:-<nicht ausfuehrbar>}  Besitzer: ${owner:-?}  Paket: $pkg"
}

show_node_status() {
    echo "--- node/npm im PATH (which -a) ---"
    which -a node 2>/dev/null || echo "  node: nicht im PATH"
    which -a npm  2>/dev/null || echo "  npm:  nicht im PATH"
    echo "--- feste Pfade ---"
    probe_bin /usr/bin/node
    probe_bin /usr/local/bin/node
    probe_bin /usr/bin/npm
    probe_bin /usr/local/bin/npm
    echo "--- apt-Paket nodejs/npm ---"
    dpkg -l 2>/dev/null | grep -iE '^ii +(nodejs|npm) ' || echo "  (kein apt-Paket nodejs/npm installiert)"
    echo "--- NodeSource-Source-Listen ---"
    grep -rniE 'nodesource' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || echo "  (keine)"
}

confirm() {
    # $1 = Frage; Rueckgabe 0 = ja
    local a
    read -rp "$1 [j/N] " a
    case "$a" in j|J|y|Y) return 0 ;; *) return 1 ;; esac
}

# Alle apt-Quellen-Dateien ausgeben (Basis + Drop-ins, .list und .sources).
all_source_files() {
    [ -f /etc/apt/sources.list ] && echo /etc/apt/sources.list
    shopt -s nullglob
    local f
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        echo "$f"
    done
    shopt -u nullglob
}

# ============================================================
# 3) Node/npm via apt-get
# ============================================================
apt_node_menu() {
    echo "--- apt-get: Kandidat pruefen ---"
    apt-cache policy nodejs 2>/dev/null | head -4
    local cand
    cand=$(apt-cache policy nodejs 2>/dev/null | awk '/Candidate:/{print $2}')
    if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
        echo "<WARNUNG> Kein apt-Kandidat fuer 'nodejs' - auf dieser Plattform via apt nicht installierbar."
    else
        echo "apt wuerde installieren: nodejs $cand  (Debian-Version, oft aelter als NodeSource/DietPi)."
    fi
    echo ""
    echo "  1) nodejs + npm via apt installieren"
    echo "  2) nodejs + npm via apt deinstallieren (purge)"
    echo "  0) zurueck"
    local c; read -rp "Auswahl: " c
    case "$c" in
        1)
            if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
                confirm "Trotzdem versuchen?" || return
            fi
            apt-get update
            apt-get install -y nodejs npm
            ;;
        2)
            confirm "nodejs/npm wirklich per apt purgen?" || return
            apt-get purge -y nodejs npm
            apt-get autoremove -y
            ;;
        *) : ;;
    esac
}

# ============================================================
# 4) Node/npm via NodeSource
# ============================================================
refresh_nodesource_key() {
    mkdir -p "$(dirname "$NODESOURCE_KEYRING")"
    if curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
         | gpg --batch --yes --dearmor -o "$NODESOURCE_KEYRING" 2>/dev/null; then
        chmod 0644 "$NODESOURCE_KEYRING"
        echo "NodeSource-Key aktualisiert ($NODESOURCE_KEYRING)."
    else
        echo "<WARNUNG> NodeSource-Key konnte nicht geladen werden."
    fi
}

ensure_nodesource_repo() {
    local major="$1"
    local want="deb [signed-by=$NODESOURCE_KEYRING] https://deb.nodesource.com/node_${major}.x nodistro main"
    if [ -f "$NODESOURCE_LIST" ] && grep -qF "node_${major}.x" "$NODESOURCE_LIST"; then
        echo "NodeSource-Liste bereits korrekt (node $major)."
    else
        echo "$want" > "$NODESOURCE_LIST"
        echo "NodeSource-Liste geschrieben: $want"
    fi
}

nodesource_node_menu() {
    local rec; rec=$(recommended_nodesource_major)
    echo "--- NodeSource ---"
    if [ -n "$rec" ]; then
        echo "Empfohlen fuer ${CODENAME}: node $rec"
    else
        echo "Hinweis: Auf ${CODENAME:-?} nutzt LoxBerry normalerweise DietPi, NICHT NodeSource."
        echo "         (Menuepunkt 7 fuer DietPi.)"
    fi
    echo ""
    echo "  1) NodeSource-Node installieren"
    echo "  2) NodeSource-Node deinstallieren (purge + Liste entfernen)"
    echo "  0) zurueck"
    local c; read -rp "Auswahl: " c
    case "$c" in
        1)
            local major="$rec"
            read -rp "Node-Major-Version [${rec:-z.B. 22}]: " major
            [ -z "$major" ] && major="$rec"
            if ! [[ "$major" =~ ^[0-9]+$ ]]; then
                echo "Ungueltige Version."
                return
            fi
            # Sicherheitsabfragen, wenn es nach unserem Wissen nicht passen kann.
            if [ -n "$rec" ] && [ "$major" != "$rec" ]; then
                echo "<WARNUNG> Fuer ${CODENAME} ist node $rec vorgesehen, du waehlst node $major."
                confirm "Trotzdem fortfahren?" || return
            fi
            if ! nodesource_arch_plausible "$major"; then
                echo "<WARNUNG> Fuer Architektur $NODE_ARCH gibt es fuer node $major moeglicherweise KEINE Builds."
                confirm "Trotzdem versuchen?" || return
            fi
            refresh_nodesource_key
            ensure_nodesource_repo "$major"
            apt-get update
            if apt-get install -y nodejs; then
                echo "Ergebnis: node=$(node -v 2>/dev/null || echo n/a), npm=$(npm -v 2>/dev/null || echo n/a)"
            else
                echo "<WARNUNG> apt-get install nodejs (NodeSource node $major) fehlgeschlagen -"
                echo "          evtl. kein Build fuer $NODE_ARCH oder Version am EOL."
            fi
            ;;
        2)
            confirm "NodeSource-Node purgen und Liste entfernen?" || return
            apt-get purge -y nodejs
            apt-get autoremove -y
            rm -f "$NODESOURCE_LIST"
            echo "NodeSource-Liste entfernt."
            ;;
        *) : ;;
    esac
}

# ============================================================
# 5) NodeSource-Eintrag in der Sources-Liste pruefen/hinzufuegen
# ============================================================
sources_check_menu() {
    echo "--- Vorhandene NodeSource-Eintraege ---"
    if grep -rniE 'nodesource' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        :
    else
        echo "  (kein NodeSource-Eintrag vorhanden)"
        local rec; rec=$(recommended_nodesource_major)
        if [ -n "$rec" ]; then
            echo "Empfohlen fuer ${CODENAME}: node $rec"
        else
            echo "Hinweis: Auf ${CODENAME:-?} nutzt LoxBerry normalerweise DietPi, NICHT NodeSource."
        fi
        local major
        read -rp "NodeSource-Eintrag hinzufuegen? Node-Major [Enter=${rec:-abbrechen}]: " major
        [ -z "$major" ] && major="$rec"
        if [ -z "$major" ]; then
            echo "Abgebrochen."
            return
        fi
        if ! [[ "$major" =~ ^[0-9]+$ ]]; then
            echo "Ungueltige Version."
            return
        fi
        if [ -n "$rec" ] && [ "$major" != "$rec" ]; then
            echo "<WARNUNG> Fuer ${CODENAME} ist node $rec vorgesehen, du waehlst node $major."
            confirm "Trotzdem eintragen?" || return
        fi
        if ! nodesource_arch_plausible "$major"; then
            echo "<WARNUNG> Fuer Architektur $NODE_ARCH gibt es fuer node $major moeglicherweise KEINE Builds."
            confirm "Trotzdem eintragen?" || return
        fi
        refresh_nodesource_key
        ensure_nodesource_repo "$major"
        apt-get update
    fi
}

# ============================================================
# 6) Abgelaufene/fehlende Repo-Keys erneuern
# ============================================================
renew_keys_menu() {
    echo "--- Konfigurierte APT-Quellen ---"
    all_source_files | sed 's/^/  /'
    echo ""
    echo "--- apt-get update (Signaturen/Keys pruefen) ---"
    local PROBLEM_RE='NO_PUBKEY|EXPKEY|KEYEXPIRED|no valid OpenPGP|couldn.?t be verified|not be verified|is not signed|invalid signature|^Err:|^W: (GPG|An error)'
    local out
    out=$(apt-get update 2>&1)
    echo "$out"
    # Signatur-/Key-Probleme breit erkennen (nicht nur NO_PUBKEY/EXPKEY -
    # ein korruptes/fehlendes signed-by-Keyring meldet apt anders).
    local problems
    problems=$(echo "$out" | grep -iE "$PROBLEM_RE")
    if [ -z "$problems" ]; then
        echo "Keine Signatur-/Key-Probleme gefunden."
        return
    fi
    echo ""
    echo "Gefundene Probleme:"
    echo "$problems"
    echo ""
    # Nur die Repos auffrischen, die im apt-Update tatsaechlich betroffen waren.
    if echo "$problems" | grep -qiE 'nodesource'; then
        echo "-> NodeSource-Key auffrischen ..."
        refresh_nodesource_key
    fi
    if echo "$problems" | grep -qiE 'yarnpkg|dl\.yarnpkg'; then
        echo "-> Yarn-Key auffrischen ..."
        curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --batch --yes --dearmor -o "$YARN_KEYRING" 2>/dev/null \
            && chmod 0644 "$YARN_KEYRING" && echo "Yarn-Key aktualisiert." \
            || echo "<WARNUNG> Yarn-Key konnte nicht geladen werden."
    fi
    # Uebrige, unbekannte fehlende Keys per ID melden.
    local missing
    missing=$(echo "$out" | grep -oiE 'NO_PUBKEY [0-9A-F]+' | awk '{print $2}' | sort -u)
    [ -n "$missing" ] && echo "Fehlende Key-IDs (unbekannte Repos, ggf. manuell): $missing"
    echo ""
    echo "--- erneute Pruefung ---"
    if apt-get update 2>&1 | grep -qiE "$PROBLEM_RE"; then
        echo "<WARNUNG> Es bleiben Probleme - betroffene Repos manuell pruefen."
    else
        echo "OK - keine Signatur-/Key-Probleme mehr."
    fi
}

# ============================================================
# 7) DietPi-Node verwalten (Bookworm/Trixie / LB4)
# ============================================================
dietpi_node_menu() {
    if [ "$IS_DIETPI" -ne 1 ]; then
        echo "DietPi nicht gefunden (/boot/dietpi/dietpi-software)."
        echo "Dieser Weg ist nur auf DietPi-Basis (Bookworm/Trixie, LB4) relevant."
        return
    fi
    echo "DietPi verwaltet Node.js als Software-ID 9 (Ziel: /usr/local/bin/node)."
    echo "Bei beschaedigtem Node genuegt ein Reinstall - KEIN kompletter LoxBerry-Neuaufbau noetig."
    echo ""
    echo "  1) Node neu installieren (reinstall)  <- bei Beschaedigung"
    echo "  2) Node deinstallieren"
    echo "  3) Node installieren"
    echo "  0) zurueck"
    local c; read -rp "Auswahl: " c
    case "$c" in
        1) confirm "DietPi: Node (Software 9) neu installieren?" && /boot/dietpi/dietpi-software reinstall 9 ;;
        2) confirm "DietPi: Node (Software 9) deinstallieren?"    && /boot/dietpi/dietpi-software uninstall 9 ;;
        3) confirm "DietPi: Node (Software 9) installieren?"      && /boot/dietpi/dietpi-software install 9 ;;
        *) : ;;
    esac
}

# ============================================================
# 8) Manuell installiertes Node/npm unter /usr/local entfernen
# ============================================================
remove_local_node_menu() {
    echo "--- Manuell installiertes Node/npm unter /usr/local ---"
    local found=0 p
    for p in /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack; do
        if [ -e "$p" ] || [ -L "$p" ]; then echo "  $p"; found=1; fi
    done
    if [ -d /usr/local/lib/node_modules ]; then
        echo "  /usr/local/lib/node_modules/  ($(ls -1 /usr/local/lib/node_modules 2>/dev/null | tr '\n' ' '))"
        found=1
    fi
    [ -e /usr/local/include/node ] && { echo "  /usr/local/include/node"; found=1; }
    if [ "$found" -eq 0 ]; then
        echo "  Nichts gefunden - kein /usr/local-Node vorhanden."
        return
    fi
    if [ "$IS_DIETPI" -eq 1 ]; then
        echo ""
        echo "<WARNUNG> DietPi erkannt! Auf Bookworm/Trixie ist /usr/local/bin/node das"
        echo "          LEGITIME System-Node (von DietPi verwaltet). Zum Reparieren besser"
        echo "          Menuepunkt 7 (DietPi reinstall) nutzen, statt hier zu loeschen."
    fi
    echo ""
    confirm "Diese /usr/local-Node/npm-Dateien wirklich LOESCHEN?" || return
    for p in /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack; do
        if [ -e "$p" ] || [ -L "$p" ]; then rm -f "$p" && echo "entfernt: $p"; fi
    done
    [ -d /usr/local/lib/node_modules ] && rm -rf /usr/local/lib/node_modules && echo "entfernt: /usr/local/lib/node_modules"
    [ -e /usr/local/include/node ] && rm -rf /usr/local/include/node && echo "entfernt: /usr/local/include/node"
    echo "Fertig."
}

# ============================================================
# 9) APT-Repo-Dateien verwalten (anzeigen/loeschen)
# ============================================================
sources_manage_menu() {
    echo "--- Alle APT-Quellen-Dateien ---"
    local files=()
    mapfile -t files < <(all_source_files)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "  (keine gefunden)"
        return
    fi
    local i=1 f firstdeb tag
    for f in "${files[@]}"; do
        firstdeb=$(grep -m1 -iE '^\s*(deb |Types:|URIs:)' "$f" 2>/dev/null | sed 's/^ *//')
        tag=""
        [ "$f" = "/etc/apt/sources.list" ] && tag="  <-- Debian-Basis (Loeschen bricht apt!)"
        echo "  $i) $f$tag"
        echo "       [${firstdeb:-leer}]"
        i=$((i+1))
    done
    echo "  0) zurueck"
    local c; read -rp "Nummer zum LOESCHEN (0 = zurueck): " c
    if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 1 ] || [ "$c" -gt "${#files[@]}" ]; then
        echo "Abgebrochen."
        return
    fi
    local sel="${files[$((c-1))]}"
    echo ""
    echo "Inhalt von $sel:"
    cat "$sel"
    echo ""
    if [ "$sel" = "/etc/apt/sources.list" ]; then
        echo "<WARNUNG> Das ist die Debian-Basis-Quelle - Loeschen legt apt lahm"
        echo "          (keine Updates/Installs mehr moeglich)!"
    fi
    confirm "Diese Datei ($sel) wirklich loeschen?" || return
    rm -f "$sel" && echo "geloescht: $sel"
    echo "Hinweis: danach 'apt-get update' (z.B. via Menue 6) ausfuehren."
}

# ============================================================
# Hauptmenue
# ============================================================
detect_system

while true; do
    echo ""
    echo "============================================================"
    echo " LoxBerry Node/npm-Tool  (${CODENAME:-?} / $ARCH)"
    echo "============================================================"
    echo " 1) System-Info (Plattform, Architektur, Debian-Version)"
    echo " 2) Node/npm-Status (welche wo installiert)"
    echo " 3) Node/npm via apt-get installieren/deinstallieren"
    echo " 4) Node/npm via NodeSource installieren/deinstallieren"
    echo " 5) NodeSource-Eintrag in Sources-Liste pruefen/hinzufuegen"
    echo " 6) Abgelaufene/fehlende Repo-Keys erneuern"
    echo " 7) Node via DietPi verwalten (Bookworm/Trixie / LB4)"
    echo " 8) Manuell installiertes Node/npm unter /usr/local entfernen"
    echo " 9) APT-Repo-Dateien verwalten (anzeigen/loeschen)"
    echo " 0) Beenden"
    echo "------------------------------------------------------------"
    read -rp "Auswahl: " CHOICE
    echo ""
    case "$CHOICE" in
        1) show_system_info ;;
        2) show_node_status ;;
        3) apt_node_menu ;;
        4) nodesource_node_menu ;;
        5) sources_check_menu ;;
        6) renew_keys_menu ;;
        7) dietpi_node_menu ;;
        8) remove_local_node_menu ;;
        9) sources_manage_menu ;;
        0) echo "Beendet."; exit 0 ;;
        *) echo "Ungueltige Auswahl." ;;
    esac
done
