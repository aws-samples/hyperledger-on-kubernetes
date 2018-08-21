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

function updateRepo {
    if [ $# -ne 2 ]; then
        echo "Usage: updateRepo <home-dir> <repo-name>"
        exit 1
    fi
    local HOME=$1
    local REPO=$2
    echo "Updating repo $REPO at $HOME"
    cd $HOME
    if [ ! -d $REPO ]; then
        # clone repo, if it hasn't already been cloned
        git clone https://github.com/MCLDG/$REPO.git
    else
        # update repo, if it has already been cloned
        cd $REPO
        git pull
    fi
    cd $HOME
}

function genTemplates {
    if [ $# -ne 2 ]; then
        echo "Usage: genTemplates <home-dir> <repo-name>"
        exit 1
    fi
    local HOME=$1
    local REPO=$2
    echo "Generating K8s YAML deployment files"
    cd $HOME/$REPO
    gen-fabric.sh
}

function makeDirs {
    if [ $# -ne 1 ]; then
        echo "Usage: makeDirs <data-dir - probably something like /opt/share>"
        echo "input args are '$@'"
        exit 1
    fi
    local DATA=$1
    echo "Making directories at $DATA"
    cd $DATA
    mkdir -p rca-data
    mkdir -p rca-scripts
    mkdir -p orderer
}

function copyScripts {
    if [ $# -ne 3 ]; then
        echo "Usage: copyScripts <home-dir> <repo-name> <data-dir - probably something like /opt/share>"
        exit 1
    fi
    local HOME=$1
    local REPO=$2
    local DATA=$3
    echo "Copying scripts folder from $REPO to $DATA"
    cd $HOME
    sudo cp $HOME/$REPO/scripts/* $DATA/rca-scripts/
    sudo chmod 777 $DATA/rca-scripts/gen-channel-artifacts.sh
}

#merge the contents of the env.sh file
#the env.sh in $SCRIPTS will have been updated with the DNS of the various endpoints, such as ORDERER and
#ANCHOR PEER. We need to merge the contents of env-remote-peer.sh into $SCRIPTS/env.sh in order to retain
#these DNS endpoints as they are used by the remote peer
function mergeEnv {
    if [ $# -ne 4 ]; then
        echo "Usage: mergeEnv <home-dir> <repo-name> <data-dir - probably something like /opt/share> <filename - env file to be merged into main env.sh>"
        exit 1
    fi
    local HOME=$1
    local REPO=$2
    local DATA=$3
    local FILE=$4
    echo "Merging the ENV files"
    cd $HOME/$REPO
    start='^##--BEGIN REPLACE CONTENTS--##$'
    end='^##--END REPLACE CONTENTS--##$'
    newfile=`sed -e "/$start/,/$end/{ /$start/{p; r $FILE
        }; /$end/p; d }" $DATA/rca-scripts/env.sh`
    sudo chown ec2-user $DATA/rca-scripts/env.sh
    echo "$newfile" > $DATA/rca-scripts/env.sh
    cp $DATA/rca-scripts/env.sh scripts/env.sh
}
