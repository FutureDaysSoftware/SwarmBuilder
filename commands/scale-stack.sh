#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nChange the number of replicas of the \'_web\' service in a stack.

Usage:
$(basename "$0") scale-stack <swarmName> --stack-name <stackName> --replicas <#> [flags]

Where:
    <swarmName>     The name of the swarm that is hosting the stack to be scaled.
    --stack-name    The name of the service stack to be scaled. Only the service named \'stack-name_web\' will be scaled.
    --replicas      The integer number of replicas of the web service that should exist on the swarm.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"


## Set default options
## This command has no defaults

## Process flags and options
SHORTOPTS="t:n:"
LONGOPTS="token:,stack-name:,replicas:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
    case ${1} in
        -n | --stack-name)
            shift
            STACK_NAME="$1"
            ;;
        --replicas)
            shift
            REPLICAS_DESIRED_QTY="$1"
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

## Enforce required arguments
if [[ $# -eq 0 ]] || [[ -z "$STACK_NAME" ]] || [[ -z "$REPLICAS_DESIRED_QTY" ]]; then
    printf "$USAGE"
    exit 0
fi

## Read arguments
SWARM_NAME="$1"; shift
SERVICE_NAME="${STACK_NAME}_web"  # Assume that the service to be scaled is named 'web' within the requested stack

## Determine whether we need to add new worker nodes

## Count the current number of nodes in the swarm (workers AND managers, since both can accept tasks)
ALL_NODES_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME} \
    --format Name \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} )

readarray -t ALL_NODES <<< "$ALL_NODES_STRING"
ALL_NODES_QTY=${#ALL_NODES[@]}
WORKERS_TO_ADD=$((REPLICAS_DESIRED_QTY - ALL_NODES_QTY))

printf "The ${SWARM_NAME} swarm currently has ${ALL_NODES_QTY} nodes (including managers)... "

if [[ ${WORKERS_TO_ADD} -gt 0 ]]; then
    printf "Adding ${WORKERS_TO_ADD} worker(s) to the ${SWARM_NAME} swarm...\n"
    ${DIR}/helpers/add-worker.sh "$SWARM_NAME" --add "$WORKERS_TO_ADD" --wait --token "$DO_ACCESS_TOKEN" || exit 1
else
    printf "No new droplets are needed to achieve ${REPLICAS_DESIRED_QTY} replicas.\n"
fi

## Scale the '_web' service for the specified stack
${DIR}/helpers/scale-service.sh ${SWARM_NAME} --service ${SERVICE_NAME} --replicas ${REPLICAS_DESIRED_QTY} --token ${DO_ACCESS_TOKEN} >/dev/null

## Output a summary of the services in the stack
${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "docker stack ps ${STACK_NAME}"

## TODO: Check for idle nodes and prune unused droplets. Use `docker node ps mySwarm-01 mySwarm-02 mySwarm...`