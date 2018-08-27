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

function copyEnvToS3 {
    echo "Copying the env file to S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        aws s3api put-object --bucket $S3BucketName --key ${NEW_ORG}/env.sh --body /opt/share/rca-scripts/env.sh
        aws s3api put-object-acl --bucket $S3BucketName ${NEW_ORG} --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketName ${NEW_ORG}/env.sh --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-object-acl --bucket $S3BucketName ${NEW_ORG} --acl public-read
        aws s3api put-object-acl --bucket $S3BucketName ${NEW_ORG}/env.sh --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the env file to S3 complete"
}

function copyEnvFromS3 {
    echo "Copying the env file from S3"
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        aws s3api get-object --bucket $S3BucketName --key ${NEW_ORG}/env.sh /opt/share/rca-scripts/env.sh
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Copying the env file from S3 complete"
}

function createS3Bucket {
    #create the s3 bucket
    echo -e "creating s3 bucket $S3BucketName"
    #quick way of determining whether the AWS CLI is installed and a default profile exists
    if [[ $(aws configure list) && $? -eq 0 ]]; then
        if [[ "$region" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket $S3BucketName --region $region
        else
            aws s3api create-bucket --bucket $S3BucketName --region $region --create-bucket-configuration LocationConstraint=$region
        fi
        aws s3api put-bucket-acl --bucket $S3BucketName --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
        aws s3api put-bucket-acl --bucket $S3BucketName --acl public-read
    else
        echo "AWS CLI is not configured on this node. To run this script install and configure the AWS CLI"
    fi
    echo "Creating the S3 bucket complete"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
region=us-west-2
S3BucketName=mcdg-blockchain-workshop

# This is a little hack I found here: https://stackoverflow.com/questions/8818119/how-can-i-run-a-function-from-a-script-in-command-line
# that allows me to call this bash script and invoke a specific function from the command line
"$@"

