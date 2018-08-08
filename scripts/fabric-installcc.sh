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
       echo "File '$file' exists - peer '$PEERORG' admin installing CC for a new/deleted org '$NEW_ORG'"
       log "Installing latest chaincode version on peers in org '$PEERORG'"

       cloneFabricSamples

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       export ORG=$PEERORG
       local COUNT=1
       while [[ "$COUNT" -le $NUM_PEERS ]]; do
            initPeerVars $ORG $COUNT
            installChaincode
            COUNT=$((COUNT+1))
       done

       log "Congratulations! The org has installed the chaincode version '$MAXCCVERSION' on peer '$PEERORG'"

    else
        echo "File '$file' does not exist - no new org will have chaincode installed - exiting"
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

function installChaincode {
   switchToAdminIdentity
   getChaincodeVersion
   MAXCCVERSION=$((MAXCCVERSION+1))
   log "MAXCCVERSION '$MAXCCVERSION'"
   if [[ $MAXINSTALLEDCCVERSION -ge $MAXCCVERSION ]]; then
        log "Installed chaincode version is '$MAXINSTALLEDCCVERSION', and we need '$MAXCCVERSION' on '$PEER_HOST', so no need to install"
   else
        log "Installing chaincode version '$MAXCCVERSION' on '$PEER_HOST'; currently at version '$MAXINSTALLEDCCVERSION'"
        peer chaincode install -n mycc -v $MAXCCVERSION -p github.com/hyperledger/fabric-samples/chaincode/abac/go
   fi
}

function getChaincodeVersion {
   switchToAdminIdentity
   env
   log "Getting chaincode version on $PEER_HOST ..."
   #find the max version number
   MAXINSTALLEDCCVERSION=0
   #We get the installed versions only to prevent us
   #from reinstalling if we've previously installed the latest version.
   while read -r line ; do
        echo "processing line '$line'"
        CCVERSION=`echo $line | awk '{print $4}' | cut -d "," -f 1 | cut -d "." -f 1`
        log "CCVERSION '$CCVERSION'"
        if [[ $CCVERSION -gt $MAXINSTALLEDCCVERSION ]]; then
            MAXINSTALLEDCCVERSION=$CCVERSION
        fi
   done < <(peer chaincode list --installed | grep mycc)
   log "MAXINSTALLEDCCVERSION '$MAXINSTALLEDCCVERSION'"

   #find the max version number
   MAXCCVERSION=0
   #We are interested in the chaincode instantiated
   #on the channel, not the version installed on the peer. Reason: we want the same
   #version on all peers, so we get the instantiated version and increment it
   while read -r line ; do
        CCVERSION=`echo $line | awk '{print $4}' | cut -d "," -f 1 | cut -d "." -f 1`
        log "CCVERSION '$CCVERSION'"
        if [[ $CCVERSION -gt $MAXCCVERSION ]]; then
            MAXCCVERSION=$CCVERSION
        fi
   done < <(peer chaincode list -C $CHANNEL_NAME --instantiated | grep mycc)
   log "MAXCCVERSION '$MAXCCVERSION'"
 }

function fatalr {
   log "FATAL: $*"
   exit 1
}

main
