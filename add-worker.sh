#!/usr/bin/env bash

## Import config variables
source ./config.sh

USAGE="\nAdd worker nodes to an existing swarm.

Usage:
$(basename "$0") <exampleSwarmName> [--token] [-n 1]

where:
    exampleSwarmName    The name of the existing swarm.
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'
    -n, --add           The number of worker nodes to create (Default 1).\n\n"

## Set default options
WORKERS_TO_ADD=1

## Process flags and options
SHORTOPTS="n:t:"
LONGOPTS="add:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-n | --add)
            shift
		    WORKERS_TO_ADD="$1"
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


## Find a manager node for the requested swarm
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

	JOIN_TOKEN=$(doctl compute ssh ${MANAGER_ID} --access-token ${DO_ACCESS_TOKEN} --ssh-command "docker swarm join-token -q worker")
	if [ -z "$JOIN_TOKEN" ]; then
		printf "Couldn't get swarm token from manager node \"${MANAGER_NAME}\"\n\n" 1>&2
		exit 1
	fi
fi


## Find the next sequential node number to start naming the new worker droplets
## Method:
#   -Get a list of all droplets in the requested swarm
#   -Sort alphanumerically
#   -Take the LAST item
#   -Split the droplet's name on the '-' character and return the substring on the right
LAST_INDEX_IN_SWARM=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME} \
    --format Name \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | sort | tail -n1 | cut -d'-' -f 2)

NEXT_INDEX_IN_SWARM=$((${LAST_INDEX_IN_SWARM} + 1))


## Write the cloud-init script for the new worker node(s)
SCRIPT_JOIN="#!/bin/bash
ufw allow 2377/tcp
ufw allow 7946
ufw allow 4789
export PUBLIC_IPV4=\$(curl -s ${DO_IP_DISCOVERY_URL})
docker swarm join --advertise-addr \"\${PUBLIC_IPV4}:2377\" --token \"$JOIN_TOKEN\" \"$MANAGER_IP:2377\""

if [ ! -d "cloud-init" ]; then
	mkdir cloud-init
fi
echo "$SCRIPT_JOIN" > cloud-init/bootstrap.sh
chmod a+x cloud-init/bootstrap.sh

## Create the new worker node(s)
DROPLET_NAMES=""
for ((i=NEXT_INDEX_IN_SWARM; i<=((${LAST_INDEX_IN_SWARM} + ${WORKERS_TO_ADD})); i++))
do
    if [[ "$i" -lt 10 ]]; then
        DROPLET_NAMES="${DROPLET_NAMES} ${SWARM_NAME}-0${i}"  # Add 0-padding for single-digit numbers
    else
        DROPLET_NAMES="${DROPLET_NAMES} ${SWARM_NAME}-${i}"
    fi
done

printf "Creating worker droplet(s): \"${DROPLET_NAMES}\" ...\n"

doctl compute droplet create ${DROPLET_NAMES} \
--image ${DO_DROPLET_IMAGE} \
--region ${DO_DROPLET_REGION} \
--size ${DO_DROPLET_SIZE} \
--ssh-keys ${DO_DROPLET_SSH_KEYS} \
--tag-names "swarm,$SWARM_NAME,$SWARM_NAME-worker" \
--access-token ${DO_ACCESS_TOKEN} \
--user-data-file ./cloud-init/bootstrap.sh \
${DO_DROPLET_FLAGS}

if [[ $? -ne 0 ]]; then
    printf "\nError while creating worker nodes. Exiting.\n\n" 1>&2
    exit 1
fi

printf "\nDone!\n\n"
exit 0
