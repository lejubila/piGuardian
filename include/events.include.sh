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


