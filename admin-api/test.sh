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

# Try and add a channel profile for an org that does not exist. This should fail as the new org does not exist
PROFILENAME=org3profile;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/profiles -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","orgs":["org1","org3"]}')
echo $response

# add the new org
ORG=org3;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# add the new channel profile that includes the new org
PROFILENAME=org3profile;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/profiles -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","orgs":["org1","org3"]}')
echo $response

# Start the CA for the new org
ORG=org3;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/ca -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# Register the new org
ORG=org3;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/register -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# create the channel configuration transaction file
PROFILENAME=org3profile;
CHANNELNAME=org3channel;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/channelconfigs -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","channelname":"'"${CHANNELNAME}"'"}')
echo $response

# create the channel
CHANNELNAME=org3channel;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'"}')
echo $response


