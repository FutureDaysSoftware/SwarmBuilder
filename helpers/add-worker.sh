#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nAdd worker nodes to an existing swarm.

Usage:
$(basename "$0") <exampleSwarmName> [--token] [-n 1]

where:
    exampleSwarmName    The name of the existing swarm.
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'
    -n, --add           The number of worker nodes to create (Default 1).
        --wait          Wait for the droplets to finish booting and join the swarm before returning.\n\n"

## Set default options
WORKERS_TO_ADD=1
POLL_NEW_NODES_UNTIL_READY=false

## Process flags and options
SHORTOPTS="n:t:"
LONGOPTS="add:,token:,wait"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-n | --add)
            shift
		    WORKERS_TO_ADD="$1"
		    shift
		    ;;
		--wait)
		    shift
		    DO_DROPLET_FLAGS="$DO_DROPLET_FLAGS --wait"
		    POLL_NEW_NODES_UNTIL_READY=true
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
elif [[ ${WORKERS_TO_ADD} -eq 0 ]]; then
    printf "No worker nodes will be added\n"
    exit 0;
fi

## Grab command-line parameters
## Note: options & flags have been 'shift'ed off the stack.
SWARM_NAME="$1"


## Get the join-token for the swarm
JOIN_TOKEN=$(${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "docker swarm join-token -q worker")
if [[ "$?" != 0 ]] || [[ -z "${JOIN_TOKEN}" ]]; then
    printf "Couldn't get the swarm join-token from manager node. Unable to add workers to the swarm.\n\n" 1>&2
    exit 1
fi

## Get the IP address of the manager node (needed for the `swarm join` command)
MANAGER_IP=$(${DIR}/helpers/get-manager-info.sh ${SWARM_NAME} --format PublicIPv4 --token ${DO_ACCESS_TOKEN}) || exit 1

## Find the next sequential node number to start naming the new worker droplets
## Method:
#   -Get a list of all droplets in the requested swarm
#   -Sort alphanumerically ( |sort )
#   -Take the LAST item ( |tail -n1 )
#   -Split the droplet's name on the '-' character and return the substring on the right ( |cut -d'-' -f2- )
LAST_INDEX_IN_SWARM=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME} \
    --format Name \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | sort | tail -n1 | cut -d'-' -f2-)

NEXT_INDEX_IN_SWARM=$((${LAST_INDEX_IN_SWARM} + 1))


## Write the cloud-init script for the new worker node(s)
JOIN_SCRIPT_FILENAME=$(${DIR}/helpers/create-cloud-init-script.sh ${JOIN_TOKEN} ${MANAGER_IP})

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
--format ${DO_DROPLET_INFO_FORMAT} \
--access-token ${DO_ACCESS_TOKEN} \
--user-data-file ${JOIN_SCRIPT_FILENAME} \
${DO_DROPLET_FLAGS}

if [[ $? -ne 0 ]]; then
    printf "\nError while creating worker droplets. Exiting.\n\n" 1>&2
    exit 1
fi

if [[ ${POLL_NEW_NODES_UNTIL_READY} ]]; then
    printf "Waiting for new workers to join the swarm...\n"

    POLLING_COMMAND="${DIR}/helpers/poll-for-active-node.sh ${SWARM_NAME}"

    ## Send the hostname to the polling script of every new worker node that was just created
    for NODE in $(echo "$DROPLET_NAMES" | cut -d' ' -f1-); do
        POLLING_COMMAND="$POLLING_COMMAND --hostname ${NODE}"
    done

    ## Poll the swarm manager until ALL new workers have joined the swarm
    eval ${POLLING_COMMAND}
fi

printf "\nDone!\n\n"
exit 0
