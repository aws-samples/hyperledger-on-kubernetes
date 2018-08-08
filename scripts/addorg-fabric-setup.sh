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

source $(dirname "$0")/env.sh

function main {

    file=/${DATA}/updateorg
    if [ -f "$file" ]; then
       NEW_ORG=$(cat $file)
       echo "File '$file' exists - peer '$PEERORG' admin creating a new org '$NEW_ORG'"

       cloneFabricSamples

       log "Generating the channel config for new org '$NEW_ORG'"

       # Set ORDERER_PORT_ARGS to the args needed to communicate with the 1st orderer
       IFS=', ' read -r -a OORGS <<< "$ORDERER_ORGS"
       initOrdererVars ${OORGS[0]} 1
       export ORDERER_PORT_ARGS="-o $ORDERER_HOST:$ORDERER_PORT --tls --cafile $CA_CHAINFILE --clientauth"

       initPeerVars ${PEERORG} 1

       generateNewOrgConfig

       # Fetch config block
       fetchConfigBlock

       # Create config update envelope with CRL and update the config block of the channel
       log "About to start createConfigUpdate"
       createConfigUpdate
       if [ $? -eq 1 ]; then
           log "Org '$NEW_ORG' already exists in the channel config. Config will not be updated or signed"
           exit 0
       else
           log "Congratulations! The config file for the new org '$NEW_ORG' was successfully added by peer '$PEERORG' admin. Now it must be signed by all org admins"
           log "After this pod completes, run the pod which contains the script addorg-fabric-sign.sh"
           exit 0
       fi
    else
        log "File '$file' does not exist - no new org will be created - exiting"
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

function generateNewOrgConfig() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    fatal "configtxgen tool not found. exiting"
  fi

  log "Printing the new Org configuration for '$NEW_ORG' at '/$DATA'"
  export FABRIC_CFG_PATH=/$DATA
  cd $FABRIC_CFG_PATH
  configtxgen -printOrg $NEW_ORG > /tmp/$NEW_ORG.json
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
    log "Checking whether org '$NEW_ORG' exists in the channel config"
    local JSONFILE=$1

    # check if the org exists in the channel config
    log "About to execute jq '.channel_group.groups.Application.groups | contains({$NEW_ORG})'"
    if cat ${JSONFILE} | jq -e ".channel_group.groups.Application.groups | contains({$NEW_ORG})" > /dev/null; then
        log "Org '$NEW_ORG' exists in the channel config"
        return 0
    else
        log "Org '$NEW_ORG' does not exist in the channel config"
        return 1
    fi
}

function createConfigUpdate {
   log "Creating config update payload for the new organization '$NEW_ORG'"
   # Start the configtxlator
   configtxlator start &
   configtxlator_pid=$!
   log "configtxlator_pid:$configtxlator_pid"
   log "Sleeping 5 seconds for configtxlator to start..."
   sleep 5

   pushd /tmp

   #make a copy of the .json files below
   jsonbkdir=/$DATA/addorg-${NEW_ORG}-`date +%Y%m%d-%H%M`
   mkdir $jsonbkdir

   CTLURL=http://127.0.0.1:7059
   # Convert the config block protobuf to JSON
   curl -X POST --data-binary @$CONFIG_BLOCK_FILE $CTLURL/protolator/decode/common.Block > ${NEW_ORG}_config_block.json
   # Extract the config from the config block
   jq .data.data[0].payload.data.config ${NEW_ORG}_config_block.json > ${NEW_ORG}_config.json
   sudo cp ${NEW_ORG}_config_block.json $jsonbkdir
   sudo cp ${NEW_ORG}_config.json $jsonbkdir

   isOrgInChannelConfig ${NEW_ORG}_config.json
   if [ $? -eq 0 ]; then
        log "Org '$NEW_ORG' already exists in the channel config. Config will not be updated. Exiting createConfigUpdate"
        return 1
   fi

   # Append the new org configuration information
   jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"'$NEW_ORG'":.[1]}}}}}' ${NEW_ORG}_config.json ${NEW_ORG}.json > ${NEW_ORG}_updated_config.json
   # copy the block config to the /data directory in case we need to update it with another config change later
   cp /tmp/${NEW_ORG}_updated_config.json $jsonbkdir

   # Create the config diff protobuf
   curl -X POST --data-binary @${NEW_ORG}_config.json $CTLURL/protolator/encode/common.Config > ${NEW_ORG}_config.pb
   curl -X POST --data-binary @${NEW_ORG}_updated_config.json $CTLURL/protolator/encode/common.Config > ${NEW_ORG}_updated_config.pb
   curl -X POST -F original=@${NEW_ORG}_config.pb -F updated=@${NEW_ORG}_updated_config.pb $CTLURL/configtxlator/compute/update-from-configs -F channel=$CHANNEL_NAME > ${NEW_ORG}_config_update.pb

   # Convert the config diff protobuf to JSON
   curl -X POST --data-binary @${NEW_ORG}_config_update.pb $CTLURL/protolator/decode/common.ConfigUpdate > ${NEW_ORG}_config_update.json
   cp /tmp/${NEW_ORG}_config_update.json $jsonbkdir

   # Create envelope protobuf container config diff to be used in the "peer channel update" command to update the channel configuration block
   echo '{"payload":{"header":{"channel_header":{"channel_id":"'"${CHANNEL_NAME}"'", "type":2}},"data":{"config_update":'$(cat ${NEW_ORG}_config_update.json)'}}}' > ${NEW_ORG}_config_update_as_envelope.json
   curl -X POST --data-binary @${NEW_ORG}_config_update_as_envelope.json $CTLURL/protolator/encode/common.Envelope > /tmp/${NEW_ORG}_config_update_as_envelope.pb
   # copy to the /data directory so the file can be signed by other admins
   cp /tmp/${NEW_ORG}_config_update_as_envelope.pb /$DATA
   cp /tmp/${NEW_ORG}_config_update_as_envelope.pb $jsonbkdir
   cp /tmp/${NEW_ORG}_config_update_as_envelope.json $jsonbkdir
   ls -lt $jsonbkdir

   # Stop configtxlator
   kill $configtxlator_pid
   log "Created config update payload for the new organization '$NEW_ORG', in file /${DATA}/${NEW_ORG}_config_update_as_envelope.pb"

   popd
   return 0
}

main
