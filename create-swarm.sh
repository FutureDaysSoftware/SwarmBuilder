#!/usr/bin/env bash

DROPLET_CONFIG="\
  --region nyc3 \
  --image docker-16-04 \
  --size 512mb \
  --enable-private-networking \
"

USAGE="Usage:
$(basename "$0") exampleSwarmName DO_API_KEY -- Create a new swarm with a single manager node on DigitalOcean.

where:
    exampleSwarmName    The name of the swarm. All droplets will use this name with an incrementing number appended.
    DO_API_KEY          Your DigitalOcean API key.\n\n"

if [ $# -eq 0 ]
then
    printf "$USAGE"
    exit 0
fi


SWARM_NAME="$1"
DO_API_KEY="$2"
DROPLET_NAME="$SWARM_NAME-01"
SSH_FINGERPRINT=$(./ssh-fingerprint.sh)
DO_IP_DISCOVERY_URL="http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address"


## Check for existing droplets with this Swarm Name
EXISTING_DROPLETS=$(doctl compute droplet list --tag-name ${SWARM_NAME} --format Name --no-header --access-token ${DO_API_KEY})
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
doctl compute droplet create ${DROPLET_NAME} ${DROPLET_CONFIG} \
    --ssh-keys ${SSH_FINGERPRINT} \
    --tag-names "$SWARM_NAME,swarm,manager" \
    --access-token ${DO_API_KEY} \
    --user-data-file ./cloud-init/bootstrap.sh
