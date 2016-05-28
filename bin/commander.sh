#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ACTION=${1}
START_COMMAND="python /home/pryormic/hologram/bin/../PythonServer/commander.py --governor_host=212.227.84.229"
${DIR}/run.sh ${ACTION} "commander" "${START_COMMAND}"
