#!/usr/bin/env bash

## Import config variables
source ./config.sh

USAGE="\nScale a service within the swarm

Usage:
$(basename "$0") <exampleSwarmName> --service <serviceName> --replicas <#> [--token]

where:
    exampleSwarmName    The name of an existing swarm.

        --service       The name of the service to be scaled.
        --replicas      The desired number of replicas of the service.
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'\n\n"

## Set default options
## This command has no defaults

## Process flags and options
SHORTOPTS="t:"
LONGOPTS="service:,replicas:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		--service)
            shift
		    SERVICE_NAME="$1"
		    shift
		    ;;
		--replicas)
		    shift
		    REPLICAS_DESIRED_QTY="$1"
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


## Find a manager node for the requested swarm
MANAGER_NODE_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME}-manager \
    --format Name,ID,PublicIPv4 \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | head -n1)

## Connect to the manager and scale the service
if [ -z "$MANAGER_NODE_STRING" ]; then
    printf "No manager node found for the \"${SWARM_NAME}\" swarm. Does the swarm exist yet?\n\n" 1>&2
    exit 1
else

    MANAGER_NODE_ARRAY=(${MANAGER_NODE_STRING})
    MANAGER_NAME=${MANAGER_NODE_ARRAY[0]}
    MANAGER_ID=${MANAGER_NODE_ARRAY[1]}
    MANAGER_IP=${MANAGER_NODE_ARRAY[2]}

	yes | doctl compute ssh ${MANAGER_ID} \
	--access-token ${DO_ACCESS_TOKEN} \
	--ssh-command "docker service scale ${SERVICE_NAME}=${REPLICAS_DESIRED_QTY}"
fi