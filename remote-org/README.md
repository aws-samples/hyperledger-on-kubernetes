# Hyperledger Fabric on Kubernetes - Part 3: Create a new remote organisation with its own CA

Configure and start a new Hyperledger Fabric organisation in one account, and join it to an existing Fabric network 
running in another account. Then add a peer to the new organisation and join an existing channel.

This differs from other examples provided on the Internet, for example, http://hyperledger-fabric.readthedocs.io/en/release-1.1/channel_update_tutorial.html
and https://www.ibm.com/developerworks/cloud/library/cl-add-an-organization-to-your-hyperledger-fabric-blockchain/index.html.
These examples run a Fabric network on a single host, with all peers co-located, and the ability to share and use certs/keys
belonging to other organisations. Proper Fabric networks should be distributed, with members of the network potentially
being located in different regions and running their peers on different platforms or on-premise. Each Fabric organisation
should maintain its own Certificate Authority (CA) and only share the public keys used to identify the organisation
and its members.

The README below will focus on integrating a new organisation into an existing Fabric network, where the new org could
be running its peers anywhere.

## What is the process for creating a new organisation?
The process for adding a new, remote organisation to an existing network is as follows:

* In an AWS account and/or region different from the main Fabric network, use fabric-CA to generate the certs and keys 
for the new organisation
* Copy the public certs/keys from the new org to the main Fabric network
* In the main Fabric network, an admin user generates a new config block for the new org and updates the channel config
with the new config. This will enable the new org to join an existing channel
* Copy the genesis block of the channel to the new org. Peers in the new org will use this to join the channel
* In the new org, start the peers and join the channel

## Getting Started

### Step 1: Create a Kubernetes cluster
You need an EKS cluster to start. The EKS cluster should be in a different account to the main EKS cluster you created in
Part 1, and could also be in a different region. 

The easiest way to do this is to create an EKS cluster using the eksctl tool. In the same 
VPC as EKS you'll also need an EFS drive (for the Fabric cryptographic material) and an EC2 bastion host, which you'll
use to create and manage the Fabric network. Open the [EKS Readme](../eks/README.md) in this repo and follow the instructions. 
Once you are complete come back to this README.

### Pre-requisites
* SSH into the EC2 instance you created in the new AWS account
* Navigate to the `hyperledger-on-kubernetes` repo
* Edit the file `remote-org/scripts/env-remote-org.sh`. Update the following fields:
    * Set PEER_ORGS to the name of your new organisation. Example: PEER_ORGS="org7"
    * Set PEER_DOMAINS to the domain of your new organisation. Example: PEER_DOMAINS="org7"
    * Set PEER_PREFIX to any name you choose. This will become the name of your peer on the network. 
      Try to make this unique within the network. Example: PEER_PREFIX="michaelpeer"
* Make sure the other properties in this file match your /scripts/env.sh

In the new AWS account:
* Edit the file `./remote-org/step1-mkdirs.sh`, and add the new org and domain to the two ENV variables at the 
top of the file

In the original AWS account with the main Fabric network:
* Edit the file `./remote-org/step3-create-channel-config.sh`, and add the new org and domain to the two ENV variables at the 
top of the file

### Step 1 - make directories
On the EC2 instance in the new org.

Run the script `./remote-org/step1-mkdirs.sh`. 

This creates directories on EFS and copies the ./scripts directory to EFS

### Step 1a - configure env.sh
After completing step 1, copy the file `env.sh` from the EFS drive in your main Fabric network (see /opt/share/rca-scripts/env.sh) 
to the same location in the EFS drive in your new org.

You can do this by either copying and pasting the file contents, or by using the SCP commands used below for copying certificates.

### Step 2 - Create the certs/keys for the new org and copy to Fabric network
On the EC2 instance in the new org.

Run the script `./remote-org/step2-register-new-org.sh`. 

This will start a root CA, and optionally start an intermediate CA. It will then register the organisation with the CA
and generate the certs/keys for the new org.

To join a new Fabric organisation to an existing Fabric network, you need to copy the certificates for the new org
to the existing network. The certificates of interest are the admincerts, cacerts and tlscacerts found in the new
org's msp folder. This folder is located on the EFS drive here: /opt/share/rca-data/orgs/<org name>/msp

Copy the certificate and key information from the new org to the Fabric network in the main Kubernetes cluster, as follows:

* SSH into the EC2 instance you created in the new AWS account, which is hosting the new organisation
* In the home directory, execute `sudo tar cvf org7msp.tar  /opt/share/rca-data/orgs/org7/msp`, to zip up the org's msp
directory. Replace 'org7' with your org name
* Exit the SSH, back to your local laptop or host
* Copy the tar file to your local laptop or host using (replace with your directory name, EC2 DNS and keypair):
  `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key-account1.pem ec2-user@ec2-34-228-23-44.compute-1.amazonaws.com:/home/ec2-user/org7msp.tar /Users/edgema/Documents/apps/hyperledger-on-kubernetes/org7msp.tar`
* Copy the tar file to your SSH EC2 host in your original AWS account (the one hosting the main Fabric network) using (replace with your directory name, EC2 DNS and keypair): 
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key.pem org7msp.tar ec2-user@ec2-18-236-169-96.us-west-2.compute.amazonaws.com:/home/ec2-user/org7msp.tar`
* SSH into the EC2 instance in your original Kubernetes cluster in your original AWS account
* `cd /`
* `sudo tar xvf ~/org7msp.tar` - this should extract they certs for the new org onto the EFS drive, at /opt/share

### Step 2a - Copy the orderer pem file
Copy the orderer cert pem file from the original ec2 instance to the new ec2 instance. The pem file should be in the same
directory on both - i.e. on the EFS drive accessible to the Kuberentes clusters.

You can either use scp for this, or just copy and paste the contents (I use 'vi' to make sure there are no issues with carriage returns/line feeds in the file)

/opt/share/rca-data/org0-ca-chain.pem

### Step 3 - Update channel config to include new org
On the EC2 instance in the existing Fabric network, i.e. where the orderer is running.

* Edit the file `./remote-org/step3-create-channel-config.sh`, and add the new org and domain to the two ENV variables at the 
top of the file
* Run the script `./remote-org/step3-create-channel-config.sh`. 

### Step 4 - Sign channel config created in step 3
On the EC2 instance in the existing Fabric network, i.e. where the orderer is running.

* Run the script `./remote-org/step4-sign-channel-config.sh`.
 
You may need to run this against multiple organisations, depending on how your Fabric network is structured. The channel
config must be signed by the orgs specified in the channel update policy.

### Step 5 - Update channel config created in step 3
On the EC2 instance in the existing Fabric network, i.e. where the orderer is running.

* Run the script `./remote-org/step5-update-channel-config.sh`.

This updates the channel with the new channel config.

### Step 6 - Start the new peer
On the EC2 instance in the new org.

Run the script `./remote-org/step6-start-new-peer.sh`. 

### Step 7 - copy the channel genesis block to the new org
On your local laptop or host.

Copy the <channel-name>.block file from the main Fabric network to the new org, as follows:

* Copy the <channel-name>.block file to your local laptop or host using (replace with your directory name, EC2 DNS and keypair):
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key.pem ec2-user@ec2-18-236-169-96.us-west-2.compute.amazonaws.com:/opt/share/rca-data/mychannel.block mychannel.block`
* Copy the local <channel-name>.block file to the EFS drive in your new AWS account using (replace with your directory name, EC2 DNS and keypair):
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key-account1.pem /Users/edgema/Documents/apps/hyperledger-on-kubernetes/mychannel.block  ec2-user@ec2-34-228-23-44.compute-1.amazonaws.com:/opt/share/rca-data/mychannel.block`

The file <channel-name>.block would have been created when you first created the channel. If you can't find it,
you can always pull it from the channel itself using `peer channel fetch 0 mychannel.block`.

The certificates used when a peer connects to an orderer for channel specific tasks (such as joining a channel
or instantiating chaincode) are the certs contained in the channel config block. It should be pretty obvious that 
the certs for the new org are NOT in the genesis block as the new org did not exist when the genesis block was created. 
However, when the peer joins the channel it will read the blocks in the channel and process each config block in turn,
eventually ending up with the latest config (created in steps 3-5 above).

### Step 8 - Join the channel
On the EC2 instance in the new org.

Run the script `./remote-org/step8-join-channel.sh`. 
