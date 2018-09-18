
function start_socket_server {

	rm -f "$TCPSERVER_PID_FILE"
	echo $TCPSERVER_PID_SCRIPT > "$TCPSERVER_PID_FILE"
	$TCPSERVER -v -RHl0 $TCPSERVER_IP $TCPSERVER_PORT $0 socket_server_command 

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

	# @todo implementare credenziali socket server

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

		alarm_enable)
			alarm_enable "$arg2" &> /dev/null
			json_status
			;;

		alarm_disable)
			alarm_disable &> /dev/null
			json_status
			;;

		alarm_disable_sensor)
			alarm_disable_sensor $arg2 $arg3 &> /dev/null
			json_status
			;;

		alarm_enable_all_sensor)
			alarm_enable_all_sensor &> /dev/null
			json_status
			;;

		open)
	                if [ "empty$arg2" == "empty" ]; then
        	                json_error 0 "Alias solenoid not specified"
			else
                		ev_open $arg2 $arg3 &> /dev/null
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


