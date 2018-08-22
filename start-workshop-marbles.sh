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
    echo "Beginning setup of Marbles chaincode for the Fabric workshop ..."
    cd $HOME/$REPO
    source fabric-main/util-prep.sh
    source $SCRIPTS/env.sh
    cd $HOME/$REPO
    source fabric-main/utilities.sh
    startTestMarbles $HOME $REPO
    whatsRunning
    echo "Setup of Marbles chaincode for the Fabric workshop complete"

    echo "Copying the crypto material to S3"
    #create the s3 bucket, used to store the 'tar' of the keys/certs in the EFS directory /opt/share
    echo -e "creating s3 bucket $S3BucketName"
    #quick way of determining whether the AWS CLI is installed and a profile exists
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        if [[ "$region" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket $S3BucketName --region $region
        else
            aws s3api create-bucket --bucket $S3BucketName --region $region --create-bucket-configuration LocationConstraint=$region
        fi
        # 'tar' the keys/certs in the EFS /opt/share directory, and upload to s3
        cd $HOME
        sudo tar -cvf opt.tar /opt/share/
        aws s3api put-object --bucket $S3BucketName --key opt.tar --body opt.tar
        aws s3api put-bucket-acl --bucket $S3BucketName --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketName --key opt.tar --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-bucket-acl --bucket $S3BucketName --acl public-read
        aws s3api put-object-acl --bucket $S3BucketName --key opt.tar --acl public-read
    else
        echo "AWS CLI is not configured on this node. If you want the script to automatically create the S3 bucket, install and configure the AWS CLI"
    fi
    echo "Copying the crypto material to S3 complete"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
region=us-west-2
S3BucketName=mcdg-blockchain-workshop
main

