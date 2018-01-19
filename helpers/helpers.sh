#!/usr/bin/env bash

function confirm() {
    # Prompt the user for confirmation.
    # Usage:
    #  confirm && rm *
    #
    # or with a custom prompt:
    #  confirm "Really delete everything?" $$ rm *

    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

