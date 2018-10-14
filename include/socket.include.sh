
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

        if [ ! -z "$TCPSERVER_USER" ] && [ ! -z "$TCPSERVER_PWD" ]; then
                local user=""
                local password=""
                read -t 3 user
                read -t 3 password
                user=$(echo "$user" | $TR -d '[\r\n]')
                password=$(echo "$password" | $TR -d '[\r\n]')
                if [ "$user" != "$TCPSERVER_USER" ] || [ "$password" != "$TCPSERVER_PWD" ]; then
                        log_write "socket connection from: $TCPREMOTEIP - Bad socket server credentials - user:$user"
                        json_error 0 "Bad socket server credentials"
                        return
                fi
        fi

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
	
	#reset_messages &> /dev/null

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

		set_state)
			sensor_set_state "$arg2" "$arg3" &> /dev/null
			json_status
			mqtt_status
			;;

		*)
			json_error 0 "invalid command"
			;;

	esac
	
	#reset_messages &> /dev/null

}


