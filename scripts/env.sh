#!/bin/bash
# Copyright 2018-2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

#####################################################################################
# The following variables describe the topology and may be modified to provide
# different organization names or the number of peers in each peer organization.
#####################################################################################
##--BEGIN REPLACE CONTENTS--##
# This section may be replaced when creating a remote peer. See `start-remote-peer.sh`

# Type of network. Options are: POC or PROD
# If FABRIC_NETWORK_TYPE="PROD" I will generate NLB (network load balancers) to expose the orderers and anchor peers
# so they can communicate with remote peers located in other regions and/or accounts. This simulates a production network
# which consists of remote members, with peers on premise or on other Cloud platforms.
# If FABRIC_NETWORK_TYPE="POC" I will assume all peers and orderers are running in the same account / region and will
# assume local, in-cluster DNS using standard Kuberentes service names for lookup
FABRIC_NETWORK_TYPE="PROD"

# Names of the Orderer organizations. Regardless of the FABRIC_NETWORK_TYPE there will be a single
# Orderer org. You may change the names of the ORG and DOMAIN to match your organisation
ORDERER_ORGS="org0"
ORDERER_DOMAINS="org0"

# ORDERER_TYPE can be "kafka" or "solo". If you set this to Kafka, a Kafka/Zookeeper cluster will be created in
# the same AWS account as the orderer. Otherwise, you may choose 'solo'
# If FABRIC_NETWORK_TYPE="PROD", this should be set to kafka
ORDERER_TYPE="kafka"

# Names of the peer organizations.
PEER_ORGS="org1 org2"
PEER_DOMAINS="org1 org2"
PEER_PREFIX="peer"

# Number of peers in each peer organization
NUM_PEERS=1

##--END REPLACE CONTENTS--##
#####################################################################################
# The remainder of this file contains variables which typically would not be changed.
# The exception would be FABRIC_TAG, which you use to change to a different Fabric version.
#####################################################################################

# The tag of the docker images to download for Fabric CA and Fabric. Equates to the Fabric version
FABRIC_TAG="1.4"

# Leave these blank. They are populated by other scripts
EXTERNAL_ORDERER_ADDRESSES=""
EXTERNAL_ANCHOR_PEER_ADDRESSES=""
EXTERNAL_KAFKA_BROKER=""
EXTERNALORDERERHOSTNAME=""
EXTERNALORDERERPORT=""
declare -A RCA_PORTS_IN_USE
declare -A ICA_PORTS_IN_USE
declare -A ORDERER_PORTS_IN_USE
declare -A PEER_PORTS_IN_USE

# All org names
ORGS="$ORDERER_ORGS $PEER_ORGS"
DOMAINS="$ORDERER_DOMAINS $PEER_DOMAINS"

# Set to true to populate the "admincerts" folder of MSPs
ADMINCERTS=true

# Number of Orderer nodes. We generate 3 orderers as follows:
# 1) for peers connecting to the orderer locally, from within the same K8s cluster. No NLB is required for OSN #1
# 2) for peers connecting to the orderer remotely, via TLS. An NLB is required that handles TLS traffic
# 3) for client applications connecting to the orderer remotely, without TLS. An NLB is required that handles
NUM_ORDERERS=3

# The volume mount to share data between containers
DATA=data

# The path to the genesis block
GENESIS_BLOCK_FILE=/$DATA/genesis.block

# The path to a channel transaction
CHANNEL_TX_FILE=/$DATA/channel.tx

# Name of test channel
CHANNEL_NAME=mychannel

# Query timeout in seconds
QUERY_TIMEOUT=15

# Setup timeout in seconds (for setup container to complete)
SETUP_TIMEOUT=120

# Log directory
LOGDIR=$DATA/logs
LOGPATH=/$LOGDIR

# Affiliation is not used to limit users in this sample, so just put
# all identities in the same affiliation.
export FABRIC_CA_CLIENT_ID_AFFILIATION=org1

# Set to true to enable use of intermediate CAs
USE_INTERMEDIATE_CA=true

# Config block file path
CONFIG_BLOCK_FILE=/tmp/config_block.pb

# Update config block payload file path
CONFIG_UPDATE_ENVELOPE_FILE=/tmp/config_update_as_envelope.pb

# initOrgVars <ORG>
function initOrgVars {
   if [ $# -ne 1 ]; then
      echo "Usage: initOrgVars <ORG>"
      exit 1
   fi
   ORG=$1
   getDomain $ORG
   ORG_CONTAINER_NAME=${ORG//./-}
   ROOT_CA_HOST=rca-${ORG}.${DOMAIN}
#   ROOT_CA_HOST=rca-${ORG}
   ROOT_CA_NAME=rca-${ORG}.${DOMAIN}
   ROOT_CA_LOGFILE=$LOGDIR/${ROOT_CA_NAME}.log
   INT_CA_HOST=ica-${ORG}.${DOMAIN}
#   INT_CA_HOST=ica-${ORG}
   INT_CA_NAME=ica-${ORG}.${DOMAIN}
   INT_CA_LOGFILE=$LOGDIR/${INT_CA_NAME}.log

   # Root CA admin identity
   ROOT_CA_ADMIN_USER=rca-${ORG}-admin
   ROOT_CA_ADMIN_PASS=${ROOT_CA_ADMIN_USER}pw
   ROOT_CA_ADMIN_USER_PASS=${ROOT_CA_ADMIN_USER}:${ROOT_CA_ADMIN_PASS}
   # Root CA intermediate identity to bootstrap the intermediate CA
   ROOT_CA_INT_USER=ica-${ORG}
   ROOT_CA_INT_PASS=${ROOT_CA_INT_USER}pw
   ROOT_CA_INT_USER_PASS=${ROOT_CA_INT_USER}:${ROOT_CA_INT_PASS}
   # Intermediate CA admin identity
   INT_CA_ADMIN_USER=ica-${ORG}-admin
   INT_CA_ADMIN_PASS=${INT_CA_ADMIN_USER}pw
   INT_CA_ADMIN_USER_PASS=${INT_CA_ADMIN_USER}:${INT_CA_ADMIN_PASS}
   # Admin identity for the org
   ADMIN_NAME=admin-${ORG}
   ADMIN_PASS=${ADMIN_NAME}pw
   # Typical user identity for the org
   USER_NAME=user-${ORG}
   USER_PASS=${USER_NAME}pw
   # Marbles user identity for the org
   MARBLES_USER_NAME=marbles-${ORG}
   MARBLES_USER_PASS=${MARBLES_USER_NAME}pw

   ROOT_CA_CERTFILE=/${DATA}/${ORG}-ca-cert.pem
   INT_CA_CHAINFILE=/${DATA}/${ORG}-ca-chain.pem
   ANCHOR_TX_FILE=/${DATA}/orgs/${ORG}/anchors.tx
   ORG_MSP_ID=${ORG}MSP
   ORG_MSP_DIR=/${DATA}/orgs/${ORG}/msp
   ORG_ADMIN_CERT=${ORG_MSP_DIR}/admincerts/cert.pem
   ORG_ADMIN_HOME=/${DATA}/orgs/$ORG/admin

   if test "$USE_INTERMEDIATE_CA" = "true"; then
      CA_NAME=$INT_CA_NAME
      CA_HOST=$INT_CA_HOST
      CA_CHAINFILE=$INT_CA_CHAINFILE
      CA_ADMIN_USER_PASS=$INT_CA_ADMIN_USER_PASS
      CA_LOGFILE=$INT_CA_LOGFILE
   else
      CA_NAME=$ROOT_CA_NAME
      CA_HOST=$ROOT_CA_HOST
      CA_CHAINFILE=$ROOT_CA_CERTFILE
      CA_ADMIN_USER_PASS=$ROOT_CA_ADMIN_USER_PASS
      CA_LOGFILE=$ROOT_CA_LOGFILE
   fi
}

# initOrdererVars <NUM>
function initOrdererVars {
   if [ $# -ne 2 ]; then
      echo "Usage: initOrdererVars <ORG> <NUM>"
      exit 1
   fi
   ORG=$1
   NUM=$2
   initOrgVars $ORG
   getDomain $ORG
   if [ $FABRIC_NETWORK_TYPE == "PROD" ] && [[ -v $"REMOTE_PEER" ]]; then
     ORDERER_HOST=$EXTERNALORDERERHOSTNAME
     ORDERER_PORT=$EXTERNALORDERERPORT
   else
     ORDERER_HOST=orderer${NUM}-${ORG}.${DOMAIN}
     ORDERER_PORT=7050
   fi
   ORDERER_NAME=orderer${NUM}-${ORG}
   ORDERER_PASS=${ORDERER_NAME}pw
   ORDERER_NAME_PASS=${ORDERER_NAME}:${ORDERER_PASS}
   ORDERER_LOGFILE=$LOGDIR/${ORDERER_NAME}.log
   MYHOME=/etc/hyperledger/orderer

   export FABRIC_CA_CLIENT=$MYHOME
   export ORDERER_GENERAL_LOGLEVEL=debug
   export ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
   export ORDERER_GENERAL_GENESISMETHOD=file
   export ORDERER_GENERAL_GENESISFILE=$GENESIS_BLOCK_FILE
   export ORDERER_GENERAL_LOCALMSPID=$ORG_MSP_ID
   export ORDERER_GENERAL_LOCALMSPDIR=$MYHOME/msp
   # enabled TLS
   export ORDERER_GENERAL_TLS_ENABLED=true
   TLSDIR=$MYHOME/tls
   export ORDERER_GENERAL_TLS_PRIVATEKEY=$TLSDIR/server.key
   export ORDERER_GENERAL_TLS_CERTIFICATE=$TLSDIR/server.crt
   export ORDERER_GENERAL_TLS_ROOTCAS=[$CA_CHAINFILE]
   export ORDERER_GENERAL_TLS_CLIENTROOTCAS=[$CA_CHAINFILE]
   export ORDERER_GENERAL_TLS_CLIENTAUTHREQUIRED=true
}

function genClientTLSCert {
   if [ $# -ne 3 ]; then
      echo "Usage: genClientTLSCert <host name> <cert file> <key file>: $*"
      exit 1
   fi

   echo "Generating genClientTLSCert for host: <host name> <cert file> <key file>: $*"
   HOST_NAME=$1
   CERT_FILE=$2
   KEY_FILE=$3

   if ! [ -x "$(command -v fabric-ca-client)" ]; then
      echo 'fabric-ca-client is not installed - installing it now.'
      installFabricCA
   fi

   # Get a client cert
   fabric-ca-client enroll -d --enrollment.profile tls -u $ENROLLMENT_URL -M /tmp/tls --csr.hosts $HOST_NAME

   mkdir /$DATA/tls || true
   cp /tmp/tls/signcerts/* $CERT_FILE
   cp /tmp/tls/keystore/* $KEY_FILE
   rm -rf /tmp/tls
}

# initPeerVars <ORG> <NUM>
function initPeerVars {
   if [ $# -ne 2 ]; then
      echo "Usage: initPeerVars <ORG> <NUM>: $*"
      exit 1
   fi

   ORG=$1
   NUM=$2
   initOrgVars $ORG
   getDomain $ORG
   PEER_NAME=${PEER_PREFIX}${NUM}-${ORG}
   # When building a PROD network, the 1st peer of each org will be considered the anchor peer, and it's endpoint
   # must be exposed via an NLB so that it can communicate with peers in other accounts/regions
   if [ $FABRIC_NETWORK_TYPE == "PROD" ] && [ $NUM -eq 1 ] && [[ ! -v $"REMOTE_PEER" ]]; then
     getExternalAnchorPeer $ORG
     if [ -z "$EXTERNALANCHORPEER" ]; then
        PEER_HOST=${PEER_NAME}.${DOMAIN}
     else
        PEER_HOST=$EXTERNALANCHORPEER
     fi
   else
     PEER_HOST=${PEER_NAME}.${DOMAIN}
   fi
   PEER_PASS=${PEER_NAME}pw
   PEER_NAME_PASS=${PEER_NAME}:${PEER_PASS}
   PEER_LOGFILE=$LOGDIR/${PEER_NAME}.log
   MYHOME=/opt/gopath/src/github.com/hyperledger/fabric/peer
   TLSDIR=$MYHOME/tls

   export FABRIC_CA_CLIENT=$MYHOME
   #export CORE_PEER_ID=$PEER_HOST
   export CORE_PEER_ID=${PEER_NAME}.${DOMAIN}
   export CORE_PEER_ADDRESS=$PEER_HOST:7051
#   export CORE_PEER_CHAINCODELISTENADDRESS=$PEER_HOST:7052
   export CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
   export CORE_PEER_LOCALMSPID=$ORG_MSP_ID
   export CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
   # the following setting starts chaincode containers on the same
   # bridge network as the peers
   # https://docs.docker.com/compose/networking/
   #export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=${COMPOSE_PROJECT_NAME}_${NETWORK}
   #export CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE=net_${NETWORK}
   # export CORE_LOGGING_LEVEL=ERROR
   export FABRIC_LOGGING_SPEC="peer=DEBUG"
   export CORE_PEER_TLS_ENABLED=true
   export CORE_PEER_TLS_CLIENTAUTHREQUIRED=true
   export CORE_PEER_TLS_ROOTCERT_FILE=$CA_CHAINFILE
   export CORE_PEER_TLS_CLIENTCERT_FILE=/$DATA/tls/$PEER_NAME-cli-client.crt
   export CORE_PEER_TLS_CLIENTKEY_FILE=/$DATA/tls/$PEER_NAME-cli-client.key
   export CORE_PEER_PROFILE_ENABLED=true
   # gossip variables
   export CORE_PEER_GOSSIP_USELEADERELECTION=true
   export CORE_PEER_GOSSIP_ORGLEADER=false
   export CORE_PEER_GOSSIP_EXTERNALENDPOINT=$PEER_HOST:7051
   if [ $FABRIC_NETWORK_TYPE == "PROD" ] && [ $NUM -gt 1 ]; then
      # Point the non-anchor peers to the remote anchor peer, which is always the 1st peer
      export CORE_PEER_GOSSIP_BOOTSTRAP=peer1-${EXTERNALANCHORPEER}:${EXTERNALANCHORPORT}
   elif [ $FABRIC_NETWORK_TYPE == "POC" ] && [ $NUM -gt 1 ]; then
      # Point the non-anchor peers to the local anchor peer, which is always the 1st peer
      export CORE_PEER_GOSSIP_BOOTSTRAP=${PEER_NAME}.${DOMAIN}:7051
   fi
   export ORDERER_CONN_ARGS="$ORDERER_PORT_ARGS --keyfile $CORE_PEER_TLS_CLIENTKEY_FILE --certfile $CORE_PEER_TLS_CLIENTCERT_FILE"
#   export ORDERER_CONN_ARGS="$ORDERER_PORT_ARGS"
}

# Switch to the current org's admin identity.  Enroll if not previously enrolled.
function switchToAdminIdentity {
   if [ ! -d $ORG_ADMIN_HOME ]; then
      dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
      log "Enrolling admin '$ADMIN_NAME' with $CA_HOST ..."
      export FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME
      export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      if ! [ -x "$(command -v fabric-ca-client)" ]; then
         echo 'fabric-ca-client is not installed - installing it now.'
         installFabricCA
      fi
      fabric-ca-client enroll -d -u https://$ADMIN_NAME:$ADMIN_PASS@$CA_HOST:7054
      # If admincerts are required in the MSP, copy the cert there now and to my local MSP also
      if [ $ADMINCERTS ]; then
         mkdir -p $(dirname "${ORG_ADMIN_CERT}")
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ORG_ADMIN_CERT
         mkdir $ORG_ADMIN_HOME/msp/admincerts
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ORG_ADMIN_HOME/msp/admincerts
      fi
   fi
   export CORE_PEER_MSPCONFIGPATH=$ORG_ADMIN_HOME/msp
}

# Switch to the current org's user identity.  Enroll if not previously enrolled.
function switchToUserIdentity {
   log "Switching to user '$USER_NAME'"
   export FABRIC_CA_CLIENT_HOME=/etc/hyperledger/fabric/orgs/$ORG/user
   export CORE_PEER_MSPCONFIGPATH=$FABRIC_CA_CLIENT_HOME/msp
   if [ ! -d $FABRIC_CA_CLIENT_HOME ]; then
      dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
      log "Enrolling user '$USER_NAME' for organization $ORG with home directory $FABRIC_CA_CLIENT_HOME ..."
      export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      env
      if ! [ -x "$(command -v fabric-ca-client)" ]; then
         echo 'fabric-ca-client is not installed - installing it now.'
         installFabricCA
      fi
      fabric-ca-client enroll -d -u https://$USER_NAME:$USER_PASS@$CA_HOST:7054
      # Set up admincerts directory if required
      if [ $ADMINCERTS ]; then
         ACDIR=$CORE_PEER_MSPCONFIGPATH/admincerts
         mkdir -p $ACDIR
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ACDIR
      fi
   fi
}

# Switch to the Marble app user identity.  Enroll if not previously enrolled.
function switchToMarbleIdentity {
   log "Switching to user '$MARBLES_USER_NAME'"
   export FABRIC_CA_CLIENT_HOME=/etc/hyperledger/fabric/orgs/$ORG/marblesuser
   export CORE_PEER_MSPCONFIGPATH=$FABRIC_CA_CLIENT_HOME/msp
   if [ ! -d $FABRIC_CA_CLIENT_HOME ]; then
      dowait "$CA_NAME to start" 60 $CA_LOGFILE $CA_CHAINFILE
      log "Enrolling user '$MARBLES_USER_NAME' for organization $ORG with home directory $FABRIC_CA_CLIENT_HOME ..."
      export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
      env
      if ! [ -x "$(command -v fabric-ca-client)" ]; then
         echo 'fabric-ca-client is not installed - installing it now.'
         installFabricCA
      fi
      fabric-ca-client enroll -d -u https://$MARBLES_USER_NAME:$MARBLES_USER_PASS@$CA_HOST:7054
      # Set up admincerts directory if required
      if [ $ADMINCERTS ]; then
         ACDIR=$CORE_PEER_MSPCONFIGPATH/admincerts
         mkdir -p $ACDIR
         cp $ORG_ADMIN_HOME/msp/signcerts/* $ACDIR
      fi
   fi
}

# Revokes the fabric user
function revokeFabricUserAndGenerateCRL {
   switchToAdminIdentity
   export  FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME
   log "Revoking the user '$USER_NAME' of the organization '$ORG' with Fabric CA Client home directory set to $FABRIC_CA_CLIENT_HOME and generating CRL ..."
   export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
   if ! [ -x "$(command -v fabric-ca-client)" ]; then
     echo 'fabric-ca-client is not installed - installing it now.'
     installFabricCA
   fi
   fabric-ca-client revoke -d --revoke.name $USER_NAME --gencrl
}

# Generates a CRL that contains serial numbers of all revoked enrollment certificates.
# The generated CRL is placed in the crls folder of the admin's MSP
function generateCRL {
   switchToAdminIdentity
   export FABRIC_CA_CLIENT_HOME=$ORG_ADMIN_HOME
   log "Generating CRL for the organization '$ORG' with Fabric CA Client home directory set to $FABRIC_CA_CLIENT_HOME ..."
   export FABRIC_CA_CLIENT_TLS_CERTFILES=$CA_CHAINFILE
   if ! [ -x "$(command -v fabric-ca-client)" ]; then
     echo 'fabric-ca-client is not installed - installing it now.'
     installFabricCA
   fi
   fabric-ca-client gencrl -d
}

# Copy the org's admin cert into some target MSP directory
# This is only required if ADMINCERTS is enabled.
function copyAdminCert {
   if [ $# -ne 1 ]; then
      fatal "Usage: copyAdminCert <targetMSPDIR>"
   fi
   if $ADMINCERTS; then
      dstDir=$1/admincerts
      log "copyAdminCert - copying '$ORG_ADMIN_CERT' to '$dstDir'"
      mkdir -p $dstDir
      cp $ORG_ADMIN_CERT $dstDir
   fi
}

# Create the TLS directories of the MSP folder if they don't exist.
# The fabric-ca-client should do this.
function finishMSPSetup {
   log "finishMSPSetup - copying '$1'/cacerts/* to '$1'/tlscacerts and '$1'/intermediatecerts/* '$1'/tlsintermediatecerts"
   if [ $# -ne 1 ]; then
      fatal "Usage: finishMSPSetup <targetMSPDIR>"
   fi
   if [ ! -d $1/tlscacerts ]; then
      mkdir $1/tlscacerts
      cp $1/cacerts/* $1/tlscacerts
      if [ -d $1/intermediatecerts ]; then
         mkdir $1/tlsintermediatecerts
         cp $1/intermediatecerts/* $1/tlsintermediatecerts
      fi
   fi
}

# Get the domain associated with the ORG. ORG is input, DOMAIN is output
function getDomain {
   if [ $# -ne 1 ]; then
      echo "Usage: getDomain <ORG>"
      exit 1
   fi
   orgsarr=($ORGS)
   domainarr=($DOMAINS)

   for i in "${!orgsarr[@]}"; do
      if [[ "${orgsarr[$i]}" = "${1}" ]]; then
           DOMAIN=${domainarr[$i]}
           return
      fi
   done
}

# Get the external anchor peer endpoint associated with the ORG
function getExternalAnchorPeer {
   if [ $# -ne 1 ]; then
      echo "Usage: getExternalAnchorPeer <ORG>"
      exit 1
   fi
   orgsarr=($PEER_ORGS)
   anchorarr=($EXTERNAL_ANCHOR_PEER_ADDRESSES)
   EXTERNALANCHORPEER=""

   for i in "${!orgsarr[@]}"; do
      if [[ "${orgsarr[$i]}" = "${1}" ]]; then
        # make sure this index exists in the anchor peers array
        if [[ "${#anchorarr[@]}" -le "${i}" ]]; then
            return
        fi
        IFS=':' read -r -a arr <<< "${anchorarr[$i]}"
        EXTERNALANCHORPEER=${arr[0]}
        EXTERNALANCHORPORT=${arr[1]}
        return
      fi
   done
}

# Wait for one or more files to exist
# Usage: dowait <what> <timeoutInSecs> <errorLogFile> <file> [<file> ...]
function dowait {
   if [ $# -lt 4 ]; then
      fatal "Usage: dowait: $*"
   fi
   local what=$1
   local secs=$2
   local logFile=$3
   shift 3
   local logit=true
   local starttime=$(date +%s)
   for file in $*; do
      until [ -f $file ]; do
         if [ "$logit" = true ]; then
            log -n "Waiting for $what ..."
            logit=false
         fi
         sleep 1
         if [ "$(($(date +%s)-starttime))" -gt "$secs" ]; then
            echo ""
            fatal "Failed waiting for $what ($file not found); see $logFile"
         fi
         echo -n "."
      done
   done
   echo ""
}

# log a message
function log {
   if [ "$1" = "-n" ]; then
      shift
      echo -n "##### `date '+%Y-%m-%d %H:%M:%S'` $*"
   else
      echo "##### `date '+%Y-%m-%d %H:%M:%S'` $*"
   fi
}

# fatal a message
function fatal {
   log "FATAL: $*"
   exit 1
}

function installFabricCA {
    # Install fabric-ca. Recent versions of Hyperledger Fabric Docker images do not include fabric-ca-tools, fabric-ca-peer, etc., where the
    # fabric-ca-client is included. So we will need to build fabric-ca-client ourselves.
    log "Installing fabric-ca-client"

#    wget https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz
#    tar -xzf go1.10.3.linux-amd64.tar.gz
#    mv go /usr/local
#    sleep 5
#    export GOROOT=/usr/local/go
#    export GOPATH=$HOME/go
#    export PATH=$GOROOT/bin:$PATH
#    apt-get update
#    apt-get install git-core -y
#    apt-get install libtool libltdl-dev -y
#    apt-get install build-essential -y
#    sleep 5
    go get -u github.com/hyperledger/fabric-ca/cmd/...
    sleep 10
#    cd $HOME/go/src/github.com/hyperledger/fabric-ca
#    make fabric-ca-client
#    sleep 5
#    export PATH=$PATH:$HOME/go/src/github.com/hyperledger/fabric-ca/bin

    log "Install complete - fabric-ca-client"
}