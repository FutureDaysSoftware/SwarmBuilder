#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")"

## Import config variables
source ${DIR}/config.sh

USAGE="\nDeploy a service stack to the swarm

Usage:
$(basename "$0") <exampleSwarmName> --compose-file [PATH] --stack-name [STACKNAME] [--token]

where:
    exampleSwarmName            The name of an existing swarm.

    -c, --compose-file string   The path to a \'docker-compose.yml\' file that describes the stack to be deployed.
    -n, --stack-name string     The name to give to this stack in the swarm.
    -t, --token                 Your DigitalOcean API key (optional).
                                 If omitted here, it must be provided in \'config.sh\'\n\n"

## Set default options
## This command has no defaults

## Process flags and options
SHORTOPTS="f:n:t:"
LONGOPTS="compose-file:,stack-name:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-c | --compose-file)
            shift
		    COMPOSE_FILE="$1"
		    if [ ! -f "$COMPOSE_FILE" ]; then
                printf "\nThe file \'${COMPOSE_FILE}\' could not be found. You must provide a valid \'docker-compose.yml\' file." 1>&2; exit 1
            fi
		    shift
		    ;;
		-n | --stack-name)
		    shift
		    STACK_NAME="$1"
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

if [[ $# -eq 0 ]] || [[ -z ${STACK_NAME} ]] || [[ -z ${COMPOSE_FILE} ]]; then
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

## Connect to the manager and deploy the stack. Pipe the 'docker-compose.yml' file into 'docker stack deploy' through STDIN
cat "${COMPOSE_FILE}" | ${DIR}/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "docker stack deploy --compose-file - ${STACK_NAME} && docker stack ps ${STACK_NAME}"
