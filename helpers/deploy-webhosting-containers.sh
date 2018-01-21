#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(dirname "$(readlink -f "$0")")")"

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nDeploy nginx-proxy to the specified host

Usage:
$(basename "$0") --swarm <swarmName> [--token]

where:
    -s, --swarm         The name of the swarm to target.
                         Nginx will be deployed to the master node in this swarm (swarmName-01).
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'\n\n"

## Set defaults
COMPOSE_FILE="${DIR}/containers/traefik-compose.yml"
CONFIG_FILE="${DIR}/containers/traefik.toml"
STACK_NAME="traefik"
OVERLAY_NETWORK_NAME="http-proxy"


## Process flags and options
SHORTOPTS="s:t:"
LONGOPTS="swarm:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-s | --swarm)
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

if [[ -z "$SWARM_NAME" ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z ${DO_ACCESS_TOKEN} ]]; then
    printf "A DigitalOcean access token was not provided.
    You must provide one on the command line when using this command, or set one in the \'config.sh\' file.\n\n"
    exit 1
fi

## Construct the commands that will run on the remote host.
##  1.  We need to create the 'attachable' overlay network that all the web apps on the swarm
##      will use to communicate with the reverse-proxy.
##  2.  Send the Traefik config (.toml) file and create 'acme.json' for storing LetsEncrypt keys.
##  3.  Write the ACME_DO_ACCESS_TOKEN to an env file on the remote host. It will be used in 'traefik-compose.yml'
##      and is necessary for LetsEncrypt to perform DNS verification while issuing SSL certificates.
##  4.  Deploy the reverse-proxy application stack (traefik)
SSH_COMMAND="docker network create --driver=overlay --attachable ${OVERLAY_NETWORK_NAME}; \
touch acme.json \
&& chmod 600 acme.json \
&& echo \"DO_AUTH_TOKEN=${ACME_DO_ACCESS_TOKEN}\" > .env;"

printf "Creating \'${OVERLAY_NETWORK_NAME}\' overlay network...
Creating \'acme.json\' to store SSL certificates...
Storing DigitalOcean Auth Token in a Docker .env (for LetsEncrypt to perform DNS verification)...\n"
${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --master --ssh-command "${SSH_COMMAND}"

printf "\nSending traefik config file \'${CONFIG_FILE}\'...\n"
cat ${CONFIG_FILE} | ${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --master --ssh-command "cat > $(basename ${CONFIG_FILE})"

printf "\nSending docker compose file for the http proxy stack...\n"
cat ${COMPOSE_FILE} | ${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --master --ssh-command "docker stack deploy --compose-file - ${STACK_NAME} && sleep 2 && docker ps"

