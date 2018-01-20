#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nPoll a swarm manager until the specified node(s) becomes available.  If multiple hostnames are specified,
the polling will continue until ALL of the nodes are ready.  The polling loop runs on the remote manager node to prevent
SSH rate-limiting.

Usage:
$(basename "$0") <exampleSwarmName> --hostname [HOSTNAME] [--hostname ...] [OPTIONS]

Where:
    exampleSwarmName    The name of the existing swarm.
    -h, --hostname      Required.  The name of the node to look for. Multiple nodes can be passed in by providing
                         this flag multiple times, i.e. --hostname myHost-01 --hostname myHost-03

Available Options:
        --timeout       The number of seconds to continue polling before giving up. Default 90.
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'

Example:

    $(basename "$0") mySwarm --hostname mySwarm-02 --timeout 30 \n\n"

## Set default options
TIMEOUT=90
HOSTNAMES_TO_FIND=""

## Process flags and options
SHORTOPTS="h:t:"
LONGOPTS="hostname:,timeout:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
	    -h | --hostname)
            shift
		    HOSTNAMES_TO_FIND="$1 $HOSTNAMES_TO_FIND"
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

## Find a manager node in the swarm and get the IP
MANAGER_IP=$(${DIR}/helpers/get-manager-info.sh ${SWARM_NAME} --format PublicIPv4 --token ${DO_ACCESS_TOKEN}) || exit 1

## The following 3 commands will all be run on the remote docker manager:
## getStatus() will return the status of a single docker node (i.e. "Ready")
FUNCTION_GETSTATUS="function getStatus() { docker node ls --format \"{{.Hostname}},{{.Status}}\" | grep \"\$1\" | cut -d',' -f2; }"

## allReady() accepts a list of hostnames and returns the word "Ready" if ALL hostnames have a status of "Ready"
FUNCTION_ALL_READY="function allReady() { STATUS=\"Ready\"; for NODE in \$(echo \"\$1\" | cut -d' ' -f1-); do if [[ \$(getStatus \"\$NODE\") != \"Ready\" ]]; then STATUS=\"Pending\"; fi; done; printf \$STATUS; }"

## This polling loop calls the allReady() function every 5 seconds until it returns "Ready" or the timeout is reached.
SSH_LOOP="export TIMER=0; while [[ \$(allReady \"$HOSTNAMES_TO_FIND\") != Ready ]] && [[ \${TIMER} < ${TIMEOUT} ]]; do let TIMER=TIMER+5 && sleep 5; done && if [[ \$(allReady \"$HOSTNAMES_TO_FIND\") == \"Ready\" ]]; then echo \"Ready\"; else echo \"Timeout\"; fi"

HOST_STATUS=""
START_TIME=$SECONDS

# Use a loop to retry the SSH connection if it fails.
# Common failures occur if the droplet isn't fully booted or SSH connections are throttled from too many attempts.

while [[ "$HOST_STATUS" != "Ready" ]] && [[ $(( SECONDS - START_TIME )) -lt ${TIMEOUT} ]]; do
    HOST_STATUS=$(${DIR}/helpers/ssh-to-manager.sh --ip ${MANAGER_IP} -c "${FUNCTION_GETSTATUS}; ${FUNCTION_ALL_READY}; ${SSH_LOOP} 2>/dev/null;") 2>/dev/null
    if [[ $? -ne 0 ]]; then sleep 30; fi  ## Attempt to wait out an SSH rate-limit failure before retrying
done

if [[ ${HOST_STATUS} == "Ready" ]]; then
    printf "Nodes ${HOSTNAMES_TO_FIND} are all READY!\n\n"
    exit 0
else
    printf "Some nodes still aren\'t ready. Polling has timed out.\n\n" 1>&2
    exit 1
fi
