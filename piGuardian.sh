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

	if [ ! -f "$FILE_ALARM_DISABLE_SENSOR" ]; then
		touch "$FILE_ALARM_DISABLE_SENSOR"
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
# $2 default value
#
function sensor_get_state {
	local STATE_FILE="$STATUS_DIR/$1"
	local DEFAULT="$2"

	if [ -z "$DEFAULT" ]; then
		DEFAULT=0
	fi

	if [ ! -e "$STATE_FILE" ]; then
		sensor_set_state "$1" "$DEFAULT"
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
# $1 tipo allarme: home, away, empty
#
function alarm_enable {
	local TIME_ALARM=-`date +%s`
	local TYPE="$1"
	local ARMED="armed"
	# Imposta alarm_enabled con stato negativo per indicare che è stato richiesto l'attivazione dell'allarme
	# l'allarme viene abilitato dalla funzione start_guard avviata in background quando alarm_enabled viene trovato 
	# con stato negativo e tutti i sensori non sono in allarme
	sensor_set_state "alarm_enabled" $TIME_ALARM
	
	trigger_event "alarm_pending" "$output"
	sensor_set_state "alarm_state" "pending"

	local i=0
	local time_sleep=10
	local alarm_state=0

	# Se è stato scelto l'allarme di tipo home abilita tutti i sensori ad accezione dei sensori di movimento (pir)
log_write "TYPE = $TYPE"
	if [ "$TYPE" == "home" ]; then
log_write "**** dentro home"
		alarm_enable_all_sensor
		alarm_disable_sensor pir all
		ARMED="armed_home"
	# Se è stato scelto l'allarme di tipo away abilita tutti i sensori
	elif [ "$TYPE" == "away" ]; then
		alarm_enable_all_sensor
		ARMED="armed_away"
	fi

	# Ettende un tempo minimo per verificare se l'allarme sia stato attivato dalla funzione start_guard che gira in background
	while [ $i -lt $time_sleep ]
	do
		alarm_state=`alarm_get_status`
		if [ $alarm_state -gt 0 ]; then
			break
		fi
		i=$[$i+1]
		sleep 1
	done	

	alarm_state=`alarm_get_status`
	local output=""
	if [ $alarm_state -lt 0 ]; then
		sensor_set_state "alarm_enabled" 0
		sensor_set_state "alarm_state" "disarmed"
		output="Alarm not activated: some sensors are in alarm" 
		log_write "$output"
		message_write "warning" "$output"
		trigger_event "alarm_enable_fail" "$output"
	elif [ $alarm_state -gt 0 ]; then
		output="Alarm activated $ARMED" 
		sensor_set_state "alarm_state" "$ARMED"
		trigger_event "alarm_enable" ""
	else
		sensor_set_state "alarm_state" "disarmed"
		output="Alarm not activated" 
		log_write "$output"
		message_write "warning" "$output"
		trigger_event "alarm_enable_fail" "$output"
	fi
	echo "$output"

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

	sensor_set_state "alarm_state" "disarmed"

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

	sensor_set_state "alarm_state" "triggered"
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

	local output="Sensor successfully disabled: $TYPE $2"
	echo $output
	log_write " $output"
	message_write "success" "Sensor successfully disabled"

	trigger_event "alarm_disable_sensor" "$TYPE $2"
}

#
# Riabilita tutti i sensori quando l'allarme è attivo eliminando il file contentente i sensori diabbilitati con alarm_disable_sensor
#

function alarm_enable_all_sensor {

	rm -f "$FILE_ALARM_DISABLE_SENSOR" 2> /dev/null

	local output="All sensor successfully enabled"
	echo $output
	log_write " $output"
	message_write "success" "$output"

	trigger_event "alarm_enable_all_sensor" "$TYPE $2"

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
	echo -e "\t$NAME_SCRIPT alarm_enable [home|away]                     enable alarm"
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
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT start_socket_server [force]                  start socket server"
	echo -e "\t                                                           with 'force' parameter force close socket server if already open"
	echo -e "\t$NAME_SCRIPT stop_socket_server                           stop socket server"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT json_status [get_cron]                       show status in json format"
	echo -e "\t$NAME_SCRIPT mqtt_status                                  send status in json format to mqtt broker"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT set_cron_init                                set crontab for initialize control unit"
	echo -e "\t$NAME_SCRIPT del_cron_init                                remove crontab for initialize control unit"
	echo -e "\t$NAME_SCRIPT set_cron_start_socket_server                 set crontab for start socket server"
	echo -e "\t$NAME_SCRIPT del_cron_start_socket_server                 remove crontab for start socket server"
	echo -e "\t"
	echo -e "\t$NAME_SCRIPT debug1 [parameter]|[parameter]|..]           Run debug code 1"
	echo -e "\t$NAME_SCRIPT debug2 [parameter]|[parameter]|..]           Run debug code 2"
}


#
# Stampa un json contanente lo status della centralina
# $1 .. $6 parametri opzionali
# 	- get_cron: aggiunge i dati relativi ai crontab delle scehdulazioni di apertura/chisura delle elettrovalvole
#
function json_status {
	local json=""
	local json_version="\"version\":{\"ver\":$VERSION,\"sub\":$SUB_VERSION,\"rel\":$RELEASE_VERSION}"
	local json_error="\"error\":{\"code\":0,\"description\":\"\"}"
	local json_perimetral=""
	local json_pir=""
	local json_tamper=""
	local json_alarm=""
	local json_sensor_disabled=""
	local last_info=""
	local last_warning=""
	local last_success=""
	local with_get_cron="0"

	local vret=""
	for i in $1 $2 $3 $4 $5 $6
        do
		if [ $i = "get_cron" ]; then
			with_get_cron="1"
		fi
	done

	local a
	local av

	json=""
	for i in $(seq $PERIMETRAL_TOTAL)
	do
		a=PERIMETRAL"$i"_ALIAS
		av=${!a}
		local s=`perimetral_get_status $av`
		local al=0
		if [ $s -gt 0 ]; then
			al=1
		fi
		if [ -n "$json" ]; then
			json="$json,"
		fi
		json="$json\"$av\":{\"name\":\"$av\",\"state\":$s,\"alarm\":$al}"
	done
	json_perimetral="\"perimetral\":{$json}"

	json=""
	for i in $(seq $PIR_TOTAL)
	do
		a=PIR"$i"_ALIAS
		av=${!a}
		local s=`pir_get_status $av`
		local al=0
		if [ $s -gt 0 ]; then
			al=1
		fi
		if [ -n "$json" ]; then
			json="$json,"
		fi
		json="$json\"$av\":{\"name\":\"$av\",\"state\":$s,\"alarm\":$al}"
	done
	json_pir="\"pir\":{$json}"

	json=""
	for i in $(seq $TAMPER_TOTAL)
	do
		a=TAMPER"$i"_ALIAS
		av=${!a}
		local s=`tamper_get_status $av`
		local al=0
		if [ $s -gt 0 ]; then
			al=1
		fi
		if [ -n "$json" ]; then
			json="$json,"
		fi
		json="$json\"$av\":{\"name\":\"$av\",\"state\":$s,\"alarm\":$al}"
	done
	json_tamper="\"tamper\":{$json}"

	local json_pir_disabled=""
	local json_perimetral_disabled=""
	for i in $(cat "$FILE_ALARM_DISABLE_SENSOR" 2> /dev/null)
	do
		local name_sensor_disabled=""
		if [[ "$i" == perimetral_* ]]; then
			name_sensor_disabled="${i#perimetral_}"
			if [ -n "$json_perimetral_disabled" ]; then
				json_perimetral_disabled="$json_perimetral_disabled,"
			fi
			json_perimetral_disabled="$json_perimetral_disabled\"$name_sensor_disabled\""
		elif [[ "$i" == pir_* ]]; then
			name_sensor_disabled="${i#pir_}"
			if [ -n "$json_pir_disabled" ]; then
				json_pir_disabled="$json_pir_disabled,"
			fi
			json_pir_disabled="$json_pir_disabled\"$name_sensor_disabled\""
		fi
	done
	json_sensor_disabled="\"sensor_disabled\":{\"perimetral\":[$json_perimetral_disabled],\"pir\":[$json_pir_disabled]}"

	local alarm_fired_status=$(alarm_fired_get_status)
	local al=0
	if [ $alarm_fired_status -gt 0 ]; then
		al=1
	fi
	json_alarm="\"alarm\":{\"enabled\":\"$(alarm_get_status)\", \"fired\":\"$alarm_fired_status\", \"alarm\":\"$al\"}"

	if [ -f "$LAST_INFO_FILE.$!" ]; then
		last_info=`cat "$LAST_INFO_FILE.$!"`
	fi
	if [ -f "$LAST_WARNING_FILE.$!" ]; then
		last_warning=`cat "$LAST_WARNING_FILE.$!"`
	fi
	if [ -f "$LAST_SUCCESS_FILE.$!" ]; then
		last_success=`cat "$LAST_SUCCESS_FILE.$!"`
	fi
	local json_last_info="\"info\":\"$last_info\""	
	local json_last_warning="\"warning\":\"$last_warning\""	
	local json_last_success="\"success\":\"$last_success\""	

	local json_get_cron=""			
	if [ $with_get_cron != "0" ]; then
		local values_open="" 
		local values_close="" 
		local element_for=""
		if [ "$with_get_cron" == "1" ]; then
			element_for="$(seq $EV_TOTAL)"
		else
			ev_alias2number $with_get_cron
			element_for=$?
		fi
		for i in $element_for
		do
			local a=EV"$i"_ALIAS
			local av=${!a}
			local crn="$(cron_get "open" $av)"
			crn=`echo "$crn" | sed ':a;N;$!ba;s/\n/%%/g'`
			values_open="\"$av\": \"$crn\", $values_open"
			local crn="$(cron_get "close" $av)"
			crn=`echo "$crn" | sed ':a;N;$!ba;s/\n/%%/g'`
			values_close="\"$av\": \"$crn\", $values_close"
		done
		if [[ !  -z  $values_open ]]; then
			values_open="${values_open::-2}"
		fi
		if [[ !  -z  $values_close ]]; then
			values_close="${values_close::-2}"
		fi

		json_get_cron="\"open\": {$values_open},\"close\": {$values_close}"
	fi
	local json_cron="\"cron\":{$json_get_cron}"			

	json="{$json_version,$json_perimetral,$json_pir,$json_tamper,$json_sensor_disabled,$json_alarm,$json_error,$json_last_info,$json_last_warning,$json_last_success,$json_cron}"

	echo "$json"

}

json_error()
{
	echo "{\"error\":{\"code\":$1,\"description\":\"$2\"}}"
}

#
# Invia al broker mqtt il json contentente lo stato del sistema
#
function mqtt_status {

	local js=$(json_status)
	$MOSQUITTO_PUB -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PWD -i $MQTT_CLIENT_ID -r -t "$MQTT_TOPIC" -m "$js"
	$MOSQUITTO_PUB -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PWD -i $MQTT_CLIENT_ID -r -t "$MQTT_TOPIC/alarm_state" -m "$(sensor_get_state alarm_state disarmed)"
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

. "$DIR_SCRIPT/include/cron.include.sh"
. "$DIR_SCRIPT/include/events.include.sh"
. "$DIR_SCRIPT/include/socket.include.sh"
. "$DIR_SCRIPT/include/guard.include.sh"

FILE_ALARM_DISABLE_SENSOR="$STATUS_DIR/alarm_disable_sensor"

LAST_INFO_FILE="$STATUS_DIR/last_info"
LAST_WARNING_FILE="$STATUS_DIR/last_warning"
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
		alarm_enable "$2"
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

	json_status)
		json_status $2 $3 $4 $5 $6
		;;
	mqtt_status)
		mqtt_status
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

reset_messages &> /dev/null


