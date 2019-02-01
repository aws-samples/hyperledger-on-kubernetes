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

function main {

    echo "Copying the msp material to S3"
    if [[ -z "${S3BUCKETNAME}" ]]; then
      echo "S3BUCKETNAME must be set before calling this script. The bucket we will copy the MSP information to"
      exit 1
    fi
    if [[ -z "${REGION}" ]]; then
      echo "REGION must be set before calling this script. The region to create the S3 bucket in"
      exit 1
    fi
    if [[ -z "${ACCOUNT}" ]]; then
      echo "ACCOUNT must be set before calling this script. The account to share the MSP information with"
      exit 1
    fi
    if [[ -z "${ORG}" ]]; then
      echo "ORG must be set before calling this script. The new org whose peer nodes will run in the other AWS account"
      exit 1
    fi
    #create the s3 bucket, used to store the 'tar' of the keys/certs in the EFS directory /opt/share
    echo -e "creating s3 bucket $S3BUCKETNAME"
    #quick way of determining whether the AWS CLI is installed and a default profile exists
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        # create the bucket if it doesn't exist
        if [[ "$region" == "us-east-1" ]]; then
            aws s3api head-bucket --bucket $S3BUCKETNAME --region $REGION || aws s3api create-bucket --bucket $S3BUCKETNAME --region $REGION
        else
            aws s3api head-bucket --bucket $S3BUCKETNAME --region $REGION || aws s3api create-bucket --bucket $S3BUCKETNAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION
        fi
        # add the bucket policy to limit access to the other account
        sed -e "s/%account%/${ACCOUNT}/g" -e "s/%bucket%/${S3BUCKETNAME}/g" bucket-policy-template.json > bucket-policy.json
        aws s3api put-bucket-policy --bucket $S3BUCKETNAME --policy file://bucket-policy.json

        # 'tar' the keys/certs in the EFS /opt/share directory, and upload to s3
        cd $HOME
        sudo tar -cvf opt.tar /opt/share/rca-data/orgs/${ORG}
        aws s3api put-object --bucket $S3BUCKETNAME --key /${ORG}/opt.tar --body opt.tar
        aws s3api put-object --bucket $S3BUCKETNAME --key /${ORG}/${ORG}-ca-cert.pem --body /opt/share/rca-data/${ORG}-ca-cert.pem
        aws s3api put-object --bucket $S3BUCKETNAME --key /${ORG}/${ORG}-ca-chain.pem --body /opt/share/rca-data/${ORG}-ca-chain.pem
        aws s3api put-object --bucket $S3BUCKETNAME --key /${ORG}/${ORG}channel.block --body /opt/share/rca-data/${ORG}channel.block
    else
        echo "AWS CLI is not configured on this node. If you want the script to automatically create the S3 bucket, install and configure the AWS CLI"
    fi
    echo "Copying the msp material to S3 complete"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
S3BUCKETNAME=$1
REGION=$2
ACCOUNT=$3
ORG=$4
main

