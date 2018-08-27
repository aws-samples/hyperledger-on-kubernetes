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

# This script is used to start a remote peer, in a different account/region to the main Fabric network.
# See the README.md in the remote-peer folder for details.

# these scripts add an org into the Fabric network. The org and its domain are captured in the
# 2 ENV variables below.
NEW_ORG="org7"
NEW_DOMAIN="org7"

set -e

function main {
    echo "Step1: Beginning setup of remote org on Hyperledger Fabric on Kubernetes ..."
    cd $HOME/$REPO
    source fabric-main/util-prep.sh
    updateRepo $HOME $REPO
    makeDirs $DATADIR
    copyScripts $HOME $REPO $DATADIR
    echo "Step1 of remote org on Hyperledger Fabric on Kubernetes complete"
}


SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
main

# create a temp file. The scripts/addorg* shell scripts will check for files; if they find them
# they will setup, join, sign, etc., as necessary.
# this is a cheap and nasty way of sending events. I should change this to use SNS or some other
# mechanism for sending events between the different containers.
DATADIR=/opt/share/
cat > ${DATADIR}/rca-data/updateorg << EOF
${NEW_ORG}
EOF
