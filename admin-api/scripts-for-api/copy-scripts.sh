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

set -e

function main {
    echo "Copying scripts to $DATADIR"
    cd $HOME/$REPO/fabric-main
    source util-prep.sh
    # prevent overwriting env.sh if it exists. We use env.sh as a config - it contains the list of orgs in the network
    if [ -f "${SCRIPTS}/env.sh" ]; then
        echo "File ${SCRIPTS}/env.sh exists. I will NOT overwrite it. If you want to overwrite it, copy it manually. Note that I won't be overwriting any scripts in this directory"
    else
        copyScripts $HOME $REPO $DATADIR
    fi
    sudo chown ec2-user $SCRIPTS/env.sh
    echo "Copied scripts to $DATADIR"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
main
