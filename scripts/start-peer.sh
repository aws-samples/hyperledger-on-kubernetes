#!/bin/bash
# Copyright 2018-2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

source $(dirname "$0")/env.sh

log "Preparing to start peer '$CORE_PEER_ID', host '$PEER_HOST', enrolled via '$ENROLLMENT_URL' with MSP at '$CORE_PEER_MSPCONFIGPATH'"

# Install fabric-ca. Recent version of Hyperledger Fabric do not include a fabric-ca-tools, fabric-ca-peer, etc., where the
# fabric-ca-client is included. So we will need to build fabric-ca-client ourselves.
log "Installing fabric-ca-client"

wget https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz
tar -xzf go1.10.3.linux-amd64.tar.gz
mv go /usr/local
sleep 5
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$PATH
export PATH=$PATH:$HOME/go/src/github.com/hyperledger/fabric-ca/bin
apt-get update
apt-get install git-core -y
apt-get install libtool libltdl-dev -y
apt-get install build-essential -y
sleep 5
go get -u github.com/hyperledger/fabric-ca/cmd/...
sleep 10
cd $HOME/go/src/github.com/hyperledger/fabric-ca
make fabric-ca-client
sleep 5
export PATH=$PATH:$HOME/go/src/github.com/hyperledger/fabric-ca/bin

log "Install complete - fabric-ca-client"

# Although a peer may use the same TLS key and certificate file for both inbound and outbound TLS,
# we generate a different key and certificate for inbound and outbound TLS simply to show that it is permissible

# Generate server TLS cert and key pair for the peer
fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $PEER_HOST

# Copy the TLS key and cert to the appropriate place
TLSDIR=$PEER_HOME/tls
mkdir -p $TLSDIR
cp /tmp/tls/signcerts/* $CORE_PEER_TLS_CERT_FILE
cp /tmp/tls/keystore/* $CORE_PEER_TLS_KEY_FILE
rm -rf /tmp/tls

# Generate client TLS cert and key pair for the peer
genClientTLSCert $PEER_HOST $CORE_PEER_TLS_CLIENTCERT_FILE $CORE_PEER_TLS_CLIENTKEY_FILE

# Generate client TLS cert and key pair for the peer CLI
genClientTLSCert $PEER_HOST /$DATA/tls/$PEER_NAME-cli-client.crt /$DATA/tls/$PEER_NAME-cli-client.key

# Enroll the peer to get an enrollment certificate and set up the core's local MSP directory
fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $CORE_PEER_MSPCONFIGPATH
sleep 10
finishMSPSetup $CORE_PEER_MSPCONFIGPATH
copyAdminCert $CORE_PEER_MSPCONFIGPATH

# Start the peer
log "Starting peer '$CORE_PEER_ID' with MSP at '$CORE_PEER_MSPCONFIGPATH'"
env | grep CORE
peer node start
