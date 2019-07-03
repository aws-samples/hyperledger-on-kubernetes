#!/usr/bin/env bash

set -e
OFFCHAINDEPLOYDIR=offchain_services

function confirmDeployments {
    echo "Checking whether all deployments are ready"

    for TMPORG in $ORGS; do
        NUMPENDING=$(kubectl get deployments -n $TMPORG | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
        while [ "${NUMPENDING}" != "0" ]; do
            echo "Waiting on pending deployments in namespace $TMPORG. Deployments pending = ${NUMPENDING}"
            NUMPENDING=$(kubectl get deployments -n $TMPORG | awk '{print $5}' | grep 0 | wc -l | awk '{print $1}')
            sleep 3
        done
    done
}

function deployBLServer {
    # if [ $# -ne 1 ]; then
    #     echo "Usage: deployBLServer <home-dir>"
    #     exit 1
    # fi
    # local HOME=$1
    # local REPO=$2
    # cd $HOME

    for ORG in $PEER_ORGS; do
        log "Deploying BLServer on K8s for $ORG"
        kubectl apply -f $OFFCHAINDEPLOYDIR/blserver-$ORG.yaml
    done
    confirmDeployments
}

function deployIdentityServer {
    # if [ $# -ne 1 ]; then
    #     echo "Usage: deployIdentityServer <home-dir> <repo-name>"
    #     exit 1
    # fi
    # local HOME=$1
    # local REPO=$2
    # cd $HOME

    for ORG in $PEER_ORGS; do
        log "Deploying identity on K8s for $ORG"
        kubectl apply -f $OFFCHAINDEPLOYDIR/identity-$ORG.yaml
    done
    confirmDeployments
}

function deployAnalyticsServer {
    # if [ $# -ne 2 ]; then
    #     echo "Usage: deployAnalyticsServer <home-dir> <repo-name>"
    #     exit 1
    # fi
    # local HOME=$1
    # local REPO=$2
    # cd $HOME

    for ORG in $PEER_ORGS; do
        log "Deploying Analytics on K8s for $ORG"
        kubectl apply -f $OFFCHAINDEPLOYDIR/analytics-$ORG.yaml
    done
    confirmDeployments
}

function whatsRunning {
    echo "Check what is running"
    for TMPORG in $ORGS; do
        kubectl get deploy -n $TMPORG
        kubectl get po -n $TMPORG
    done
}

function main {
    echo "Beginning deployment of offchain services ..."
    # source ../fabric-main/utilities.sh
    echo "Deploying BL Server"
    deployBLServer $HOME $REPO
    echo "Deploying ID server"
    deployIdentityServer $HOME $REPO
    echo "Deploying Common Services"
    deployAnalyticsServer $HOME $REPO
    whatsRunning
    echo "Finished setup of offchain services"
}

# REPO=hyperledger-on-kubernetes
main
