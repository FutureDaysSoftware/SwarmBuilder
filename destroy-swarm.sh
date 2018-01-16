#!/usr/bin/env bash

## Import config variables
source ./config.sh

USAGE="\nDestroy ALL nodes in the specified Swarm

Usage:
$(basename "$0") <exampleSwarmName> [DO_ACCESS_TOKEN] [-yf]

where:
    exampleSwarmName    The name of the swarm to be destroyed.
    DO_ACCESS_TOKEN     Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'
    -f, --force         Bypass the interactive confirmation.\n\n"

## Set default options
BYPASS_CONFIRMATION=false

## Process flags and options
SHORTOPTS="f"
LONGOPTS="force"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-f | --force)
            shift
            BYPASS_CONFIRMATION=true
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

## Use the appropriate DO_ACCESS_TOKEN.  The order of precedence is:
##   1. Use the token given on the command line, if present.
##   2. Use the token provided in `config.sh`, if present.
##   3. Throw an error.

if [[ $# -eq 0 ]]; then
    printf "$USAGE"
    exit 0
elif [[ $# -eq 2 ]]; then
    DO_ACCESS_TOKEN="$2"
elif [[ -z ${DO_ACCESS_TOKEN} ]]; then
    printf "A DigitalOcean access token was not provided.
    You must provide one on the command line when using this command, or set one in the \'config.sh\' file.\n\n"
    exit 1
fi


## Grab command-line parameters
## Note: options & flags have been 'shift'ed off the stack.
SWARM_NAME="$1"

## Get a list of all droplets in the specified swarm
DROPLET_IDS_IN_SWARM=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME} \
    --format ID\
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} )

if [[ -z ${DROPLET_IDS_IN_SWARM} ]]; then
    printf "\nNo swarm was found with the name \"${SWARM_NAME}\". No changes have been made.\n\n"
    exit 0
fi


# Pass through the --force parameter to the doctl 'delete' command
DO_COMMAND_FLAGS=""
if [[ "$BYPASS_CONFIRMATION" = true ]]; then
    DO_COMMAND_FLAGS=" --force"
fi

## Delete the droplets
doctl compute droplet delete ${DROPLET_IDS_IN_SWARM} --access-token ${DO_ACCESS_TOKEN}${DO_COMMAND_FLAGS}

