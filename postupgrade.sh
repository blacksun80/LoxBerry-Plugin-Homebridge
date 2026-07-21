#!/bin/bash
# Shell script which is executed *AFTER* complete installation is done, but
# ONLY in case of an update (matching preupgrade.sh). Restores the Homebridge
# config that preupgrade.sh saved to /tmp before the LoxBerry core installer
# deleted the plugin's old config folder. Runs BEFORE postroot.sh, so the
# config.json is already back in place when postroot.sh calls
# "hb-service ... install" (hb-service only creates a default config.json if
# none exists - an existing one is left untouched).
#
# Exit code must be 0 if executed successfull.
# Exit code 1 gives a warning but continues installation.
# Exit code 2 cancels installation.
#
# Will be executed as user "loxberry".
#
# You can use all vars from /etc/environment in this script.
#
# We add 5 additional arguments when executing this script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>

COMMAND=$0    # Zero argument is shell command
PTEMPDIR=$1   # First argument is temp folder during install
PSHNAME=$2    # Second argument is Plugin-Name for scipts etc.
PDIR=$3       # Third argument is Plugin installation folder
PVERSION=$4   # Forth argument is Plugin version
LBHOMEDIR=$5  # Fifth argument is Base folder of LoxBerry
PTEMPPATH=$6  # Sixth argument is full temp path during install

# Combine them with /etc/environment
PCONFIG=$LBPCONFIG/$PDIR

HB_STORAGE_DIR="$PCONFIG"
HB_BACKUP_STAGING="/tmp/homebridge_config_backup"

if [ -d "$HB_BACKUP_STAGING" ]; then
    echo "<INFO> Stelle gesicherte Homebridge-Konfiguration wieder her."
    echo "<INFO> Ziel: $HB_STORAGE_DIR"
    mkdir -p "$HB_STORAGE_DIR"
    cp -a "$HB_BACKUP_STAGING"/. "$HB_STORAGE_DIR"/
    if [ $? -eq 0 ]; then
        echo "<OK> Homebridge-Konfiguration erfolgreich wiederhergestellt."
        # Zwischenlager aufraeumen - wird nicht mehr benoetigt (liegt ohnehin
        # in /tmp und wuerde spaetestens beim naechsten Reboot verschwinden).
        rm -rf "$HB_BACKUP_STAGING"
    else
        echo "<ERROR> Wiederherstellung der Homebridge-Konfiguration ist fehlgeschlagen. Backup liegt noch unter $HB_BACKUP_STAGING."
        exit 1
    fi
else
    echo "<INFO> Keine gesicherte Konfiguration gefunden (vermutlich Erstinstallation) - nichts wiederherzustellen."
fi

exit 0