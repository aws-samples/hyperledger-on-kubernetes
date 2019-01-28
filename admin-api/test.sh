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
ORG=org3
PROFILENAME=org3profile;
CHANNELNAME=org3channel;

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

# Register a peer for new org - this will generate an identity
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/peers/register -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# Start a peer for new org - this will generate an MSP for the peer
# It could take up to 5 minutes for enrollment of the peer to complete. This is because the Kubernetes pod
# starts a Fabric Tools image which does not contain a fabric-ca. It seems the newer Docker images for Fabric do
# not include a CA client, so I have to install it in the script. This takes time to download and build.
# An alternative would be to move the code that registers the TLS certs and identities to the /peers/register script
# above, since this already runs a fabric-ca image, but this will require some work to set the right ENV variables
# Another alternative would be to use the Fabric SDK to generate the necessary id's and TLS certs
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/peers/start -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response
sleep 300

####
#### Wait 5 minutes before starting this. See comment above
#### Do a 'kubectl logs' on the peer pod started above to check whether fabric-ca has been built, and has generated the identities required
#### Look for this log entry: 2019-01-28 03:35:39.458 UTC [nodeCmd] serve -> INFO 020 Started peer with ID=[name:"peer2-org3" ], network ID=[dev], address=[192.168.188.57:7051]
####
# join the channel
# You should see something like this in the peer logs:
# $ kubectl logs peer2-org3-59988dbdf-f29dm  -n org3 -c peer2-org3 | grep org3channel
# 2019-01-28 03:37:32.993 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block
#
# and something similar in the logs for the other org:
# $ kubectl logs peer2-org1-65c97bb4b7-l7cnl -n org1 -c peer2-org1 | grep org3channel
# 2019-01-28 03:37:31.923 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block

response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/join -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","orgs":["org1","org3"]}')
echo $response


