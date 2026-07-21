# LoxBerry Homebridge Plugin

Installiert und betreibt [Homebridge](https://homebridge.io/) samt der Weboberfläche
[homebridge-config-ui-x](https://github.com/homebridge/homebridge-config-ui-x) direkt auf
einem LoxBerry. Homebridge läuft in einer **eigenen, isolierten Node.js-Umgebung** – das
System-Node des LoxBerry wird dafür nicht verändert.

## Funktionen

- Homebridge + Config-UI-X werden automatisch installiert und als Dienst eingerichtet.
- **Isoliertes Node.js**: passende Node-Version wird automatisch anhand der Anforderungen von
  Config-UI-X gewählt und getrennt vom System installiert.
- **Konfiguration übersteht Updates**: Pairings/Einstellungen werden vor jedem Update gesichert
  und danach automatisch wiederhergestellt.
- **Schnelle Updates**: die Node-/Homebridge-Runtime liegt an einem dauerhaften Ort und wird nur
  neu aufgebaut, wenn sich wirklich etwas ändert (neue Node- oder Homebridge-Version).
- Läuft auf Raspberry Pi (arm64/armv7) und x86_64.

## Voraussetzungen

- LoxBerry **ab Version 2.0.0**.
- Internetzugang während der Installation (Node.js und die npm-Pakete werden geladen).
- Etwas Geduld bei der Erstinstallation: Homebridge baut native Module – das dauert auf einem
  Raspberry Pi einige Minuten. Der Fortschritt ist im Installationslog sichtbar.

## Installation

Über die LoxBerry-Plugin-Verwaltung installieren (Plugin-Archiv hochladen oder Autoupdate).
Ein Neustart ist nicht erforderlich.

Nach der Installation ist die Homebridge-Weboberfläche erreichbar unter:

```
http://<LoxBerry-IP>:8082
```

## Bedienung / Konfiguration

Homebridge selbst wird komplett über die **Config-UI-X-Weboberfläche** (Port 8082) konfiguriert –
dort werden Plugins installiert, Zubehör eingerichtet und die Bridge mit HomeKit gekoppelt.

- **Speicherort der Konfiguration:** `/opt/loxberry/config/plugins/homebridge`
- **Dienst:** systemd-Dienst `homebridge.service` (User `loxberry`)

## Updates

Ein Plugin-Update installiert eine ggf. neuere Homebridge-/Config-UI-X-Version. Die bestehende
Konfiguration inklusive aller HomeKit-Pairings bleibt dabei erhalten – sie wird vor dem Update
gesichert und anschließend zurückgespielt (es werden die letzten 5 Sicherungen aufbewahrt unter
`data/system/tmp/homebridge_config_backup`).

## Deinstallation

Beim Entfernen des Plugins werden der Dienst, die isolierte Node-Runtime und die Konfigurations-
Sicherungen aufgeräumt. Das apt-System-Node bleibt bewusst erhalten, da es von anderen
Komponenten genutzt werden könnte.

## Hinweise zur Technik

Details zum internen Ablauf (Installationsskripte, Pfade, Kompatibilität) stehen in
[CLAUDE.md](CLAUDE.md).

## Weiterführende Links

- LoxBerry-Wiki: <https://wiki.loxberry.de/plugins/homebridge/start>
- Homebridge: <https://homebridge.io/>
