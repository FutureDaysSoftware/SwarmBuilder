#!/usr/bin/env bash

## Import config variables
source ./config.sh

USAGE="\nRemove worker nodes from an existing swarm.

Usage:
$(basename "$0") <exampleSwarmName> [--token] [--remove 1]

where:
    exampleSwarmName    The name of the existing swarm.
    -t, --token         Your DigitalOcean API key (optional).
                         If omitted here, it must be provided in \'config.sh\'
    -n, --remove        The number of worker nodes to remove (Default 1).\n\n"

## Set default options
QTY_WORKERS_TO_REMOVE=1

## Process flags and options
SHORTOPTS="t:n:"
LONGOPTS="token:,remove:"
ARGS=$(getopt -s bash --options ${SHORTOPTS} --longoptions ${LONGOPTS} -- "$@" )
eval set -- ${ARGS}

while true; do
	case ${1} in
		-n | --remove)
            shift
		    QTY_WORKERS_TO_REMOVE="$1"
		    ;;
		-t | --token)
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

## Find a manager node for the requested swarm
MANAGER_NODE_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME}-manager \
    --format Name,ID \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | head -n1)

## Get the address of the manager node
if [ -z "$MANAGER_NODE_STRING" ]; then
    printf "No manager node found for the \"${SWARM_NAME}\" swarm. Does the swarm exist yet?\n\n" 1>&2
    exit 1
else
    MANAGER_NODE_ARRAY=(${MANAGER_NODE_STRING})
    MANAGER_NAME=${MANAGER_NODE_ARRAY[0]}
    MANAGER_ID=${MANAGER_NODE_ARRAY[1]}
fi


## Get a list of all worker nodes in the requested swarm, sorted in reverse alphanumerical order
WORKER_NODES_STRING=$(doctl compute droplet list \
    --tag-name ${SWARM_NAME}-worker \
    --format Name,ID \
    --no-header \
    --access-token ${DO_ACCESS_TOKEN} | sort -k1 -r )

## Limit the list of workers to the requested quantity
readarray -t ALL_WORKER_NODES <<< "$WORKER_NODES_STRING"
WORKER_NODES_TO_REMOVE=("${ALL_WORKER_NODES[@]:0:${QTY_WORKERS_TO_REMOVE}}")

if [[ -z ${ALL_WORKER_NODES} || ${#WORKER_NODES_TO_REMOVE[@]} -eq 0 ]]; then
    printf "There are no worker nodes in the \"${SWARM_NAME}\" swarm. Exiting.\n\n"
    exit 0
elif [[ ${QTY_WORKERS_TO_REMOVE} -gt ${#WORKER_NODES_TO_REMOVE[@]} ]]; then
    printf "Only ${#WORKER_NODES_TO_REMOVE[@]} worker nodes exist in the \"${SWARM_NAME}\" swarm.  All will be removed.\n"
fi


## Drain all nodes to be deleted
for i in "${WORKER_NODES_TO_REMOVE[@]}";
do
    WORKER_NODE=(${i})
    NODE_NAME=${WORKER_NODE[0]}
    NODE_ID=${WORKER_NODE[1]}

    printf "Draining tasks from node \"${NODE_NAME}\"..."
	doctl compute ssh ${MANAGER_ID} --access-token ${DO_ACCESS_TOKEN} --ssh-command "docker node update --availability drain ${NODE_NAME}"
	printf "done\n"
done
printf "\n"

sleep 2
### Remove the drained nodes from the swarm
for i in "${WORKER_NODES_TO_REMOVE[@]}";
do
    WORKER_NODE=(${i})
    NODE_NAME=${WORKER_NODE[0]}
    NODE_ID=${WORKER_NODE[1]}

	printf "Removing ${NODE_NAME} from the swarm..."
	doctl compute ssh ${MANAGER_ID} --access-token ${DO_ACCESS_TOKEN} --ssh-command "docker node rm ${NODE_NAME} -f"
	printf "done\n"
done
printf "\n"

### Delete the droplets
for i in "${WORKER_NODES_TO_REMOVE[@]}";
do
    WORKER_NODE=(${i})
    NODE_NAME=${WORKER_NODE[0]}
    NODE_ID=${WORKER_NODE[1]}

	printf "Removing droplet: ${NODE_NAME}..."
	doctl compute droplet delete ${NODE_ID} -f -v --access-token ${DO_ACCESS_TOKEN}
	printf "done\n"
done
