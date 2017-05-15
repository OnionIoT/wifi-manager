#!/bin/bash
SCRIPTTYPE=$1
OMEGANAME=$2

case "$SCRIPTTYPE" in
    setup|manager)
        chmod +x ./bin/wifi-$SCRIPTTYPE.sh
        rsync -av ./bin/wifi-$SCRIPTTYPE.sh root@omega-$OMEGANAME.local:/usr/bin/wifi"$SCRIPTTYPE"
        exit
    ;;
    *)
        echo "Invalid script file."
        exit 1
    ;;
esac