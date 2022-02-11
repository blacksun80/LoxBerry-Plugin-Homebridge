#!/bin/bash

# Bashscript which is executed by bash *AFTER* complete installation is done
# (*AFTER* postinstall but *BEFORE* postupdate). Use with caution and remember,
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
#LBHOMEDIR=$5 # Comes from /etc/environment now. Fifth argument is
              # Base folder of LoxBerry

# Combine them with /etc/environment
PCGI=$LBPCGI/$PDIR
PHTML=$LBPHTML/$PDIR
PTEMPL=$LBPTEMPL/$PDIR
PDATA=$LBPDATA/$PDIR
PLOG=$LBPLOG/$PDIR # Note! This is stored on a Ramdisk now!
PCONFIG=$LBPCONFIG/$PDIR
PSBIN=$LBPSBIN/$PDIR
PBIN=$LBPBIN/$PDIR

echo "<INFO> Command is: $COMMAND"
echo "<INFO> Temporary folder is: $TEMPDIR"
echo "<INFO> (Short) Name is: $PSHNAME"
echo "<INFO> Installation folder is: $ARGV3"
echo "<INFO> Plugin version is: $ARGV4"
echo "<INFO> Plugin CGI folder is: $PCGI"
echo "<INFO> Plugin HTML folder is: $PHTML"
echo "<INFO> Plugin Template folder is: $PTEMPL"
echo "<INFO> Plugin Data folder is: $PDATA"
echo "<INFO> Plugin Log folder (on RAMDISK!) is: $PLOG"
echo "<INFO> Plugin CONFIG folder is: $PCONFIG"
echo "<INFO> Plugin SBIN folder is: $PSBIN"
echo "<INFO> Plugin BIN folder is: $PBIN"

# Homebridge installieren
npm install -g --unsafe-perm homebridge

# Homebridge Config UI installieren
npm install -g --unsafe-perm homebridge-config-ui-x

echo "<INFO> Kopiere Datei homebridge.service."
cp -r $5/bin/plugins/$3/homebridge.service /etc/systemd/system

echo "<INFO> Kopiere Datei homebridge."
cp -r $5/bin/plugins/$3/homebridge /etc/default

echo "<INFO> Service homebridge erzeugen"
systemctl enable homebridge
systemctl daemon-reload

if [ ! -f "/tmp/config.json" ]
then
    echo "<INFO> Keine Konfigurationsdatei zum Wiederherstellen vorhanden"
else
    echo "<INFO> Konfigurationsdatei config.json wiederherstellen"
    cp -ar /tmp/homebridge /$5/config/plugins/
    rm -r /tmp/homebridge
fi

# Ist der Service homebridge installiert?
status="$(systemctl status homebridge | grep homebridge)"
if [ "${status}" ]
then
    echo "<INFO> Service homebridge wurde installiert"
    
    # Service homebridge starten
    echo "<INFO> Starte Service Homebridge..."
    systemctl start homebridge
    
    # Läuft der Service homebridge aktuell?
    status="$(systemctl is-active homebridge.service)"
    if [ "${status}" = "active" ] 
    then
        echo "<INFO> Service homebridge wurde erfolgreich gestartet"
        exit 0
    else
        echo "<ERROR> Service homebridge konnte nicht gestartet"
        exit 1
    fi
else
    echo "<ERROR> Service homebridge konnte nicht installiert werden"
    exit 1
fi
