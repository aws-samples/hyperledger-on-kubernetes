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

#
# This script does the following:
# 1) registers peers with intermediate fabric-ca-servers
#

function main {
   export ORG=$PEERORG
   log "Registering peer for org $ORG ..."
   registerPeerIdentities
   log "Finished registering peer for org $ORG"
}

# Enroll the CA administrator
function enrollCAAdmin {
   initOrgVars $ORG
   log "Enrolling with $CA_NAME as bootstrap identity ..."
   export FABRIC_CA_CLIENT_HOME=$HOME/cas/$CA_NAME
   export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
   fabric-ca-client enroll -d -u https://$CA_ADMIN_USER_PASS@$CA_HOST:7054
}

# Register any identities associated with a peer
function registerPeerIdentities {
    initOrgVars $ORG
    enrollCAAdmin
    local COUNT=1
    while [[ "$COUNT" -le $NUM_PEERS ]]; do
        initPeerVars $ORG $COUNT
        log "##### Registering $PEER_NAME with $CA_NAME. Executing: fabric-ca-client register -d --id.name $PEER_NAME --id.secret $PEER_PASS --id.type peer"
        fabric-ca-client register -d --id.name $PEER_NAME --id.secret $PEER_PASS --id.type peer
        COUNT=$((COUNT+1))
    done
}

set -e

SDIR=$(dirname "$0")
source $SDIR/env.sh

main
