#!/bin/sh -e
if [ -z "$1" ]; then
   echo "Usage: $0 COMMAND" 1>&2
   exit 1
fi

COMMAND="$1"
JOB="sudo -u pryormic /home/pryormic/git_source_control/app_dev/run_governor_sub.sh >> /home/pryormic/governor.log 2>&1"
KILL_JOB="pkill -f governor.py"
echo "Job is $JOB"
echo "Kill job is $KILL_JOB"
case $COMMAND in
status)
    echo "STATUS"
;;

stop)
   $KILL_JOB
;;

start)
   $JOB &
;;

restart)
   $KILL_JOB
   $JOB &
;;
esac
