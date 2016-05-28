#!/bin/sh -e
if [ ! -d "$LOG_DIR" ]; then
   echo "FAIL: LOG_DIR environment variable not set, should be in .bashrc"
   exit 1
fi

COMMAND="$1"
SCRIPT_NAME="$2"
SCRIPT_TO_RUN="$3"
JOB="${SCRIPT_TO_RUN}"
KILL_JOB="pkill -f $SCRIPT_NAME"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"

runItem() {
    $JOB >> "${LOG_FILE}" 2>&1 &
}

case $COMMAND in
stop)
   $KILL_JOB
;;

start)
   runItem
;;

restart)
   $KILL_JOB
   runItem
;;

lesslog)
   less ${LOG_FILE}
;;

*)
   echo FAIL: available commands are: stop, start, restart, lesslog.
;;
esac
