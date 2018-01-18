#!/usr/bin/env bash

## Import config variables
source ./config.sh

USAGE="\nPoll a swarm manager until the specified node becomes available

Usage:
$(basename "$0") <exampleSwarmName> [OPTIONS]

Where:
    exampleSwarmName    The name of the existing swarm.

Available Options:
    -h, --hostname      Required.  The name of the node to look for.
        --timeout       The number of seconds to continue polling before giving up. Default 60.
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'

Example:

    $(basename "$0") mySwarm --hostname mySwarm-02 --timeout 30 \n\n"

## Set default options
TIMEOUT=60

## Process flags and options
SHORTOPTS="h:t:"
LONGOPTS="hostname:,timeout:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
	    -h | --hostname)
            shift
		    HOSTNAME_TO_FIND="$1"
		    ;;
		--timeout)
		    shift
		    TIMEOUT="$1"
		    ;;
		-t | --token)
		    shift
		    DO_ACCESS_TOKEN="$1"
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
	shift;
done

if [[ $# -eq 0 ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z ${DO_ACCESS_TOKEN} ]]; then
    printf "A DigitalOcean access token was not provided.
    You must provide one on the command line when using this command, or set one in the \'config.sh\' file.\n\n"
    exit 1
fi

## Grab command-line parameters
## Note: options & flags have been 'shift'ed off the stack.
SWARM_NAME="$1"


## Find an existing manager node for the requested swarm
MANAGER_NODE_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME}-manager \
    --format Name,ID,PublicIPv4 \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | head -n1)

## Get the swarm join-token from the manager node
if [ -z "$MANAGER_NODE_STRING" ]; then
    printf "No manager node found for the \"${SWARM_NAME}\" swarm. Does the swarm exist yet?\n\n" 1>&2
    exit 1
else

    MANAGER_NODE_ARRAY=(${MANAGER_NODE_STRING})
    MANAGER_NAME=${MANAGER_NODE_ARRAY[0]}
    MANAGER_ID=${MANAGER_NODE_ARRAY[1]}
    MANAGER_IP=${MANAGER_NODE_ARRAY[2]}

    SSH_COMMAND="docker node ls --format \"{{.Hostname}},{{.Status}},{{.Availability}}\""

    TIMER=0
    RESPONSE=$(doctl compute ssh ${MANAGER_ID} --access-token ${DO_ACCESS_TOKEN} --ssh-command "${SSH_COMMAND}")
    HOST_STATUS=$(echo ${RESPONSE} | grep ${HOSTNAME_TO_FIND} | cut -d',' -f2)

    while [[ ${HOST_STATUS} != "Ready" ]] && [[ ${TIMER} < ${TIMEOUT} ]]; do
        printf "The ${HOSTNAME_TO_FIND} node isn\'t ready yet. Waiting 10 seconds...\n"
        sleep 10
        let TIMER=TIMER+10

        RESPONSE=$(doctl compute ssh ${MANAGER_ID} --access-token ${DO_ACCESS_TOKEN} --ssh-command "${SSH_COMMAND}")
        HOST_STATUS=$(echo ${RESPONSE} | grep ${HOSTNAME_TO_FIND} | cut -d',' -f2)
    done

    if [[ ${HOST_STATUS} == "Ready" ]]; then
        printf "The ${HOSTNAME_TO_FIND} node is READY!\n\n"
    else
        printf "The ${HOSTNAME_TO_FIND} node still isn\'t ready. Polling has timed out.\n\n"
    fi
fi
