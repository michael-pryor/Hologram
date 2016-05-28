#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ACTION=${1}
START_COMMAND="python /home/pryormic/hologram/bin/../PythonServer/governor.py --tcp_port=54321 --udp_port=54322"
${DIR}/run.sh ${ACTION} "governor" "${START_COMMAND}"
