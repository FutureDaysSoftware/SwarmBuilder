#!/usr/bin/env bash

## Import config variables
source ${BASH_SOURCE%/*}/config.sh
source ${BASH_SOURCE%/*}/helpers.sh

USAGE="\nRemove a service stack from the swarm

Usage:
$(basename "$0") <exampleSwarmName> --stack-name [STACKNAME] [OPTIONS]

where:
    exampleSwarmName            The name of an existing swarm.

    -n, --stack-name string     The name of the stack to be removed.

Available Options:
    -f, --force                 Bypass interactive confirmation. The stack will be removed immediately.
    -t, --token                 Your DigitalOcean API key (optional).
                                 If omitted here, it must be provided in \'config.sh\'\n\n"

## Set default options
BYPASS_CONFIRMATION=false

## Process flags and options
SHORTOPTS="fn:t:"
LONGOPTS="force,stack-name:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-f | --force)
            shift
            BYPASS_CONFIRMATION=true
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

if [[ $# -eq 0 ]] || [[ -z ${STACK_NAME} ]]; then
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
if [[ ${BYPASS_CONFIRMATION} != true ]]; then
    confirm || exit 0
fi

## Connect to the manager and remove the stack, then output a summary of stacks remaining in the swarm
${BASH_SOURCE%/*}/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "docker stack rm ${STACK_NAME} && docker stack ls"
