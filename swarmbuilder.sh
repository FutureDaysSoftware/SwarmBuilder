#!/usr/bin/env bash

## Import config variables
if [ ! -f "${BASH_SOURCE%/*}/config.sh" ]; then
    printf "Config file not found - creating \'config.sh\' from the template.
    You should customize the contents of \'config.sh\' before using this script.\n"
    $(cp ${BASH_SOURCE%/*}/config.example.sh ${BASH_SOURCE%/*}/config.sh && chmod a+x ${BASH_SOURCE%/*}/config.sh) || printf "\nUnable to create config file.\n" 1>&2 && exit 1
fi
source ${BASH_SOURCE%/*}/config.sh

USAGE="\nCreate & manage a Docker swarm on DigitalOcean droplets

Usage:
$(basename "$0") [command] [flags]

Available commands:
    create          Create a new swarm on fresh droplets.
    scale-swarm     Change the number of nodes in the swarm (and the number of droplets).
    scale-stack     Change the number of replicas of a service stack running in the swarm.
    remove-stack    Completely remove a stack from the swarm.
    destroy         Destroy the entire swarm and delete all its droplets.

Flags:
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"

CREATE_USAGE="\nCreate a new swarm on fresh droplets.

Usage:
$(basename "$0") create <swarmName> [flags]

Where:
    <swarmName>                 The name of the swarm to be created.
                                 All droplets and swarm nodes will use this as their base name.

Flags:
        --managers integer      The number of manager nodes to create.  Default 1.
        --workers integer       The number of worker nodes to create (Default 0) in addition to the single manager node.
        --deploy-file string    The filename of a \'docker-compose.yml\' file that describes a service stack to deploy.
                                 This argument must be accompanied by \'--deploy-name\'.
        --deploy-name string    The name to give to the stack being deployed.
                                 This argument must be accompanied by \'--deploy-file\'.
    -t, --token                 Your DigitalOcean API key (optional).
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

SCALE_STACK_USAGE="\nChange the number of replicas of the \'_web\' service in a stack.

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
        LONGOPTS="token:,managers:,workers:,deploy-file:,deploy-name:"
        ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
        eval set -- ${ARGS}

        while true; do
            case ${1} in
                --managers)
                    shift
                    MANAGERS_TO_ADD=$(($1 - 1))
                    if [[ ${MANAGERS_TO_ADD} -gt 0 ]]; then
                        FLAGS=" --wait"
                    elif [[ ${MANAGERS_TO_ADD} -lt 0 ]]; then
                        printf "\nYou must have at least 1 manager in the swarm\n\n" 1>&2; exit 1;
                    fi
                    ;;
                --workers)
                    shift
                    WORKERS_TO_ADD="$1"
                    ;;
                --deploy-file)
                    shift
                    COMPOSE_FILE="$1"
                    if [ ! -f "$COMPOSE_FILE" ]; then
                        printf "\nThe file \'${COMPOSE_FILE}\' could not be found. You must provide a valid \'docker-compose.yml\' file." 1>&2; exit 1
                    fi
                    ;;
                --deploy-name)
                    shift
                    STACK_NAME="$1"
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

        ## Perform this check early as a courtesy (so the user can re-issue the command instead of having to wait
        ## for the deploy step to fail at the very end.
        if [[ -z ${STACK_NAME} || -z ${COMPOSE_FILE} && ! (-z ${STACK_NAME} && -z ${COMPOSE_FILE}) ]]; then
            printf "\nThe \'--deploy-name\' and \'--deploy-file\' arguments must be used together (you can\'t just
            provide one or the other)\n\n" 1>&2
            exit 1
        fi

        ## Read arguments
        SWARM_NAME="$1"; shift
        MANAGER_NAME="${SWARM_NAME}-01"  # This assumption is generally safe and saves an API call. Replace with a lookup if it causes problems.

        ## Create the swarm
        ${BASH_SOURCE%/*}/create-swarm.sh "$SWARM_NAME" --token "$DO_ACCESS_TOKEN" || exit 1

        ## Wait for docker to initialize the swarm (so a swarm join token will be available) before adding workers
        printf "\nWaiting for swarm manager to initialize the swarm...\n"
        ${BASH_SOURCE%/*}/poll-for-active-node.sh "$SWARM_NAME" --hostname "$SWARM_NAME-01"
        printf "\n"
        if [[ ${WORKERS_TO_ADD} -gt 0 ]]; then
            ${BASH_SOURCE%/*}/add-worker.sh ${SWARM_NAME} --add ${WORKERS_TO_ADD} --token ${DO_ACCESS_TOKEN}${FLAGS}
        fi

        if [[ ${MANAGERS_TO_ADD} -gt 0 ]]; then
            ${BASH_SOURCE%/*}/add-manager.sh ${SWARM_NAME} --add ${MANAGERS_TO_ADD} --token ${DO_ACCESS_TOKEN} || exit 1
        fi

        if [[ -n ${COMPOSE_FILE} ]] && [[ -n ${STACK_NAME} ]]; then
            ${BASH_SOURCE%/*}/deploy-stack.sh ${SWARM_NAME} --compose-file ${COMPOSE_FILE} --stack-name ${STACK_NAME} --token ${DO_ACCESS_TOKEN}
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
            ${BASH_SOURCE%/*}/add-worker.sh "$SWARM_NAME" --add "$WORKERS_TO_ADD" --token "$DO_ACCESS_TOKEN" || exit 1
            exit 0
        elif [[ ${WORKERS_DESIRED} -lt ${WORKER_NODES_COUNT} ]]; then
            printf "Removing ${WORKERS_TO_REMOVE} worker(s) from the ${SWARM_NAME} swarm\n"
            ${BASH_SOURCE%/*}/remove-worker.sh "$SWARM_NAME" --remove "$WORKERS_TO_REMOVE" --token "$DO_ACCESS_TOKEN" || exit 1
            exit 0
        elif [[ ${WORKERS_DESIRED} -eq ${WORKER_NODES_COUNT} ]]; then
            printf "This swarm already has ${WORKERS_DESIRED} worker nodes.\n"
            exit 0
        else
            printf "Couldn\'t determine whether to add or remove worker nodes.\n" 1>&2
            exit 1
        fi
        ;;

    scale-stack)
        ## Set default options
        ## This command has no defaults

        ## Process flags and options
        SHORTOPTS="t:"
        LONGOPTS="token:,stack:,replicas:"
        ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
        eval set -- ${ARGS}

        while true; do
            case ${1} in
                --stack)
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
            printf "$SCALE_STACK_USAGE"
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
            ${BASH_SOURCE%/*}/add-worker.sh "$SWARM_NAME" --add "$WORKERS_TO_ADD" --wait --token "$DO_ACCESS_TOKEN" || exit 1
        else
            printf "No new droplets are needed to achieve ${REPLICAS_DESIRED_QTY} replicas.\n"
        fi

        ## Scale the '_web' service for the specified stack
        ${BASH_SOURCE%/*}/scale-service.sh ${SWARM_NAME} --service ${SERVICE_NAME} --replicas ${REPLICAS_DESIRED_QTY} --token ${DO_ACCESS_TOKEN} >/dev/null

        ## Output a summary of the services in the stack
        ${BASH_SOURCE%/*}/ssh-to-manager.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN} --ssh-command "docker stack ps ${STACK_NAME}"

        ## TODO: Check for idle nodes and prune unused droplets. Use `docker node ps mySwarm-01 mySwarm-02 mySwarm...`

        ;;

    remove-stack)
        ${BASH_SOURCE%/*}/remove-stack.sh "$@"
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
        ${BASH_SOURCE%/*}/destroy-swarm.sh ${SWARM_NAME} --token ${DO_ACCESS_TOKEN}${FLAGS} || exit 1
        ;;
esac
