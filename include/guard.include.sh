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
	if [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -gt 0 ]]; then
		alarm_fired "reactive"
	else
		sensor_set_state "alarm_fired" 0
	fi


	local I=0

	#
	# Inizio ciclo di lettura dei sensori
	#
	while [ 1 ]; do

		local TOTAL_SENSOR_IN_ALARM=0
		local ALARM_ENABLED=`alarm_get_status`

		if [ "$I" -eq "100" ]; then
			#log_write "debug"
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
					trigger_event "perimetral_on" "$a"
				fi

				# Fa scattare l'allarme se è abiltiato e se non è ancora scattato
				#local ALARM_ENABLED=`alarm_get_status`
				local ALARM_FIRED=`alarm_fired_get_status`
#log_write "*****************"
#if [[ "$ALARM_ENABLED" -lt 0 || ( "$ALARM_ENABLED" -gt 0 && "$ALARM_FIRED" -eq 0 ) ]]; then
#if [ "$ALARM_ENABLED" -lt 0 ] || [[ "$ALARM_ENABLED" -gt 0 && "$ALARM_FIRED" -eq 0 ]]; then
#	log_write "*X* ALARM_ENABLED=$ALARM_ENABLED - ALARM_FIRED=$ALARM_FIRED"
#fi

				if [[ "$ALARM_ENABLED" -lt 0 || ( "$ALARM_ENABLED" -gt 0 && "$ALARM_FIRED" -eq 0 ) ]]; then
					local RE="^perimetral_$a$"
					local R=$($GREP "$RE" "$FILE_ALARM_DISABLE_SENSOR")
#	log_write "*** R=$R"
#if [ -z "$R" ] ; then
#	log_write "*0* R=vuoto"
#fi
					
					if [ -z "$R" ]  && [ "$ALARM_ENABLED" -lt 0 ]; then
						TOTAL_SENSOR_IN_ALARM=$((TOTAL_SENSOR_IN_ALARM+1))
#log_write "*1* $ALARM_ENABLED - TOTAL_SENSOR_IN_ALARM=$TOTAL_SENSOR_IN_ALARM"
					elif [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -eq 0 ]]; then
						if [ -z "$R" ]; then
							alarm_fired "Perimetral $a"
						else
							local OUTPUT="Perimetral $a: sensor disabled, not fired alarm $TIME_OPEN"
							log_write "$OUTPUT"
							echo "$OUTPUT"
						fi
					fi

					#local RE="^perimetral_$a$"
					#if ! $GREP "$RE" "$FILE_ALARM_DISABLE_SENSOR" > /dev/null; then
					#	alarm_fired "Perimetral $a"
					#else
					#	local OUTPUT="Perimetral $a: sensor disabled, not fired alarm $TIME_OPEN"
					#	log_write "$OUTPUT"
					#	echo "$OUTPUT"
					#fi

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
					trigger_event "perimetral_off" "$a"
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
					trigger_event "pir_on" "$a"
				fi

				# Fa scattare l'allarme se è abiltiato e se non è ancora scattato
				#local ALARM_ENABLED=`alarm_get_status`
				local ALARM_FIRED=`alarm_fired_get_status`
				if [[ "$ALARM_ENABLED" -lt 0 || ( "$ALARM_ENABLED" -gt 0 && "$ALARM_FIRED" -eq 0 ) ]]; then
					local RE="^pir_$a$"
					local R=$($GREP "$RE" "$FILE_ALARM_DISABLE_SENSOR")
					
					if [ -z "$R" ]  && [ "$ALARM_ENABLED" -lt 0 ]; then
						TOTAL_SENSOR_IN_ALARM=$((TOTAL_SENSOR_IN_ALARM+1))
					elif [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -eq 0 ]]; then
						if [ -z "$R" ]; then
							alarm_fired "Pir $a"
						else
							local OUTPUT="Pir $a: sensor disabled, not fired alarm $TIME_OPEN"
							log_write "$OUTPUT"
							echo "$OUTPUT"
						fi
					fi
				fi

				#if [[ "$ALARM_ENABLED" -gt 0 ]] && [[ "$ALARM_FIRED" -eq 0 ]]; then
				#	local RE="^pir_$a$"
				#	if ! $GREP "$RE" "$FILE_ALARM_DISABLE_SENSOR" > /dev/null; then
				#		alarm_fired "Pir $a"
				#	else
				#		local OUTPUT="Pir $a: sensor disabled, not fired alarm $TIME_OPEN"
				#		log_write "$OUTPUT"
				#		echo "$OUTPUT"
				#	fi
				#fi

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
					trigger_event "pir_off" "$a"
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

		# Se lo stato di alarm_enabled è negativo vuole dire che è stata richiesto l'attivazione dell'allarme,
		# se nessun sensore è in allarme, lo abilita impostando alarm_enabled con valore positivo.
		#local ALARM_ENABLED=`alarm_get_status`
#log_write "ALARM_ENABLED=$ALARM_ENABLED - TOTAL_SENSOR_IN_ALARM=$TOTAL_SENSOR_IN_ALARM"
		if [[ "$ALARM_ENABLED" -lt 0 ]] && [[ "$TOTAL_SENSOR_IN_ALARM" -eq 0 ]]; then
#log_write "ALARM_ENABLED=$ALARM_ENABLED - TOTAL_SENSOR_IN_ALARM=$TOTAL_SENSOR_IN_ALARM"
			local TIME_ALARM=`date +%s`
			sensor_set_state "alarm_enabled" $TIME_ALARM
			#trigger_event "alarm_enable" ""
			log_write "Alarm enabled $TIME_ALARM"
			message_write "success" "Alarm enabled"
			sleep 1
		fi

	done

	log_write "Guard end"

}

