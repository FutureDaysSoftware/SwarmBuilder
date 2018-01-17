#!/usr/bin/env bash

## Import config variables
source ./config.sh

USAGE="\nCreate & manage a Docker swarm on DigitalOcean droplets

Usage:
$(basename "$0") [command] [flags]

Available commands:
    create          Create a new swarm on fresh droplets.
    scale           Change the number of nodes in the swarm (and the number of droplets).
    destroy         Destroy the entire swarm and delete all its droplets.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

CREATE_USAGE="\nCreate a new swarm on fresh droplets.

Usage:
$(basename "$0") create <swarmName> [flags]

Where:
    swarmName       The name of the swarm to be created.
                     All droplets and swarm nodes will use this as their base name.

Flags:
    --workers       The integer number of worker nodes to create (Default 0) in addition to the single manager node.
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

SCALE_USAGE="\nChange the number of worker nodes in the swarm.

Usage:
$(basename "$0") scale <swarmName> --workers [flags]

Where:
    swarmName       The name of the swarm to be created.
                     All droplets and swarm nodes will use this as their base name.

Flags:
    --workers       The integer number of worker nodes that should exist.
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

DESTROY_USAGE="\nDestroy the entire swarm and delete all its droplets

Usage:
$(basename "$0") destroy <swarmName> [flags]

Where:
    swarmName       The name of the swarm to be destroyed.
                     All droplets in this swarm will be deleted.

Flags:
    -f, --force     Bypass interactive confirmation.  Droplets will be deleted immediately.
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

if [[ $# -eq 0 ]]; then
    printf "$USAGE"
    exit 0

fi

## Determine which subcommand was requested
## Note: options & flags have been 'shift'ed off the stack.
SUBCOMMAND="$1"; shift  # Remove the subcommand from the argument list


case "$SUBCOMMAND" in
    create)
        ## Set default options
        MANAGERS_TO_ADD=1
        WORKERS_TO_ADD=0

        ## Process flags and options
        SHORTOPTS="t:"
        LONGOPTS="token:,managers:,workers:"
        ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
        eval set -- ${ARGS}

        while true; do
            case ${1} in
                --managers)
                    shift
                    MANAGERS_TO_ADD="$1"
                    ;;
                --workers)
                    shift
                    WORKERS_TO_ADD="$1"
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

        if [[ $# -eq 0 ]]; then
            printf "$CREATE_USAGE"
            exit 0
        fi

        ## Read arguments
        SWARM_NAME="$1"; shift

        ## Create the swarm
        ./create-swarm.sh "$SWARM_NAME" --token "$DO_ACCESS_TOKEN" || exit 1
        printf "Waiting for swarm manager to come online..."
        sleep 30
        printf "done\n"
        if [[ ${WORKERS_TO_ADD} -gt 0 ]]; then
            ./add-worker.sh "$SWARM_NAME" --add "$WORKERS_TO_ADD" --token "$DO_ACCESS_TOKEN" || exit 1
        fi
        ;;

    scale)
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
            printf "$SCALE_USAGE"
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

        readarray -t ALL_WORKER_NODES <<< "$WORKER_NODES_STRING"
        WORKER_NODES_COUNT=${#ALL_WORKER_NODES[@]}
        WORKERS_TO_ADD=$((WORKERS_DESIRED - WORKER_NODES_COUNT))
        WORKERS_TO_REMOVE=$((WORKERS_TO_ADD * -1))

        if [[ ${WORKERS_DESIRED} -gt ${WORKER_NODES_COUNT} ]]; then
            printf "Adding ${WORKERS_TO_ADD} worker(s) to the ${SWARM_NAME} swarm\n"
            ./add-worker.sh "$SWARM_NAME" --add "$WORKERS_TO_ADD" --token "$DO_ACCESS_TOKEN" || exit 1
            exit 0
        elif [[ ${WORKERS_DESIRED} -lt ${WORKER_NODES_COUNT} ]]; then
            printf "Removing ${WORKERS_TO_REMOVE} worker(s) from the ${SWARM_NAME} swarm\n"
            ./remove-worker.sh "$SWARM_NAME" --remove "$WORKERS_TO_REMOVE" --token "$DO_ACCESS_TOKEN" || exit 1
            exit 0
        else
            printf "This swarm already has ${WORKERS_DESIRED} worker nodes.\n"
            exit 0
        fi
        ;;

    destroy)
        ## Set default options
        ## This command has no defaults
        FLAGS=""

        ## Process flags and options
        SHORTOPTS="t:f"
        LONGOPTS="token:,force"
        ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
        eval set -- ${ARGS}

        while true; do
            case ${1} in
                -f | --force )
                    shift
                    FLAGS=" --force"
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

        if [[ $# -eq 0 ]]; then
            printf "$DESTROY_USAGE"
            exit 0
        fi

        ## Read arguments
        SWARM_NAME="$1"; shift

        ## Destroy the swarm
        ./destroy-swarm.sh ${SWARM_NAME} --token ${DO_ACCESS_TOKEN}${FLAGS} || exit 1
        ;;
esac
