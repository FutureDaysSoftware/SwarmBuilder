#!/usr/bin/env bash

## Import config variables
#source ${BASH_SOURCE%/*}/config.sh  # Config is NOT imported

USAGE="\nExecute a command on a manager node.

Usage:
$(basename "$0") --ssh-command <COMMAND> --token <TOKEN> [OPTIONS]

where:
    exampleSwarmName    The name of an existing swarm.
    -c, --ssh-command   The command to execute on the remote host.
    -t, --token         Your DigitalOcean API key.

Available Options:
    --swarm             The name of the swarm that should be targeted.
                         A manager node within this swarm will be SSH'd into.
                         If this parameter is omitted, then --manager-id must be provided.
    --manager-id        The DigitalOcean droplet ID to connect to. Providing this saves
                         a doctl API call.
                         If this parameter is omitted, then --swarm must be provided.
\n"

## Set default options
MANAGER_ID=""

## Process flags and options
SHORTOPTS="t:,c:"
LONGOPTS="ssh-command:,token:,swarm:,manager-id:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-c | --ssh-command)
		    shift
		    SSH_COMMAND="$1"
		    shift
		    ;;
		--manager-id)
		    shift
		    MANAGER_ID="$1"
		    shift
		    ;;
		--swarm)
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

if [[ $# -eq 0 ]] && [[ -z "$MANAGER_ID" ]] && [[ -z "$SWARM_NAME" ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z "$SSH_COMMAND" ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z ${DO_ACCESS_TOKEN} ]]; then
    printf "A DigitalOcean access token was not provided.
    You must provide one on the command line when using this command.\n\n"
    exit 1
fi


## Find a manager node to connect to
if [[ -z "$MANAGER_ID" ]]; then
    MANAGER_ID=$(${BASH_SOURCE%/*}/get-manager-info.sh ${SWARM_NAME} --format ID --token ${DO_ACCESS_TOKEN}) || exit 1
fi

## Connect to the manager and scale the service
doctl compute ssh ${MANAGER_ID} \
	--access-token ${DO_ACCESS_TOKEN} \
	--ssh-command "${SSH_COMMAND}"

