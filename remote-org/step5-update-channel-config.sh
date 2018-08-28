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

# this script updates the channel config created in Step 3. This will write the channel config to the channel as a block.

function main {
    file=/${DATADIR}/rca-data/updateorg
    if [ -f "$file" ]; then
       NEW_ORG=$(cat $file)
       echo "File '$file' exists - new org is '$NEW_ORG'"
    else
       echo "File '$file' does not exist - cannot determine new org. Exiting..."
       exit 1
    fi

    log "Step4: Updating channel config for new org $NEW_ORG ..."
    #Now we need to update the channel config to add the new org
    set +
    getAdminOrg
    updateConfOrgFabric $HOME $REPO $ADMINORG
}

DATADIR=/opt/share/
SCRIPTS=$DATADIR/rca-scripts
REPO=hyperledger-on-kubernetes
source $SCRIPTS/env.sh
source $HOME/$REPO/fabric-main/signorgconfig.sh
main



