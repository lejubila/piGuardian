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
	#rm -f "$STATUS_DIR"/*

	# Inizializza i gpio dei sensori perimetrali 
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		g=PERIMETRAL"$i"_GPIO
		$GPIO -g mode ${!g} in			# setta il gpio nella modalita di lettura
		#perimetral_set_state $i 0
	done

	# Inizializza i gpio dei sensori pir 
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		g=PIR"$i"_GPIO
		$GPIO -g mode ${!g} in			# setta il gpio nella modalita di lettura
		#pir_set_state $i 0
	done

	# Inizializza i gpio dei sensori tamper 
	for i in $(seq $TAMPER_TOTAL)
	do
		g=TAMPER"$i"_GPIO
		$GPIO -g mode ${!g} in			# setta il gpio nella modalita di lettura
		#tamper_set_state $i 0
	done


	# Inizializza i gpio delle sirene e le spenge
	if [ "$SIREN_TOTAL" -gt 0 ]; then
		for i in $(seq $SIREN_TOTAL)
		do
			g=SIREN"$i"_GPIO
			$GPIO -g mode ${!g} out
		done
		alarm_unfired > /dev/null
	fi

	trigger_event "init" ""
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
# Imposta lo stato di un sensore 
# $1 alias del sensore
# $2 stato da scrivere
#
function sensor_set_state {
	echo "$2" > "$STATUS_DIR/$1"
}

#
# Legge lo stato di un sensore 
# $1 alias del sensore
#
function sensor_get_state {
	local STATE_FILE="$STATUS_DIR/$1"

	if [ ! -e "$STATE_FILE" ]; then
		sensor_set_state "$1" 0
		echo 0
	else
		cat "$STATE_FILE"
	fi
}

#
# Mostra lo stato di tutti i sensori
#
function sensor_status_all {
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		a=PERIMETRAL"$i"_ALIAS
		av=${!a}
		local s=`perimetral_get_status $av`
		echo -e "perimetral $av: $s"
	done

	for i in $(seq $PIR_TOTAL)
	do
		a=PIR"$i"_ALIAS
		av=${!a}
		local s=`pir_get_status $av`
		echo -e "pir $av: $s"
	done

	for i in $(seq $TAMPER_TOTAL)
	do
		a=TAMPER"$i"_ALIAS
		av=${!a}
		local s=`tamper_get_status $av`
		echo -e "tamper $av: $s"
	done

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
# Mostra lo stato di un sensore perimetrale
# $1 alias sensore
#
function perimetral_get_status {
	if [[ "$(perimetral_alias_exists $1)" == "FALSE" ]]; then
		local output="alias perimetral sensor not found: $1"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi

	sensor_get_state "perimetral_$1"
}

#
# Scrive lo stato di un sensore perimetrale
# $1 alias sensore
# $2 stato
#
function perimetral_set_status {
	if [[ "$(perimetral_alias_exists $1)" == "FALSE" ]]; then
		local output="alias perimetral sensor not found: $1"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi

	sensor_set_state "perimetral_$1" $2
}

#
# Mostra lo stato dei sensori perimetrali
#
function perimetral_list_alias {

                for i in $(seq $PERIMETRAL_TOTAL)
                do
                        local a=PERIMETRAL"$i"_ALIAS
                        local al=${!a}
                        echo $al
                done

}



#
# Passando un alias di un sensore tamper recupera il numero gpio associato 
# $1 alias sensore
#
function tamper_get_gpio4alias {
	for i in $(seq $PIR_TOTAL)
	do
		local g=TAMPER"$i"_GPIO
		local a=TAMPER"$i"_ALIAS
		local gv=${!g}
		local av=${!a}
		if [ "$av" == "$1" ]; then
			return $gv
		fi
	done

	log_write "ERROR tamper sensor alias not found: $1"
	message_write "warning" "Tamper sensor alias not found"
	exit 1
}

#
# Recupera il numero di sensore tamper in base all'alias
# $1 alias del sensore
#
function tamper_get_number4alias {
	for i in $(seq $PIR_TOTAL)
	do
		local a=TAMPER"$i"_ALIAS
		local av=${!a}
		if [ "$av" == "$1" ]; then
			return $i
		fi
	done

	log_write "ERROR tamper sensor alias not found: $1"
	message_write "warning" "Tamper sensor alias not found"
	exit 1
}

#
# Recupera l'alias di sensore tamper in base al numero
# $1 numero del sensore
#
function tamper_get_alias4number {
	local n=TAMPER"$1"_ALIAS
	local a=${!n}
	
	if [ ! -z "$a" ]; then
		echo "$a"
		return
	fi

	log_write "ERROR tamper sensor number not found: $1"
	message_write "warning" "Tamper sensor number not found"
	exit 1
}

#
# Verifica se l'alias di una sensore tamper esiste
# $1 alias del sensore
#
function tamper_alias_exists {
	local vret='FALSE'
	for i in $(seq $PIR_TOTAL)
	do
		a=TAMPER"$i"_ALIAS
		av=${!a}
		if [ "$av" == "$1" ]; then
			vret='TRUE'
		fi
	done

	echo $vret
}

#
# Recupera il numero di gpio associato in base al numero di sensore tamper 
# $1 numero sensore
#
function tamper_get_gpio4number {
#	echo "numero ev $1"
	i=$1
	g=TAMPER"$i"_GPIO
	gv=${!g}
#	echo "gv = $gv"
	return $gv
}

#
# Mostra lo stato di un sensore tamper
# $1 alias sensore
#
function tamper_get_status {
	if [[ "$(tamper_alias_exists $1)" == "FALSE" ]]; then
		local output="alias tamper sensor not found: $1"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi
	sensor_get_state "tamper_$1"
}

#
# Scrive lo stato di un sensore tamper
# $1 alias sensore
# $2 stato
#
function tamper_set_status {
	if [[ "$(tamper_alias_exists $1)" == "FALSE" ]]; then
		local output="alias tamper sensor not found: $1"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi
	sensor_set_state "tamper_$1" $2
}

#
# Mostra lo stato dei sensori tamper
#
function tamper_list_alias {

                for i in $(seq $TAMPER_TOTAL)
                do
                        local a=TAMPER"$i"_ALIAS
                        local al=${!a}
                        echo $al
                done

}



#
# Passando un alias di un sensore pir recupera il numero gpio associato 
# $1 alias sensore
#
function pir_get_gpio4alias {
	for i in $(seq $PIR_TOTAL)
	do
		local g=PIR"$i"_GPIO
		local a=PIR"$i"_ALIAS
		local gv=${!g}
		local av=${!a}
		if [ "$av" == "$1" ]; then
			return $gv
		fi
	done

	log_write "ERROR pir sensor alias not found: $1"
	message_write "warning" "Pir sensor alias not found"
	exit 1
}

#
# Recupera il numero di sensore pir in base all'alias
# $1 alias del sensore
#
function pir_get_number4alias {
	for i in $(seq $PIR_TOTAL)
	do
		local a=PIR"$i"_ALIAS
		local av=${!a}
		if [ "$av" == "$1" ]; then
			return $i
		fi
	done

	log_write "ERROR pir sensor alias not found: $1"
	message_write "warning" "Pir sensor alias not found"
	exit 1
}

#
# Recupera l'alias di sensore pir in base al numero
# $1 numero del sensore
#
function pir_get_alias4number {
	local n=PIR"$1"_ALIAS
	local a=${!n}
	
	if [ ! -z "$a" ]; then
		echo "$a"
		return
	fi

	log_write "ERROR pir sensor number not found: $1"
	message_write "warning" "Pir sensor number not found"
	exit 1
}

#
# Verifica se l'alias di una sensore pir esiste
# $1 alias del sensore
#
function pir_alias_exists {
	local vret='FALSE'
	for i in $(seq $PIR_TOTAL)
	do
		a=PIR"$i"_ALIAS
		av=${!a}
		if [ "$av" == "$1" ]; then
			vret='TRUE'
		fi
	done

	echo $vret
}

#
# Recupera il numero di gpio associato in base al numero di sensore pir 
# $1 numero sensore
#
function pir_get_gpio4number {
#	echo "numero ev $1"
	i=$1
	g=PIR"$i"_GPIO
	gv=${!g}
#	echo "gv = $gv"
	return $gv
}

#
# Mostra lo stato di un sensore pir
# $1 alias sensore
#
function pir_get_status {
	if [[ "$(pir_alias_exists $1)" == "FALSE" ]]; then
		local output="alias pir sensor not found: $1"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi
	sensor_get_state "pir_$1"
}

#
# Scrive lo stato di un sensore pir
# $1 alias sensore
# $2 stato
#
function pir_set_status {
	if [[ "$(pir_alias_exists $1)" == "FALSE" ]]; then
		local output="alias pir sensor not found: $1"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi
	sensor_set_state "pir_$1" $2
}

#
# Mostra lo stato dei sensori pir
#
function pir_list_alias {

                for i in $(seq $PIR_TOTAL)
                do
                        local a=PIR"$i"_ALIAS
                        local al=${!a}
                        echo $al
                done

}


#
# Legge se è abiltiato l'allarme
#
function alarm_get_status {
	sensor_get_state "alarm_enabled"
}

#
# Abilita l'allarme
#
function alarm_enable {
	local TIME_ALARM=`date +%s`
	sensor_set_state "alarm_enabled" $TIME_ALARM
	log_write "Alarm enabled $TIME_ALARM"

	trigger_event "alarm_enable" ""
}

#
# Disabilita l'allarme
#
function alarm_disable {
	local TIME_ALARM=`date +%s`
	sensor_set_state "alarm_enabled" 0
	log_write "Alarm disabled $TIME_ALARM"

	if [ "$(alarm_fired_get_status)" -gt 0 ]; then
		alarm_unfired
	fi

	trigger_event "alarm_disable" ""
}

#
# Legge se è scattato l'allarme
#
function alarm_fired_get_status {
	sensor_get_state "alarm_fired"
}

#
# Fa scattare l'allarme
# $1 indica chi ha fatto scattare l'allarme
#
function alarm_fired {
	local cause="UNKNOW"
	if [[ ! -z $1 ]]; then
		cause=$1
	fi

	local TIME_ALARM=`date +%s`
	sensor_set_state "alarm_fired" $TIME_ALARM
	local OUTPUT="WARNING !!! Alarm fired ($cause) $TIME_ALARM"
	log_write "$OUTPUT"
	echo "$OUTPUT"

	#
	# Attiva le sirene
	#
	if [ "$SIREN_TOTAL" -gt 0 ]; then
		for i in $(seq $SIREN_TOTAL)
		do
			g=SIREN"$i"_GPIO
			$GPIO -g write ${!g} $SIREN_GPIO_STATE_ON
		done
	fi

	trigger_event "alarm_fired" "$cause"

}

#
# Disattiva l'allarme scattato
#
function alarm_unfired {
	local TIME_ALARM=`date +%s`
	sensor_set_state "alarm_fired" 0
	local OUTPUT="Alarm unfired $TIME_ALARM"
	log_write "$OUTPUT"
	echo "$OUTPUT"

	#
	# Disattiva le sirene 
	#
	if [ "$SIREN_TOTAL" -gt 0 ]; then
		for i in $(seq $SIREN_TOTAL)
		do
			g=SIREN"$i"_GPIO
			$GPIO -g write ${!g} $SIREN_GPIO_STATE_OFF
		done
	fi


	trigger_event "alarm_unfired" ""

}

#
# Disabilita dei sensori quando l'allarme è attivo
# $1	tipologia sensore: perimetral|pir
# $2	alias del sensore da disabilitare oppure 'all' per disabilitarli tutti
#
function alarm_disable_sensor {
	local TYPE="$1"
	local ALIAS="$2"
	if [ "$TYPE" != 'perimetral' ] && [ "$TYPE" != 'pir' ]; then
		local output="type "$TYPE" is wrong"
		echo $output
		log_write "ERROR $output"
		message_write "warning" "$output"
		exit 
	fi

	local ALIASIS
	if [ "$ALIAS" == 'all' ] && [ "$TYPE" == 'perimetral' ]; then
		ALIASIS="$(perimetral_list_alias)"
	elif [ "$ALIAS" == 'all' ] && [ "$TYPE" == 'pir' ]; then
		ALIASIS="$(pir_list_alias)"
	else
		if [ "$TYPE" == "perimetral" ] && [ "$(perimetral_alias_exists $ALIAS)" == "FALSE" ]; then
			local output="alias perimetal sensor not found: $ALIAS"
			echo $output
			log_write "ERROR $output"
			message_write "warning" "$output"
			exit 
		elif [ "$TYPE" == "pir" ] && [ "$(pir_alias_exists $ALIAS)" == "FALSE" ]; then
			local output="alias pir sensor not found: $ALIAS"
			echo $output
			log_write "ERROR $output"
			message_write "warning" "$output"
			exit 
		fi
		ALIASIS="$ALIAS"
	fi

	for a in $ALIASIS
	do
		echo "${TYPE}_$a" >> "$FILE_ALARM_DISABLE_SENSOR"
	done

}

#
# Riabilita tutti i sensori quando l'allarme è attivo eliminando il file contentente i sensori diabbilitati con alarm_disable_sensor
#

function alarm_enable_all_sensor {

	rm -f "$FILE_ALARM_DISABLE_SENSOR" 2> /dev/null

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

#
# Triggered an event and executge associated scripts
# $1 event
# $2 cause
#

function trigger_event {

	local EVENT="$1"
	local CAUSE="$2"
	local current_event_dir="$EVENT_DIR/$EVENT"

	if [ -d "$current_event_dir" ]; then
		local FILES="$current_event_dir/*"
		for f in $FILES
		do
			if [ -x "$f" ]; then
				$f "$EVENT" "$CAUSE" `date +%s`  &> /dev/null &
			fi
		done

	fi

}


function show_usage {
	echo -e "piGuardian v. $VERSION.$SUB_VERSION.$RELEASE_VERSION"
	echo -e ""
	echo -e "Usage:"
	echo -e "\t$NAME_SCRIPT init                                         initialize systm"
	echo -e "\t$NAME_SCRIPT start_guard [fg|force]                       start monitoring, with 'fg' parameter run monitoring in foreground mode"
	echo -e "\t                                                           with 'fg' parameter run monitoring in foreground mode"
	echo -e "\t                                                           with 'force' parameter force close guard service if already open"
	echo -e "\t$NAME_SCRIPT stop_guard                                   stop guard daemon"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT alarm_enable                                 enable alarm"
	echo -e "\t$NAME_SCRIPT alarm_disable                                disable alarm"
	echo -e "\t$NAME_SCRIPT alarm_get_status                             show status alarm"
	echo -e "\t$NAME_SCRIPT alarm_fired                                  fired alarm"
	echo -e "\t$NAME_SCRIPT alarm_unfired                                unfired alarm"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT alarm_disable_sensor [perimetral|pir] [alias_name|all]"
	echo -e "\t                                                           disables one or more sensors from the alarm"
	echo -e "\t$NAME_SCRIPT alarm_enable_all_sensor                      enable all sensor from the alarm"
	echo -e ""
	echo -e "\t$NAME_SCRIPT perimetral_list_alias                        view list of perimetral sensor"
	echo -e "\t$NAME_SCRIPT perimetral_status alias                      show perimetral sensor status"
	echo -e "\t$NAME_SCRIPT pir_list_alias                               view list of pir sensor"
	echo -e "\t$NAME_SCRIPT pir_status alias                             show pir sensor status"
	echo -e "\t$NAME_SCRIPT tamper_list_alias                            view list of tamper sensor"
	echo -e "\t$NAME_SCRIPT tamper_status alias                          show tamper sensor status"
	echo -e "\t$NAME_SCRIPT sensor_status_all                            show all sensor status"
	echo -e "\t$NAME_SCRIPT start_socket_server [force]                  start socket server"
	echo -e "\t                                                           with 'force' parameter force close socket server if already open"
	echo -e "\t$NAME_SCRIPT stop_socket_server                           stop socket server"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT set_cron_init                                set crontab for initialize control unit"
	echo -e "\t$NAME_SCRIPT del_cron_init                                remove crontab for initialize control unit"
	echo -e "\t$NAME_SCRIPT set_cron_start_socket_server                 set crontab for start socket server"
	echo -e "\t$NAME_SCRIPT del_cron_start_socket_server                 remove crontab for start socket server"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT debug1 [parameter]|[parameter]|..]           Run debug code 1"
	echo -e "\t$NAME_SCRIPT debug2 [parameter]|[parameter]|..]           Run debug code 2"
}

function start_guard_daemon {

	rm -f "$GUARD_PID_FILE"
	echo $GUARD_PID_SCRIPT > "$GUARD_PID_FILE"
	start_guard 

}

function stop_guard {

        if [ ! -f "$GUARD_PID_FILE" ]; then
                echo "Daemon is not running"
                exit 1
        fi

	log_write "stop guard daemon"
	echo "stop guard daemon"

        kill -9 $(list_descendants `cat "$GUARD_PID_FILE"`) 2> /dev/null
        kill -9 `cat "$GUARD_PID_FILE"` 2> /dev/null
        rm -f "$GUARD_PID_FILE"

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

	local SENSORS_PERIMETRAL=`perimetral_list_alias`
	local SENSORS_PIR=`pir_list_alias`
	local SENSORS_TAMPER=`tamper_list_alias`

	declare -A LAST_STATE

	#
	# Recupera l'ultimo stato dei sensori
	#
	for a in $SENSORS_PERIMETRAL
	do
		LAST_STATE[perimetral_$a]=`perimetral_get_status $a`
		#echo $a: ${LAST_STATE[perimetral_$a]}
	done
	for a in $SENSORS_PIR
	do
		LAST_STATE[pir_$a]=`pir_get_status $a`
		#echo $a: ${LAST_STATE[perimetral_$a]}
	done
	for a in $SENSORS_TAMPER
	do
		LAST_STATE[tamper_$a]=`tamper_get_status $a`
		#echo $a: ${LAST_STATE[perimetral_$a]}
	done




	# Fa scattare l'allarme se era già attivato precedentemente altrimenti ne imposta lo stato a zero
	local ALARM_ENABLED=`alarm_get_status`
	local ALARM_FIRED=`alarm_fired_get_status`
	if [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -eq 0 ]]; then
		alarm_fired "reactive"
	else
		sensor_set_state "alarm_fired" 0
	fi



	local I=0

	#
	# Inizio ciclo di lettura dei sensori
	#
	while [ 1 ]; do

		if [ "$I" -eq "100" ]; then
			log_write "debug"
			I=0
		fi
		I=$((I+1))

		#
		# Controlla i sensori perimetrali
		#
		for a in $SENSORS_PERIMETRAL
		do
			perimetral_get_gpio4alias $a
			local G=$?
			local STATE=`$GPIO -g read $G`

			# Sensore in allarme
			if [ "$STATE" == "$PERIMETRAL_GPIO_STATE" ]; then
				# Passa da stato di non allarme ad allarme
				if [ "${LAST_STATE[perimetral_$a]}" -eq 0 ]; then
					local TIME_OPEN=`date +%s`
					perimetral_set_status $a $TIME_OPEN
					LAST_STATE[perimetral_$a]=$TIME_OPEN
					local OUTPUT="Perimetral $a: OPEN $TIME_OPEN"
					log_write "$OUTPUT"
					echo "$OUTPUT"
					trigger_event "perimetral_open" "$a"
				fi

				# Fa scattare l'allarme se è abiltiato e se non è ancora scattato
				local ALARM_ENABLED=`alarm_get_status`
				local ALARM_FIRED=`alarm_fired_get_status`
				if [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -eq 0 ]]; then
					alarm_fired "Perimetral $a"
				fi

			# Il sensore non è in allarme
			else
				# Passa da stato di allarme a non allarme
				if [ "${LAST_STATE[perimetral_$a]}" -gt 0 ]; then
					local TIME_CLOSE=`date +%s`
					perimetral_set_status $a 0
					LAST_STATE[perimetral_$a]=0
					local OUTPUT="Perimetral $a: CLOSE $TIME_CLOSE"
					log_write "$OUTPUT"
					echo "$OUTPUT"
					trigger_event "perimetral_close" "$a"
				fi
			fi

			sleep $DELAY_LOOP_STATE
		done


		#
		# Controlla i sensori pir
		#
		for a in $SENSORS_PIR
		do
			pir_get_gpio4alias $a
			local G=$?
#echo $a - $?
			local STATE=`$GPIO -g read $G`

			# Sensore in allarme
			if [ "$STATE" == "$PIR_GPIO_STATE" ]; then
				# Passa da stato di non allarme ad allarme
				if [ "${LAST_STATE[pir_$a]}" -eq 0 ]; then
					local TIME_OPEN=`date +%s`
					pir_set_status $a $TIME_OPEN
					LAST_STATE[pir_$a]=$TIME_OPEN
					local OUTPUT="Pir $a: ALERT $TIME_OPEN"
					log_write "$OUTPUT"
					echo "$OUTPUT"
					trigger_event "pir_detect" "$a"
				fi

				# Fa scattare l'allarme se è abiltiato e se non è ancora scattato
				local ALARM_ENABLED=`alarm_get_status`
				local ALARM_FIRED=`alarm_fired_get_status`
				if [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -eq 0 ]]; then
					alarm_fired "Pir $a"
				fi

			# Il sensore non è in allarme
			else
				# Passa da stato di allarme a non allarme
				if [ "${LAST_STATE[pir_$a]}" -gt 0 ]; then
					local TIME_CLOSE=`date +%s`
					pir_set_status $a 0
					LAST_STATE[pir_$a]=0
					local OUTPUT="Pir $a: END ALERT $TIME_CLOSE"
					log_write "$OUTPUT"
					echo "$OUTPUT"
				fi
			fi

			sleep $DELAY_LOOP_STATE
		done


		#
		# Controlla i sensori tamper
		#
		for a in $SENSORS_TAMPER
		do
			tamper_get_gpio4alias $a
			local G=$?
			local STATE=`$GPIO -g read $G`

			# Sensore in allarme
			if [ "$STATE" == "$TAMPER_GPIO_STATE" ]; then
				# Passa da stato di non allarme ad allarme
				if [ "${LAST_STATE[tamper_$a]}" -eq 0 ]; then
					local TIME_OPEN=`date +%s`
					tamper_set_status $a $TIME_OPEN
					LAST_STATE[tamper_$a]=$TIME_OPEN
					local OUTPUT="Tamper $a: ALERT $TIME_OPEN"
					log_write "$OUTPUT"
					echo "$OUTPUT"
					trigger_event "tamper_detect" "$a"
				fi

				# Fa scattare l'allarme se non è ancora scattato (anche se l'allarme non è abilitato)
				local ALARM_FIRED=`alarm_fired_get_status`
				if [[ "$ALARM_FIRED" -eq 0 ]]; then
					alarm_fired "Tamper $a"
				fi

			# Il sensore non è in allarme
			else
				# Passa da stato di allarme a non allarme
				if [ "${LAST_STATE[tamper_$a]}" -gt 0 ]; then
					local TIME_CLOSE=`date +%s`
					tamper_set_status $a 0
					LAST_STATE[tamper_$a]=0
					local OUTPUT="Tamper $a: END ALERT $TIME_CLOSE"
					log_write "$OUTPUT"
					echo "$OUTPUT"
				fi
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
CONFIG_ETC="/home/pi/piGuardian/conf/piGuardian.conf"
TMP_PATH="/run/shm"
if [ ! -d "$TMP_PATH" ]; then
	TMP_PATH="/tmp"
fi
TCPSERVER_PID_FILE="$TMP_PATH/piGuardianTcpServer.pid"
TCPSERVER_PID_SCRIPT=$$
RUN_FROM_TCPSERVER=0

GUARD_PID_FILE="$TMP_PATH/piGuardianGuard.pid"
GUARD_PID_SCRIPT=$$

TMP_CRON_FILE="$TMP_PATH/piguardian.user.cron.$$"

if [ -f $CONFIG_ETC ]; then
	. $CONFIG_ETC
else
	echo -e "Config file not found in $CONFIG_ETC"
	exit 1
fi

FILE_ALARM_DISABLE_SENSOR="$STATUS_DIR/alarm_disable_sensor"

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
		perimetral_get_status $2
		;;

	pir_list_alias)
		pir_list_alias
		;;

	pir_status)
		pir_get_status $2
		;;

	tamper_list_alias)
		tamper_list_alias
		;;

	tamper_status)
		tamper_get_status $2
		;;

	sensor_status_all)
		sensor_status_all
		;;

	start_guard)
		if [ "$2" == "fg" ]; then
			start_guard
		else

                	if [ -f "$GUARD_PID_FILE" ]; then
                        	echo "Daemon is already running, use \"$0 stop_guard\" to stop the service"

				if [ "x$2" == "xforce" ]; then
					sleep 5
					stop_guard
				else
                        		exit 1
				fi
                	fi

                	nohup $0 start_guard_daemon > /dev/null 2>&1 &

                	echo "Daemon is started widh pid $!"
			log_write "start guard daemon with pid $!"

		fi
		;;

	start_guard_daemon)
		start_guard_daemon
		;;

	stop_guard)
		stop_guard
		;;


	alarm_enable)
		alarm_enable
		;;

	alarm_disable)
		alarm_disable
		;;

	alarm_get_status)
		alarm_get_status
		;;

	alarm_fired)
		alarm_fired "manual activate"
		;;

	alarm_unfired)
		alarm_unfired
		;;

	alarm_disable_sensor)
		alarm_disable_sensor "$2" "$3"
		;; 

	alarm_enable_all_sensor)
		alarm_enable_all_sensor
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

