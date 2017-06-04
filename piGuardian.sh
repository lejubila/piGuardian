#!/bin/bash
#
# Bash script to manage an anti-theft system built with a Raspberry Pi
# Author: david.bigagli@gmail.com
# Url: https://github.com/lejubila/piGuardian
#

#
# Inizializza il sistema
#
function initialize {

	log_write "Run initialize"

	# Elimina tutti gli stati preesistenti
	rm -f "$STATUS_DIR"/*

	# Inizializza i gpio dei sensori perimetrali 
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		g=PERIMETRAL"$i"_GPIO
		$GPIO -g mode ${!g} in			# setta il gpio nella modalita di lettura
		perimetral_set_state $i 0
	done

	log_write "End initialize"

}

function reset_messages {
	rm -f "$LAST_INFO_FILE.$!"
	rm -f "$LAST_WARNING_FILE.$!"
	rm -f "$LAST_SUCCESS_FILE.$!"
}

#
# Commuta un elettrovalvola nello stato aperto
# $1 alias elettrovalvola
# $2 se specificata la string "force" apre l'elettrovalvola anche se c'é pioggia
#
function ev_open {
	
	cron_del open_in $1 > /dev/null 2>&1

	if [ ! "$2" = "force" ]; then
		if [[ "$NOT_IRRIGATE_IF_RAIN_ONLINE" -gt 0 && -f $STATUS_DIR/last_rain_online ]]; then
			local last_rain=`cat $STATUS_DIR/last_rain_online`
			local now=`date +%s`
			local dif=0
			let "dif = now - last_rain"
			if [ $dif -lt $NOT_IRRIGATE_IF_RAIN_ONLINE ]; then
				log_write "Solenoid '$1' not open for rain (online check)"
				message_write "warning" "Solenoid not open for rain"
				return
			fi
		fi

		check_rain_sensor
		if [[ "$NOT_IRRIGATE_IF_RAIN_SENSOR" -gt 0 && -f $STATUS_DIR/last_rain_sensor ]]; then
			local last_rain=`cat $STATUS_DIR/last_rain_sensor`
			local now=`date +%s`
			local dif=0
			let "dif = now - last_rain"
			if [ $dif -lt $NOT_IRRIGATE_IF_RAIN_SENSOR ]; then
				log_write "Solenoid '$1' not open for rain (sensor check)"
				message_write "warning" "Solenoid not open for rain"
				return
			fi
		fi
	fi

	local state=1
	if [ "$2" = "force" ]; then
		state=2
	fi

	# Dall'alias dell'elettrovalvola recupero il numero e dal numero recupero gpio da usare
	ev_alias2number $1
	EVNUM=$?
	ev_number2gpio $EVNUM
	g=$?

	# Gestisce l'apertura dell'elettrovalvola in base alla tipologia (monostabile / bistabile) 
	if [ "$EV_MONOSTABLE" == "1" ]; then
		$GPIO -g write $g $RELE_GPIO_CLOSE
	else
		supply_positive
		$GPIO -g write $g $RELE_GPIO_CLOSE
		sleep 1
		$GPIO -g write $g $RELE_GPIO_OPEN
	fi

	ev_set_state $EVNUM $state

	log_write "Solenoid '$1' open"
	message_write "success" "Solenoid open"
}

#
# Scrive un messaggio nel file di log
# $1 log da scrivere
#
function log_write {
	if [ -e "$LOG_FILE" ]; then
		local actualsize=$($WC -c <"$LOG_FILE")
		if [ $actualsize -ge $LOG_FILE_MAX_SIZE ]; then
			$GZIP $LOG_FILE
			$MV $LOG_FILE.gz $LOG_FILE.`date +%Y%m%d%H%M`.gz	
		fi
	fi

	echo -e "`date`\t\t$1" >> $LOG_FILE
}

#
# Scrive una tipologia di messaggio da inviare via socket server
# $1 tipo messaggio: info, warning, success
# $2 messaggio
#
function message_write {
	local file_message=""
	if [ "$1" = 'info' ]; then
		file_message="$LAST_INFO_FILE.$!"
	elif [ "$1" = "warning" ]; then
		file_message="$LAST_WARNING_FILE.$!"
	elif [ "$1" = "success" ]; then
		file_message="$LAST_SUCCESS_FILE.$!"
	else
		return
	fi
	
	echo "$2" > "$file_message"
}

#
# Imposta lo stato di un sensore perimetrale
# $1 numero del sensore 
# $2 stato da scrivere
#
function perimetral_set_state {
	echo "$2" > "$STATUS_DIR/perimetral$1"
}

#
# Legge lo stato di un sensore perimetrale
#
function perimetral_get_state {
	return `cat "$STATUS_DIR/perimetral$1"`
}

#
# Passando un alias di un sensore perimetrale recupera il numero gpio associato 
# $1 alias sensore
#
function perimetral_get_gpio4alias {
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		local g=PERIMETRAL"$i"_GPIO
		local a=PERIMETRAL"$i"_ALIAS
		local gv=${!g}
		local av=${!a}
		if [ "$av" == "$1" ]; then
			return $gv
		fi
	done

	log_write "ERROR perimetral sensor alias not found: $1"
	message_write "warning" "Perimetral sensor alias not found"
	exit 1
}

#
# Recupera il numero di sensore perimetrale in base all'alias
# $1 alias del sensore
#
function perimetral_get_number4alias {
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		local a=PERIMETRAL"$i"_ALIAS
		local av=${!a}
		if [ "$av" == "$1" ]; then
			return $i
		fi
	done

	log_write "ERROR perimetral sensor alias not found: $1"
	message_write "warning" "Perimetral sensor alias not found"
	exit 1
}

#
# Recupera l'alias di sensore perimetrale in base al numero
# $1 numero del sensore
#
function perimetral_get_alias4number {
	local n=PERIMETRAL"$1"_ALIAS
	local a=${!n}
	
	if [ ! -z "$a" ]; then
		echo "$a"
		return
	fi

	log_write "ERROR perimetral sensor number not found: $1"
	message_write "warning" "Perimetral sensor number not found"
	exit 1
}

#
# Verifica se l'alias di una sensore perimetrale esiste
# $1 alias del sensore
#
function perimetral_alias_exists {
	local vret='FALSE'
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		a=PERIMETRAL"$i"_ALIAS
		av=${!a}
		if [ "$av" == "$1" ]; then
			vret='TRUE'
		fi
	done

	echo $vret
}

#
# Recupera il numero di gpio associato in base al numero di sensore perimentrale 
# $1 numero sensore
#
function perimetral_get_gpio4number {
#	echo "numero ev $1"
	i=$1
	g=PERIMETRAL"$i"_GPIO
	gv=${!g}
#	echo "gv = $gv"
	return $gv
}

#
# Mostra lo stato di tutti i sensori
#
function sensor_status_all {
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		a=PERIMETRAL"$i"_ALIAS
		av=${!a}
		perimetral_get_state $i
		echo -e "$av: $?"
	done
}

#
# Mostra lo stato di un sensore perimetrale
# $1 alias elettrovalvola
#
function perimetral_status {
	perimetral_get_number4alias $1
	i=$?
	perimetral_get_state $i
	local state=$?
	echo -e "$state"
	return $state
}

function perimetral_list_alias {

                for i in $(seq $PERIMETRAL_TOTAL)
                do
                        local a=PERIMETRAL"$i"_ALIAS
                        local al=${!a}
                        echo $al
                done

}

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


function show_usage {
	echo -e "piGuardian v. $VERSION.$SUB_VERSION.$RELEASE_VERSION"
	echo -e ""
	echo -e "Usage:"
	echo -e "\t$NAME_SCRIPT init                                         initialize systm"
	echo -e "\t$NAME_SCRIPT start_guard                                  start monitoring"

	echo -e "\t$NAME_SCRIPT perimetral_list_alias                        view list of perimetral sensor"
	echo -e "\t$NAME_SCRIPT perimetral_status alias                      show perimetral sensor status"
	echo -e "\t$NAME_SCRIPT sensor_status_all                            show all sensor status"
	echo -e "\t$NAME_SCRIPT start_socket_server [force]                  start socket server, with 'force' parameter force close socket server if already open"
	echo -e "\t$NAME_SCRIPT stop_socket_server                           stop socket server"
	echo -e "\n"
	echo -e "\t$NAME_SCRIPT set_cron_init                                set crontab for initialize control unit"
	echo -e "\t$NAME_SCRIPT del_cron_init                                remove crontab for initialize control unit"
	echo -e "\t$NAME_SCRIPT set_cron_start_socket_server                 set crontab for start socket server"
	echo -e "\t$NAME_SCRIPT del_cron_start_socket_server                 remove crontab for start socket server"
	echo -e "\n"
	echo -e "\t$NAME_SCRIPT debug1 [parameter]|[parameter]|..]           Run debug code 1"
	echo -e "\t$NAME_SCRIPT debug2 [parameter]|[parameter]|..]           Run debug code 2"
}

function start_socket_server {

	rm -f "$TCPSERVER_PID_FILE"
	echo $TCPSERVER_PID_SCRIPT > "$TCPSERVER_PID_FILE"
	$TCPSERVER -v -RHl0 $TCPSERVER_IP $TCPSERVER_PORT $0 socket_server_command 

	#if [ $? -eq 0 ]; then
	#	echo $TCPSERVER_PID_SCRIPT > "$TCPSERVER_PID_FILE"
	#	trap stop_socket_server EXIT

	#	log_write "start socket server ";
	#	return 0
	#else
	#	log_write "start socket server failed";
	#	return 1
	#fi
}

function stop_socket_server {

        if [ ! -f "$TCPSERVER_PID_FILE" ]; then
                echo "Daemon is not running"
                exit 1
        fi

	log_write "stop socket server"

        kill -9 $(list_descendants `cat "$TCPSERVER_PID_FILE"`) 2> /dev/null
        kill -9 `cat "$TCPSERVER_PID_FILE"` 2> /dev/null
        rm -f "$TCPSERVER_PID_FILE"

}

function socket_server_command {

	RUN_FROM_TCPSERVER=1

	local line=""
	read line
	line=$(echo "$line " | $TR -d '[\r\n]')
	arg1=$(echo "$line " | $CUT -d ' ' -f1)
	arg2=$(echo "$line " | $CUT -d ' ' -f2)
	arg3=$(echo "$line " | $CUT -d ' ' -f3)
	arg4=$(echo "$line " | $CUT -d ' ' -f4)
	arg5=$(echo "$line " | $CUT -d ' ' -f5)
	arg6=$(echo "$line " | $CUT -d ' ' -f6)
	arg7=$(echo "$line " | $CUT -d ' ' -f7)

	log_write "socket connection from: $TCPREMOTEIP - command: $arg1 $arg2 $arg3 $arg4 $arg5 $arg6 $arg7"
	
	reset_messages &> /dev/null

	case "$arg1" in
        	status)
			json_status $arg2 $arg3 $arg4 $arg5 $arg6 $arg7
			;;

		open)
	                if [ "empty$arg2" == "empty" ]; then
        	                json_error 0 "Alias solenoid not specified"
			else
                		ev_open $arg2 $arg3 &> /dev/null
				json_status "get_cron_open_in"
			fi
			;;

		open_in)
			ev_open_in $arg2 $arg3 $arg4 $arg5 &> /dev/null
			json_status "get_cron_open_in"
			;;	

		close)
	                if [ "empty$arg2" == "empty" ]; then
        	                json_error 0 "Alias solenoid not specified"
			else
                		ev_close $arg2 &> /dev/null
				json_status "get_cron_open_in"
                	fi
			;;

		set_general_cron)
			local vret=""
			for i in $arg2 $arg3 $arg4 $arg5 $arg6 $arg7
		        do
				if [ $i = "set_cron_init" ]; then
					vret="$(vret)`set_cron_init`"
				elif [ $i = "set_cron_start_socket_server" ]; then
					vret="$(vret)`set_cron_start_socket_server`"
				elif [ $i = "set_cron_check_rain_sensor" ]; then
					vret="$(vret)`set_cron_check_rain_sensor`"
				elif [ $i = "set_cron_check_rain_online" ]; then
					vret="$(vret)`set_cron_check_rain_online`"
				elif [ $i = "set_cron_close_all_for_rain" ]; then
					vret="$(vret)`set_cron_close_all_for_rain`"
				fi
			done

			if [[ ! -z $vret ]]; then
				json_error 0 "Cron set failed"
				log_write "Cron set failed: $vret"
			else
				message_write "success" "Cron set successfull"
				json_status
			fi

			;;

		del_cron_open)
			local vret=""

			vret=`del_cron_open $arg2`

			if [[ ! -z $vret ]]; then
				json_error 0 "Cron set failed"
				log_write "Cron del failed: $vret"
			else
				message_write "success" "Cron set successfull"
				json_status
			fi

			;;

		del_cron_open_in)
			local vret=""

			vret=`del_cron_open_in $arg2`

			if [[ ! -z $vret ]]; then
				json_error 0 "Cron del failed"
				log_write "Cron del failed: $vret"
			else
				message_write "success" "Scheduled start successfully deleted"
				json_status "get_cron_open_in"
			fi

			;;


		del_cron_close)
			local vret=""

			vret=`del_cron_close $arg2`

			if [[ ! -z $vret ]]; then
				json_error 0 "Cron set failed"
				log_write "Cron set failed: $vret"
			else
				message_write "success" "Cron set successfull"
				json_status
			fi

			;;

			add_cron_open)
				local vret=""

			vret=`add_cron_open "$arg2" "$arg3" "$arg4" "$arg5" "$arg6" "$arg7"`

			if [[ ! -z $vret ]]; then
				json_error 0 "Cron set failed"
				log_write "Cron set failed: $vret"
			else
				message_write "success" "Cron set successfull"
				json_status
			fi

			;;

		add_cron_close)
			local vret=""

			vret=`add_cron_close "$arg2" "$arg3" "$arg4" "$arg5" "$arg6" "$arg7"`

			if [[ ! -z $vret ]]; then
				json_error 0 "Cron set failed"
				log_write "Cron set failed: $vret"
			else
				message_write "success" "Cron set successfull"
				json_status
			fi

			;;

		*)
			json_error 0 "invalid command"
			;;

	esac
	
	reset_messages &> /dev/null

}

json_error()
{
	echo "{\"error\":{\"code\":$1,\"description\":\"$2\"}}"
}

list_descendants ()
{
  local children=$(ps -o pid= --ppid "$1")

  for pid in $children
  do
    list_descendants "$pid"
  done

  echo "$children"
}

#
# Avvia la sorveglianza
#
function start_guard()
{

	log_write "Guard start"

	while [ 1 ]; do

		local SENSORS=`perimetral_list_alias`
		#local SENSORS=`perimetral_list_alias | $TR '\n' ' '`
#		SENSOR=`echo "$COMMAND"|$TR '\n' ' '`

#echo "$SENSORS"
#echo "************"

		# Controlla i sensori perimetrali
		for a in $SENSORS
		do
			perimetral_get_gpio4alias $a
			local G=$?

			local STATE=`$GPIO -g read $G`
			if [ "$STATE" == "$PERIMETRAL_GPIO_STATE" ]; then

				echo "$a - ALLARME"

			else

				echo "$a - CHIUSO"

			fi

			sleep $DELAY_LOOP_STATE
		done






	done

	log_write "Guard end"

}

function debug1 {
	. "$DIR_SCRIPT/debug/debug1.sh"	
}

function debug2 {
	. "$DIR_SCRIPT/debug/debug1.sh"	
}

VERSION=0
SUB_VERSION=0
RELEASE_VERSION=1

DIR_SCRIPT=`dirname $0`
NAME_SCRIPT=${0##*/}
#CONFIG_ETC="/etc/piGarden.conf"
CONFIG_ETC="/home/pi/piGuardian/conf/piGuardian.conf.example"
TMP_PATH="/run/shm"
if [ ! -d "$TMP_PATH" ]; then
	TMP_PATH="/tmp"
fi
TCPSERVER_PID_FILE="$TMP_PATH/piGuardianTcpServer.pid"
TCPSERVER_PID_SCRIPT=$$
RUN_FROM_TCPSERVER=0
TMP_CRON_FILE="$TMP_PATH/piguardian.user.cron.$$"

if [ -f $CONFIG_ETC ]; then
	. $CONFIG_ETC
else
	echo -e "Config file not found in $CONFIG_ETC"
	exit 1
fi

LAST_INFO_FILE="$STATUS_DIR/last_info"
LAST_WARNING_FILE="$STATUS_DIR/last_worning"
LAST_SUCCESS_FILE="$STATUS_DIR/last_success"

case "$1" in
	init) 
		initialize
		;;

	perimetral_list_alias)
		perimetral_list_alias
		;;

	perimetral_status)
		perimetral_status $2
		;;

	sensor_status_all)
		sensor_status_all
		;;

	start_guard)
		start_guard
		;;
		

        start_socket_server)
                if [ -f "$TCPSERVER_PID_FILE" ]; then
                        echo "Daemon is already running, use \"$0 stop_socket_server\" to stop the service"

			if [ "x$2" == "xforce" ]; then
				sleep 5
				stop_socket_server
			else
                        	exit 1
			fi
                fi

                nohup $0 start_socket_server_daemon > /dev/null 2>&1 &

                echo "Daemon is started widh pid $!"
		log_write "start socket server with pid $!"
                ;;

	start_socket_server_daemon)
		start_socket_server
		;;

	stop_socket_server)
		stop_socket_server
		;;

	socket_server_command)
		socket_server_command
		;;

	set_cron_init)
		set_cron_init
		;;

	del_cron_init)
		del_cron_init
		;;

	set_cron_start_socket_server)
		set_cron_start_socket_server
		;;

	del_cron_start_socket_server)
		del_cron_start_socket_server
		;;

	debug1)
		debug1 $2 $3 $4 $5
		;;

	debug2)
		debug2 $2 $3 $4 $5
		;;


	*) 
		show_usage
		exit 1
		;;
esac

# Elimina eventuali file temporane utilizzati per la gestione dei cron
rm "$TMP_CRON_FILE" 2> /dev/null
rm "$TMP_CRON_FILE-2" 2> /dev/null

