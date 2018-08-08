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

######################################################################################
# The following section will be merged into env.sh and used to configure a remote peer
######################################################################################

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
PEER_ORGS="org7"
PEER_DOMAINS="org7"
PEER_PREFIX="michaelpeer"

# Number of peers in each peer organization
NUM_PEERS=1

REMOTE_PEER=true
