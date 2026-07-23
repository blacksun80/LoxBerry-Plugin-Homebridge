#!/bin/bash
# node_uninstall.sh
#
# Entfernt ALLE Spuren einer System-Node/npm-Installation auf einem
# LoxBerry-Testgeraet, damit ein sauberer "kein System-Node vorhanden"-Zustand
# fuer Testzwecke hergestellt werden kann (z.B. um Schritt 1 von postroot.sh
# zu testen).
#
# Entfernt:
#   1. apt-Paket "nodejs"/"npm" (falls vorhanden, per purge inkl. Configs)
#   2. NodeSource-Repo-Eintraege unter /etc/apt/sources.list.d/
#   3. Manuell/anders installierte Binaries unter /usr/local/bin (node, npm,
#      npx, corepack) - typische Ueberbleibsel z.B. von NodeSource-Installern
#      oder manuellen Installationen ausserhalb von apt.
#   4. Globale npm-Pakete unter /usr/local/lib/node_modules (unabhaengig vom
#      apt-Paket - npm install -g legt dort ab, das apt purge NICHT anfasst).
#   5. Doku-/Include-Reste unter /usr/local/include/node, /usr/share/doc/nodejs.
#
# Fasst NICHT an:
#   - Die isolierte Homebridge-Runtime unter
#     /opt/loxberry/data/system/homebridge_runtime/ (die ist komplett getrennt
#     und bleibt unberuehrt - bewusst NICHT Teil dieses Skripts).
#   - nvm/n-Installationen im Home-Verzeichnis eines Users (~/.nvm, ~/.n) -
#     falls vorhanden, bitte manuell pruefen/entfernen.
#
# Nutzung:
#   sudo bash node_uninstall.sh          # fragt vor dem Loeschen nach
#   sudo bash node_uninstall.sh --yes    # keine Rueckfrage, direkt loeschen

set -e

ASSUME_YES=0
if [ "$1" = "--yes" ] || [ "$1" = "-y" ]; then
    ASSUME_YES=1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "FEHLER: Bitte als root ausfuehren (sudo bash node_uninstall.sh)."
    exit 1
fi

echo "============================================================"
echo "IST-Zustand vor dem Aufraeumen"
echo "============================================================"
echo "--- dpkg (nodejs/npm) ---"
dpkg -l 2>/dev/null | grep -iE 'nodejs|^ii  npm ' || echo "(kein passendes apt-Paket gefunden)"
echo "--- which -a node/npm ---"
which -a node 2>/dev/null || echo "(node nicht gefunden)"
which -a npm 2>/dev/null || echo "(npm nicht gefunden)"
echo "--- Versionen (falls aufloesbar) ---"
node -v 2>/dev/null || echo "node: n/a"
npm -v 2>/dev/null || echo "npm: n/a"
echo "--- NodeSource-Repo-/Keyring-/Pinning-Dateien ---"
NODESOURCE_PREVIEW=$( { grep -rli "nodesource" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; \
                        find /etc/apt/sources.list.d/ /etc/apt/keyrings /etc/apt/trusted.gpg.d /usr/share/keyrings /etc/apt/preferences.d \
                             -iname '*nodesource*' 2>/dev/null; } | sort -u )
if [ -n "$NODESOURCE_PREVIEW" ]; then
    printf '%s\n' "$NODESOURCE_PREVIEW"
else
    echo "(kein NodeSource-Eintrag gefunden)"
fi
echo "--- Globale npm-Module (/usr/local/lib/node_modules) ---"
ls -1 /usr/local/lib/node_modules 2>/dev/null || echo "(nicht vorhanden)"
echo ""

if [ "$ASSUME_YES" -eq 0 ]; then
    read -rp "Wirklich ALLE System-Node/npm-Spuren oben entfernen? [j/N] " ANTWORT
    case "$ANTWORT" in
        j|J|y|Y) ;;
        *) echo "Abgebrochen - nichts wurde geloescht."; exit 0 ;;
    esac
fi

echo ""
echo "============================================================"
echo "1. apt-Paket nodejs/npm entfernen"
echo "============================================================"
if dpkg -l 2>/dev/null | grep -qiE '^ii  (nodejs|npm) '; then
    apt-get purge -y nodejs npm 2>/dev/null || apt-get purge -y nodejs 2>/dev/null || true
    apt-get autoremove -y || true
    echo "<OK> apt-Paket(e) entfernt (purge + autoremove)."
else
    echo "<INFO> Kein apt-Paket nodejs/npm installiert - nichts zu tun."
fi

echo ""
echo "============================================================"
echo "2. NodeSource-Repo-Eintraege entfernen"
echo "============================================================"
# Breiter suchen als nur "deb.nodesource.com" als Text: neuere apt-Versionen
# nutzen das deb822-Format (.sources statt .list), dort steht die URL z.B. als
# "URIs: https://deb.nodesource.com/..." - und der Installer legt je nach
# Version unterschiedliche Dateinamen an (z.B. "nodesource.list",
# "nodesource.sources"). Deshalb sowohl nach Inhalt ("nodesource") als auch
# nach Dateinamen suchen, und mehrere moegliche Keyring-Verzeichnisse abklappern
# (aeltere Installer: /etc/apt/trusted.gpg.d/, neuere: /etc/apt/keyrings/ oder
# /usr/share/keyrings/).
NODESOURCE_FILES=$( { grep -rli "nodesource" /etc/apt/sources.list.d/ 2>/dev/null; \
                      find /etc/apt/sources.list.d/ -iname '*nodesource*' 2>/dev/null; } | sort -u )
if [ -n "$NODESOURCE_FILES" ]; then
    for f in $NODESOURCE_FILES; do
        echo "<INFO> Entferne NodeSource-Repo-Datei $f ..."
        rm -f "$f"
    done
else
    echo "<INFO> Kein NodeSource-Repo unter /etc/apt/sources.list.d/ gefunden."
fi

# Zugehoerige GPG-Keys/Pinning ueber alle bekannten Ablageorte hinweg entfernen -
# harmlos, falls dort nichts liegt.
find /etc/apt/keyrings /etc/apt/trusted.gpg.d /usr/share/keyrings /etc/apt/preferences.d \
    -iname '*nodesource*' -delete 2>/dev/null || true

if [ -n "$NODESOURCE_FILES" ]; then
    apt-get update || echo "<INFO> apt-get update nach Repo-Entfernung mit Warnungen/Fehlern - meist unkritisch (andere Quellen)."
    echo "<OK> NodeSource-Repo entfernt."
fi

echo ""
echo "============================================================"
echo "3. Manuelle Binaries unter /usr/local/bin entfernen"
echo "============================================================"
for b in node npm npx corepack; do
    if [ -e "/usr/local/bin/$b" ] || [ -L "/usr/local/bin/$b" ]; then
        echo "<INFO> Entferne /usr/local/bin/$b ..."
        rm -f "/usr/local/bin/$b"
    else
        echo "<INFO> /usr/local/bin/$b nicht vorhanden - nichts zu tun."
    fi
done

echo ""
echo "============================================================"
echo "4. Globale npm-Module unter /usr/local/lib/node_modules entfernen"
echo "============================================================"
if [ -d /usr/local/lib/node_modules ]; then
    echo "<INFO> Entferne /usr/local/lib/node_modules (Inhalt: $(ls -1 /usr/local/lib/node_modules 2>/dev/null | tr '\n' ' '))"
    rm -rf /usr/local/lib/node_modules
else
    echo "<INFO> /usr/local/lib/node_modules nicht vorhanden - nichts zu tun."
fi

echo ""
echo "============================================================"
echo "5. Doku-/Include-Reste entfernen"
echo "============================================================"
for p in /usr/local/include/node /usr/share/doc/nodejs; do
    if [ -e "$p" ]; then
        echo "<INFO> Entferne $p ..."
        rm -rf "$p"
    else
        echo "<INFO> $p nicht vorhanden - nichts zu tun."
    fi
done

echo ""
echo "============================================================"
echo "Ergebnis"
echo "============================================================"
hash -r 2>/dev/null || true
echo "--- dpkg (nodejs/npm) ---"
dpkg -l 2>/dev/null | grep -iE 'nodejs|^ii  npm ' || echo "(kein apt-Paket mehr vorhanden)"
echo "--- which -a node/npm ---"
which -a node 2>/dev/null || echo "(node nicht mehr gefunden)"
which -a npm 2>/dev/null || echo "(npm nicht mehr gefunden)"
echo "--- Versionen ---"
node -v 2>/dev/null || echo "node: n/a"
npm -v 2>/dev/null || echo "npm: n/a"
echo ""
echo "Fertig. System-Node/npm sollte jetzt vollstaendig entfernt sein."
echo "Hinweis: Die isolierte Homebridge-Runtime unter"
echo "/opt/loxberry/data/system/homebridge_runtime/ wurde NICHT angefasst."

exit 0