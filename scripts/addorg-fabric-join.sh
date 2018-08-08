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

source $(dirname "$0")/env.sh

function main {

    file=/${DATA}/updateorg
    if [ -f "$file" ]; then
       NEW_ORG=$(cat $file)
       echo "File '$file' exists - joining a new org '$NEW_ORG'"

       log "Organisation '$NEW_ORG' is joining the channel '$CHANNEL_NAME'"

       cloneFabricSamples

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       # All peers join the channel. Note that 'channel join' can only be performed after the peer has started
       # This is because the switchToAdminIdentity requires the peers TLS certs in order to join the channel,
       # and these are generated when the peer starts for the first time.
       export ORG=$NEW_ORG
       local COUNT=1
       while [[ "$COUNT" -le $NUM_PEERS ]]; do
            initPeerVars $ORG $COUNT
            joinChannel
            COUNT=$((COUNT+1))
       done

       log "Congratulations! The new org has joined the channel '$CHANNEL_NAME', new org '$NEW_ORG'"

    else
        echo "File '$file' does not exist - no new org will be joined to channel - exiting"
        exit 1
    fi
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

# Enroll as a fabric admin and join the channel
function joinChannel {
   switchToAdminIdentity
   set +e
   local COUNT=1
   MAX_RETRY=10
   while true; do
      log "Peer $PEER_HOST is attempting to join channel '$CHANNEL_NAME' (attempt #${COUNT}) ..."
      # note that we pass in the channel genesis block. Though this block does not contain the new org
      # we must start the ledger with the genesis block (i.e. block 0), not the latest config block
      output=$( peer channel join -b /$DATA/$CHANNEL_NAME.block 2>&1 )
      echo "output of peer channel join is '$output'"
      if [ $? -eq 0 ]; then
         set -e
         log "Peer $PEER_HOST successfully joined channel '$CHANNEL_NAME'"
         return
      fi
      if [[ $output == *"LedgerID already exists"* ]]; then
         log "Peer $PEER_HOST has previously joined channel '$CHANNEL_NAME'"
         return
      fi
      if [ $COUNT -gt $MAX_RETRY ]; then
         fatalr "Peer $PEER_HOST failed to join channel '$CHANNEL_NAME' in $MAX_RETRY retries"
      fi
      COUNT=$((COUNT+1))
      sleep 1
   done
}

function fatalr {
   log "FATAL: $*"
   exit 1
}

main
