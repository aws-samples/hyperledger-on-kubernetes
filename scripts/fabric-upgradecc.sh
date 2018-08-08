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
       echo "File '$file' exists - peer '$PEERORG' admin is upgrading CC for new/deleted org '$NEW_ORG'"
       cloneFabricSamples

       log "Updating the endorsement policy for the chaincode for the new org '$NEW_ORG'"

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       makePolicy
       initPeerVars ${PEERORG} 1
       switchToAdminIdentity
       upgradeCC

       log "Congratulations! You have updated the endorsement policy that allows the new/deleted org '$NEW_ORG' to endorse TX"

    else
        echo "File '$file' does not exist - no new org CC will be updated - exiting"
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

# once the chaincode is upgraded, queries and invoke TX will automatically use the new version. It is not possible to specify
# a version when executing chaincode - the latest valid version will be used.
function upgradeCC {
   getChaincodeVersion
   MAXCCVERSION=$((MAXCCVERSION+1))
   log "Upgrade chaincode mycc, version '$MAXCCVERSION' on channel '$CHANNEL_NAME' on '$PEER_HOST'"
   peer chaincode upgrade -C $CHANNEL_NAME -n mycc -v $MAXCCVERSION -c '{"Args":["init","a","100","b","200"]}' -P "$POLICY" $ORDERER_CONN_ARGS
}

function getChaincodeVersion {
   switchToAdminIdentity
   log "Getting chaincode version on $PEER_HOST ..."
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
