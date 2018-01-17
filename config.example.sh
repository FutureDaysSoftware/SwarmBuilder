#!/usr/bin/env bash

## Digital Ocean Access Token / API key (if omitted here, it can be provided on the command line)
export DO_ACCESS_TOKEN=""

## ----------------------------------------------
## Digital Ocean droplet configuration

## DO_DROPLET_SSH_KEYS is a comma-separated list of the FINGERPRINT values for SSH keys that have been uploaded to DO
## The fingerprint values can be found on the "Settings -> Security -> SSH keys" menu on Digital Ocean.
export DO_DROPLET_SSH_KEYS="39:cd:f5:dd:3a:fe:24:33:50:c5:0d:bd:36:fa:4e:99,74:4b:9f:e6:eb:0d:b9:10:50:37:fc:3f:4e:ae:29:d1"
export DO_DROPLET_SIZE="512mb"
export DO_DROPLET_IMAGE="docker-16-04"
export DO_DROPLET_REGION="nyc3"

## DO_DROPLET_FLAGS is a list of space-delimited parameters that the doctl command-line tool accepts.
## i.e. "--enable-private-networking --enable-backups --enable-ipv6"
export DO_DROPLET_FLAGS="--enable-private-networking"

##  DO_IP_DISCOVERY_URL is the URL of DigitalOcean's internal 'what's-my-ip' service.  This shouldn't need to be changed.
export DO_IP_DISCOVERY_URL="http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address"


## ----------------------------------------------