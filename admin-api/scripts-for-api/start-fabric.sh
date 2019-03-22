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

# Builds the main Fabric network on a Kubernetes cluster.
# This script can be rerun if it fails. It will simply rerun the K8s commands, which will have
# no impact if they've been run previously
set -e

function main {
    echo "Beginning setup of Hyperledger Fabric on Kubernetes ..."
    cd $HOME/$REPO/fabric-main
    source util-prep.sh
    updateRepo $HOME $REPO
    makeDirs $DATADIR
    # prevent overwriting env.sh if it exists. We use env.sh as a config - it contains the list of orgs in the network
    if [ -f "${SCRIPTS}/env.sh" ]; then
        echo "File ${SCRIPTS}/env.sh exists. I will NOT overwrite it. If you want to overwrite it, copy it manually. Note that I won't be overwriting any scripts in this directory"
    else
        copyScripts $HOME $REPO $DATADIR
    fi
    source $SCRIPTS/env.sh
    cd $HOME/$REPO/fabric-main
    source utilities.sh
    makeDirsForOrg $DATADIR
    genTemplates $HOME $REPO
    createNamespaces $HOME $REPO
    startKafka $HOME $REPO
    startPVC $HOME $REPO
    startRCA $HOME $REPO
    startICA $HOME $REPO
    startRegisterOrgs $HOME $REPO
    sleep 30
    startRegisterOrderers $HOME $REPO
    startRegisterPeers $HOME $REPO
    if [ $FABRIC_NETWORK_TYPE == "PROD" ]; then
        startOrdererNLB $HOME $REPO
        startAnchorPeerNLB $HOME $REPO
    fi
    if [ -f "${DATADIR}/rca-data/configtx.yaml" ]; then
        echo "File ${DATADIR}/rca-data/configtx.yaml exists. I will NOT overwrite it. If you want to overwrite it, copy it manually. This means I will also not be running gen-channel-artifacts.sh"
    else
        updateChannelArtifacts $HOME $REPO
    fi
    startOrderer $HOME $REPO
    startCLI $HOME $REPO
    startPeers $HOME $REPO
    if [ $FABRIC_NETWORK_TYPE == "PROD" ]; then
        checkNLBHealthy
    fi
    echo "starting next test case: ABAC"
    startTestABAC $HOME $REPO
    echo "sleeping for 1 minute before starting next test case: Marbles"
    sleep 60
    startTestMarbles $HOME $REPO
    echo "sleeping for 1 minute before starting next test case: Marbles Workshop"
    sleep 60
    startTestMarblesWorkshop $HOME $REPO
    whatsRunning
    echo "Setup of Hyperledger Fabric on Kubernetes complete"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
main

