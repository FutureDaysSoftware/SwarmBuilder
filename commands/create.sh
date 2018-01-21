#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nCreate a new swarm on fresh droplets.

Usage:
$(basename "$0") create <swarmName> [flags]

Where:
    <swarmName>                 The name of the swarm to be created.
                                 All droplets and swarm nodes will use this as their base name.

Flags:
        --managers integer      The number of manager nodes to create.  Default 1.
        --workers integer       The number of worker nodes to create (Default 0) in addition to the single manager node.
    -c, --compose-file string   The filename of a \'docker-compose.yml\' file that describes a service stack to deploy.
                                 This argument must be accompanied by \'--stack-name\'.
    -n, --stack-name string     The name to give to the stack being deployed.
                                 This argument must be accompanied by \'--compose-file\'.
    -b, --bare                  The swarm will be configured, but no webhosting environment (nginx, etc) will be deployed.
    -t, --token                 Your DigitalOcean API key (optional).
                                 If omitted here, it must be provided in \'config.sh\'\n\n"


## Set default options
MANAGERS_TO_ADD=0
WORKERS_TO_ADD=0
FLAGS=""
DEPLOY_WEBHOST=true

## Process flags and options
SHORTOPTS="t:c:n:b"
LONGOPTS="token:,managers:,workers:,compose-file:,stack-name:,bare"
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
            shift
            ;;
        --workers)
            shift
            WORKERS_TO_ADD="$1"
            shift
            ;;
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
        -b | --bare)
            DEPLOY_WEBHOST=false
            shift
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
    printf "$USAGE"
    exit 0
fi

## Perform this check early as a courtesy (so the user can re-issue the command instead of having to wait
## for the deploy step to fail at the very end.
if [[ -z ${STACK_NAME} || -z ${COMPOSE_FILE} ]] && [[ ! ( -z ${STACK_NAME} && -z ${COMPOSE_FILE} ) ]]; then
    printf "\nThe \'--stack-name\' and \'--compose-file\' arguments must be used together (you can\'t just provide one or the other)\n\n" 1>&2
    exit 1
fi

## Read arguments
SWARM_NAME="$1"; shift
MANAGER_NAME="${SWARM_NAME}-01"  # This assumption is generally safe and saves an API call. Replace with a lookup if it causes problems.

## Create the swarm
${DIR}/helpers/create-swarm.sh "$SWARM_NAME" --token "$DO_ACCESS_TOKEN" || exit 1

## Wait for docker to initialize the swarm (so a swarm join token will be available) before adding workers
printf "\nWaiting for swarm manager to initialize the swarm...\n"
${DIR}/helpers/poll-for-active-node.sh "$SWARM_NAME" --hostname "$MANAGER_NAME"
if [[ "$?" != 0 ]]; then
    printf "Attempting to continue. If a swarm join-token can\'t be retrieved from the
manager node yet, you\'ll need to wait a little longer until the docker swarm finishes initializing the swarm.\n"

    if [[ ${WORKERS_TO_ADD} -gt 0 ]]; then
        printf "Then you can manually add worker nodes by running:\n\n\t$0 scale-swarm ${SWARM_NAME} --workers ${WORKERS_TO_ADD}\n\n"
    fi

    if [[ -n "$STACK_NAME" ]]; then
        printf "Then you can manually deploy your app by running:\n\n\t$0 deploy ${SWARM_NAME} --compose-file ${COMPOSE_FILE} --stack-name ${STACK_NAME}\n\n"
    fi
fi


if [[ "${DEPLOY_WEBHOST}" = true ]]; then
    ## Set up the webhosting environment on the master swarm node
    printf "\nDeploying hosting environment to the master node.\n"

    ## Disable SSH rate-limiting on the remote host
    ${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --master --ssh-command "ufw allow ssh"

    ${DIR}/helpers/deploy-webhosting-containers.sh --swarm ${SWARM_NAME} --token ${DO_ACCESS_TOKEN}

    ## Re-enable SSH rate-limiting on the remote host
    ${DIR}/helpers/ssh-to-manager.sh --swarm ${SWARM_NAME} --master --ssh-command "ufw limit ssh"

    # TODO: Allow webhost deployment to run asynchronously with the 'add-worker' command next (but wait before adding managers or deploying app stack)
fi

if [[ ${WORKERS_TO_ADD} -gt 0 ]]; then
    ${DIR}/helpers/add-worker.sh ${SWARM_NAME} --add ${WORKERS_TO_ADD} --token ${DO_ACCESS_TOKEN}${FLAGS}
fi

if [[ ${MANAGERS_TO_ADD} -gt 0 ]]; then
    ${DIR}/helpers/add-manager.sh ${SWARM_NAME} --add ${MANAGERS_TO_ADD} --token ${DO_ACCESS_TOKEN} || exit 1
fi

if [[ -n ${COMPOSE_FILE} ]] && [[ -n ${STACK_NAME} ]]; then
    ${DIR}/commands/deploy.sh ${SWARM_NAME} --compose-file ${COMPOSE_FILE} --stack-name ${STACK_NAME} --token ${DO_ACCESS_TOKEN}
fi
