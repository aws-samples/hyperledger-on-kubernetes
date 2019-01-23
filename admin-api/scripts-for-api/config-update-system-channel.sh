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

function main {

       log "Generating the channel update config for the system channel '$CHANNEL_NAME' for the new org '$NEW_ORG'"

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       # Use the first peer of the first org for admin activities
       IFS=', ' read -r -a PORGS <<< "$PEER_ORGS"
       initPeerVars ${PORGS[0]} 1

       # Create config update envelope with CRL and update the config block of the channel
       log "About to start createConfigUpdate"
       createConfigUpdateSystemChannel
       if [ $? -eq 1 ]; then
           log "Org '$NEW_ORG' already exists in the channel config in channel $CHANNEL_NAME. Config will not be updated or signed"
           exit 0
       else
           log "Congratulations! The channel update config for the new org '$NEW_ORG' was successfully added by peer '$PEERORG' admin. Now it must be signed by all org admins"
           exit 0
       fi
}


function isOrgInChannelConfig {
    if [ $# -ne 1 ]; then
        log "Usage: isOrgInChannelConfig <Config JSON file>"
        exit 1
    fi
    log "Checking whether org '$NEW_ORG' exists in the channel config"
    local JSONFILE=$1

    # check if the org exists in the channel config
    log "About to execute jq 'channel_group.groups.Consortiums.groups.SampleConsortium.groups | contains({$NEW_ORG})'"
    if cat ${JSONFILE} | jq -e ".channel_group.groups.Consortiums.groups.SampleConsortium.groups | contains({$NEW_ORG})" > /dev/null; then
        log "Org '$NEW_ORG' exists in the channel config"
        return 0
    else
        log "Org '$NEW_ORG' does not exist in the channel config"
        return 1
    fi
}


# Adds a new org to the consortium configured in the system channel
function createConfigUpdateSystemChannel {
   log "Creating config update payload for the new organization '$NEW_ORG'"
   echo "Creating the config update payload for the new organization '$NEW_ORG'"
   # Start the configtxlator
   configtxlator start &
   configtxlator_pid=$!
   log "configtxlator_pid:$configtxlator_pid"
   log "Sleeping 5 seconds for configtxlator to start..."
   sleep 5

   pushd /tmp

   #make a copy of the .json files below
   jsonbkdir=/$DATA/${CHANNEL_NAME}-${NEW_ORG}-`date +%Y%m%d-%H%M`
   mkdir $jsonbkdir

   CTLURL=http://127.0.0.1:7059
   # Convert the config block protobuf to JSON
   curl -X POST --data-binary @$CONFIG_BLOCK_FILE $CTLURL/protolator/decode/common.Block > ${CHANNEL_NAME}-${NEW_ORG}_config_block.json
   # Extract the config from the config block
   jq .data.data[0].payload.data.config ${CHANNEL_NAME}-${NEW_ORG}_config_block.json > ${CHANNEL_NAME}-${NEW_ORG}_config.json
   sudo cp ${CHANNEL_NAME}-${NEW_ORG}_config_block.json $jsonbkdir
   sudo cp ${CHANNEL_NAME}-${NEW_ORG}_config.json $jsonbkdir

   isOrgInChannelConfig ${CHANNEL_NAME}-${NEW_ORG}_config.json
   if [ $? -eq 0 ]; then
        log "Org '$NEW_ORG' already exists in the channel config for channel $CHANNEL_NAME. Config will not be updated. Exiting createConfigUpdate"
        return 1
   fi

   # Append the new org configuration information
   jq -s '.[0] * {"channel_group":{"groups":{"Consortiums":{"groups": {"SampleConsortium": {"groups": {"'${NEW_ORG}'":.[1]}}}}}}}' ${CHANNEL_NAME}-${NEW_ORG}_config.json ${DATADIR}/${NEW_ORG}.json > ${CHANNEL_NAME}-${NEW_ORG}_updated_config.json
   # copy the block config to the /data directory in case we need to update it with another config change later
   cp /tmp/${CHANNEL_NAME}-${NEW_ORG}_updated_config.json $jsonbkdir

   # Create the config diff protobuf
   curl -X POST --data-binary @${CHANNEL_NAME}-${NEW_ORG}_config.json $CTLURL/protolator/encode/common.Config > ${CHANNEL_NAME}-${NEW_ORG}_config.pb
   curl -X POST --data-binary @${CHANNEL_NAME}-${NEW_ORG}_updated_config.json $CTLURL/protolator/encode/common.Config > ${CHANNEL_NAME}-${NEW_ORG}_updated_config.pb
   curl -X POST -F original=@${CHANNEL_NAME}-${NEW_ORG}_config.pb -F updated=@${NEW_ORG}_updated_config.pb $CTLURL/configtxlator/compute/update-from-configs -F channel=$CHANNEL_NAME > ${CHANNEL_NAME}-${NEW_ORG}_config_update.pb

   # Convert the config diff protobuf to JSON
   curl -X POST --data-binary @${CHANNEL_NAME}-${NEW_ORG}_config_update.pb $CTLURL/protolator/decode/common.ConfigUpdate > ${CHANNEL_NAME}-${NEW_ORG}_config_update.json
   cp /tmp/${CHANNEL_NAME}-${NEW_ORG}_config_update.json $jsonbkdir

   # Create envelope protobuf container config diff to be used in the "peer channel update" command to update the channel configuration block
   echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'", "type":2}},"data":{"config_update":'$(cat ${CHANNEL_NAME}-${NEW_ORG}_config_update.json)'}}}' > ${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.json
   curl -X POST --data-binary @${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.json $CTLURL/protolator/encode/common.Envelope > /tmp/${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.pb
   # copy to the /data directory so the file can be signed by other admins
   cp /tmp/${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.pb /$DATA
   cp /tmp/${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.pb $jsonbkdir
   cp /tmp/${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.json $jsonbkdir
   ls -lt $jsonbkdir

   # Stop configtxlator
   kill $configtxlator_pid
   log "Created config update payload for the new organization '$NEW_ORG', in file /${DATA}/${CHANNEL_NAME}-${NEW_ORG}_config_update_as_envelope.pb"

   popd
   return 0
}

DATADIR=/data
SCRIPTS=/scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
echo "Args are: " $*
CHANNEL_NAME=$1
NEW_ORG=$2
CONFIG_BLOCK_FILE=${DATADIR}/${CHANNEL_NAME}.pb
main
