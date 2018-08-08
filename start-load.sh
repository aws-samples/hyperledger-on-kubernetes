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

set -e

SDIR=$(dirname "$0")
DATA=/opt/share
SCRIPTS=$DATA/rca-scripts
source $SCRIPTS/env.sh
REPO=hyperledger-on-kubernetes

function main {
    log "Beginning setup of Hyperledger Fabric on Kubernetes ..."
    startLoad
    whatsRunning
    log "Setup of Hyperledger Fabric on Kubernetes complete"
}

function startLoad {
    log "Starting Load Test in K8s"
    cd $HOME
    orgsarr=($PEER_ORGS)
    ORG=${orgsarr[0]}
    kubectl apply -f $REPO/k8s/fabric-deployment-load-fabric-$ORG.yaml
    confirmDeployments
}

function confirmDeployments {
    log "Checking whether all deployments are ready"

    for ORG in $ORGS; do
        NUMPENDING=$(kubectl get deployments -n $ORG | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
        while [ "${NUMPENDING}" != "0" ]; do
            echo "Waiting on pending deployments in namespace $ORG. Deployments pending = ${NUMPENDING}"
            NUMPENDING=$(kubectl get deployments -n $ORG | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
            sleep 3
        done
    done
}

function whatsRunning {
    log "Check what is running"
    for ORG in $ORGS; do
        kubectl get deploy -n $ORG
        kubectl get po -n $ORG
    done
}

main

