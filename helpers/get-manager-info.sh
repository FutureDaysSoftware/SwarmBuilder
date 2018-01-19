#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
#source ${DIR}/config/config.sh  # Config is NOT imported

USAGE="\nFind a manager node for a swarm and return info about it. If there is more than 1 manager node in the swarm,
info will be reported for the one with the name that occurs first alphabetically.

Usage:
$(basename "$0") <exampleSwarmName> --token [OPTIONS]

where:
    exampleSwarmName        The name of an existing swarm.
    -t, --token             Your DigitalOcean API key (required).

Available Options:
    -f, --format string     Columns for output in a comma separated list.
                            Possible values: ID,Name,PublicIPv4,PrivateIPv4,
                            PublicIPv6,Memory,VCPUs,Disk,Region,Image,
                            Status,Tags,Features,Volumes
                            (Default: Name,ID,PublicIPv4)

Output:
The return string will be a list of all requested properties on a single line,
separated by the field-break character in the order requested.

These can be captured by calling this script like this, for example:
MANAGER_INFO=(\$($(basename "$0") mySwarm --format Name,ID))
MANAGER_NAME=\${MANAGER_INFO[0]}
MANAGER_ID=\${MANAGER_INFO[1]}
\n\n"

## Set default options
FORMAT="Name,ID,PublicIPv4"

## Process flags and options
SHORTOPTS="t:,f:"
LONGOPTS="format:,token:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
	    -f | --format)
	        shift
	        FORMAT="$1"
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

if [[ $# -eq 0 ]]; then
    printf "$USAGE"
    exit 0
elif [[ -z ${DO_ACCESS_TOKEN} ]]; then
    printf "A DigitalOcean access token was not provided.
    You must provide one on the command line when using this command.\n\n"
    exit 1
fi

## Grab command-line parameters
## Note: options & flags have been 'shift'ed off the stack.
SWARM_NAME="$1"


## Find a manager node for the requested swarm
MANAGER_NODE_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME}-manager \
    --format ${FORMAT} \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | head -n1)

## Connect to the manager and scale the service
if [ -z "$MANAGER_NODE_STRING" ]; then
    printf "No manager node found for the \"${SWARM_NAME}\" swarm. Does the swarm exist yet?\n\n" 1>&2
    exit 1
else
    printf "$MANAGER_NODE_STRING\n"
    exit 0
fi

