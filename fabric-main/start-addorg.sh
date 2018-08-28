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
    log "Beginning setup of a new org in Hyperledger Fabric on Kubernetes ..."
    # Stop all jobs. Previous jobs would have either added/removed an org - they must be stopped
    # before we genTemplates. If the org structure has changed, the yaml files for the orgs may
    # have been deleted, e.g. if I previously removed an org, this org will not exist in env.sh
    # and genTemplates would therefore not generate a yaml for it. If I tried to delete this job
    # after run genTemplates, the yaml file would not exist and the delete would fail. However,
    # the job would still be running, and the routines that check for running jobs would run forever.
    stopJobsFabric $HOME $REPO

    #updateRepo
    genTemplates $HOME $REPO
    makeDirs $DATA
    makeDirsForOrg $DATA
    # don't want to do this. It will overwrite the new env.sh we have just created.
    #copyScripts $HOME $REPO $DATA

    #create K8s objects for the new org
    createNamespaces $HOME $REPO
    startKafka $HOME $REPO
    startPVC $HOME $REPO
    startRCA $HOME $REPO
    startICA $HOME $REPO
    startRegisterOrderers $HOME $REPO
    startRegisterPeers $HOME $REPO
    updateChannelArtifacts $HOME $REPO

    #Now we need to update the channel config
    set +e
    startaddorgFabric
    SIGNCONFIG=$?
    if [ $SIGNCONFIG -eq 1 ]; then
        log "Job fabric-job-addorg-setup-$ORG.yaml did not achieve a successful completion - check the logs; exiting"
        return 1
    elif [ $SIGNCONFIG -eq 0 ]; then
        for ORG in $PEER_ORGS; do
            signConfOrgFabric $HOME $REPO $ORG $NEW_ORG
        done
        getAdminOrg
        updateConfOrgFabric $HOME $REPO $ADMINORG
    fi


    #Now we can start the new peers; we default to starting everything. With K8s, if it's
    #already running there will be no impact
    startOrderer $HOME $REPO
    startPeers $HOME $REPO
    startTest $HOME $REPO

    #Now we join the new org to the channel, and install/upgrade the chaincode
    if [ $SIGNCONFIG -eq 0 ]; then
        joinaddorgFabric $HOME $REPO $NEW_ORG
        stopInstallJobsFabric
        set +e
        installCCOrgFabric
        upgradeCCOrgFabric
    fi
    whatsRunning
    log "Setup of new org in Hyperledger Fabric on Kubernetes complete"
}

function startaddorgFabric {
    log "Starting addorg Fabric in K8s"

    getAdminOrg
    getDomain $ADMINORG
    kubectl apply -f $REPO/k8s/fabric-job-addorg-setup-$ADMINORG.yaml --namespace $DOMAIN
    confirmJobs "addorg-fabric-setup"
    if [ $? -eq 1 ]; then
        log "Job fabric-job-addorg-setup-$ADMINORG.yaml failed; exiting"
        exit 1
    fi

    set +e
    #domain is overwritten by confirmJobs, so we look it up again
    getDomain $ADMINORG
    # check whether the setup of the new org has completed
    for i in {1..10}; do
        if kubectl logs jobs/addorg-fabric-setup --namespace $DOMAIN --tail=10 | grep -q "Congratulations! The config file for the new org"; then
            log "New org configuration created by fabric-job-addorg-setup-$ADMINORG.yaml"
            return 0
        elif kubectl logs jobs/addorg-fabric-setup --namespace $DOMAIN --tail=10 | grep -q "Org '$NEW_ORG' already exists in the channel config"; then
            log "Org '$NEW_ORG' already exists in the channel config - I will cleanup but will not attempt to update the channel config"
            return 99
        else
            log "Waiting for fabric-job-addorg-setup-$ADMINORG.yaml to complete"
            sleep 5
        fi
    done
    return 1
}

# this script adds an org into the Fabric network. The org and its domain are captured in the
# 2 ENV variables below.
NEW_ORG="org3"
NEW_DOMAIN="org3"
DATA=/opt/share/

# create a temp file. The scripts/addorg* shell scripts will check for files; if they find them
# they will setup, join, sign, etc., as necessary.
# this is a cheap and nasty way of sending events. I should change this to use SNS or some other
# mechanism for sending events between the different containers.
cat > ${DATA}/rca-data/updateorg << EOF
${NEW_ORG}
EOF

SDIR=$(dirname "$0")
SCRIPTS=$DATA/rca-scripts
source $SDIR/gen-env-file.sh
genNewEnvAddOrg $NEW_ORG $NEW_DOMAIN $SCRIPTS
sudo cp $SCRIPTS/envaddorgs.sh $SCRIPTS/env.sh
source $SCRIPTS/env.sh
source $SDIR/util-prep.sh
source $SDIR/utilities.sh
source $SDIR/signorgconfig.sh
source $SDIR/installchaincode.sh
log "PEER_ORGS at start of addorg.sh: '$PEER_ORGS'"
log "PEER_DOMAINS at start of addorg.sh: '$PEER_DOMAINS'"
DATA=/opt/share/
REPO=hyperledger-on-kubernetes
main



