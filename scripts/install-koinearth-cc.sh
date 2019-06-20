#!/bin/bash

# Copyright 2018 Koinearth India Pvt. Ltd., Inc. or its affiliates. All Rights Reserved.
#

set +e

source $(dirname "$0")/env.sh

function main {

   done=false

   cloneKoinearthChaincode

   log "Installing koinearth general chaincode"

   # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
   IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
   initOrdererVars ${OORGS[0]} 1
   export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"
#   export ORDERER_PORT_ARGS="-o $ORDERER_HOST:7050 --cafile $CA_CHAINFILE"

   # Convert PEER_ORGS to an array named PORGS
   IFS=', ' read -r -a PORGS <<< "$PEER_ORGS"

   # Install chaincode on the 1st peer in each org
   for ORG in $PEER_ORGS; do
      initPeerVars $ORG 1
      installChaincode
   done

   log "Congratulations! The marbles chaincode was installed successfully."

   done=true
}

# git clone fabric-samples. We need this repo for the chaincode
function cloneKoinearthChaincode {
    # here we need to clone koinearth repo
   log "clone Koinearth app: https://github.com/IBM-Blockchain/marbles.git"
   mkdir -p /opt/gopath/src/github.com/hyperledger
   cd /opt/gopath/src/github.com/hyperledger
   git clone https://github.com/hyperledger/fabric.git
   cd ..
   git clone https://github.com/koinearth/golang-supplychain.git
   git checkout development
   log "cloned koinearth chaincode repo"
   mv golang-supplychain/* .
}

function installChaincode {
   switchToAdminIdentity
   log "Installing marbles chaincode on $PEER_HOST ..."
   peer chaincode install -n koinearthcc -v 1.0 -p github.com/fabcar2/go
#    peer chaincode install --clientauth --certfile $DATA/tls/$PEER_NAME-client.crt --keyfile /data/tls/peer1-org2-client.key -n koinearthcc -v 1.0 -p github.com/fabcar2/go
}

main
