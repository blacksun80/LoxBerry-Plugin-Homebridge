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

# Sprache + Texte.
my $lang = LoxBerry::System::lblanguage() || 'en';
my %T = $lang eq 'de'
    ? ( title  => 'Homebridge',
        running => 'Homebridge laeuft',
        stopped => 'Homebridge laeuft nicht',
        unknown => 'Status unbekannt',
        open    => 'Homebridge-Oberflaeche oeffnen',
        state   => 'Status' )
    : ( title  => 'Homebridge',
        running => 'Homebridge is running',
        stopped => 'Homebridge is not running',
        unknown => 'Status unknown',
        open    => 'Open Homebridge interface',
        state   => 'Status' );

# Host fuer den 8082-Link (Port des Aufrufs abschneiden).
my $host = $ENV{'HTTP_HOST'} || $ENV{'SERVER_NAME'} || 'localhost';
$host =~ s/:\d+$//;
my $hburl = "http://$host:8082";

my $status = hb_status();

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
  #hb-open { display: inline-block; margin-top: 1em; padding: 0.6em 1.2em; border-radius: 8px;
             background: #0a7a5a; color: #fff; text-decoration: none; }
</style>

<div id="hb-card">
  <div><span id="hb-dot"></span><span id="hb-state">...</span></div>
  <a id="hb-open" href="$hburl" target="_blank" rel="noopener">$T{open}</a>
</div>

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
})();
</script>
HTML

LoxBerry::Web::lbfooter();
exit;
