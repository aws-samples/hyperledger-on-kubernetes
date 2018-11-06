#!/usr/bin/env bash

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

set +e

NEW_ORG="org7"

# copy the file env.sh from the Fabric orderer network to S3
function copyEnvToS3 {
    echo "Copying the env file to S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        aws s3api put-object --bucket $S3BucketNameOrderer --key ${NEW_ORG}/env.sh --body ${SCRIPTS}/env.sh
        aws s3api put-object-acl --bucket $S3BucketNameOrderer --key ${NEW_ORG}/env.sh --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketNameOrderer --key ${NEW_ORG}/env.sh --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the env file to S3 complete"
}

# copy the file env.sh from S3 to the new Fabric org
function copyEnvFromS3 {
    echo "Copying the env file from S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        sudo chown ec2-user ${SCRIPTS}/env.sh
        aws s3api get-object --bucket $S3BucketNameOrderer --key ${NEW_ORG}/env.sh ${SCRIPTS}/env.sh
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the env file from S3 complete"
}

# copy the certificates for the new Fabric org to S3
function copyCertsToS3 {
    echo "Copying the certs for the new org to S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        cd $HOME
        sudo tar -cvf ${NEW_ORG}msp.tar ${DATA}/orgs/${NEW_ORG}/msp
        aws s3api put-object --bucket $S3BucketNameNewOrg --key ${NEW_ORG}/${NEW_ORG}msp.tar --body ${NEW_ORG}msp.tar
        aws s3api put-object-acl --bucket $S3BucketNameNewOrg --key ${NEW_ORG}/${NEW_ORG}msp.tar --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketNameNewOrg --key ${NEW_ORG}/${NEW_ORG}msp.tar --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the certs for the new org to S3 complete"
}

# copy the certificates for the new Fabric org from S3 to the Fabric orderer network
function copyCertsFromS3 {
    echo "Copying the certs from S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        aws s3api get-object --bucket $S3BucketNameNewOrg --key ${NEW_ORG}/${NEW_ORG}msp.tar ~/${NEW_ORG}msp.tar
        cd /
        sudo tar xvf ~/${NEW_ORG}msp.tar
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the certs from S3 complete"
}

# copy the orderer PEM file from the Fabric orderer network to S3
function copyOrdererPEMToS3 {
    echo "Copying the orderer PEM file to S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        aws s3api put-object --bucket $S3BucketNameOrderer --key org0/org0-ca-chain.pem --body ${DATA}/org0-ca-chain.pem
        aws s3api put-object-acl --bucket $S3BucketNameOrderer --key org0/org0-ca-chain.pem --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketNameOrderer --key org0/org0-ca-chain.pem --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the orderer PEM file to S3 complete"
}

# copy the orderer PEM file from S3 to the new Fabric org
function copyOrdererPEMFromS3 {
    echo "Copying the orderer PEM file from S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        sudo chown ec2-user ${DATA}/org0-ca-chain.pem
        aws s3api get-object --bucket $S3BucketNameOrderer --key org0/org0-ca-chain.pem ${DATA}/org0-ca-chain.pem
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the orderer PEM file from S3 complete"
}

# copy the Channel Genesis block from the Fabric orderer network to S3
function copyChannelGenesisToS3 {
    echo "Copying the Channel Genesis block to S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        aws s3api put-object --bucket $S3BucketNameOrderer --key org0/mychannel.block --body ${DATA}/mychannel.block
        aws s3api put-object-acl --bucket $S3BucketNameOrderer --key org0/mychannel.block --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketNameOrderer --key org0/mychannel.block --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the Channel Genesis block to S3 complete"
}

# copy the Channel Genesis block from S3 to the new Fabric org
function copyChannelGenesisFromS3 {
    echo "Copying the Channel Genesis block from S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        sudo chown ec2-user ${DATA}/mychannel.block
        aws s3api get-object --bucket $S3BucketNameOrderer --key org0/mychannel.block ${DATA}/mychannel.block
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the Channel Genesis block from S3 complete"
}

# create S3 bucket to copy files from the Fabric orderer organisation. Bucket will be read-only to other organisations
function createS3BucketForOrderer {
    #create the s3 bucket
    echo -e "creating s3 bucket for orderer org: $S3BucketNameOrderer"
    #quick way of determining whether the AWS CLI is installed and a default profile exists
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        if [[ "$region" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket $S3BucketNameOrderer --region $region
        else
            aws s3api create-bucket --bucket $S3BucketNameOrderer --region $region --create-bucket-configuration LocationConstraint=$region
        fi
        aws s3api put-bucket-acl --bucket $S3BucketNameOrderer --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-bucket-acl --bucket $S3BucketNameOrderer --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Creating the S3 bucket complete"
}

# create S3 bucket to copy files from the new organisation. Bucket will be read-only to other organisations
function createS3BucketForNewOrg {
    #create the s3 bucket
    echo -e "creating s3 bucket for new org $NEW_ORG: $S3BucketNameNewOrg"
    #quick way of determining whether the AWS CLI is installed and a default profile exists
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        if [[ "$region" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket $S3BucketNameNewOrg --region $region
        else
            aws s3api create-bucket --bucket $S3BucketNameNewOrg --region $region --create-bucket-configuration LocationConstraint=$region
        fi
        aws s3api put-bucket-acl --bucket $S3BucketNameNewOrg --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-bucket-acl --bucket $S3BucketNameNewOrg --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Creating the S3 bucket complete"
}

DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
DATA=$DATADIR/rca-data
region=us-west-2
S3BucketNameOrderer=mcdg-blockchain-orderer
S3BucketNameNewOrg=mcdg-blockchain-neworg

# This is a little hack I found here: https://stackoverflow.com/questions/8818119/how-can-i-run-a-function-from-a-script-in-command-line
# that allows me to call this bash script and invoke a specific function from the command line
"$@"

