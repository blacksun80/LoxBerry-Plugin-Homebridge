#!/bin/bash
# preupgrade.sh
#
# Laeuft als User "loxberry", NUR bei einem Update, VOR dem Loeschen der
# alten Plugin-Ordner.
#
# Sichert Config und Runtime aus dem Plugin-Ordner in einen gemeinsamen
# Backup-Root (per "mv").
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
PDATA=$LBPDATA/$PDIR
HB_RUNTIME_DIR="$PDATA/homebridge_runtime"

BACKUP_ROOT="$LBHOMEDIR/data/system/tmp/homebridge_backup"
CONFIG_BACKUP="$BACKUP_ROOT/config"
RUNTIME_BACKUP="$BACKUP_ROOT/runtime"

mkdir -p "$BACKUP_ROOT"

# Alte Backup-Reste entfernen.
rm -rf "$CONFIG_BACKUP" "$RUNTIME_BACKUP"

echo "============================================================"
echo "Config sichern"
echo "============================================================"

# Config per "cp" sichern (Original bleibt bis zum LoxBerry-Loeschlauf liegen).
# So bleibt die Config bei einem Abbruch erhalten und geht nie verloren.
if [ -d "$PCONFIG" ] && [ -n "$(ls -A "$PCONFIG" 2>/dev/null)" ]; then
    mkdir -p "$CONFIG_BACKUP"
    if cp -a "$PCONFIG"/. "$CONFIG_BACKUP"/; then
        echo "<OK> Config nach $CONFIG_BACKUP gesichert."
    else
        echo "<ERROR> Sicherung der Config fehlgeschlagen - Update wird abgebrochen."
        exit 2
    fi
else
    echo "<INFO> Kein Config-Ordner ($PCONFIG) vorhanden - nichts zu sichern."
fi

echo ""
echo "============================================================"
echo "Runtime sichern"
echo "============================================================"

if [ -d "$HB_RUNTIME_DIR" ] && [ -n "$(ls -A "$HB_RUNTIME_DIR" 2>/dev/null)" ]; then
    if mv "$HB_RUNTIME_DIR" "$RUNTIME_BACKUP"; then
        echo "<OK> Runtime nach $RUNTIME_BACKUP verschoben."
    else
        echo "<ERROR> Sicherung der Runtime fehlgeschlagen - Update wird abgebrochen."
        exit 2
    fi
else
    echo "<INFO> Kein Runtime-Ordner ($HB_RUNTIME_DIR) vorhanden - nichts zu sichern."
fi

exit 0
