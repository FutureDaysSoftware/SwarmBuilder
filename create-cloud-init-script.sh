#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")"

## Import config variables
source ${DIR}/config.sh

USAGE="\nWrite a script that can be run by a droplet at boot-time to join an existing swarm.

Usage:
$(basename "$0") <JOIN-TOKEN> <SWARM-MANAGER-IP>

If both JOIN-TOKEN and SWARM-MANAGER-IP are provided, a swarm-join script will be generated.
The join-script can be run on a remote host to join an existing swarm.

If no arguments are provided, a swarm-init script will be generated.
The init-script can be run on a remote host to create a new swarm.\n\n"


## Set Defaults
FOLDER="${DIR}/cloud-init"
FILENAME="bootstrap.sh"
FILEPATH="${FOLDER}/${FILENAME}"


if [[ $# -eq 2 ]]; then
    # Create a swarm-join script

    ## Grab command-line parameters
    JOIN_TOKEN="$1"
    MANAGER_IP="$2"

    ## Write the cloud-init script
    SCRIPT_OUTPUT="#!/bin/bash
    ufw allow 2377/tcp
    ufw allow 7946
    ufw allow 4789
    export PUBLIC_IPV4=\$(curl -s ${DO_IP_DISCOVERY_URL})
    docker swarm join --advertise-addr \"\${PUBLIC_IPV4}:2377\" --token \"$JOIN_TOKEN\" \"$MANAGER_IP:2377\""

elif [[ $# -eq 0 ]]; then
    # Create a swarm-init script

    SCRIPT_OUTPUT="#!/bin/bash
    ufw allow 2377/tcp
    ufw allow 7946
    ufw allow 4789
    export PUBLIC_IPV4=\$(curl -s ${DO_IP_DISCOVERY_URL})
    docker swarm init --advertise-addr \"\${PUBLIC_IPV4}:2377\""

else
    printf "$USAGE"
    exit 1
fi


if [ ! -d ${FOLDER} ]; then
	mkdir ${FOLDER}
fi

echo "$SCRIPT_OUTPUT" > ${FILEPATH}
chmod a+x ${FILEPATH}

# Output the filename for use by the calling script
printf "${FILEPATH}"