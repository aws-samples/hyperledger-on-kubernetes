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

EFSSERVER=fs-c9141a61.efs.us-west-2.amazonaws.com
REPO=hyperledger-on-kubernetes
source $HOME/$REPO/fabric-main/gen-fabric-functions.sh
DATA=/opt/share

function main {
    log "Beginning creation of Hyperledger Fabric Kubernetes YAML files..."
    cd $HOME/$REPO
#    rm -rf $K8SYAML
    mkdir -p $K8SYAML
    file=${DATA}/rca-data/updateorg
    if [ -f "$file" ]; then
       NEW_ORG=$(cat $file)
       echo "File '$file' exists - gen_fabric.sh identifies a new org '$NEW_ORG', and will generate appropriate K8s YAML files"
    fi
    genFabricOrgs
    genNamespaces
    genPVC
    genRCA
    genICA
    genRegisterOrg
    genRegisterOrderer
    genRegisterPeers
    genChannelArtifacts
    genOrderer
    genPeers
    genRemotePeers
    genWorkshopRemotePeers
    genPeerJoinChannel
    genFabricTest
    genFabricTestMarbles
    genInstallMarblesCC
    genLoadFabric
    genLoadFabricMarbles
    genAddOrg
    genSignAddOrg
    genUpdateConfAddOrg
    genJoinAddOrg
    genInstallCCAddOrg
    genUpgradeCCAddOrg
    genTestCCAddOrg
    genFabricTestMarblesWorkshop
    genDeleteOrg
    genCLI
    log "Creation of Hyperledger Fabric Kubernetes YAML files complete"
}

main

