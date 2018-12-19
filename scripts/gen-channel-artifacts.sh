#!/bin/bash

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

#
# This script does the following:
# 1) registers orderer and peer identities with intermediate fabric-ca-servers
# 2) Builds the channel artifacts (e.g. genesis block, etc)
#

function main {
   log "Beginning building channel artifacts ..."
   makeConfigTxYaml
   generateChannelArtifacts
   log "Finished building channel artifacts"
}

# printOrg
function printOrg {
   echo "
  - &$ORG_CONTAINER_NAME

    Name: $ORG

    # ID to load the MSP definition as
    ID: $ORG_MSP_ID

    # MSPDir is the filesystem path which contains the MSP configuration
    MSPDir: $ORG_MSP_DIR

    AdminPrincipal: Role.ADMIN

    Policies:
        Readers:
            Type: Signature
            Rule: \"OR(\'$ORG_MSP_ID.member\')\"
        Writers:
            Type: Signature
            Rule: \"OR(\'$ORG_MSP_ID.member\')\"
        Admins:
            Type: Signature
            Rule: \"OR(\'$ORG_MSP_ID.admin\')\""
}

# printOrdererOrg <ORG>
function printOrdererOrg {
   initOrgVars $1
   printOrg
}

# printPeerOrg <ORG> <COUNT>
function printPeerOrg {
   initPeerVars $1 $2
   printOrg
   echo "
    AnchorPeers:
       - Host: $PEER_HOST
         Port: 7051"
}

function makeConfigTxYaml {
   {
   echo "
################################################################################
#
#   SECTION: Capabilities
#
################################################################################
Capabilities:
    Global: &ChannelCapabilities
        V1_4: true

    Orderer: &OrdererCapabilities
        V1_4: true

    Application: &ApplicationCapabilities
        V1_4: true"

   echo "
################################################################################
#
#   Section: Organizations
#
################################################################################
Organizations:"

   for ORG in $ORDERER_ORGS; do
      printOrdererOrg $ORG
   done

   for ORG in $PEER_ORGS; do
      printPeerOrg $ORG 1
   done

   echo "
################################################################################
#
#   SECTION: Orderer
#
################################################################################
Orderer: &OrdererDefaults

    # Orderer Type: The orderer implementation to start.
    # Available types are \"solo\" and \"kafka\".
    OrdererType: $ORDERER_TYPE

    Addresses:
$EXTERNAL_ORDERER_ADDRESSES"

    for ORG in $ORDERER_ORGS; do
      local COUNT=1
      while [[ "$COUNT" -le $NUM_ORDERERS ]]; do
         if [ $FABRIC_NETWORK_TYPE == "PROD" ] && [[ "$COUNT" -gt 1 ]]; then
            COUNT=$((COUNT+1))
            continue
         fi
         initOrdererVars $ORG $COUNT
         echo "        - $ORDERER_HOST:$ORDERER_PORT"
         COUNT=$((COUNT+1))
      done
    done

    echo "
    # Batch Timeout: The amount of time to wait before creating a batch.
    BatchTimeout: 2s

    # Batch Size: Controls the number of messages batched into a block.
    BatchSize:

        # Max Message Count: The maximum number of messages to permit in a
        # batch.
        MaxMessageCount: 10

        # Absolute Max Bytes: The absolute maximum number of bytes allowed for
        # the serialized messages in a batch. If the 'kafka' OrdererType is
        # selected, set 'message.max.bytes' and 'replica.fetch.max.bytes' on the
        # Kafka brokers to a value that is larger than this one.
        AbsoluteMaxBytes: 98 MB

        # Preferred Max Bytes: The preferred maximum number of bytes allowed for
        # the serialized messages in a batch. A message larger than the
        # preferred max bytes will result in a batch larger than preferred max
        # bytes.
        PreferredMaxBytes: 512 KB

    # Max Channels is the maximum number of channels to allow on the ordering
    # network. When set to 0, this implies no maximum number of channels.
    MaxChannels: 0

    Kafka:
        # Brokers: A list of Kafka brokers to which the orderer connects. Edit
        # this list to identify the brokers of the ordering service.
        # NOTE: Use IP:port notation.
        Brokers:
            - broker.kafka:9092
            $EXTERNAL_KAFKA_BROKER

    # Organizations is the list of orgs which are defined as participants on
    # the orderer side of the network.
    Organizations:"

    for ORG in $ORDERER_ORGS; do
      initOrgVars $ORG
      echo "        - *${ORG_CONTAINER_NAME}"
    done

   echo "
    # Policies defines the set of policies at this level of the config tree
    # For Orderer policies, their canonical path is
    #   /Channel/Orderer/<PolicyName>
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"
        # BlockValidation specifies what signatures must be included in the block
        # from the orderer for the peer to validate it.
        BlockValidation:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"

    # Capabilities describes the orderer level capabilities, see the
    # dedicated Capabilities section elsewhere in this file for a full
    # description
    Capabilities:
        <<: *OrdererCapabilities"

   echo "
################################################################################
#
#   CHANNEL
#
#   This section defines the values to encode into a config transaction or
#   genesis block for channel related parameters.
#
################################################################################
Channel: &ChannelDefaults
    # Policies defines the set of policies at this level of the config tree
    # For Channel policies, their canonical path is
    #   /Channel/<PolicyName>
    Policies:
        # Who may invoke the 'Deliver' API
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        # Who may invoke the 'Broadcast' API
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        # By default, who may modify elements at this config level
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"


    # Capabilities describes the channel level capabilities, see the
    # dedicated Capabilities section elsewhere in this file for a full
    # description
    Capabilities:
        <<: *ChannelCapabilities"

   echo "
################################################################################
#
#   SECTION: Application
#
################################################################################
Application: &ApplicationDefaults
    ACLs: &ACLsDefault
        # This section provides defaults for policies for various resources
        # in the system. These \"resources\" could be functions on system chaincodes
        # (e.g., \"GetBlockByNumber\" on the \"qscc\" system chaincode) or other resources
        # (e.g.,who can receive Block events). This section does NOT specify the resource's
        # definition or API, but just the ACL policy for it.
        #
        # User's can override these defaults with their own policy mapping by defining the
        # mapping under ACLs in their channel definition

        #---Lifecycle System Chaincode (lscc) function to policy mapping for access control---#

        # ACL policy for lscc's \"getid\" function
        lscc/ChaincodeExists: /Channel/Application/Readers

        # ACL policy for lscc's \"getdepspec\" function
        lscc/GetDeploymentSpec: /Channel/Application/Readers

        # ACL policy for lscc's \"getccdata\" function
        lscc/GetChaincodeData: /Channel/Application/Readers

        # ACL Policy for lscc's \"getchaincodes\" function
        lscc/GetInstantiatedChaincodes: /Channel/Application/Readers

        #---Query System Chaincode (qscc) function to policy mapping for access control---#

        # ACL policy for qscc's \"GetChainInfo\" function
        qscc/GetChainInfo: /Channel/Application/Readers

        # ACL policy for qscc's \"GetBlockByNumber\" function
        qscc/GetBlockByNumber: /Channel/Application/Readers

        # ACL policy for qscc's  \"GetBlockByHash\" function
        qscc/GetBlockByHash: /Channel/Application/Readers

        # ACL policy for qscc's \"GetTransactionByID\" function
        qscc/GetTransactionByID: /Channel/Application/Readers

        # ACL policy for qscc's \"GetBlockByTxID\" function
        qscc/GetBlockByTxID: /Channel/Application/Readers

        #---Configuration System Chaincode (cscc) function to policy mapping for access control---#

        # ACL policy for cscc's \"GetConfigBlock\" function
        cscc/GetConfigBlock: /Channel/Application/Readers

        # ACL policy for cscc's \"GetConfigTree\" function
        cscc/GetConfigTree: /Channel/Application/Readers

        # ACL policy for cscc's \"SimulateConfigTreeUpdate\" function
        cscc/SimulateConfigTreeUpdate: /Channel/Application/Readers

        #---Miscellanesous peer function to policy mapping for access control---#

        # ACL policy for invoking chaincodes on peer
        peer/Propose: /Channel/Application/Writers

        # ACL policy for chaincode to chaincode invocation
        peer/ChaincodeToChaincode: /Channel/Application/Readers

        #---Events resource to policy mapping for access control###---#

        # ACL policy for sending block events
        event/Block: /Channel/Application/Readers

        # ACL policy for sending filtered block events
        event/FilteredBlock: /Channel/Application/Readers

    # Organizations is the list of orgs which are defined as participants on
    # the application side of the network.
    Organizations:

    # Policies defines the set of policies at this level of the config tree
    # For Application policies, their canonical path is
    #   /Channel/Application/<PolicyName>
    Policies: &ApplicationDefaultPolicies
        Readers:
            Type: ImplicitMeta
            Rule: \"ANY Readers\"
        Writers:
            Type: ImplicitMeta
            Rule: \"ANY Writers\"
        Admins:
            Type: ImplicitMeta
            Rule: \"MAJORITY Admins\"

    # Capabilities describes the application level capabilities, see the
    # dedicated Capabilities section elsewhere in this file for a full
    # description
    Capabilities:
        <<: *ApplicationCapabilities"

   echo "
################################################################################
#
#   Profiles
#
################################################################################
Profiles:

    OrgsOrdererGenesis:
        <<: *ChannelDefaults
        Orderer:
            <<: *OrdererDefaults
            Organizations:"
                for ORG in $ORDERER_ORGS; do
                  initOrgVars $ORG
                  echo "                    - *${ORG_CONTAINER_NAME}"
                done
   echo "
            Capabilities:
                <<: *OrdererCapabilities
        Application:
            <<: *ApplicationDefaults
            Organizations:"
                for ORG in $ORDERER_ORGS; do
                  initOrgVars $ORG
                  echo "                    - *${ORG_CONTAINER_NAME}"
                done
   echo "
            Capabilities:
                <<: *ApplicationCapabilities
        Consortiums:
            SampleConsortium:
                Organizations:"
                    for ORG in $PEER_ORGS; do
                      initOrgVars $ORG
                      echo "                - *${ORG_CONTAINER_NAME}"
                    done

   echo "
    OrgsChannel:
        Capabilities:
            <<: *ChannelCapabilities
        Consortium: SampleConsortium
        Application:
            <<: *ApplicationDefaults
            Organizations:"
                    for ORG in $PEER_ORGS; do
                      initOrgVars $ORG
                      echo "            - *${ORG_CONTAINER_NAME}"
                    done
   echo "
            Capabilities:
                <<: *ApplicationCapabilities"
   } > /etc/hyperledger/fabric/configtx.yaml
   # Copy it to the data directory to make debugging easier
   cp /etc/hyperledger/fabric/configtx.yaml /$DATA
}

function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    fatal "configtxgen tool not found. exiting"
  fi

  log "Generating orderer genesis block at $GENESIS_BLOCK_FILE"
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  configtxgen -profile OrgsOrdererGenesis -outputBlock $GENESIS_BLOCK_FILE
  if [ "$?" -ne 0 ]; then
    fatal "Failed to generate orderer genesis block"
  fi

  log "Generating channel configuration transaction at $CHANNEL_TX_FILE"
  configtxgen -profile OrgsChannel -outputCreateChannelTx $CHANNEL_TX_FILE -channelID $CHANNEL_NAME
  if [ "$?" -ne 0 ]; then
    fatal "Failed to generate channel configuration transaction"
  fi

  for ORG in $PEER_ORGS; do
     initOrgVars $ORG
     log "Generating anchor peer update transaction for $ORG at $ANCHOR_TX_FILE"
     configtxgen -profile OrgsChannel -outputAnchorPeersUpdate $ANCHOR_TX_FILE \
                 -channelID $CHANNEL_NAME -asOrg $ORG
     if [ "$?" -ne 0 ]; then
        fatal "Failed to generate anchor peer update for $ORG"
     fi
  done
}

set -e

SDIR=$(dirname "$0")
source $SDIR/env.sh

main
