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
        running => 'Homebridge läuft',
        stopped => 'Homebridge läuft nicht',
        unknown => 'Status unbekannt',
        open    => 'Homebridge-Oberfläche öffnen',
        state   => 'Status',
        nodehint => 'Eine neue, mit Homebridge, Config UI X und allen installierten Plugins gemeinsam kompatible Node.js-Version ist verfügbar',
        nodefrom => 'aktuell',
        nodeto   => 'empfohlen',
        nodelink => 'Plugin-Release auf GitHub öffnen' )
    : ( title  => 'Homebridge',
        running => 'Homebridge is running',
        stopped => 'Homebridge is not running',
        unknown => 'Status unknown',
        open    => 'Open Homebridge interface',
        state   => 'Status',
        nodehint => 'A newer Node.js version compatible with Homebridge, Config UI X and all installed plugins is available',
        nodefrom => 'current',
        nodeto   => 'recommended',
        nodelink => 'Open plugin release on GitHub' );

# Node-Update-Check: gecacht, damit nicht bei jedem Seitenaufruf die
# npm-Registry und nodejs.org abgefragt werden ("ab und an" statt live).
my $lbhomedir  = $ENV{'LBHOMEDIR'} || '/opt/loxberry';
my $checkscript = "$lbhomedir/bin/plugins/homebridge/check_node_update.sh";
my $cachefile    = "$lbhomedir/data/plugins/homebridge/homebridge_runtime/.node-update-check";
my $cache_max_age = 24 * 3600;

my %nodecheck;
my $cache_age = -e $cachefile ? (time() - (stat($cachefile))[9]) : undef;
if ( !defined($cache_age) || $cache_age > $cache_max_age ) {
    if ( -x $checkscript ) {
        my $out = `"$checkscript" 2>/dev/null`;
        if ( defined $out && $out ne '' ) {
            if ( open( my $fh, '>', $cachefile ) ) {
                print $fh $out;
                close $fh;
            }
        }
    }
}
if ( open( my $fh, '<', $cachefile ) ) {
    while ( my $line = <$fh> ) {
        chomp $line;
        if ( $line =~ /^([A-Z_]+)=(.*)$/ ) {
            $nodecheck{$1} = $2;
        }
    }
    close $fh;
}

my $nodebox = '';
if ( ( $nodecheck{UPDATE_AVAILABLE} // '' ) eq '1' ) {
    my $releaseurl = "https://github.com/blacksun80/LoxBerry-Plugin-Homebridge/releases/latest";
    my $cur = $nodecheck{CURRENT}     // '?';
    my $rec = $nodecheck{RECOMMENDED} // '?';
    $nodebox = qq{
<div id="hb-nodecard">
  <div>$T{nodehint}: $T{nodefrom} $cur &rarr; $T{nodeto} $rec</div>
  <div id="hb-nodelinkwrap"><a href="$releaseurl" target="_blank" rel="noopener">$T{nodelink}</a></div>
</div>};
}

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
                 border: 1px solid rgba(255,180,0,0.6); background: rgba(255,180,0,0.08);
                 text-align: center; font-size: 0.95em; }
  #hb-nodelinkwrap { margin-top: 0.6em; }
</style>

<div id="hb-card">
  <div><span id="hb-dot"></span><span id="hb-state">...</span></div>
  <div id="hb-btnwrap">$btn</div>
</div>
$nodebox

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
