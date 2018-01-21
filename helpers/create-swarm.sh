#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="Create a new swarm with a single manager node on DigitalOcean.

Usage:
$(basename "$0") <exampleSwarmName> [--token]

where:
    exampleSwarmName    The name of the swarm. All droplets will use this name with an incrementing number appended.
    -t, --token         Your DigitalOcean API key (optional). If omitted here, it must be provided in \'config.sh\'\n\n"

## Process flags and options
SHORTOPTS="t:"
LONGOPTS="token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
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
SWARM_NAME="$1"
DROPLET_NAME="$SWARM_NAME-01"


## Check for existing droplets with this Swarm Name
EXISTING_DROPLETS=$(doctl compute droplet list --tag-name ${SWARM_NAME} --format Name --no-header --access-token ${DO_ACCESS_TOKEN})
if [[ -n ${EXISTING_DROPLETS} ]]; then
    printf "\nAn existing swarm is already using the name \"${SWARM_NAME}\". The member droplets are:
${EXISTING_DROPLETS}\n\n" >&2
    exit 1
fi


## Create a script that will run on the new droplet as soon as it's booted up
INIT_SCRIPT_FILENAME=$(${DIR}/helpers/create-cloud-init-script.sh)


## Create the new droplet
printf "\nCreating droplet \"${DROPLET_NAME}\" as a new swarm manager - this could take a minute...\n\n"
doctl compute droplet create ${DROPLET_NAME} \
    --wait \
    --image ${DO_DROPLET_IMAGE} \
    --region ${DO_DROPLET_REGION} \
    --size ${DO_DROPLET_SIZE} \
    --ssh-keys ${DO_DROPLET_SSH_KEYS} \
    --tag-names "swarm,$SWARM_NAME,$SWARM_NAME-manager" \
    --format ${DO_DROPLET_INFO_FORMAT} \
    --access-token ${DO_ACCESS_TOKEN} \
    --user-data-file ${INIT_SCRIPT_FILENAME} \
    ${DO_DROPLET_FLAGS}

## Assign a floating IP to the new manager node, if provided in config.sh
if [[ -n ${FLOATING_IP} ]]; then
    printf "Assigning floating IP ${FLOATING_IP} to swarm master \'${DROPLET_NAME}\'"
    MASTER_NODE_ID=$(${DIR}/helpers/get-manager-info.sh ${SWARM_NAME} --format ID --token ${DO_ACCESS_TOKEN})
    doctl compute floating-ip-action assign ${FLOATING_IP} ${MASTER_NODE_ID} -t ${DO_ACCESS_TOKEN}
fi
