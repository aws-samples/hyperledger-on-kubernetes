#!/bin/bash

# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set -e

function main {

    echo "In create-channel.sh script"
    source $SCRIPTS/env.sh
    CHANNEL_NAME=$1
    echo "In create-channel.sh script - creating new channel: $CHANNEL_NAME"

    # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
    IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
    initOrdererVars ${OORGS[0]} 1
    export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"
    #   export ORDERER_PORT_ARGS="-o $ORDERER_HOST:7050 --cafile $CA_CHAINFILE"

    # Convert PEER_ORGS to an array named PORGS
    IFS=', ' read -r -a PORGS <<< "$PEER_ORGS"

    # Create the channel
    createChannel

    log "Congratulations! $CHANNEL_NAME created successfully."
}


# Enroll as a peer admin and create the channel
function createChannel {
   initPeerVars ${PORGS[0]} 1
   switchToAdminIdentity
   log "Creating channel '$CHANNEL_NAME' with file '$CHANNEL_TX_FILE' on $ORDERER_HOST using connection '$ORDERER_CONN_ARGS'"
   local CHANNELLIST=`peer channel list | grep -c ${CHANNEL_NAME}`
   if [ $CHANNELLIST -gt 0 ]; then
       log "Channel '$CHANNEL_NAME' already exists - creation request ignored"
   else
       peer channel create --logging-level=DEBUG -c $CHANNEL_NAME -f $CHANNEL_TX_FILE $ORDERER_CONN_ARGS
       cp ${CHANNEL_NAME}.block /$DATA
   fi
}

DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
main

