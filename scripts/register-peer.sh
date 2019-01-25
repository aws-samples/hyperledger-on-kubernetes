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

        # Generate server TLS cert and key pair for the peer
        log "##### Generating server TLS certs and keys. Executing: fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $PEER_HOST"
        fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $PEER_HOST

        # Copy the TLS key and cert to the appropriate place
        TLSDIR=$PEER_HOME/tls
        mkdir -p $TLSDIR
        cp /tmp/tls/signcerts/* $CORE_PEER_TLS_CERT_FILE
        cp /tmp/tls/keystore/* $CORE_PEER_TLS_KEY_FILE
        rm -rf /tmp/tls

        # Generate client TLS cert and key pair for the peer
        log "##### Generating client TLS certs"
        genClientTLSCert $PEER_NAME $CORE_PEER_TLS_CLIENTCERT_FILE $CORE_PEER_TLS_CLIENTKEY_FILE

        # Generate client TLS cert and key pair for the peer CLI
        genClientTLSCert $PEER_NAME /$DATA/tls/$PEER_NAME-cli-client.crt /$DATA/tls/$PEER_NAME-cli-client.key

        # Enroll the peer to get an enrollment certificate and set up the core's local MSP directory
        log "##### Creating MSP for peer. Executing: fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $CORE_PEER_MSPCONFIGPATH"
        fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $CORE_PEER_MSPCONFIGPATH
        sleep 10
        finishMSPSetup $CORE_PEER_MSPCONFIGPATH
        copyAdminCert $CORE_PEER_MSPCONFIGPATH

        COUNT=$((COUNT+1))
    done
}

set -e

SDIR=$(dirname "$0")
source $SDIR/env.sh

main
