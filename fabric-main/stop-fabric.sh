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

function main {
    log "Stopping Hyperledger Fabric on Kubernetes ..."
    cd $HOME
    stopJobsFabric $HOME $REPO
    set +e
    stopTest $HOME $REPO
    stopChannelArtifacts $HOME $REPO
    stopRegisterOrgs $HOME $REPO
    stopRegisterOrderers $HOME $REPO
    stopOrderer $HOME $REPO
    stopKafka $HOME $REPO
    for DELETE_ORG in $ORGS; do
        stopPeers $HOME $REPO $DELETE_ORG
        stopRegisterPeers $HOME $REPO $DELETE_ORG
        stopICA $HOME $REPO $DELETE_ORG
        stopRCA $HOME $REPO $DELETE_ORG
        stopPVC $HOME $REPO $DELETE_ORG
        getDomain $DELETE_ORG
        removeNamespaces $HOME $REPO $DOMAIN
    done
    kubectl delete pv --all
    removeDirs $DATA
    whatsRunning
    log "Hyperledger Fabric on Kubernetes stopped"
}

SDIR=$(dirname "$0")
DATA=/opt/share/
SCRIPTS=$DATA/rca-scripts
source $SCRIPTS/env.sh
source $SDIR/utilities.sh
DATA=/opt/share/
REPO=hyperledger-on-kubernetes
main
