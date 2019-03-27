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
REPO=https://github.com/Yolean/kubernetes-kafka.git
REPODIR=kubernetes-kafka
FABRICREPO=hyperledger-on-kubernetes
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts

function main {
    echo "Beginning setup of Kafka for Hyperledger Fabric on Kubernetes ..."
    getRepo
    startStorageService
    startZookeeper
    startExternalELB
    startKafka
#    testKafka
    whatsRunning
    echo "Setup of Kafka for Hyperledger Fabric on Kubernetes complete"
}

function getRepo {
    echo "Getting repo $REPO at $SDIR"
    cd $HOME
    if [ ! -d $REPODIR ]; then
        # clone repo, if it hasn't already been cloned
        git clone $REPO
        cd $REPODIR
        #git checkout tags/v3.2.0 - this works
        #git checkout tags/v3.1.0 - this doesn't work
        #git checkout tags/v3.0.0 - different folder structure - does not support AWS storage classes
        git checkout tags/v4.1.0
    fi
}

function startStorageService {
    echo "Starting storage service required for Kafka"
    cd $HOME/$REPODIR
    kubectl apply -f configure/aws-storageclass-zookeeper-gp2.yml
    kubectl apply -f configure/aws-storageclass-broker-gp2.yml
}

function startZookeeper {
    echo "Starting Zookeeper service"
    cd $HOME/$REPODIR
    kubectl apply -f 00-namespace.yml
    kubectl apply -f zookeeper/10zookeeper-config.yml
    kubectl apply -f zookeeper/20pzoo-service.yml
    kubectl apply -f zookeeper/21zoo-service.yml
    kubectl apply -f zookeeper/30service.yml
    kubectl apply -f zookeeper/50pzoo.yml
    kubectl apply -f zookeeper/51zoo.yml
}

function startExternalELB {
    echo "Starting External ELB service for Kafka brokers"
    cd $HOME/$FABRICREPO
    kubectl apply -f kafka/elb.yml
    #wait for service to be created and hostname to be available. This could take a few seconds
    ELBHOSTNAME=$(kubectl get svc external-broker -n kafka -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')
    ELBHOSTPORT=$(kubectl get svc external-broker -n kafka -o jsonpath='{.spec.ports[*].port}')
    while [[ "${ELBHOSTNAME}" != *"elb"* ]]; do
        echo "Waiting on Kafka to create service. Hostname = ${ELBHOSTNAME}"
        ELBHOSTNAME=$(kubectl get svc external-broker -n kafka -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')
        ELBHOSTPORT=$(kubectl get svc external-broker -n kafka -o jsonpath='{.spec.ports[*].port}')
        sleep 10
    done
    echo "Updating 50kafka-aws.yml and ${SCRIPTS}/gen-channel-artifacts.sh with hostname: ${ELBHOSTNAME}:${ELBHOSTPORT}"
    #update 50kafka.yml with the hostname. This is used in the external Kafka broker address
    sed -e "s/%ELBHOSTNAME%/${ELBHOSTNAME}:${ELBHOSTPORT}/g" -e "s/%KAFKA_SIZE%/${KAFKA_SIZE}/g" -e "s/%KAFKA_REPLICAS%/${KAFKA_REPLICAS}/g" kafka/50kafka.yml > kafka/50kafka-aws.yml
    #update env.sh with the Kafka Broker external hostname. This will be used in scripts/gen-channel-artifacts.sh, and
    # add the broker name to configtx.yaml
    echo "Updating env.sh with Kafka Broker endpoint: ${ELBHOSTNAME}"
    sed -e "s/EXTERNAL_KAFKA_BROKER=\"\"/EXTERNAL_KAFKA_BROKER=\"- ${ELBHOSTNAME}:${ELBHOSTPORT}\"/g" -i $SCRIPTS/env.sh

}

function startKafka {
    echo "Starting Kafka service"
    cd $HOME/$REPODIR
    kubectl apply -f kafka/10broker-config.yml
    kubectl apply -f kafka/20dns.yml
    kubectl apply -f kafka/30bootstrap-service.yml
    #override the 50kafka.yml in the repo
    kubectl apply -f $HOME/$FABRICREPO/kafka/50kafka-aws.yml
    #wait for Kafka to deploy. This could take a couple of minutes
    PODSPENDING=$(kubectl get pods --namespace=kafka | awk '{print $2}' | cut -d '/' -f1 | grep 0 | wc -l | awk '{print $1}')
    while [ "${PODSPENDING}" != "0" ]; do
        echo "Waiting on Kafka to deploy. Pods pending = ${PODSPENDING}"
        PODSPENDING=$(kubectl get pods --namespace=kafka | awk '{print $2}' | cut -d '/' -f1 | grep 0 | wc -l | awk '{print $1}')
        sleep 10
    done
}

function testKafka {
    echo "Testing the Kafka service"
    cd $HOME/$REPODIR
    kubectl apply -f kafka/test/
    #wait for the tests to complete. This could take a couple of minutes
    TESTSPENDING=$(kubectl get pods -l test-type=readiness --namespace=test-kafka | awk '{print $2}' | cut -d '/' -f1 | grep 0 | wc -l | awk '{print $1}')
    while [ "${TESTSPENDING}" != "0" ]; do
        echo "Waiting on Kafka test cases to complete. Tests pending = ${TESTSPENDING}"
        TESTSPENDING=$(kubectl get pods -l test-type=readiness --namespace=test-kafka | awk '{print $2}' | cut -d '/' -f1 | grep 0 | wc -l | awk '{print $1}')
        sleep 10
    done
}

function whatsRunning {
    echo "Check what is running"
    kubectl get all -n kafka
}

main

