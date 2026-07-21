#!/bin/bash
# Shell script which is executed in case of an update (if this plugin is already
# installed on the system). This script is executed as very first step (*BEFORE*
# preinstall.sh) and is used here to save the existing Homebridge config
# (config.json, persist/, .uix-secrets etc.) to /tmp - because the LoxBerry
# core installer unconditionally deletes the plugin's config/bin/data folders
# as part of EVERY update (step "Removing old installation"), BEFORE
# postroot.sh ever gets to run. See postupgrade.sh for the matching restore.
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

# Homebridge-Storage (config.json, persist/ ...), siehe hb-service -U Parameter
# in postroot.sh. Zwischenlager bewusst in /tmp - das empfiehlt die offizielle
# LoxBerry-Doku fuer preupgrade.sh genau fuer diesen Zweck.
HB_STORAGE_DIR="$PCONFIG"
HB_BACKUP_STAGING="/tmp/homebridge_config_backup"

echo "<INFO> Sichere bestehende Homebridge-Konfiguration vor dem Update."
echo "<INFO> Quelle: $HB_STORAGE_DIR"

if [ -d "$HB_STORAGE_DIR" ]; then
    rm -rf "$HB_BACKUP_STAGING"
    mkdir -p "$HB_BACKUP_STAGING"
    cp -a "$HB_STORAGE_DIR"/. "$HB_BACKUP_STAGING"/
    if [ $? -eq 0 ]; then
        echo "<OK> Homebridge-Konfiguration nach $HB_BACKUP_STAGING gesichert."
    else
        echo "<WARNING> Sicherung der Homebridge-Konfiguration ist fehlgeschlagen. Das Update laeuft trotzdem weiter - die bestehende Konfiguration koennte dabei verloren gehen."
    fi
else
    echo "<INFO> Kein bestehendes Konfigurationsverzeichnis gefunden ($HB_STORAGE_DIR) - nichts zu sichern."
fi

exit 0