#!/bin/bash
SCRIPTTYPE=$1
OMEGANAME=$2

case "$SCRIPTTYPE" in
    setup|manager)
        rsync -av ./bin/wifi-$SCRIPTTYPE.sh root@omega-$OMEGANAME.local:/usr/bin/wifi"$SCRIPTTYPE"
        exit
    ;;
    *)
        echo "Invalid script file."
        exit 1
    ;;
esac