#!/usr/bin/env bash

## Import config variables
if [ ! -f "./config.sh" ]; then
    printf "Config file not found - creating \'config.sh\' from the template.
    You should customize the contents of \'config.sh\' before using this script.\n"
    $(cp ./config.example.sh ./config.sh && chmod a+x ./config.sh) || printf "\nUnable to create config file.\n" 1>&2 && exit 1
fi
source ./config.sh

USAGE="\nCreate & manage a Docker swarm on DigitalOcean droplets

Usage:
$(basename "$0") [command] [flags]

Available commands:
    create          Create a new swarm on fresh droplets.
    scale-swarm     Change the number of nodes in the swarm (and the number of droplets).
    scale-stack     Change the number of replicas of a service stack running in the swarm.
    destroy         Destroy the entire swarm and delete all its droplets.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

CREATE_USAGE="\nCreate a new swarm on fresh droplets.

Usage:
$(basename "$0") create <swarmName> [flags]

Where:
    <swarmName>     The name of the swarm to be created.
                     All droplets and swarm nodes will use this as their base name.

Flags:
    --managers      The integer number of manager nodes to create.  Default 1.
    --workers       The integer number of worker nodes to create (Default 0) in addition to the single manager node.
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

SCALE_SWARM_USAGE="\nChange the number of worker nodes in the swarm.

Usage:
$(basename "$0") scale-swarm <swarmName> --workers <#> [flags]

Where:
    <swarmName>     The name of the swarm to be scaled.
                     All droplets and swarm nodes will use this as their base name.
    --workers       The integer number of worker nodes that should exist.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

SCALE_STACK_USAGE="\nChange the number of replicas of the \'-web\' service in a stack.

Usage:
$(basename "$0") scale-stack <swarmName> --stack <stackName> --replicas <#> [flags]

Where:
    <swarmName>     The name of the swarm that is hosting the stack to be scaled.
    --stack         The name of the service stack to be scaled. Only the service named \'stackName-web\' will be scaled.
    --replicas      The integer number of replicas of the web service that should exist on the swarm.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

DESTROY_USAGE="\nDestroy the entire swarm and delete all its droplets

Usage:
$(basename "$0") destroy <swarmName> [flags]

Where:
    <swarmName>     The name of the swarm to be destroyed.
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
        MANAGERS_TO_ADD=0
        WORKERS_TO_ADD=0
        FLAGS=""

        ## Process flags and options
        SHORTOPTS="t:"
        LONGOPTS="token:,managers:,workers:"
        ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
        eval set -- ${ARGS}

        while true; do
            case ${1} in
                --managers)
                    shift
                    MANAGERS_TO_ADD=$(($1 - 1))
                    if [[ ${MANAGERS_TO_ADD} -gt 0 ]]; then
                        FLAGS=" --wait"
                    fi
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

        function WAIT_FOR_MANAGER () {
            MANAGER_NAME=${1}
            RESPONSE="This node is not a swarm manager"
            TIMER=0
            while [[ ( ${RESPONSE} == *"This node is not a swarm manager"*  ||  ${RESPONSE} == *"Connection refused"* ) ]] && [[ ${TIMER} < 120 ]]; do
                RESPONSE=$(yes | doctl compute ssh ${MANAGER_NAME} --access-token ${DO_ACCESS_TOKEN} --ssh-command "docker node ls")
                printf "Docker hasn\'t initialized the swarm manager yet. Waiting 10 seconds...\n"
                sleep 10
                let TIMER=TIMER+10
            done

            if [[ ${RESPONSE} == *"This node is not a swarm manager"* ]]; then
                printf "Manager node \"${MANAGER_NAME}\" still hasn\'t initialized the swarm.  Try in a few minutes.\n"
                exit 1
            fi

            printf "Manager node ${MANAGER_NAME} is ready!\n"
        }

        ## Create the swarm
        ./create-swarm.sh "$SWARM_NAME" --token "$DO_ACCESS_TOKEN" || exit 1
        printf "\nWaiting for swarm manager to initialize the swarm..."
        WAIT_FOR_MANAGER "${SWARM_NAME}-01"
        printf "\n"
        if [[ ${WORKERS_TO_ADD} -gt 0 ]]; then
            spawn ./add-worker.sh ${SWARM_NAME} --add ${WORKERS_TO_ADD} --token ${DO_ACCESS_TOKEN}${FLAGS}
            expect {
                "(yes/no"

        fi

        if [[ ${MANAGERS_TO_ADD} -gt 0 ]]; then
            printf "\nWaiting for workers to join the swarm..."
            sleep 30
            printf "done\n"
            ./add-manager.sh "$SWARM_NAME" --add "$MANAGERS_TO_ADD" --token "$DO_ACCESS_TOKEN" || exit 1
        fi
        ;;

    scale-swarm)
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
            printf "$SCALE_SWARM_USAGE"
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

    scale-stack)
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
            printf "$SCALE_SWARM_USAGE"
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
            printf "$DESTROY_USAGE"
            exit 0
        fi

        ## Read arguments
        SWARM_NAME="$1"; shift

        ## Destroy the swarm
        ./destroy-swarm.sh ${SWARM_NAME} --token ${DO_ACCESS_TOKEN}${FLAGS} || exit 1
        ;;
esac
