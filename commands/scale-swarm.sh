#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nChange the number of worker nodes in the swarm.

Usage:
$(basename "$0") scale-swarm <swarmName> --workers <#> [flags]

Where:
    <swarmName>     The name of the swarm to be scaled.
                     All droplets and swarm nodes will use this as their base name.
    --workers       The integer number of worker nodes that should exist.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"


## Set default options
## This command has no defaults

## Process flags and options
SHORTOPTS="t:"
LONGOPTS="token:,workers:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
    case ${1} in
        --workers)
            shift
            WORKERS_DESIRED="$1"
            ;;
        -t | --token )
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

if [[ $# -eq 0 ]] || [[ -z "$WORKERS_DESIRED" ]]; then
    printf "$USAGE"
    exit 0
fi

## Read arguments
SWARM_NAME="$1"; shift

## Count the current number of worker nodes in the swarm
WORKER_NODES_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME}-worker \
    --format Name \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} )

if [[ -n "$WORKER_NODES_STRING" ]]; then
    readarray -t ALL_WORKER_NODES <<< "$WORKER_NODES_STRING"
    WORKER_NODES_COUNT=${#ALL_WORKER_NODES[@]}
else
    WORKER_NODES_COUNT=0
fi
WORKERS_TO_ADD=$((WORKERS_DESIRED - WORKER_NODES_COUNT))
WORKERS_TO_REMOVE=$((WORKERS_TO_ADD * -1))

if [[ ${WORKERS_DESIRED} -gt ${WORKER_NODES_COUNT} ]]; then
    printf "Adding ${WORKERS_TO_ADD} worker(s) to the ${SWARM_NAME} swarm\n"
    ${DIR}/helpers/add-worker.sh "$SWARM_NAME" --add "$WORKERS_TO_ADD" --token "$DO_ACCESS_TOKEN" || exit 1
    exit 0
elif [[ ${WORKERS_DESIRED} -lt ${WORKER_NODES_COUNT} ]]; then
    printf "Removing ${WORKERS_TO_REMOVE} worker(s) from the ${SWARM_NAME} swarm\n"
    ${DIR}/helpers/remove-worker.sh "$SWARM_NAME" --remove "$WORKERS_TO_REMOVE" --token "$DO_ACCESS_TOKEN" || exit 1
    exit 0
elif [[ ${WORKERS_DESIRED} -eq ${WORKER_NODES_COUNT} ]]; then
    printf "This swarm already has ${WORKERS_DESIRED} worker nodes.\n"
    exit 0
else
    printf "Couldn\'t determine whether to add or remove worker nodes.\n" 1>&2
    exit 1
fi