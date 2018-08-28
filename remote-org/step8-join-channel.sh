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

# This script is used to join a remote peer to a channel, in a different account/region to the main Fabric network.

set -e

function main {
    file=/${DATADIR}/rca-data/updateorg
    if [ -f "$file" ]; then
       NEW_ORG=$(cat $file)
       echo "File '$file' exists - new org is '$NEW_ORG'"
    else
       echo "File '$file' does not exist - cannot determine new org. Exiting..."
       exit 1
    fi

    log "Step8: Peer for $NEW_ORG joining channel"
    cd $HOME/$REPO
    joinaddorgFabric $HOME $REPO $NEW_ORG

    echo "Step8: Joining channel complete"
}

SDIR=$(dirname "$0")
DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
source $HOME/$REPO/fabric-main/utilities.sh
main

