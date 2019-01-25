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

    echo "In join-channel.sh script - joining org ${ORG} to new channel: ${CHANNEL_NAME}"

    # Join the first peer to the channel. You could loop through all peers in the org and add them here, if necessary
    initPeerVars $ORG 1

    # Create the channel
    joinChannel

    log "Congratulations! $CHANNEL_NAME created successfully."
}


# Enroll as a peer admin and create the channel
function joinChannel {
    switchToAdminIdentity
    cd $DATADIR
    log "Joining channel '$CHANNEL_NAME' with genesis block file '${DATADIR}/${CHANNEL_NAME}.block'"
    log "Peer $PEER_HOST is attempting to join channel '$CHANNEL_NAME'"
    peer channel join -b ${DATADIR}/${CHANNEL_NAME}.block
}

DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
echo "Args are: " $*
CHANNEL_NAME=$1
ORG=$2
main

