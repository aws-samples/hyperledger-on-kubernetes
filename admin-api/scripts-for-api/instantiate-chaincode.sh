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

    log "In instantiate-chaincode.sh script. instantiating chaincode name: ${CHAINCODE_NAME}, version ${CHAINCODE_VERSION} on all peers in org: ${CHAINCODE_ORG}"

    # Checking if the chaincode has been copied to the appropriate directory. Note that the /opt/share/rca-scripts directory
    # on the bastion is mounted into all Kubernetes pods as /scripts
    if [ ! -d "$SCRIPTS/chaincode/${CHAINCODE_NAME}" ]; then
        log "Copy your chaincode into this directory before calling this script: /opt/share/rca-scripts/chaincode/${CHAINCODE_NAME}"
        exit 1
    fi

    # If the chaincode is written in golang, copy the chaincode to the golang folder expected by 'peer chaincode instantiate'
    CHAINCODE_DIR="";
    if [ "$CHAINCODE_LANGUAGE" == "golang" ]; then
        mkdir -p /opt/gopath/src/chaincode/${CHAINCODE_NAME}
        cp -R $SCRIPTS/chaincode/${CHAINCODE_NAME} /opt/gopath/src/chaincode
        log  "Copying chaincode as follows: cp -R $SCRIPTS/chaincode/${CHAINCODE_NAME} /opt/gopath/src/chaincode"
        CHAINCODE_DIR=chaincode/${CHAINCODE_NAME}
    else
        CHAINCODE_DIR=$SCRIPTS/chaincode/${CHAINCODE_NAME}
    fi

    # Set ORDERER_PORT_ARGS to the args needed to communicate with the 3rd orderer. TLS is set to false for orderer3
    IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
    initOrdererVars ${OORGS[0]} 3
    export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --cafile $CA_CHAINFILE"

    # Convert CHAINCODE_ORGS to an array named PORGS
    IFS=',' read -r -a PORGS <<< "$CHAINCODE_ORGS"
    log "ORGS passed to script are ${PORGS[@]}"

    # Convert CHAINCODE_INIT to an array named CINIT
    IFS=',' read -r -a CINIT <<< "$CHAINCODE_INIT"
    CINITSTRING=$(printf ",\"%s\"" "${CINIT[@]}")
    log "Chaincode init arguments passed to script are ${CINITSTRING:1}"

    makePolicy
    initPeerVars ${PORGS[0]} 1
    instantiateChaincode

    log "instantiated chaincode. Name: ${CHAINCODE_NAME}, version ${CHAINCODE_VERSION} on peer: ${PEER_NAME}"
}

function instantiateChaincode {
   switchToAdminIdentity
   log "instantiating chaincode on '$PEER_HOST'"
   log "instantiate command is: peer chaincode instantiate -C $CHANNEL_NAME -n $CHAINCODE_NAME -v $CHAINCODE_VERSION -c '{\"Args\":[${CINITSTRING:1}]}' -P \"${POLICY}\" $ORDERER_CONN_ARGS"
   peer chaincode instantiate -C $CHANNEL_NAME -n $CHAINCODE_NAME -v $CHAINCODE_VERSION -c "'"{"Args":[${CINITSTRING:1}]}"'" -P \"${POLICY}\" $ORDERER_PORT_ARGS
}

function makePolicy  {
   POLICY="OR("
   local COUNT=0
   for ORG in ${PORGS[@]}; do
      log "ORG in makePolicy: $ORG"
      if [ $COUNT -ne 0 ]; then
         POLICY="${POLICY},"
      fi
      initOrgVars $ORG
      POLICY="${POLICY}'${ORG_MSP_ID}.member'"
      COUNT=$((COUNT+1))
   done
   POLICY="${POLICY})"
   log "policy: $POLICY"
}

DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
echo "Args are: " $*
echo "Make sure to call this script with an array of orgs, as the orgs will form the endorsement policy when chaincode is instantiated"
CHAINCODE_NAME=$1
CHAINCODE_VERSION=$2
CHAINCODE_INIT=$3
CHAINCODE_ORGS=$4
CHANNEL_NAME=$5
main

