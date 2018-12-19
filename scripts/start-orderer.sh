#!/bin/bash
# Copyright 2018-2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

source $(dirname "$0")/env.sh

log "Preparing to start orderer host '$ORDERER_HOST:$ORDERER_PORT', enrolled via '$ENROLLMENT_URL' with MSP at '$ORDERER_GENERAL_LOCALMSPDIR'"

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

# Enroll to get orderer's TLS cert (using the "tls" profile)
fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $ORDERER_HOST

# Copy the TLS key and cert to the appropriate place
TLSDIR=$ORDERER_HOME/tls
mkdir -p $TLSDIR
cp /tmp/tls/keystore/* $ORDERER_GENERAL_TLS_PRIVATEKEY
cp /tmp/tls/signcerts/* $ORDERER_GENERAL_TLS_CERTIFICATE
rm -rf /tmp/tls

# Enroll again to get the orderer's enrollment certificate (default profile)
fabric-ca-client enroll -d -u $ENROLLMENT_URL -M $ORDERER_GENERAL_LOCALMSPDIR

# Finish setting up the local MSP for the orderer
finishMSPSetup $ORDERER_GENERAL_LOCALMSPDIR
copyAdminCert $ORDERER_GENERAL_LOCALMSPDIR

# Start the orderer
log "Starting orderer host '$ORDERER_HOST' with MSP at '$ORDERER_GENERAL_LOCALMSPDIR'"
env | grep ORDERER
orderer
