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

    log "In install-chaincode.sh script. Installing chaincode name: ${CHAINCODE_NAME}, version ${CHAINCODE_VERSION} on all peers in org: ${CHAINCODE_ORG}"

    # Checking if the chaincode has been copied to the appropriate directory. Note that the /opt/share/rca-scripts directory
    # on the bastion is mounted into all Kubernetes pods as /scripts
    if [ ! -d "$SCRIPTS/chaincode/${CHAINCODE_NAME}" ]; then
        log "Copy your chaincode into this directory before calling this script: /opt/share/rca-scripts/chaincode/${CHAINCODE_NAME}"
        exit 1
    fi

    # Copy the chaincode to the folder expected by 'peer chaincode install'
    mkdir -p /opt/gopath/src/chaincode/${CHAINCODE_NAME}
    cp -R $SCRIPTS/chaincode/${CHAINCODE_NAME} /opt/gopath/src/chaincode/${CHAINCODE_NAME}
    log  "Copying chaincode as follows: cp -R $SCRIPTS/chaincode/${CHAINCODE_NAME} /opt/gopath/src/chaincode/${CHAINCODE_NAME}"

    # Set ORDERER_PORT_ARGS to the args needed to communicate with the 3rd orderer. TLS is set to false for orderer3
    IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
    initOrdererVars ${OORGS[0]} 3
    export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --cafile $CA_CHAINFILE"

    local COUNT=1
    while [[ "$COUNT" -le $NUM_PEERS ]]; do
        initPeerVars $CHAINCODE_ORG $COUNT
        installChaincode
        COUNT=$((COUNT+1))
    done

    log "Installed chaincode. Name: ${CHAINCODE_NAME}, version ${CHAINCODE_VERSION} on all peers in org: ${CHAINCODE_ORG}"
}

function installChaincode {
   switchToAdminIdentity
   getChaincodeVersion
   MAXCCVERSION=$((MAXCCVERSION+1))
   log "MAXCCVERSION '$MAXCCVERSION'"
   if [[ $MAXINSTALLEDCCVERSION -ge $MAXCCVERSION ]]; then
        log "Installed chaincode version is '$MAXINSTALLEDCCVERSION', and we need '$MAXCCVERSION' on '$PEER_HOST', so no need to install"
   else
        log "Installing chaincode version '$MAXCCVERSION' on '$PEER_HOST'; currently at version '$MAXINSTALLEDCCVERSION'"
        peer chaincode install -n mycc -v $MAXCCVERSION -p chaincode/${CHAINCODE_NAME}
   fi
}

function getChaincodeVersion {
   switchToAdminIdentity
   log "Getting chaincode version on $PEER_HOST ..."
   #find the max version number
   MAXINSTALLEDCCVERSION=0
   #We get the installed versions to prevent us from reinstalling if we've previously installed the latest version.
   while read -r line ; do
        echo "processing line '$line'"
        CCVERSION=`echo $line | awk '{print $4}' | cut -d "," -f 1 | cut -d "." -f 1`
        log "CCVERSION '$CCVERSION'"
        if [[ $CCVERSION -gt $MAXINSTALLEDCCVERSION ]]; then
            MAXINSTALLEDCCVERSION=$CCVERSION
        fi
   done < <(peer chaincode list --installed | grep ${CHAINCODE_NAME})
   log "MAXINSTALLEDCCVERSION '$MAXINSTALLEDCCVERSION'"

   #find the max version number
   MAXCCVERSION=0
   #We are interested in the chaincode instantiated on the channel. We want the same
   #version on all peers, so we get the instantiated version and increment it
   while read -r line ; do
        CCVERSION=`echo $line | awk '{print $4}' | cut -d "," -f 1 | cut -d "." -f 1`
        log "CCVERSION '$CCVERSION'"
        if [[ $CCVERSION -gt $MAXCCVERSION ]]; then
            MAXCCVERSION=$CCVERSION
        fi
   done < <(peer chaincode list -C $CHANNEL_NAME --instantiated | grep ${CHAINCODE_NAME})
   log "MAXCCVERSION '$MAXCCVERSION'"
 }


DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
echo "Args are: " $*
CHAINCODE_NAME=$1
CHAINCODE_VERSION=$2
CHAINCODE_ORG=$3
CHANNEL_NAME=$4
main

