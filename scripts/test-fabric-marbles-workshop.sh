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

# There are various different versions of the Marbles chaincode, and some versions vary dramatically in terms of
# their interface.
#
# This script installs, instantiates and tests the Marbles chaincode that comes with the Marbles client application,
# found here: https://github.com/IBM-Blockchain/marbles/tree/master/chaincode/src/marbles
#
# This version should be installed if you want to run the workshop. See the README under workshop-remote-peer
#
# The only difference between this and test-fabric-marbles.sh is the ID's used when creating owners and marbles.
# I do this to ensure they can both be run against the same network without throwing exceptions due to duplicate owners.

set +e

source $(dirname "$0")/env.sh
CHAINCODE_NAME=marbles-workshop

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

   # Create the channel
   createChannel

   # All peers join the channel
   for ORG in $PEER_ORGS; do
      local COUNT=1
      while [[ "$COUNT" -le $NUM_PEERS ]]; do
         initPeerVars $ORG $COUNT
         joinChannel
         COUNT=$((COUNT+1))
      done
   done

   # Update the anchor peers
   for ORG in $PEER_ORGS; do
      initPeerVars $ORG 1
      switchToAdminIdentity
      updateAnchorPeers
   done

   # Install chaincode on the peers
   for ORG in $PEER_ORGS; do
      local COUNT=1
      while [[ "$COUNT" -le $NUM_PEERS ]]; do
          initPeerVars $ORG $COUNT
          installChaincode
          COUNT=$((COUNT+1))
      done
   done

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

# Enroll as a fabric admin and join the channel
function joinChannel {
   switchToAdminIdentity
   set +e
   local COUNT=1
   MAX_RETRY=10
   local CHANNELLIST=`peer channel list | grep -c ${CHANNEL_NAME}`
   cd /$DATA
   if [ $CHANNELLIST -gt 0 ]; then
       log "Peer $PEER_NAME has already joined channel '$CHANNEL_NAME' - channel join request ignored"
       return
   fi
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

function updateAnchorPeers {
    log "Updating anchor peers for $PEER_HOST ..."
    peer channel update -c $CHANNEL_NAME -f $ANCHOR_TX_FILE $ORDERER_CONN_ARGS
}

function installChaincode {
   switchToAdminIdentity
   log "Installing chaincode on $PEER_NAME ..."
   peer chaincode install -n $CHAINCODE_NAME -v 1.0 -p github.com/hyperledger/marbles/chaincode/src/marbles
}

function instantiateChaincode {
   switchToAdminIdentity
   log "Instantiating marbles chaincode on $PEER_HOST ..."
   peer chaincode instantiate -C $CHANNEL_NAME -n $CHAINCODE_NAME -v 1.0 -c '{"Args":["init"]}' -P "$POLICY" $ORDERER_CONN_ARGS
}

function chaincodeInit {
   log "Initialising marbles on $PEER_NAME ..."
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_owner","o9999999999999999990","edge", "United Marbles"]}' $ORDERER_CONN_ARGS
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_owner","o9999999999999999991","braendle", "United Marbles"]}' $ORDERER_CONN_ARGS
   sleep 5
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_marble","m999999999990", "blue", "50", "o9999999999999999990", "United Marbles"]}' $ORDERER_CONN_ARGS
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["init_marble","m999999999991", "red", "35", "o9999999999999999991", "United Marbles"]}' $ORDERER_CONN_ARGS
}

function chaincodeQuery {
   set +e
   log "Querying marbles chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   cd /$DATA
   peer chaincode query -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["read_everything"]}' >& log-marblesw.txt
   cat log-marblesw.txt
   log "Successfully queried marbles chaincode in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function transferMarble {
   set +e
   log "Transferring marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["set_owner","m999999999991","o9999999999999999990", "United Marbles"]}' $ORDERER_CONN_ARGS
   log "Successfully transferred marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
}

function transferMarbleAgain {
   set +e
   log "Transferring marbles in the channel '$CHANNEL_NAME' on the peer '$PEER_NAME' ..."
   peer chaincode invoke -C $CHANNEL_NAME -n $CHAINCODE_NAME -c '{"Args":["set_owner","m999999999991","o9999999999999999991", "United Marbles"]}' $ORDERER_CONN_ARGS
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
