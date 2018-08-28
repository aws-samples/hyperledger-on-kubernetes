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

# Generate a new env.sh file, which includes the new org
# Update the PEER_ORGS & PEER_DOMAINS env variables with the new org info
# I'm sure there's a better way to do this - I'm not the best bash script writer
function genNewEnvAddOrg {
    if [ $# -ne 3 ]; then
        echo "Usage: genNewEnvAddOrg <NEW_ORG> <NEW_DOMAIN> <SCRIPT_DIR>"
        exit 1
    fi
    local NEW_ORG=$1
    local NEW_DOMAIN=$2
    local SCRIPT_DIR=$3
    # get the PEER_ORGS env variable
    ln=`grep -hn 'PEER_ORGS=' ${SCRIPT_DIR}/env.sh`
    # stop processing if env.sh already contains the new org
    if [[ $ln = *"${NEW_ORG}"* ]]; then
        echo "New org '$NEW_ORG' already present in env.sh - no need to generate a new env.sh"
        return
    fi
    envfilename=$SCRIPT_DIR/envaddorgs-`date +%Y%m%d-%H%M`.sh
    cp $SCRIPT_DIR/env.sh $envfilename
    cp $SCRIPT_DIR/env.sh $SCRIPT_DIR/env-orig-`date +%Y%m%d-%H%M`.sh
    # convert it to an array
    IFS=':' read -r -a arr <<< "$ln"
    PEER_ORGS_LINE=${arr[0]}
    PEER_ORGS_STR=${arr[1]}
    # split the string so we get a list of the orgs
    ORGS=`echo $PEER_ORGS_STR | cut -d "=" -f 2`
    # remove the quotes from the orgs
    ORGS=`echo "$ORGS" | sed -e 's/^"//' -e 's/"$//'`
    # add the new org
    ORGS="$ORGS $NEW_ORG"
    # put it all back together
    PEER_ORGS_STR="PEER_ORGS=\"$ORGS\""
    # replace the env variable in the file
    echo New peer orgs ${PEER_ORGS_STR}
    awk -v PEER_ORGS_STR="$PEER_ORGS_STR" -v PEER_ORGS_LINE="$PEER_ORGS_LINE" 'NR==PEER_ORGS_LINE {$0=PEER_ORGS_STR} { print }' $envfilename > tmp && mv tmp $envfilename

    # get the PEER_DOMAINS env variable
    ln=`grep -hn 'PEER_DOMAINS=' ${SCRIPT_DIR}/env.sh`
    # convert it to an array
    IFS=':' read -r -a arr <<< "$ln"
    PEER_DOMAINS_LINE=${arr[0]}
    PEER_DOMAINS_STR=${arr[1]}
    echo $PEER_DOMAINS_LINE
    echo $PEER_DOMAINS_STR
    # split the string so we get a list of the domains
    DOMAINS=`echo $PEER_DOMAINS_STR | cut -d "=" -f 2`
    # remove the quotes from the domains
    DOMAINS=`echo "$DOMAINS" | sed -e 's/^"//' -e 's/"$//'`
    echo $DOMAINS
    # add the new domain
    DOMAINS="$DOMAINS $NEW_DOMAIN"
    # put it all back together
    echo $DOMAINS
    PEER_DOMAINS_STR="PEER_DOMAINS=\"$DOMAINS\""
    echo $PEER_DOMAINS_STR
    # replace the env variable in the file
    echo New peer domains ${PEER_DOMAINS_STR}
    awk -v PEER_DOMAINS_STR="$PEER_DOMAINS_STR" -v PEER_DOMAINS_LINE="$PEER_DOMAINS_LINE" 'NR==PEER_DOMAINS_LINE {$0=PEER_DOMAINS_STR} { print }' $envfilename > tmp && mv tmp $envfilename

    if [ -f "$envfilename" ]; then
        sudo cp $envfilename $SCRIPT_DIR/envaddorgs.sh
    fi
}

# Generate a new env.sh file, which removes the org to be deleted.
# Remove the deleted org from the PEER_ORGS & PEER_DOMAINS env variables
function genNewEnvDeleteOrg {
    if [ $# -ne 3 ]; then
        echo "Usage: genNewEnvDeleteOrg <DELETE_ORG> <DELETE_DOMAIN> <SCRIPT_DIR>"
        exit 1
    fi
    local DELETE_ORG=$1
    local DELETE_DOMAIN=$2
    local SCRIPT_DIR=$3
    # get the PEER_ORGS env variable
    ln=`grep -hn 'PEER_ORGS=' ${SCRIPT_DIR}/env.sh`
    # stop processing if env.sh already contains the new org
    envfilename=$SCRIPT_DIR/envdeleteorgs-`date +%Y%m%d-%H%M`.sh
    if [[ $ln = *"${DELETE_ORG}"* ]]; then
        echo "Org '$DELETE_ORG' present in env.sh - will be removed"
        cp $SCRIPT_DIR/env.sh $envfilename
        cp $SCRIPT_DIR/env.sh $SCRIPT_DIR/env-orig-`date +%Y%m%d-%H%M`.sh
        # convert it to an array
        IFS=':' read -r -a arr <<< "$ln"
        PEER_ORGS_LINE=${arr[0]}
        PEER_ORGS_STR=${arr[1]}
        # split the string so we get a list of the orgs
        ORGS=`echo $PEER_ORGS_STR | cut -d "=" -f 2`
        echo $ORGS
        # remove the org
        delete=($DELETE_ORG)
        allorgs=($ORGS)
        echo ${delete[@]}
        echo ${allorgs[@]}
        neworgs=( "${allorgs[@]/$delete}" )
        echo ${neworgs[@]}
        strorgs="${neworgs[@]}"
        # remove double spaces
        strorgs=`echo $strorgs | tr -s " "`
        echo "Org '$DELETE_ORG' deleted from PEER_ORGS: $strorgs"
        # put it all back together
        PEER_ORGS_STR="PEER_ORGS=$strorgs"
        # replace the env variable in the file
        echo "New peer orgs ${PEER_ORGS_STR}"
        awk -v PEER_ORGS_STR="$PEER_ORGS_STR" -v PEER_ORGS_LINE="$PEER_ORGS_LINE" 'NR==PEER_ORGS_LINE {$0=PEER_ORGS_STR} { print }' $envfilename > tmp && mv tmp $envfilename
    else
        echo "File ${SCRIPT_DIR}/env.sh is missing the org to delete, '$DELETE_ORG', in the PEER_ORGS variable in line '$ln'"
    fi

    # get the PEER_DOMAINS env variable
    ln=`grep -hn 'PEER_DOMAINS=' ${SCRIPT_DIR}/env.sh`
    if [[ $ln = *"${DELETE_DOMAIN}"* ]]; then
        # convert it to an array
        IFS=':' read -r -a arr <<< "$ln"
        PEER_DOMAINS_LINE=${arr[0]}
        PEER_DOMAINS_STR=${arr[1]}
        # split the string so we get a list of the domains
        DOMAINS=`echo $PEER_DOMAINS_STR | cut -d "=" -f 2`
        echo $DOMAINS
        # remove the domain
        delete=($DELETE_DOMAIN)
        alldomains=($DOMAINS)
        newdomains=( "${alldomains[@]/$delete}" )
        strdomains="${newdomains[@]}"
        # remove double spaces
        strdomains=`echo $strdomains | tr -s " "`
        echo "Domain '$DELETE_DOMAIN' deleted from PEER_DOMAINS: $strdomains"
        # put it all back together
        PEER_DOMAINS_STR="PEER_DOMAINS=$strdomains"
        # replace the env variable in the file
        echo "New peer domains ${PEER_DOMAINS_STR}"
        awk -v PEER_DOMAINS_STR="$PEER_DOMAINS_STR" -v PEER_DOMAINS_LINE="$PEER_DOMAINS_LINE" 'NR==PEER_DOMAINS_LINE {$0=PEER_DOMAINS_STR} { print }' $envfilename > tmp && mv tmp $envfilename
    else
        echo "File ${SCRIPT_DIR}/env.sh is missing the domain to delete, '$DELETE_DOMAIN', in the PEER_DOMAINS variable in line '$ln'"
    fi

    if [ -f "$envfilename" ]; then
        sudo cp $envfilename $SCRIPT_DIR/envdeleteorgs.sh
    fi
}
