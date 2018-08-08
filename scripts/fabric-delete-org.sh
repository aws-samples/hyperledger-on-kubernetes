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

set -e

source $(dirname "$0")/env.sh

function main {

    file=/${DATA}/updateorg
    if [ -f "$file" ]; then
       ORGTODELETE=$(cat $file)
       echo "File '$file' exists - delete org '$ORGTODELETE'"
       cloneFabricSamples

       log "Removing org '$ORGTODELETE' from the channel config"

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       initPeerVars ${PEERORG} 1

       # Fetch config block
       fetchConfigBlock

       # Create config update envelope with CRL and update the config block of the channel
       createConfigUpdate
       if [ $? -eq 1 ]; then
            log "Org '$ORGTODELETE' does not exist in the channel config. Config will not be updated or signed"
            exit 0
       else
           log "Congratulations! The config file for deleting the org '$ORGTODELETE' was successfully added. Now it must be signed by all org admins"
           log "After this pod completes, run the pod which contains the script addorg-fabric-sign.sh"
           exit 0
       fi
    else
        log "File '$file' does not exist - no org will be deleted - exiting"
        exit 1
    fi
}

# git clone fabric-samples. We need this repo for the chaincode
function cloneFabricSamples {
   log "cloneFabricSamples"
   mkdir -p /opt/gopath/src/github.com/hyperledger
   cd /opt/gopath/src/github.com/hyperledger
   git clone https://github.com/hyperledger/fabric-samples.git
   log "cloned FabricSamples"
   cd fabric-samples
   git checkout release-1.1
   log "checked out version 1.1 of FabricSamples"

   log "cloneFabric"
   mkdir /opt/gopath/src/github.com/hyperledger/fabric
}

function fetchConfigBlock {
   switchToAdminIdentity
   export FABRIC_CFG_PATH=/etc/hyperledger/fabric
   log "Fetching the configuration block into '$CONFIG_BLOCK_FILE' of the channel '$CHANNEL_NAME'"
   log "peer channel fetch config '$CONFIG_BLOCK_FILE' -c '$CHANNEL_NAME' '$ORDERER_CONN_ARGS'"
   peer channel fetch config $CONFIG_BLOCK_FILE -c $CHANNEL_NAME $ORDERER_CONN_ARGS
   log "fetched config block"
}

function isOrgInChannelConfig {
    if [ $# -ne 1 ]; then
        log "Usage: isOrgInChannelConfig <Config JSON file>"
        exit 1
    fi
    log "Checking whether org '$ORGTODELETE' exists in the channel config"
    local JSONFILE=$1

    # check if the org exists in the channel config
    log "About to execute jq '.channel_group.groups.Application.groups | contains({$ORGTODELETE})'"
    if cat ${JSONFILE} | jq -e ".channel_group.groups.Application.groups | contains({$ORGTODELETE})" > /dev/null; then
        log "Org '$ORGTODELETE' exists in the channel config"
        return 0
    else
        log "Org '$ORGTODELETE' does not exist in the channel config"
        return 1
    fi
}

function createConfigUpdate {
   log "Creating config update payload for deleting org '$ORGTODELETE'"
   # Start the configtxlator
   configtxlator start &
   configtxlator_pid=$!
   log "configtxlator_pid:$configtxlator_pid"
   log "Sleeping 5 seconds for configtxlator to start..."
   sleep 5

   pushd /tmp

   #make a copy of the .json files below
   jsonbkdir=/$DATA/delorgs-${ORGTODELETE}-`date +%Y%m%d-%H%M`
   mkdir $jsonbkdir

   CTLURL=http://127.0.0.1:7059
   # Convert the config block protobuf to JSON
   curl -X POST --data-binary @$CONFIG_BLOCK_FILE $CTLURL/protolator/decode/common.Block > ${ORGTODELETE}_config_block.json
   # Extract the config from the config block
   jq .data.data[0].payload.data.config ${ORGTODELETE}_config_block.json > ${ORGTODELETE}_config.json
   cp ${ORGTODELETE}_config_block.json $jsonbkdir
   cp ${ORGTODELETE}_config.json $jsonbkdir

   isOrgInChannelConfig ${ORGTODELETE}_config.json
   if [ $? -eq 1 ]; then
        log "Org '$ORGTODELETE' does not exist in the channel config. Config will not be updated"
        return 1
   fi

   # Delete the org configuration information
   cat ${ORGTODELETE}_config.json | jq "del(.channel_group.groups.Application.groups.${ORGTODELETE})" > ${ORGTODELETE}_updated_config.json
   cp ${ORGTODELETE}_updated_config.json $jsonbkdir


   # Create the config diff protobuf
   curl -X POST --data-binary @${ORGTODELETE}_config.json $CTLURL/protolator/encode/common.Config > ${ORGTODELETE}_config.pb
   curl -X POST --data-binary @${ORGTODELETE}_updated_config.json $CTLURL/protolator/encode/common.Config > ${ORGTODELETE}_updated_config.pb
   curl -X POST -F original=@${ORGTODELETE}_config.pb -F updated=@${ORGTODELETE}_updated_config.pb $CTLURL/configtxlator/compute/update-from-configs -F channel=$CHANNEL_NAME > ${ORGTODELETE}_config_update.pb

   # Convert the config diff protobuf to JSON
   curl -X POST --data-binary @${ORGTODELETE}_config_update.pb $CTLURL/protolator/decode/common.ConfigUpdate > ${ORGTODELETE}_config_update.json
   cp ${ORGTODELETE}_config_update.json $jsonbkdir

   # Create envelope protobuf container config diff to be used in the "peer channel update" command to update the channel configuration block
   echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'", "type":2}},"data":{"config_update":'$(cat ${ORGTODELETE}_config_update.json)'}}}' > ${ORGTODELETE}_config_update_as_envelope.json
   curl -X POST --data-binary @${ORGTODELETE}_config_update_as_envelope.json $CTLURL/protolator/encode/common.Envelope > /tmp/${ORGTODELETE}_config_update_as_envelope.pb
   # copy to the /data directory so the file can be signed by other admins
   cp /tmp/${ORGTODELETE}_config_update_as_envelope.pb /$DATA
   cp /tmp/${ORGTODELETE}_config_update_as_envelope.json $jsonbkdir
   cp /tmp/${ORGTODELETE}_config_update_as_envelope.pb $jsonbkdir
   ls -lt $jsonbkdir

   # Stop configtxlator
   kill $configtxlator_pid
   log "Created config update payload for deleting organization '$ORGTODELETE', in file /${DATA}/${ORGTODELETE}_config_update_as_envelope.pb"

   popd
   return 0
}

main
