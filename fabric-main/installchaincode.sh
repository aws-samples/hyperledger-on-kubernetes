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

function installCCOrgFabric {
    log "Installing chaincode on Fabric in K8s"
    peerorgs=($PEER_ORGS)
    # install a new version of the chaincode on all peers. This will start a pod in each org namespace, which will
    # install the chaincode on the peers in that org
    for ORG in $PEER_ORGS; do
        log "'$ORG' is installing a new version of the chaincode"
        getDomain $ORG
        kubectl apply -f $REPO/k8s/fabric-job-installcc-$ORG.yaml --namespace $DOMAIN
        confirmJobs "fabric-installcc"
        if [ $? -eq 1 ]; then
            log "Job fabric-job-installcc-$ORG.yaml failed; exiting"
            exit 1
        fi
        #domain is overwritten by confirmJobs, so we look it up again
        getDomain $ORG
        for i in {1..10}; do
            if kubectl logs jobs/fabric-installcc --namespace $DOMAIN --tail=10 | grep -q "Congratulations! The org has installed the chaincode"; then
                log "The org has installed the chaincode in job fabric-job-installcc-$ORG.yaml"
                break
            else
                log "Waiting for fabric-job-installcc-$ORG.yaml to complete"
                sleep 5
            fi
        done
    done
}

function upgradeCCOrgFabric {
    log "Upgrading chaincode and endorsement policy on Fabric in K8s"
    getAdminOrg
    getDomain $ADMINORG
    kubectl apply -f $REPO/k8s/fabric-job-upgradecc-$ADMINORG.yaml --namespace $DOMAIN
    confirmJobs "fabric-upgradecc"
    if [ $? -eq 1 ]; then
        log "Job fabric-job-upgradecc-$ADMINORG.yaml failed; exiting"
        exit 1
    fi
    #domain is overwritten by confirmJobs, so we look it up again
    getDomain $ADMINORG
    for i in {1..10}; do
        if kubectl logs jobs/fabric-upgradecc --namespace $DOMAIN --tail=10 | grep -q "Congratulations! You have updated the endorsement policy"; then
            log "Channel endorsement policy updated by fabric-job-upgradecc-$ADMINORG.yaml"
            break
        else
            log "Waiting for fabric-job-upgradecc-$ADMINORG.yaml to complete"
            sleep 5
        fi
    done
}


function confirmJobs {
    log "Checking whether all jobs are ready"

    for TMPORG in $ORGS; do
        getDomain $TMPORG
        NUMPENDING=$(kubectl get jobs --namespace $DOMAIN | awk '{print $3}' | grep 0 | wc -l | awk '{print $1}')
        local COUNT=1
        while [ "${NUMPENDING}" != "0" ]; do
            echo "Waiting on pending jobs in namespace '$DOMAIN'. Jobs pending = ${NUMPENDING}"
            NUMPENDING=$(kubectl get jobs --namespace $DOMAIN | awk '{print $3}' | grep 0 | wc -l | awk '{print $1}')
            sleep 3
            # if a job name was passed to this function, check the job status
            if [ $# -gt 0 ]; then
                COUNT=$((COUNT+1))
                if (( $COUNT % 5 == 0 )); then
                    # check for the pod status: e.g. Pods Statuses:  0 Running / 0 Succeeded / 6 Failed
                    NUMFAILED=$(kubectl describe jobs/$1 --namespace $DOMAIN | grep "Pods Statuses" | awk '{print $9}')
                    if [ $NUMFAILED -gt 0 ]; then
                        echo "'$NUMFAILED' jobs with name '$1' have failed so far in namespace '$DOMAIN'. After 6 failures we will exit"
                    fi
                    if [ $NUMFAILED -eq 6 ]; then
                        echo "'$NUMFAILED' jobs with name '$1' have failed in namespace '$DOMAIN'. We will exit"
                        return 1
                    fi

                fi
            fi
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

function stopInstallJobsFabric {
    log "Stopping Install CC Jobs on Fabric in K8s"
    set +e
    # we take a brute-force approach here and just delete all the jobs, even though not all jobs
    # run in all org namespaces. Since there is no 'set -e' in this script, it will continue
    # if there are errors
    for ORG in $PEER_ORGS; do
        getDomain $ORG
        kubectl delete -f $REPO/k8s/fabric-job-upgradecc-$ORG.yaml --namespace $DOMAIN
        kubectl delete -f $REPO/k8s/fabric-job-installcc-$ORG.yaml --namespace $DOMAIN
    done
    confirmDeploymentsStopped fabric-installcc
    confirmDeploymentsStopped fabric-upgradecc
    set -e
}

DATA=/opt/share
SCRIPTS=$DATA/rca-scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
source $HOME/$REPO/fabric-main/utilities.sh
