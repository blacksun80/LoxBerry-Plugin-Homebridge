#!/bin/bash
# preupgrade.sh
#
# Laeuft bei einem Update vor preinstall.sh, als User "loxberry".
# Sichert die bestehende Homebridge-Config nach $LBHOMEDIR/data/system/tmp,
# da der LoxBerry-Installer den Config-Ordner des Plugins bei jedem Update
# loescht. Legt bei jedem Lauf ein neues, zeitgestempeltes Backup an und
# haelt davon immer nur die letzten 5 vor.
#
# Exit code 0 = ok, 1 = Warnung (Update laeuft weiter), 2 = Update abbrechen.
#
# Argumente: command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER> <TEMPPATH>

COMMAND=$0
PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
LBHOMEDIR=$5
PTEMPPATH=$6

PCONFIG=$LBPCONFIG/$PDIR

HB_STORAGE_DIR="$PCONFIG"
BACKUP_ROOT="$LBHOMEDIR/data/system/tmp/homebridge_config_backup"
KEEP_BACKUPS=5
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/backup_${TIMESTAMP}"

echo "<INFO> Sichere bestehende Homebridge-Konfiguration vor dem Update."
echo "<INFO> Quelle: $HB_STORAGE_DIR"
echo "<INFO> Ziel:   $BACKUP_DIR"

if [ -d "$HB_STORAGE_DIR" ] && [ -n "$(ls -A "$HB_STORAGE_DIR" 2>/dev/null)" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$HB_STORAGE_DIR"/. "$BACKUP_DIR"/
    if [ $? -eq 0 ]; then
        echo "<OK> Homebridge-Konfiguration nach $BACKUP_DIR gesichert."
    else
        echo "<WARNING> Sicherung der Homebridge-Konfiguration ist fehlgeschlagen. Das Update laeuft trotzdem weiter - die bestehende Konfiguration koennte dabei verloren gehen."
        rm -rf "$BACKUP_DIR"
    fi
else
    echo "<INFO> Kein bestehendes/nicht-leeres Konfigurationsverzeichnis gefunden ($HB_STORAGE_DIR) - nichts zu sichern."
fi

# Rotation: nur die letzten $KEEP_BACKUPS Backups behalten.
if [ -d "$BACKUP_ROOT" ]; then
    mapfile -t OLD_BACKUPS < <(ls -1dt "$BACKUP_ROOT"/backup_* 2>/dev/null | tail -n "+$((KEEP_BACKUPS + 1))")
    if [ "${#OLD_BACKUPS[@]}" -gt 0 ]; then
        echo "<INFO> Entferne ${#OLD_BACKUPS[@]} alte Backup(s), behalte die letzten $KEEP_BACKUPS."
        for old in "${OLD_BACKUPS[@]}"; do
            rm -rf "$old"
        done
    fi
fi

exit 0