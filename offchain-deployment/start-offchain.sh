#!/usr/bin/env bash

set -e
OFFCHAINDEPLOYDIR=offchain_services

function genBLDepl {
    for ORG in $PEER_ORGS; do
        getDomain $ORG
        sed -e "s/%ORG%/${ORG}/g" -e "s/%DOMAIN%/${DOMAIN}/g" ${K8STEMPLATES}/blserver.yaml > ${OFFCHAINDEPLOYDIR}/blserver-$ORG.yaml
    done
}

function genIdentityDepl {
    for ORG in $PEER_ORGS; do
        getDomain $ORG
        sed -e "s/%ORG%/${ORG}/g" -e "s/%DOMAIN%/${DOMAIN}/g" ${K8STEMPLATES}/identity.yaml > ${OFFCHAINDEPLOYDIR}/identity-$ORG.yaml
    done
}

function genAnalyticsDepl {
    for ORG in $PEER_ORGS; do
        getDomain $ORG
        sed -e "s/%ORG%/${ORG}/g" -e "s/%DOMAIN%/${DOMAIN}/g" ${K8STEMPLATES}/analytics.yaml > ${OFFCHAINDEPLOYDIR}/analytics-$ORG.yaml
    done
}

function main {
    echo "Beginning deployment of offchain services on Kubernetes ..."
    cd $HOME/$REPO
    rm -rf $OFFCHAINDEPLOYDIR
    mkdir $OFFCHAINDEPLOYDIR
    genBLDepl
    genIdentityDepl
    genAnalyticsDepl
    echo "Setup of offchain services complete"
}

main
