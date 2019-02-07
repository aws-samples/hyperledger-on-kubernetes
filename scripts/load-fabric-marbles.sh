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

source $(dirname "$0")/env.sh

function main {

   done=false

   cloneFabricSamples

   log "Load test Fabric Marbles"

   # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
   IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
   initOrdererVars ${OORGS[0]} 1
   export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"
#   export ORDERER_PORT_ARGS="-o $ORDERER_HOST:7050 --cafile $CA_CHAINFILE"

    makePolicy

    # Install chaincode on all peers in the org
    export ORG=$PEERORG
    local COUNT=1
    while [[ "$COUNT" -le $NUM_PEERS ]]; do
        initPeerVars $ORG $COUNT
        installChaincode
        COUNT=$((COUNT+1))
    done

    # Instantiate chaincode on the 1st peer of the org
    initPeerVars $ORG 1
    instantiateChaincode

    #create a user
    initPeerVars $ORG 1
    switchToAdminIdentity
    export USER_NAME=marbles-$ORG
    export USER_PASS=${USER_NAME}pw
    log "Enrolling with $CA_NAME as bootstrap identity ..."
    export FABRIC_CA_CLIENT_HOME=$HOME/cas/$CA_NAME
    export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
    if ! [ -x "$(command -v fabric-ca-client)" ]; then
      echo 'fabric-ca-client is not installed - installing it now.'
      installFabricCA
    fi
    fabric-ca-client enroll -d -u https://$CA_ADMIN_USER_PASS@$CA_HOST:7054

    log "Registering admin identity with $CA_NAME"
    # The admin identity has the "admin" attribute which is added to ECert by default
    if ! [ -x "$(command -v fabric-ca-client)" ]; then
      echo 'fabric-ca-client is not installed - installing it now.'
      installFabricCA
    fi
    fabric-ca-client register -d --id.name $ADMIN_NAME --id.secret $ADMIN_PASS --id.attrs "hf.Registrar.Roles=client,hf.Registrar.Attributes=*,hf.Revoker=true,hf.GenCRL=true,admin=true:ecert,abac.init=true:ecert"

    log "Registering user identity ${USER_NAME} with $CA_NAME"
    if ! [ -x "$(command -v fabric-ca-client)" ]; then
      echo 'fabric-ca-client is not installed - installing it now.'
      installFabricCA
    fi
    fabric-ca-client register -d --id.name $USER_NAME --id.secret $USER_PASS

   # Init chaincode
   switchToUserIdentity
   sleep 2
   chaincodeInit

    #Invoke and query the chaincode infinitely
    while true; do
        local COUNT=1
        while [[ "$COUNT" -le $NUM_PEERS ]]; do
            initPeerVars $ORG $COUNT
            switchToAdminIdentity
            log "Querying chaincode on $PEER_HOST ..."
            chaincodeQuery
            log "Transferring marble transaction to $PEER_HOST ..."
            transferMarble
            sleep 3
            transferMarbleAgain
            COUNT=$((COUNT+1))
        done
        sleep 3
    done

   log "Congratulations! Marble load tests ran successfully."

   done=true
}

# git clone fabric-samples. We need this repo for the chaincode
function cloneFabricSamples {
   log "cloneFabricSamples"
   mkdir -p /opt/gopath/src/github.com/hyperledger
   cd /opt/gopath/src/github.com/hyperledger
   git clone https://github.com/hyperledger/fabric-samples.git
   log "cloned FabricSamples"
   cd fabric-samples
   git checkout release-1.1
   log "checked out version 1.1 of FabricSamples"

   log "cloneFabric"
   mkdir /opt/gopath/src/github.com/hyperledger/fabric
}

# Enroll as a peer admin and create the channel
function createChannel {
   initPeerVars $ORG 1
   switchToAdminIdentity
   log "Creating channel '$CHANNEL_NAME' with file '$CHANNEL_TX_FILE' on $ORDERER_HOST using connection '$ORDERER_CONN_ARGS'"
   peer channel create --logging-level=DEBUG -c $CHANNEL_NAME -f $CHANNEL_TX_FILE $ORDERER_CONN_ARGS
   cp ${CHANNEL_NAME}.block /$DATA
}

# Enroll as a fabric admin and join the channel
function joinChannel {
   switchToAdminIdentity
   cd /$DATA
   set +e
   local COUNT=1
   MAX_RETRY=10
   while true; do
      log "Peer $PEER_NAME is attempting to join channel '$CHANNEL_NAME' (attempt #${COUNT}) ..."
      peer channel join -b $CHANNEL_NAME.block
      if [ $? -eq 0 ]; then
         #set -e
         log "Peer $PEER_NAME successfully joined channel '$CHANNEL_NAME'"
         return
      fi
      if [ $COUNT -gt $MAX_RETRY ]; then
         log "Peer $PEER_NAME failed to join channel '$CHANNEL_NAME' in $MAX_RETRY retries"
         break
      fi
      COUNT=$((COUNT+1))
      sleep 1
   done
}

function installChaincode {
   switchToAdminIdentity
   log "Installing chaincode on $PEER_NAME ..."
   peer chaincode install -n marblescc -v 1.0 -p github.com/hyperledger/fabric-samples/chaincode/marbles02/go
}

function instantiateChaincode {
   switchToAdminIdentity
   log "Instantiating marbles chaincode on $PEER_HOST ..."
   peer chaincode instantiate -C $CHANNEL_NAME -n marblescc -v 1.0 -c '{"Args":["init"]}' -P "$POLICY" $ORDERER_CONN_ARGS
}

function chaincodeInit {
   log "Initialising marbles on $PEER_NAME ..."
   peer chaincode invoke -C $CHANNEL_NAME -n marblescc -c '{"Args":["initMarble","marble1","blue","21","edge"]}' $ORDERER_CONN_ARGS
   peer chaincode invoke -C $CHANNEL_NAME -n marblescc -c '{"Args":["initMarble","marble2","red","27","braendle"]}' $ORDERER_CONN_ARGS
}

function chaincodeQuery {
   set +e
   log "Querying marbles chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode query -C $CHANNEL_NAME -n marblescc -c '{"Args":["readMarble","marble1"]}' >& log.txt
   cat log.txt
   peer chaincode query -C $CHANNEL_NAME -n marblescc -c '{"Args":["readMarble","marble2"]}' >& log.txt
   cat log.txt
   log "Successfully queried marbles chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function transferMarble {
   set +e
   log "Transferring marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode invoke -C $CHANNEL_NAME -n marblescc -c '{"Args":["transferMarble","marble2","edge"]}' $ORDERER_CONN_ARGS
   log "Successfully transferred marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function transferMarbleAgain {
   set +e
   log "Transferring marbles again in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode invoke -C $CHANNEL_NAME -n marblescc -c '{"Args":["transferMarble","marble2","braendle"]}' $ORDERER_CONN_ARGS
   log "Successfully transferred marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function makePolicy  {
   POLICY="OR("
   local COUNT=0
   for ORG in $PEER_ORGS; do
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

function installFabricCA {
    # Install fabric-ca. Recent versions of Hyperledger Fabric Docker images do not include fabric-ca-tools, fabric-ca-peer, etc., where the
    # fabric-ca-client is included. So we will need to build fabric-ca-client ourselves.
    log "Installing fabric-ca-client"

#    wget https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz
#    tar -xzf go1.10.3.linux-amd64.tar.gz
#    mv go /usr/local
#    sleep 5
#    export GOROOT=/usr/local/go
#    export GOPATH=$HOME/go
#    export PATH=$GOROOT/bin:$PATH
#    apt-get update
#    apt-get install git-core -y
#    apt-get install libtool libltdl-dev -y
#    apt-get install build-essential -y
#    sleep 5
    go get -u github.com/hyperledger/fabric-ca/cmd/...
    sleep 10
    cd $HOME/go/src/github.com/hyperledger/fabric-ca
    make fabric-ca-client
    sleep 5
    export PATH=$PATH:$HOME/go/src/github.com/hyperledger/fabric-ca/bin

    log "Install complete - fabric-ca-client"
}

main
