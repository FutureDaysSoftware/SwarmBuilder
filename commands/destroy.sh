#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")/.."

## Import config variables
source ${DIR}/config/config.sh

USAGE="\nDestroy the entire swarm and delete all its droplets

Usage:
$(basename "$0") destroy <swarmName> [flags]

Where:
    <swarmName>     The name of the swarm to be destroyed.
                     All droplets in this swarm will be deleted.

Flags:
    -f, --force     Bypass interactive confirmation.  Droplets will be deleted immediately.
    -t, --token     Your DigitalOcean API key (optional).
                     If omitted here, it must be provided in \'config.sh\'\n\n"


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
    printf "$USAGE"
    exit 0
fi

## Read arguments
SWARM_NAME="$1"; shift

## Destroy the swarm
${DIR}/helpers/destroy-swarm.sh ${SWARM_NAME} --token ${DO_ACCESS_TOKEN}${FLAGS} || exit 1