#!/usr/bin/env bash

## Set root path
DIR="$(dirname "$(readlink -f "$0")")"

## Import config variables
source ${DIR}/config.sh
source ${DIR}/helpers.sh


## This script adds a symlink to `./swarmbuilder.sh` at `~/bin/swarmbuilder` and ensures that `~/bin` is in your PATH.

printf "
        This will allow you to use swarmbuilder from any directory without providing the path.

        A symlink will be linked to \`./swarmbuilder.sh\` at \`~/bin/swarmbuilder\` and
        your PATH will be updated to include  \`~/bin\` if it isn\'t already there.\n\n"

confirm || exit 0

[[ ":$PATH:" != *":/home/${USER}/bin:"* ]] && PATH="${PATH}:/home/${USER}/bin"

ln -s "${DIR}/swarmbuilder.sh" "/home/${USER}/bin/swarmbuilder"

printf "\nDone!  You can now use the swarmbuilder script from any directory without providing the path.\n"

