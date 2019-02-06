#!/usr/bin/env bash

# This file will be backed up for you, but if you want the extra security, you can back it up manually
cp /opt/share/rca-data/configtx.yaml /opt/share/rca-data/configtx-orig.yaml

# To see debug logs
export HFC_LOGGING='{"debug":"console","info":"console"}'

# Start the app in one Cloud9 session
nvm use lts/carbon
cd ~/hyperledger-on-kubernetes/admin-api
node app.js

# In another Cloud9 session run the test cases
export ENDPOINT=localhost
export PORT=4000
echo connecting to server: $ENDPOINT:$PORT

# Get the admin user
response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/users/admin)
echo $response

# Register and enroll a new user within a specific org
USERID=michael
ORG=org1
echo
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/users -H 'content-type: application/json' -d '{"username":"'"${USERID}"'","org":"'"${ORG}"'"}')
echo $response

# Print out the orgs and profiles contained in configtx.yaml and env.sh
response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/env/orgs)
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx/orgs)
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx/profiles)
echo $response

# Print out the ports used by the Kubernetes pods/services contained in env.sh
PORTTYPE=orderer
response=$(curl -s -X GET "http://${ENDPOINT}:${PORT}/env/ports?portType=${PORTTYPE}")
echo $response
PORTTYPE=peer
response=$(curl -s -X GET "http://${ENDPOINT}:${PORT}/env/ports?portType=${PORTTYPE}")
echo $response
PORTTYPE=rca
response=$(curl -s -X GET "http://${ENDPOINT}:${PORT}/env/ports?portType=${PORTTYPE}")
echo $response
PORTTYPE=ica
response=$(curl -s -X GET "http://${ENDPOINT}:${PORT}/env/ports?portType=${PORTTYPE}")
echo $response

########################################################################################################################
# Start a new Fabric network. After creating the EKS cluster and following the steps in the admin-api/README to install
# the API server, start the Fabric network using this API.
#
# You can rerun this as often as necessary. It reads the configuration from ./scripts/env.sh and starts a Fabric
# network using this configuration. In the background it is starting Kubernetes pods, so there is no problem running
# this multiple times.
########################################################################################################################
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/fabric/start -H 'content-type: application/json')
echo $response

########################################################################################################################
# Stop a new Fabric network. Stops everything started by /fabric/start.
# Stop your CLI container before running this, otherwise it will prevent the PV/PVC being deleted.
########################################################################################################################
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/fabric/stop -H 'content-type: application/json')
echo $response

########################################################################################################################
########################################################################################################################
# Add a new org
#
# To add a new org the steps should be carried out in this order
########################################################################################################################
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
####
#### Look for this log entry:
#### $ kubectl logs peer2-org3-6c744b54d-txxt4 -n org3 -c peer2-org3 --tail=20
#### 2019-01-28 03:35:39.458 UTC [nodeCmd] serve -> INFO 020 Started peer with ID=[name:"peer2-org3" ], network ID=[dev], address=[192.168.188.57:7051]
####

# join the channel. After joining the channel you should see something like this in the peer logs:
# $ kubectl logs peer2-org3-59988dbdf-f29dm  -n org3 -c peer2-org3 | grep org3channel
# 2019-01-28 03:37:32.993 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block
#
# and something similar in the logs for the other org:
# $ kubectl logs peer2-org1-65c97bb4b7-l7cnl -n org1 -c peer2-org1 | grep org3channel
# 2019-01-28 03:37:31.923 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block

response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/join -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","orgs":["org1","org3"]}')
echo $response

# install chaincode on all peers belonging to an org
CHANNELNAME=org3channel;
CHAINCODENAME=marblescc;
CHAINCODEVERSION=1.0;
CHAINCODELANGUAGE=golang;
ORG=org3
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/chaincode/install -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","chaincodename":"'"${CHAINCODENAME}"'","chaincodeversion":"'"${CHAINCODEVERSION}"'","chaincodelanguage":"'"${CHAINCODELANGUAGE}"'","org":"'"${ORG}"'"}')
echo $response

# instantiate chaincode on a peer
CHANNELNAME=org3channel;
CHAINCODENAME=marblescc;
CHAINCODEVERSION=1.0;
CHAINCODEINIT={"Args":["init"]};
ORG=org3
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/chaincode/instantiate -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","chaincodename":"'"${CHAINCODENAME}"'","chaincodeversion":"'"${CHAINCODEVERSION}"'","chaincodeinit":"'"${CHAINCODEINIT}"'","org":"'"${ORG}"'"}')
echo $response

########################################################################################################################
########################################################################################################################
# Add a new org with a remote peer, running in another AWS account and possibly a different AWS region
#
# There are a number of ways to do this:
#   See the README in ./remote-org for details on how to setup a remote peer with its own CA.
#   See the README in ./remote-peer for details on how to setup a remote peer where the MSP is provided by the creator org
#
# In this section we will run the CA in the same account/region as the creator org, which means the MSP directory will
# be available in the same EFS location. This is easier because it requires less interaction between the admins of the
# two orgs, however, in a full production environment you would have separate CAs running in separate accounts, each
# generating their own identities, and you would have an out-of-band process to share the public keys between each
# org. This is discussed in detail in the README in ./remote-org
#
# The steps below create a new org, then share the MSP of the org via S3. We then start a new EKS cluster in a
# different account, import the MSP, then start a CA and peer nodes. The peers connect to the orderer in the creator
# Fabric network. This is the same approach taken by ./remote-peer and the workshop in workshop-remote-peer.
#
########################################################################################################################
########################################################################################################################


########################################################################################################################
# Run these steps in the main Fabric network owned by the creator org
########################################################################################################################

# Set the variables
ORG=remoteorg1
PROFILENAME=remoteorg1profile;
CHANNELNAME=remoteorg1channel;

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
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/profiles -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","orgs":["org1","remoteorg1"]}')
echo $response

# create the channel configuration transaction file
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/channelconfigs -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","channelname":"'"${CHANNELNAME}"'"}')
echo $response

# create the channel
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'"}')
echo $response

# org1 joins the channel. After joining the channel you should see something like this in the peer logs:
# $ kubectl logs peer2-org3-59988dbdf-f29dm  -n org3 -c peer2-org3 | grep org3channel
# 2019-01-28 03:37:32.993 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block
#
# and something similar in the logs for the other org:
# $ kubectl logs peer2-org1-65c97bb4b7-l7cnl -n org1 -c peer2-org1 | grep org3channel
# 2019-01-28 03:37:31.923 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block

response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/join -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","orgs":["org1"]}')
echo $response

# install chaincode on all peers belonging to org1
CHANNELNAME=remoteorg1channel;
CHAINCODENAME=marblescc;
CHAINCODEVERSION=1.0;
CHAINCODELANGUAGE=golang;
ORG=org1
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/chaincode/install -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","chaincodename":"'"${CHAINCODENAME}"'","chaincodeversion":"'"${CHAINCODEVERSION}"'","chaincodelanguage":"'"${CHAINCODELANGUAGE}"'","org":"'"${ORG}"'"}')
echo $response

# share the MSP via S3
REGION=ap-southeast-1;
ACCOUNT=295744685835;
ORG=remoteorg1
S3BUCKETNAME=acn-bkt-s3;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/msp/upload -H 'content-type: application/json' -d '{"region":"'"${REGION}"'","account":"'"${ACCOUNT}"'","S3bucketname":"'"${S3BUCKETNAME}"'","org":"'"${ORG}"'"}')
echo $response

########################################################################################################################
# Follow the first part of the README in ./remote-peer to create an EKS cluster in a separate AWS account.
# Then run these steps in the new EKS cluster Fabric network
########################################################################################################################

# Start the app in one Cloud9 session
nvm use lts/carbon
node app.js

# In another Cloud9 session run the test cases
export ENDPOINT=localhost
export PORT=3000
echo connecting to server: $ENDPOINT:$PORT

ORG=remoteorg1

# download and extract the MSP
ORG=remoteorg1
S3BUCKETNAME=acn-bkt-s3;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/msp/download -H 'content-type: application/json' -d '{"S3bucketname":"'"${S3BUCKETNAME}"'","org":"'"${ORG}"'"}')
echo $response

# prepare the remote org
ORG=remoteorg1
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs/remote/setup -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# start a CA and peer for the remote org, which points to the MSP just downloaded
ORG=remoteorg1
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/peers/remote/start -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

# Register a peer for new org - this will generate an identity
ORG=remoteorg1
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
####
#### Look for this log entry:
#### $ kubectl logs peer2-org3-6c744b54d-txxt4 -n org3 -c peer2-org3 --tail=20
#### 2019-01-28 03:35:39.458 UTC [nodeCmd] serve -> INFO 020 Started peer with ID=[name:"peer2-org3" ], network ID=[dev], address=[192.168.188.57:7051]
####

# join the channel. After joining the channel you should see something like this in the peer logs:
# $ kubectl logs peer2-org3-59988dbdf-f29dm  -n org3 -c peer2-org3 | grep org3channel
# 2019-01-28 03:37:32.993 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block
#
# and something similar in the logs for the other org:
# $ kubectl logs peer2-org1-65c97bb4b7-l7cnl -n org1 -c peer2-org1 | grep org3channel
# 2019-01-28 03:37:31.923 UTC [ledgermgmt] CreateLedger -> INFO 022 Creating ledger [org3channel] with genesis block

response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/join -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","orgs":["remoteorg1"]}')
echo $response

# install chaincode on all peers belonging to the new org
CHANNELNAME=remoteorg1channel;
CHAINCODENAME=marblescc;
CHAINCODEVERSION=1.0;
CHAINCODELANGUAGE=golang;
ORG=remoteorg1
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/chaincode/install -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","chaincodename":"'"${CHAINCODENAME}"'","chaincodeversion":"'"${CHAINCODEVERSION}"'","chaincodelanguage":"'"${CHAINCODELANGUAGE}"'","org":"'"${ORG}"'"}')
echo $response

# instantiate chaincode on a peer
CHANNELNAME=remoteorg1channel;
CHAINCODENAME=marblescc;
CHAINCODEVERSION=1.0;
CHAINCODEINIT={"Args":["init"]};
ORG=remoteorg1
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels/chaincode/instantiate -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'","chaincodename":"'"${CHAINCODENAME}"'","chaincodeversion":"'"${CHAINCODEVERSION}"'","chaincodeinit":"'"${CHAINCODEINIT}"'","org":"'"${ORG}"'"}')
echo $response







