#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nExecute a command on a manager node.
Note: SSH will be used with the \"-oStrictHostKeyChecking=no\" flag to eliminate the need for user confirmation.

Usage:
$(basename "$0") --ssh-command <COMMAND> --token <TOKEN> [OPTIONS]

where:
    exampleSwarmName    The name of an existing swarm.
    -c, --ssh-command   The command to execute on the remote host.
    -t, --token         Your DigitalOcean API key.

Available Options:
    -s, --swarm         The name of the swarm that should be targeted.
                         A manager node within this swarm will be SSH'd into.
                         If this parameter is omitted, then \'--ip\' must be provided.
    -h, --ip            The IP address to connect to. Providing this saves a doctl API call
                         and is therefore faster.
                         If this parameter is omitted, then --swarm must be provided.
\n"

## Set default options
SSH_USER="root"

## Process flags and options
SHORTOPTS="t:c:s:h:"
LONGOPTS="ssh-command:,token:,swarm:,ip:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-c | --ssh-command)
		    shift
		    SSH_COMMAND="$1"
		    shift
		    ;;
		-h | --ip)
		    shift
		    HOST_IP="$1"
		    shift
		    ;;
		-s | --swarm)
		    shift
		    SWARM_NAME="$1"
		    shift
		    ;;
		-t | --token)
		    shift
		    DO_ACCESS_TOKEN="$1"
		    shift
		    ;;
		-- )
		    shift
		    break
		    ;;
		* )
		    shift
		    break
		    ;;
	esac
done

if [[ $# -eq 0 ]] && [[ -z "$HOST_IP" ]] && [[ -z "$SWARM_NAME" ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z "$SSH_COMMAND" ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z "$DO_ACCESS_TOKEN" ]] && [[ -z "$HOST_IP" ]]; then
    printf "A DigitalOcean access token was not provided.
    You must provide one on the command line when using this command or set one in the \'config.sh\' file.\n\n"
    exit 1
fi


## Find a manager node to connect to
if [[ -z "$HOST_IP" ]]; then
    HOST_IP=$(${DIR}/helpers/get-manager-info.sh ${SWARM_NAME} --format PublicIPv4 --token ${DO_ACCESS_TOKEN}) || exit 1
fi

## Connect to the manager and run the command (using native ssh)
ssh -oStrictHostKeyChecking=no ${SSH_USER}@${HOST_IP} "${SSH_COMMAND}"
