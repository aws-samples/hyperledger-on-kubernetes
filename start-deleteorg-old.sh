#!/usr/bin/env bash

set -e

SDIR=$(dirname "$0")
cp $SDIR/scripts/envaddorgs.sh $SDIR/scripts/env.sh
source $SDIR/scripts/env.sh
DATA=/opt/share/
REPO=hyperledger-on-kubernetes

# this value must be changed here, in gen-workshop-remote-peer.sh and in fabric-job-delete-org.yaml
ORGTODELETE="org2"
ORG=$ORGTODELETE

function main {
    log "Beginning delete org in Hyperledger Fabric on Kubernetes ..."
    updateRepo
    genTemplates
    copyScripts

    #Now we need to update the channel config, and join the peer to the channel
    startDeleteOrgFabric

    #Now we can stop the rest
    stopPeers
    stopRegisterPeers
    stopICA
    stopRCA
    stopPVC
    removeNamespaces
    removeDirs
    whatsRunning
    log "Delete of org in Hyperledger Fabric on Kubernetes complete"
}

function updateRepo {
    log "Updating repo $REPO at $SDIR"
    cd $HOME
    if [ ! -d $REPO ]; then
        # clone repo, if it hasn't already been cloned
        git clone https://github.com/MCLDG/$REPO.git
    else
        # update repo, if it has already been cloned
        cd $REPO
        git pull
    fi
    cd $HOME
}

function genTemplates {
    log "Generating K8s YAML deployment files"
    cd $HOME/$REPO
    fabric-main/gen-fabric.sh
}

function copyScripts {
    log "Copying scripts folder from $REPO to $DATA"
    cd $HOME
    sudo cp $SDIR/$REPO/scripts/* $DATA/rca-scripts/
}

function startDeleteOrgFabric {
    log "Deleting org $ORG in Fabric in K8s"
    orgsarr=($PEER_ORGS)
    kubectl apply -f $REPO/k8s/fabric-deployment-addorg-fabric-delete-org-${orgsarr[0]}.yaml
#    sleep 10
    # the other peer admins must sign the new org config update.
    # these were already started - need to figure out a way to re-trigger then
    # perhaps they loop infinitely and check for a file in a dir; if there, they sign it
#    for ORG in $PEER_ORGS; do
#        #config update is already signed by the first org, so skip it
#        if [[ "$ORG" == "${orgsarr[0]}" ]]; then
#            continue
#        fi
#        log "'$ORG' is signing the addorg config update"
#        kubectl apply -f $REPO/k8s/fabric-deployment-addorg-fabric-sign-$ORG.yaml
#        sleep 5
#    done
}

function removeDirs {
    log "Removing directories at $DATA"
    cd $DATA
    sudo rm -rf rca-data/orgs/$ORG
    sudo rm -rf rca-$ORG
    sudo rm -rf ica-$ORG
}

function removeNamespaces {
    log "Deleting K8s namespaces"
    cd $HOME
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-namespace-$ORG.yaml
}

function stopPVC {
    log "Stopping PVC in K8s"
    cd $HOME
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-$ORG.yaml
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-$ORG.yaml
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-$ORG.yaml
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-$ORG.yaml
}

function stopRCA {
    log "Stopping RCA in K8s"
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-$ORG.yaml
    confirmDeploymentsStopped rca
}

function stopICA {
    log "Stopping ICA in K8s"
    kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-$ORG.yaml
    confirmDeploymentsStopped ica
}

function stopRegisterPeers {
    log "Stopping Registering Fabric Peers"
    kubectl delete -f $REPO/k8s/fabric-deployment-register-peer-$ORG.yaml
    confirmDeploymentsStopped register-p
}

function stopPeers {
    log "Stopping Peers in K8s"
    local COUNT=1
    while [[ "$COUNT" -le $NUM_PEERS ]]; do
        kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer$COUNT-$ORG.yaml
        COUNT=$((COUNT+1))
    done
    confirmDeploymentsStopped peer
}


function confirmDeploymentsStopped {
    if [ $# -ne 1 ]; then
        echo "Usage: confirmDeploymentsStopped <deployment>"
        exit 1
    fi
    DEPLOY=$1

    log "Checking whether all pods have stopped"

    NUMPENDING=$(kubectl get po -n $ORG | grep $DEPLOY | awk '{print $5}' | wc -l | awk '{print $1}')
    while [ "${NUMPENDING}" != "0" ]; do
        echo "Waiting on deployments matching $DEPLOY in namespace $ORG to stop. Deployments pending = ${NUMPENDING}"
        NUMPENDING=$(kubectl get po -n $ORG | grep $DEPLOY | awk '{print $5}' | wc -l | awk '{print $1}')
        sleep 3
    done
}

function whatsRunning {
    log "Check what is running"
    kubectl get deploy -n $ORG
    kubectl get po -n $ORG
}

main

