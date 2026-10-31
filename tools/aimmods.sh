#!/bin/bash
# Build / disable / enable the aim training mods in the UT2004 install.
#
#   aimmods.sh build     copy the sources into UT2004, delete the old .u and recompile
#   aimmods.sh disable   remove the mods from UT2004 (sources + compiled files) -> use before online play
#   aimmods.sh enable    put them back
#   aimmods.sh report    build the progress report from your saved rounds and open it in the browser
#
# The mods are parked in UT2004/AimMods_disabled while disabled.
# UT2004.ini keeps its EditPackages lines; only run "ucc make" while the mods are enabled.

UT=/mnt/c/UnrealTournament2004
SRC="$(cd "$(dirname "$0")/.." && pwd)"
PKGS="DamageNumbers AimTargets"
PARK="$UT/AimMods_disabled"

case "$1" in
build)
    for p in $PKGS; do
        mkdir -p "$UT/$p/Classes"
        cp "$SRC/$p/Classes/"*.uc "$UT/$p/Classes/"
        [ -d "$SRC/$p/Sounds" ] && { mkdir -p "$UT/$p/Sounds"; cp "$SRC/$p/Sounds/"* "$UT/$p/Sounds/"; }
        # ucc make answers "Success" without rebuilding if the old .u exists.
        rm -f "$UT/System/$p.u" "$UT/System/$p.ucl"
    done
    (cd "$UT/System" && ./ucc.exe make 2>&1 | tr -d '\r' | grep -E "Error|Warning|Success|Failure")
    ls -la "$UT/System/"{DamageNumbers,AimTargets}.u
    ;;
disable)
    mkdir -p "$PARK/System"
    for p in $PKGS; do
        for e in u ucl; do
            [ -f "$UT/System/$p.$e" ] && mv "$UT/System/$p.$e" "$PARK/System/"
        done
        [ -d "$UT/$p" ] && mv "$UT/$p" "$PARK/"
    done
    echo "Mods removed from the game folder (parked in $PARK)."
    ;;
enable)
    [ -d "$PARK" ] || { echo "Nothing to enable."; exit 1; }
    for p in $PKGS; do
        for e in u ucl; do
            [ -f "$PARK/System/$p.$e" ] && mv "$PARK/System/$p.$e" "$UT/System/"
        done
        [ -d "$PARK/$p" ] && mv "$PARK/$p" "$UT/"
    done
    rmdir "$PARK/System" "$PARK" 2>/dev/null
    echo "Mods back in the game folder."
    ;;
report)
    mkdir -p "$SRC/report"
    python3 -I "$SRC/tools/report.py" "$UT/System/AimTargets.ini" "$SRC/report/AimTargetsReport.html" || exit 1
    explorer.exe "$(wslpath -w "$SRC/report/AimTargetsReport.html")" >/dev/null 2>&1 || true
    echo "Report: $(wslpath -w "$SRC/report/AimTargetsReport.html")"
    ;;
*)
    echo "usage: $0 build|disable|enable|report"
    exit 1
    ;;
esac
