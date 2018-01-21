#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")"

## Import config variables
if [ ! -f "${DIR}/config/config.sh" ]; then
    printf "Config file not found - creating \'config.sh\' from the template.
    You should customize the contents of \'${DIR}/config/config.sh\' before using this script.\n"
    $(cp ${DIR}/config/config.example.sh ${DIR}/config/config.sh && chmod a+x ${DIR}/config/config.sh) || printf "\nUnable to create config file.\n" 1>&2 && exit 1
fi
source ${DIR}/config/config.sh

USAGE="\nCreate & manage a Docker swarm on DigitalOcean droplets

Usage:
$(basename "$0") [command] [flags]

Available commands:
    create          Create a new swarm on fresh droplets.
    scale-swarm     Change the number of nodes in the swarm (and the number of droplets).
    scale-stack     Change the number of replicas of a service stack running in the swarm.
    remove-stack    Completely remove a stack from the swarm.
    deploy          Deploy a new service stack or update an existing stack in the swarm.
    destroy         Destroy the entire swarm and delete all its droplets.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

if [[ $# -eq 0 ]]; then
    printf "$USAGE"
    exit 0
fi


## Determine which subcommand was requested
## Note: options & flags have been 'shift'ed off the stack.
SUBCOMMAND="$1"; shift  # Remove the subcommand from the argument list
FILEPATH=${DIR}/commands/${SUBCOMMAND}.sh

## Look for a script in the 'commands/' folder that matches the name of the given subcommand
if [[ ! -f ${FILEPATH} ]]; then
    printf "Unknown subcommand issued to swarmbuilder\n" 1>&2
    printf "$USAGE"
    exit 1
fi

## Execute the command script and forward the remaining arguments (the subcommand has been 'shift'ed off already)
eval "${FILEPATH} $@"
