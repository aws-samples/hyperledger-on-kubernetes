#!/usr/bin/env bash

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

# This script is used to start a remote peer, in a different account/region to the main Fabric network.
# See the README.md in the remote-peer folder for details.

set -e

function main {
    echo "Beginning setup of remote peer on Hyperledger Fabric on Kubernetes ..."
    cd $HOME/$REPO
    source fabric-main/util-prep.sh
    updateRepo $HOME $REPO
    mergeEnv $HOME $REPO $DATADIR $MERGEFILE
    copyScripts $HOME $REPO $DATADIR
    cd $HOME/$REPO
    source fabric-main/scripts/env.sh
    source fabric-main/utilities.sh
    makeDirsForOrg $DATADIR
    genTemplates $HOME $REPO
    createNamespaces $HOME $REPO
    startPVC $HOME $REPO
    startRCA $HOME $REPO
    startICA $HOME $REPO
    startRegisterPeers $HOME $REPO
    startRemotePeers $HOME $REPO
    joinaddorgFabric $HOME $REPO $NEW_ORG
    installChaincode $HOME $REPO $NEW_ORG
    testChaincode $HOME $REPO $NEW_ORG
    whatsRunning
    echo "Setup of remote peer on Hyperledger Fabric on Kubernetes complete"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
MERGEFILE=remote-peer/scripts/env-remote-peer.sh
main

