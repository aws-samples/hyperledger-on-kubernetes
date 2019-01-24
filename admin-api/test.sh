#!/usr/bin/env bash


cp /opt/share/rca-data/configtx-orig.yaml /opt/share/rca-data/configtx.yaml

export HFC_LOGGING='{"debug":"console","info":"console"}'

nvm use lts/carbon

node app.js &

export ENDPOINT=localhost
export PORT=3000
echo connecting to server: $ENDPOINT:$PORT

# Get the admin user
response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/users/admin)
echo $response

# Register and enroll a new user within a specific org
USERID=michael
ORG=org1
echo
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/users -H 'content-type: application/x-www-form-urlencoded' -d '{"username":"'"${USERID}"'","org":"'"${ORG}"'"}')
echo $response

# Print out the orgs and profiles contained in configtx.yaml and env.sh
response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/env/orgs)
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx/orgs)
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx/profiles)
echo $response

########################################################################################################################
# Add a new org
#
# To add a new org the steps should be carried out in this order
########################################################################################################################

# Set the variables
ORG=org5;
PROFILENAME=org5profile;
CHANNELNAME=org5channel;

# Try and add a channel profile for an org that does not exist. This should fail as the new org does not exist
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/profiles -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","orgs":["org1","org3"]}')
echo $response

# add the new org to the Fabric config file, env.sh
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/env/orgs -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# Prepare the environment for a new org: create directories, start K8s persistent volumes, etc.
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/setup -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# Start the CA for the new org
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/ca -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# Register the new org - this will generate an MSP for the org
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/register -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# add the new org
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# add the new channel profile that includes the new org
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/profiles -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","orgs":["org1","org3"]}')
echo $response

# create the channel configuration transaction file
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/channelconfigs -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","channelname":"'"${CHANNELNAME}"'"}')
echo $response

# create the channel
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'"}')
echo $response


