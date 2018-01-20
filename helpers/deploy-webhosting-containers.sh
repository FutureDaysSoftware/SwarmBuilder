#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

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
COMPOSE_FILE="${DIR}/containers/nginx-compose.yml"
STACK_NAME="nginx"


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

## Assume the name of the master swarm node - by convention, it's "SWARM_NAME-01"
MANAGER_NAME="${SWARM_NAME}-01"

## Construct the command that will run on the remote host.
##  We need to create the 'attachable' overlay network "nginx-proxy" that all the web apps on the swarm
##  will use to communicate with nginx-proxy.
##  Then deploy the "nginx" stack.
CREATE_NETWORK_COMMAND="docker network create --driver=overlay --attachable nginx-proxy"
DEPLOY_STACK_COMMAND="docker stack deploy --compose-file - ${STACK_NAME} && docker ps"
COMPOSE_UP_COMMAND="docker-compose -f - up && docker ps"

${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "${CREATE_NETWORK_COMMAND}"
cat "${COMPOSE_FILE}" | ${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "${DEPLOY_STACK_COMMAND}"
