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
    log "Beginning delete of org '$DELETE_ORG' in Hyperledger Fabric on Kubernetes ..."
    stopJobsFabric $HOME $REPO
    updateRepo $HOME $REPO
    # don't want to do this. It will result in the yaml files for the deleted org being removed, meaning we can't stop the org
    #genTemplates $HOME $REPO
    #makeDirs $DATA
    # don't want to do this. It will overwrite the new env.sh we have just created.
    #copyScripts $HOME $REPO $DATA
    updateChannelArtifacts $HOME $REPO

    #Now we need to update the channel config
    set +e
    deleteOrgFabric
    local res=$?
    echo "Result of deleteOrgFabric is: '$res'"
    if [ $res -eq 1 ]; then
        log "Job fabric-job-delete-org-$ADMINORG.yaml did not achieve a successful completion - check the logs; exiting"
        return 1
    elif [ $res -eq 0 ]; then
        signConfOrgFabric $HOME $REPO
        getAdminOrg
        updateConfOrgFabric $HOME $REPO $ADMINORG
        set +e
        installCCOrgFabric
        upgradeCCOrgFabric
    fi
    #Now we can stop the rest
    stopPeers $HOME $REPO $DELETE_ORG
    stopRegisterPeers $HOME $REPO $DELETE_ORG
    stopICA $HOME $REPO $DELETE_ORG
    stopRCA $HOME $REPO $DELETE_ORG
    stopPVC $HOME $REPO $DELETE_ORG
    removeNamespaces $HOME $REPO $DELETE_DOMAIN
    removeDirsForOrg $DATA $DELETE_ORG
    whatsRunning
    log "Delete of org in Hyperledger Fabric on Kubernetes complete"
}

function deleteOrgFabric {
    getAdminOrg
    log "Admin Org is '$ADMINORG'"
    getDomain $ADMINORG
    log "Admin Org domain is '$DOMAIN'"
    log "Starting delete of org '$DELETE_ORG' in Fabric in K8s. Running job '$REPO/k8s/fabric-job-delete-org-$ADMINORG.yaml' in namespace '$DOMAIN'"
    kubectl apply -f $REPO/k8s/fabric-job-delete-org-$ADMINORG.yaml --namespace $DOMAIN
    confirmJobs "fabric-delete-org"
    if [ $? -eq 1 ]; then
        log "Job fabric-job-delete-org-$ADMINORG.yaml failed; exiting"
        return 1
    fi

    #domain is overwritten by confirmJobs, so we look it up again
    getDomain $ADMINORG
    # check whether the setup of the new org has completed
    for i in {1..10}; do
        if kubectl logs jobs/fabric-delete-org --namespace $DOMAIN --tail=10 | grep -q "Congratulations! The config file for deleting the org '$DELETE_ORG'"; then
            log "Starting the delete of org '$DELETE_ORG' by fabric-job-delete-org-$ADMINORG.yaml"
            return 0
        elif kubectl logs jobs/fabric-delete-org --namespace $DOMAIN --tail=10 | grep -q "Org '$DELETE_ORG' does not exist in the channel config"; then
            log "Org '$DELETE_ORG' does not exist in the channel config - I will cleanup but will not attempt to update the channel config"
            return 99
        else
            log "Waiting for fabric-job-delete-org-$ADMINORG.yaml to complete"
            sleep 5
        fi
    done
    return 1
}

# this script deletes an org from the Fabric network. The org and its domain are captured in the
# 2 ENV variables below.
DELETE_ORG="org2"
DELETE_DOMAIN="org2"
DATA=/opt/share

# create a temp file. The scripts/deleteorg* shell scripts will check for files; if they find them
# they will setup, join, sign, etc., as necessary.
# this is a cheap and nasty way of sending events. I should change this to use SNS or some other
# mechanism for sending events between the different containers.
cat > ${DATA}/rca-data/updateorg << EOF
${DELETE_ORG}
EOF

SDIR=$(dirname "$0")
SCRIPTS=$DATA/rca-scripts
source $SDIR/gen-env-file.sh
genNewEnvDeleteOrg $DELETE_ORG $DELETE_DOMAIN $SCRIPTS
sudo cp $SCRIPTS/envdeleteorgs.sh $SCRIPTS/env.sh
source $SCRIPTS/env.sh
source $SDIR/util-prep.sh
source $SDIR/utilities.sh
source $SDIR/signorgconfig.sh
source $SDIR/installchaincode.sh
log "PEER_ORGS at start of deleteorg.sh: '$PEER_ORGS'"
log "PEER_DOMAINS at start of deleteorg.sh: '$PEER_DOMAINS'"
DATA=/opt/share/
REPO=hyperledger-on-kubernetes
set +e
main

