#!/usr/bin/env bash

## Import config variables
source ./config.sh

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
if [[ ! -d "cloud-init" ]]; then
	mkdir cloud-init
fi

INIT_SCRIPT="#!/bin/bash
ufw allow 2377/tcp
ufw allow 7946
ufw allow 4789
export PUBLIC_IPV4=\$(curl -s ${DO_IP_DISCOVERY_URL})
docker swarm init --advertise-addr \"\${PUBLIC_IPV4}:2377\""

echo "$INIT_SCRIPT" > cloud-init/bootstrap.sh
chmod a+x cloud-init/*.sh


## Create the new droplet
printf "\nCreating droplet \"${DROPLET_NAME}\" as a new swarm manager - this could take a minute...\n\n"
doctl compute droplet create ${DROPLET_NAME} \
    --wait \
    --image ${DO_DROPLET_IMAGE} \
    --region ${DO_DROPLET_REGION} \
    --size ${DO_DROPLET_SIZE} \
    --ssh-keys ${DO_DROPLET_SSH_KEYS} \
    --tag-names "swarm,$SWARM_NAME,$SWARM_NAME-manager" \
    --access-token ${DO_ACCESS_TOKEN} \
    --user-data-file ./cloud-init/bootstrap.sh \
    ${DO_DROPLET_FLAGS}

