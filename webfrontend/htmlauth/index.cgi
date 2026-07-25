#!/usr/bin/perl

# Homebridge-Plugin fuer LoxBerry - Webfrontend.
# Basiert auf der Struktur des LoxBerry-SamplePlugin (Michael Schlenstedt).
# Zeigt an, ob der Homebridge-Dienst laeuft, und verlinkt die Config-UI.

use strict;
use warnings;
use CGI;
use LoxBerry::System;
use LoxBerry::Web;

my $cgi = CGI->new();

# Zustand des systemd-Dienstes ermitteln (active|inactive|failed|unknown).
sub hb_status {
    my $s = `systemctl is-active homebridge.service 2>/dev/null`;
    chomp $s;
    $s = 'unknown' if !defined $s || $s eq '';
    return $s;
}

# AJAX-Endpunkt: nur den Status als Text ausgeben (fuer die Selbst-Aktualisierung).
if ( defined $cgi->param('ajax') && $cgi->param('ajax') eq 'status' ) {
    print "Content-Type: text/plain; charset=utf-8\n\n";
    print hb_status();
    exit;
}

# AJAX-Endpunkt: Node-Update-Check live ausfuehren (kein Cache - laeuft bei
# jedem Aufruf neu, damit die Anzeige nach einem Reload immer aktuell ist).
if ( defined $cgi->param('ajax') && $cgi->param('ajax') eq 'nodecheck' ) {
    print "Content-Type: text/plain; charset=utf-8\n\n";
    my $checkscript = ($ENV{'LBHOMEDIR'} || '/opt/loxberry') . "/bin/plugins/homebridge/check_node_update.sh";
    print `"$checkscript" 2>/dev/null` if -x $checkscript;
    exit;
}

# Sprache + Texte.
my $lang = LoxBerry::System::lblanguage() || 'en';
my %T = $lang eq 'de'
    ? ( title  => 'Homebridge',
        running => 'Homebridge läuft',
        stopped => 'Homebridge läuft nicht',
        unknown => 'Status unbekannt',
        open    => 'Homebridge-Oberfläche öffnen',
        state   => 'Status',
        nodehint => 'Eine neue, mit Homebridge, Config UI X und allen installierten Plugins gemeinsam kompatible Node.js-Version ist verfügbar',
        nodefrom => 'aktuell',
        nodeto   => 'empfohlen',
        nodelink => 'Plugin-Release auf GitHub öffnen',
        nodeok   => 'Node.js-Version ist aktuell',
        nodemodules => 'Node.js-Anforderungen der Module',
        nodechecking => 'Node.js-Version wird geprüft ...',
        nodenotset => 'nicht angegeben',
        nodeerror => 'Node.js-Version konnte nicht geprüft werden' )
    : ( title  => 'Homebridge',
        running => 'Homebridge is running',
        stopped => 'Homebridge is not running',
        unknown => 'Status unknown',
        open    => 'Open Homebridge interface',
        state   => 'Status',
        nodehint => 'A newer Node.js version compatible with Homebridge, Config UI X and all installed plugins is available',
        nodefrom => 'current',
        nodeto   => 'recommended',
        nodelink => 'Open plugin release on GitHub',
        nodeok   => 'Node.js version is up to date',
        nodemodules => "Modules' Node.js requirements",
        nodechecking => 'Checking Node.js version ...',
        nodenotset => 'not specified',
        nodeerror => 'Could not check Node.js version' );

# Host fuer den 8082-Link (Port des Aufrufs abschneiden).
my $host = $ENV{'HTTP_HOST'} || $ENV{'SERVER_NAME'} || 'localhost';
$host =~ s/:\d+$//;
my $hburl = "http://$host:8082";

my $status = hb_status();

# Button nativ ausgeben: neues LoxBerry-Design (LB4+, lb-btn) vs. jQuery Mobile
# (LB3 und aelter, data-role=button). Erkennung ueber die Design-CSS.
my $lbhome = $ENV{'LBHOMEDIR'} || '/opt/loxberry';
my $newdesign = -e "$lbhome/webfrontend/html/system/css/theme-soft-rounded.css";
my $btn = $newdesign
    ? qq{<a class="lb-btn lb-btn-primary" data-role="none" href="$hburl" target="_blank" rel="noopener">$T{open}</a>}
    : qq{<a href="$hburl" data-role="button" data-inline="true" target="_blank" rel="noopener">$T{open}</a>};

our $template_title = $T{title};
my $helplink = "https://wiki.loxberry.de/plugins/homebridge/start";

LoxBerry::Web::lbheader($T{title}, $helplink, "help.html");

print <<"HTML";
<style>
  #hb-card { max-width: 480px; margin: 1em auto; padding: 1.2em; border-radius: 10px;
             border: 1px solid rgba(128,128,128,0.4); text-align: center; font-size: 1.1em; }
  #hb-dot { display: inline-block; width: 14px; height: 14px; border-radius: 50%;
            background: #999; margin-right: 8px; vertical-align: middle; }
  #hb-dot.ok  { background: #3fae4b; }
  #hb-dot.bad { background: #d33; }
  #hb-btnwrap { margin-top: 1em; }
  #hb-nodecard { max-width: 480px; margin: 1em auto; padding: 1em; border-radius: 10px;
                 text-align: center; font-size: 0.95em; }
  #hb-nodecard.update { border: 1px solid rgba(255,180,0,0.6); background: rgba(255,180,0,0.08); }
  #hb-nodecard.ok     { border: 1px solid rgba(63,174,75,0.5); background: rgba(63,174,75,0.08); }
  #hb-nodelinkwrap { margin-top: 0.6em; }
  #hb-nodemodules { max-width: 480px; margin: 1em auto; padding: 1em; border-radius: 10px;
                    border: 1px solid rgba(128,128,128,0.4); font-size: 0.9em; display: none; }
  #hb-nodemodules-title { font-weight: bold; margin-bottom: 0.5em; text-align: center; }
  #hb-nodemodules table { width: 100%; border-collapse: collapse; }
  #hb-nodemodules td { padding: 0.25em 0.5em; border-top: 1px solid rgba(128,128,128,0.25); }
  #hb-nodemodules td:first-child { font-weight: bold; }
  #hb-nodemodules td:last-child { text-align: right; color: #888; }
</style>

<div id="hb-card">
  <div><span id="hb-dot"></span><span id="hb-state">...</span></div>
  <div id="hb-btnwrap">$btn</div>
</div>
<div id="hb-nodecard"><div>$T{nodechecking}</div></div>
<div id="hb-nodemodules"></div>

<script>
(function(){
  var texts = { active:"$T{running}", inactive:"$T{stopped}",
                failed:"$T{stopped}", unknown:"$T{unknown}" };
  function render(s){
    var dot = document.getElementById('hb-dot');
    var st  = document.getElementById('hb-state');
    st.textContent = texts[s] || ("$T{state}: " + s);
    dot.className = (s === 'active') ? 'ok' : (s === 'unknown' ? '' : 'bad');
  }
  function poll(){
    fetch('index.cgi?ajax=status', { cache: 'no-store' })
      .then(function(r){ return r.text(); })
      .then(function(t){ render(t.trim()); })
      .catch(function(){ /* Netzwerkfehler ignorieren, naechster Versuch folgt */ });
  }
  render("$status");
  poll();
  setInterval(poll, 5000);

  function escapeHtml(s){
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
  }
  function renderNodeCheck(text){
    var nc = {};
    text.split('\\n').forEach(function(line){
      var m = line.match(/^([A-Z_]+)=(.*)\$/);
      if (m) nc[m[1]] = m[2];
    });
    var card = document.getElementById('hb-nodecard');
    if (nc.UPDATE_AVAILABLE === '1') {
      var releaseurl = "https://github.com/blacksun80/LoxBerry-Plugin-Homebridge/releases/latest";
      card.className = 'update';
      card.innerHTML = '<div>' + "$T{nodehint}" + ': ' + "$T{nodefrom}" + ' ' + escapeHtml(nc.CURRENT || '?')
        + ' &rarr; ' + "$T{nodeto}" + ' ' + escapeHtml(nc.RECOMMENDED || '?') + '</div>'
        + '<div id="hb-nodelinkwrap"><a href="' + releaseurl + '" target="_blank" rel="noopener">' + "$T{nodelink}" + '</a></div>';
    } else if (nc.CURRENT) {
      card.className = 'ok';
      card.innerHTML = '<div>' + "$T{nodeok}" + ': ' + escapeHtml(nc.CURRENT) + '</div>';
    } else {
      card.parentNode.removeChild(card);
    }

    var modWrap = document.getElementById('hb-nodemodules');
    if (nc.MODULES) {
      var rows = nc.MODULES.split(';').map(function(entry){
        var idx = entry.indexOf(':');
        if (idx < 0) return '';
        var name = entry.substring(0, idx), range = entry.substring(idx + 1);
        if (!name) return '';
        return '<tr><td>' + escapeHtml(name) + '</td><td>' + (range ? escapeHtml(range) : "$T{nodenotset}") + '</td></tr>';
      }).join('');
      if (rows) {
        modWrap.innerHTML = '<div id="hb-nodemodules-title">' + "$T{nodemodules}" + '</div><table>' + rows + '</table>';
        modWrap.style.display = '';
      }
    }
  }
  function loadNodeCheck(){
    fetch('index.cgi?ajax=nodecheck', { cache: 'no-store' })
      .then(function(r){ return r.text(); })
      .then(renderNodeCheck)
      .catch(function(){ /* Netzwerkfehler ignorieren - Karte bleibt beim "wird geprueft" */ });
  }
  loadNodeCheck();
})();
</script>
HTML

LoxBerry::Web::lbfooter();
exit;
