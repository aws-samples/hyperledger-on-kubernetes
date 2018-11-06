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

set +e

source $(dirname "$0")/env.sh
CHAINCODE_NAME=marblescc

function main {

   done=false

   cloneFabricSamples

   log "Test network using $CHAINCODE_NAME chaincode"

   IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
   # if we are running this script in an account remote from the main orderer account, make sure we use the
   # NLB endpoint for the orderer. Otherwise, assume we are running in the same K8s cluster as the orderer and use the local endpoint.
   if [[ -v $"REMOTE_PEER" ]]; then
       initOrdererVars ${OORGS[0]} 2
   else
       initOrdererVars ${OORGS[0]} 1
   fi
   export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

   # Convert PEER_ORGS to an array named PORGS
   IFS=', ' read -r -a PORGS <<< "$PEER_ORGS"

   # Instantiate chaincode
   makePolicy
   initPeerVars ${PORGS[0]} 1
   switchToAdminIdentity
   instantiateChaincode

   # Query chaincode
   switchToMarbleIdentity
   sleep 5
   chaincodeInit
   sleep 5
   chaincodeQuery

   # Invoke chaincode
   initPeerVars ${PORGS[0]} 1
   switchToMarbleIdentity
   transferMarble

   # Query chaincode
   sleep 10
   initPeerVars ${PORGS[0]} 1
   switchToMarbleIdentity
   chaincodeQuery

   # Invoke chaincode
   initPeerVars ${PORGS[0]} 1
   switchToMarbleIdentity
   transferMarbleAgain

   # Query chaincode
   sleep 10
   initPeerVars ${PORGS[0]} 1
   switchToMarbleIdentity
   chaincodeQuery

   log "Congratulations! $CHAINCODE_NAME chaincode tests ran successfully."

   done=true
}

# git clone fabric-samples. We need this repo for the chaincode
function cloneFabricSamples {
   log "clone Marbles app: https://github.com/IBM-Blockchain/marbles.git"
   mkdir -p /opt/gopath/src/github.com/hyperledger
   cd /opt/gopath/src/github.com/hyperledger
   git clone https://github.com/IBM-Blockchain/marbles.git
   log "cloned Marbles app"
   cd marbles
   mkdir /opt/gopath/src/github.com/hyperledger/fabric
}

function instantiateChaincode {
   switchToAdminIdentity
   log "Instantiating marbles chaincode on $PEER_HOST ..."
   peer chaincode instantiate -C $CHANNEL_NAME -n $CHAINCODE_NAME -v 1.0 -c '{"Args":["init"]}' -P "$POLICY" $ORDERER_CONN_ARGS
}

function chaincodeInit {
   log "Initialising marbles on $PEER_NAME ..."
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_owner","o3333333333333333330","edge2", "United Marbles"]}' $ORDERER_CONN_ARGS
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_owner","o3333333333333333331","braendle2", "United Marbles"]}' $ORDERER_CONN_ARGS
   sleep 5
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_marble","m333333333330", "green", "50", "o3333333333333333330", "United Marbles"]}' $ORDERER_CONN_ARGS
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_marble","m333333333331", "orange", "35", "o3333333333333333331", "United Marbles"]}' $ORDERER_CONN_ARGS
}

function chaincodeQuery {
   set +e
   log "Querying marbles chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode query -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["read_everything"]}' >& log.txt
   cat log.txt
   log "Successfully queried marbles chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function transferMarble {
   set +e
   log "Transferring marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["set_owner","m333333333331","o3333333333333333330", "United Marbles"]}' $ORDERER_CONN_ARGS
   log "Successfully transferred marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function transferMarbleAgain {
   set +e
   log "Transferring marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["set_owner","m333333333331","o3333333333333333331", "United Marbles"]}' $ORDERER_CONN_ARGS
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

main
