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

       log "Generating the channel config for new org '$NEW_ORG'"

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       initPeerVars ${PEERORG} 1

       generateNewOrgConfig
}

function generateNewOrgConfig() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    fatal "configtxgen tool not found. exiting"
  fi

  log "Printing the new Org configuration for '$NEW_ORG' at '/$DATA'. See the file " /${DATADIR}/$NEW_ORG.json
  export FABRIC_CFG_PATH=/$DATA
  cd $FABRIC_CFG_PATH
  configtxgen -printOrg $NEW_ORG > /${DATADIR}/$NEW_ORG.json
}

DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
echo "Args are: " $*
NEW_ORG=$1
main
