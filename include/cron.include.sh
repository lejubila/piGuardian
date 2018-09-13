#
# Elimina una tipoliga di schedulazione dal crontab dell'utente
# $1	tipologia del crontab
# $2	argomento della tipologia
#
function cron_del {

	local CRON_TYPE=$1
	local CRON_ARG=$2

	if [ -z "$CRON_TYPE" ]; then
		echo "Cron type is empty" >&2
		log_write "Cron type is empty"
		return 1
	fi

	$CRONTAB -l > "$TMP_CRON_FILE"
	local START=`$GREP -n "# START cron $CRON_TYPE $CRON_ARG" "$TMP_CRON_FILE"| $CUT -d : -f 1`
	local END=`$GREP -n "# END cron $CRON_TYPE $CRON_ARG" "$TMP_CRON_FILE"| $CUT -d : -f 1`
	local re='^[0-9]+$'

	if ! [[ "$START" =~ $re ]] && ! [[ "$END" =~ $re ]] ; then
		echo "$1 $2 cron is not present" >&2
		return
	fi
	if ! [[ $START =~ $re ]] ; then
  		echo "Cron start don't find" >&2
  		log_write "Cron start don't find"
		return 1
	fi
	if ! [[ $END =~ $re ]] ; then
  		echo "Cron end cron don't find" >&2
  		log_write "Cron end cron don't find"
		return 1
	fi
	if [ "$START" -gt "$END" ]; then
  		echo "Wrong position for start and end in cron" >&2
  		log_write "Wrong position for start and end in cron"
		return 1
	fi


	$SED "$START,${END}d" "$TMP_CRON_FILE" | $SED '$!N; /^\(.*\)\n\1$/!P; D' | $CRONTAB -
	#$CRONTAB "$TMP_CRON_FILE"
	rm "$TMP_CRON_FILE"

}

#
# Aggiunge una schedulazione nel crontab dell'utente
# $1	tipologia del crontab
# $2	minuto
# $3	ora
# $4	giorno del mese
# $5	mese
# $6	giorno della settimana
# $7	argomento della tipologia
# $8	secondo argomento della tipologia
#
function cron_add {

	local CRON_TYPE=$1
	local CRON_M=$2
	local CRON_H=$3
	local CRON_DOM=$4
	local CRON_MON=$5
	local CRON_DOW=$6
	local CRON_ARG=$7
	local CRON_ARG2=$8
	local CRON_COMMAND=""
	local PATH_SCRIPT=`$READLINK -f "$DIR_SCRIPT/$NAME_SCRIPT"`
	local TMP_CRON_FILE2="$TMP_CRON_FILE-2"

	if [ -z "$CRON_TYPE" ]; then
		echo "Cron type is empty" >&2
		log_write "Cron type is empty"
		return 1
	fi

	$CRONTAB -l > "$TMP_CRON_FILE"
	local START=`$GREP -n "# START cron $CRON_TYPE $CRON_ARG" "$TMP_CRON_FILE"| $CUT -d : -f 1`
	local END=`$GREP -n "# END cron $CRON_TYPE $CRON_ARG" "$TMP_CRON_FILE"| $CUT -d : -f 1`
	local re='^[0-9]+$'

	local NEW_CRON=0
	local PREVIUS_CONTENT=""

	if ! [[ $START =~ $re ]] && ! [[ $END =~ $re ]] ; then
  		NEW_CRON=1
	else
		if ! [[ $START =~ $re ]] ; then
  			echo "Cron start don't find" >&2
  			log_write "Cron start don't find"
			return 1
		fi
		if ! [[ $END =~ $re ]] ; then
  			echo "Cron end cron don't find" >&2
  			log_write "Cron end cron don't find"
			return 1
		fi
		START=$(($START + 1))
		END=$(($END - 1))

		if [ "$START" -gt "$END" ]; then
  			echo "Wrong position for start and end in cron" >&2
  			log_write "Wrong position for start and end in cron"
			return 1
		fi
		
		PREVIOUS_CONTENT=`$SED -n "$START,${END}p" "$TMP_CRON_FILE"`

	fi

	case "$CRON_TYPE" in

		init)
			CRON_M="@reboot"
			CRON_H=""
			CRON_DOM=""
			CRON_MON=""
			CRON_DOW=""
			CRON_COMMAND="$PATH_SCRIPT init"
			;;

		start_socket_server)
			CRON_M="@reboot"
			CRON_H=""
			CRON_DOM=""
			CRON_MON=""
			CRON_DOW=""
			CRON_COMMAND="$PATH_SCRIPT start_socket_server force"
			;;

		*)
			echo "Wrong cron type: $CRON_TYPE"
			log_write "Wrong cron type: $CRON_TYPE"
			;;

	esac

	if [ "$NEW_CRON" -eq "0" ]; then
		START=$(($START - 1))
		END=$(($END + 1))
		$SED "$START,${END}d" "$TMP_CRON_FILE" > "$TMP_CRON_FILE2"
	else
		cat "$TMP_CRON_FILE" > "$TMP_CRON_FILE2"
	fi

	if [ "$NEW_CRON" -eq "1" ]; then
		echo "" >> "$TMP_CRON_FILE2"
	fi
	echo "# START cron $CRON_TYPE $CRON_ARG" >> "$TMP_CRON_FILE2"
	if [ "$NEW_CRON" -eq "0" ]; then
		echo "$PREVIOUS_CONTENT" >> "$TMP_CRON_FILE2"
	fi
	echo "$CRON_M $CRON_H $CRON_DOM $CRON_MON $CRON_DOW $CRON_COMMAND" >> "$TMP_CRON_FILE2"
	echo "# END cron $CRON_TYPE $CRON_ARG" >> "$TMP_CRON_FILE2"

	$CRONTAB "$TMP_CRON_FILE2"
	rm "$TMP_CRON_FILE" "$TMP_CRON_FILE2"

}

#
# Legge una tipoliga di schedulazione dal crontab dell'utente
# $1	tipologia del crontab
# $2	argomento della tipologia
#
function cron_get {

	local CRON_TYPE=$1
	local CRON_ARG=$2

	if [ -z "$CRON_TYPE" ]; then
		echo "Cron type is empty" >&2
		log_write "Cron type is empty"
		return 1
	fi

	$CRONTAB -l > "$TMP_CRON_FILE"
	local START=`$GREP -n "# START cron $CRON_TYPE $CRON_ARG" "$TMP_CRON_FILE"| $CUT -d : -f 1`
	local END=`$GREP -n "# END cron $CRON_TYPE $CRON_ARG" "$TMP_CRON_FILE"| $CUT -d : -f 1`
	local re='^[0-9]+$'

	local PREVIUS_CONTENT=""

	if ! [[ $START =~ $re ]] && ! [[ $END =~ $re ]] ; then
  		PREVIUS_CONTENT=""
	else
		if ! [[ $START =~ $re ]] ; then
  			echo "Cron start don't find" >&2
  			log_write "Cron start don't find"
			return 1
		fi
		if ! [[ $END =~ $re ]] ; then
  			echo "Cron end cron don't find" >&2
  			log_write "Cron end cron don't find"
			return 1
		fi
		START=$(($START + 1))
		END=$(($END - 1))

		if [ "$START" -gt "$END" ]; then
  			echo "Wrong position for start and end in cron" >&2
  			log_write "Wrong position for start and end in cron"
			return 1
		fi
		
		PREVIOUS_CONTENT=`$SED -n "$START,${END}p" "$TMP_CRON_FILE"`
	fi

	echo "$PREVIOUS_CONTENT"

}

function set_cron_init {

	cron_del "init" 2> /dev/null
	cron_add "init"

}

function del_cron_init {

	cron_del "init"

}

function set_cron_start_socket_server {

	cron_del "start_socket_server" 2> /dev/null
	cron_add "start_socket_server"

}

function del_cron_start_socket_server {

	cron_del "start_socket_server"
}

function set_cron_check_rain_sensor {

	cron_del "check_rain_sensor" 2> /dev/null
	cron_add "check_rain_sensor"
}


