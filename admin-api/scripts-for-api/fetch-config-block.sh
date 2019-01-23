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

function main {

    log "Fetching the configuration block for channel '$CHANNEL_NAME'"

    # Set ORDERER_PORT_ARGS to the args needed to communicate with the 3rd orderer. TLS is set to false for orderer3
    IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
    initOrdererVars ${OORGS[0]} 3
    export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --cafile $CA_CHAINFILE"

    # Set MSP to orderer
    export CORE_PEER_MSPCONFIGPATH=/data/orgs/org0/admin/msp
    export CORE_PEER_LOCALMSPID=org0MSP

    # Fetch config block
    fetchConfigBlock
}

function fetchConfigBlock {
  #  switchToAdminIdentity
    export FABRIC_CFG_PATH=/etc/hyperledger/fabric
    log "Fetching the configuration block into '$CONFIG_BLOCK_FILE' for the channel '$CHANNEL_NAME'"
    log "peer channel fetch config $CONFIG_BLOCK_FILE -c $CHANNEL_NAME $ORDERER_PORT_ARGS"
    peer channel fetch config $CONFIG_BLOCK_FILE -c $CHANNEL_NAME $ORDERER_PORT_ARGS
    log "fetched config block"
}

DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
echo "Args are: " $*
CHANNEL_NAME=$1
CONFIG_BLOCK_FILE=${DATADIR}/${CHANNEL_NAME}.pb
main
