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

# these scripts add an org into the Fabric network. The org and its domain are captured in the
# 2 ENV variables below.
NEW_ORG="org7"
NEW_DOMAIN="org7"

function main {
    log "Step3: Creating channel config for new org $NEW_ORG ..."
    # Stop all jobs. Previous jobs would have either added/removed an org - they must be stopped
    # before we genTemplates. If the org structure has changed, the yaml files for the orgs may
    # have been deleted, e.g. if I previously removed an org, this org will not exist in env.sh
    # and genTemplates would therefore not generate a yaml for it. If I tried to delete this job
    # after run genTemplates, the yaml file would not exist and the delete would fail. However,
    # the job would still be running, and the routines that check for running jobs would run forever.
    stopJobsFabric $HOME $REPO

    # create a new configtx.yaml that includes the new org
    updateChannelArtifacts $HOME $REPO

    #Now we need to create the channel config to add the new org
    set +e
    startaddorgFabric
    SIGNCONFIG=$?
    if [ $SIGNCONFIG -eq 1 ]; then
        log "Step3: Job fabric-job-addorg-setup-$ORG.yaml did not achieve a successful completion - check the logs; exiting"
        return 1
    fi
    log "Step3: Creating channel config for new org $NEW_ORG complete"
}

function startaddorgFabric {
    log "Starting addorg Fabric in K8s"

    getAdminOrg
    getDomain $ADMINORG
    kubectl apply -f $REPO/k8s/fabric-job-addorg-setup-$ADMINORG.yaml --namespace $DOMAIN
    confirmJobs "addorg-fabric-setup"
    if [ $? -eq 1 ]; then
        log "Step3: Job fabric-job-addorg-setup-$ADMINORG.yaml failed; exiting"
        exit 1
    fi

    set +e
    #domain is overwritten by confirmJobs, so we look it up again
    getDomain $ADMINORG
    # check whether the setup of the new org has completed
    for i in {1..10}; do
        if kubectl logs jobs/addorg-fabric-setup --namespace $DOMAIN --tail=10 | grep -q "Congratulations! The config file for the new org"; then
            log "Step3: New org configuration created by fabric-job-addorg-setup-$ADMINORG.yaml"
            return 0
        elif kubectl logs jobs/addorg-fabric-setup --namespace $DOMAIN --tail=10 | grep -q "Org '$NEW_ORG' already exists in the channel config"; then
            log "Step3: Org '$NEW_ORG' already exists in the channel config - I will cleanup but will not attempt to update the channel config"
            return 99
        else
            log "Step3: Waiting for fabric-job-addorg-setup-$ADMINORG.yaml to complete"
            sleep 5
        fi
    done
    return 1
}

# create a temp file. The scripts/addorg* shell scripts will check for files; if they find them
# they will setup, join, sign, etc., as necessary.
# this is a cheap and nasty way of sending events. I should change this to use SNS or some other
# mechanism for sending events between the different containers.
DATADIR=/opt/share/
cat > ${DATADIR}/rca-data/updateorg << EOF
${NEW_ORG}
EOF

SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
source $HOME/$REPO/gen-env-file.sh
genNewEnvAddOrg $NEW_ORG $NEW_DOMAIN $SCRIPTS
sudo cp $SCRIPTS/envaddorgs.sh $SCRIPTS/env.sh
source $SCRIPTS/env.sh
source $HOME/$REPO/util-prep.sh
source $HOME/$REPO/utilities.sh
source $HOME/$REPO/signorgconfig.sh
source $HOME/$REPO/installchaincode.sh
log "Step3: PEER_ORGS at start of addorg.sh: '$PEER_ORGS'"
log "Step3: PEER_DOMAINS at start of addorg.sh: '$PEER_DOMAINS'"
main



