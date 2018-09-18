#!/bin/bash
EVENT="$1"
CAUSE="$2"
DATE="$3"
#DIR_SCRIPT="$4"
DIR_SCRIPT=`dirname $0`
"$DIR_SCRIPT/../../piGuardian.sh" mqtt_status #&>> /tmp/piguardian_mqtt.log

