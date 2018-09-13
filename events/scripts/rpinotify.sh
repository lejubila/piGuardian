#!/bin/bash
#
# Send telegram notificacion on triggered event
#
# $1 = event
# $2 = cause
# $3 = time
#
# To use this script, you must get your hash. Register for the rpinotify service. Get the hash and enter it below
#

# rpinotify token
TOKEN=""

EVENT="$1"
CAUSE="$2"
TIME="$3"

BODY=""

if ! [[ "$TIME" =~ ^[0-9]+$ ]]; then
        TIME=$(date +%s)
fi


case "$EVENT" in

	alarm_fired)
		BODY=" <b>WARNING!!! **ALARM FIRED**</b> --- PiGuardian triggered new event --- EVENT: <b>$EVENT</b> --- CAUSE: <b>$CAUSE</b> --- TIME: <b>$(/bin/date -d@$TIME)</b>"
		;;

	*)
		BODY="PiGuardian triggered new event --- EVENT: <b>$EVENT</b> --- CAUSE: <b>$CAUSE</b> --- TIME: <b>$(/bin/date -d@$TIME)</b>"
		;;

esac

curl -X POST -F "text=$BODY" https://api.rpinotify.it/message/$TOKEN/
