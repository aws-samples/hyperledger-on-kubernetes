# RESTful API to manage the Fabric network

The RESTful API is a Node.js application that uses bash scripts and the Fabric SDK to interact with the Fabric network. The easiest 
location to run the API server is on the bastion host that is provisioned when you create the EKS cluster. You can create the
API server at any time after creating the EKS cluster and bastion. If you create it directly after creating the EKS cluster,
you can start the Fabric network using the API instead of following the steps in [Part 1:](../fabric-main/README.md).


Open the [EKS Readme](../eks/README.md) in this repo and follow the instructions. Once you have an EKS cluster and a
bastion host, come back to this README.

All of the steps in the README are carried out on the bastion host, so SSH into this host before continuing.

The main Node.js application can be found in $REPO/admin-api/app.js.

## Use cases supported by the API

The use cases that the API supports are as follows:

* After creating an EKS cluster, create a new Fabric network. This is the equivalent of running the script ./fabric-main/start-fabric.sh.
It will start an RCA/ICA, register the new org, start the orderer and peer nodes, create the configtx.yaml config, create a channel,
join the peers to the channel, and install/test chaincode
* Add a new org. The API assumes that the new org is going to collaborate with other network members and therefore needs
to be part of a channel profile (defined in configtx.yaml). This also means that the new org has to be defined as a consortium member.
Consortium members are defined in configtx.yaml, and are then encoded in the system channel configuration block. Adding a new
org means that the system channel config must be updated
* Revoking an org. To do this we will revoke the certificates and also update the system channel configuration block, as an extra 
security measure, to make sure that the revoked org is specifically noted in the system channel
* Create a channel profile in configtx.yaml that includes the new org plus the creator org
* Create a channel based on the channel profile above
* Join peers from the new org and the creator org to the channel
* Install, instantiate, test chaincode on the new peers
* Upload the MSP for an org to S3, so that the org owner can setup a remote peer

## Debugging
To turn on debugging, enter this on the command line before starting the node app:

export HFC_LOGGING='{"debug":"console","info":"console"}'


## Pre-requisites

### Fabric Binaries
The API server needs the Fabric binaries so we can run commands such as configtxgen on the bastion host. Install them
as follows:

```bash
cd ~
mkdir fabric-bin
cd fabric-bin/
curl -sSL http://bit.ly/2ysbOFE | bash -s 1.4.0
mv ~/fabric-bin/fabric-samples/bin/* ~/fabric-bin
rm -rf ~/fabric-bin/fabric-samples
```

Edit the file `~/.bash_profile`, and add this line towards the end, just before the export $PATH:

```bash
PATH=$PATH:$HOME/fabric-bin
export PATH
```

Source the file, and check that you can execute the Fabric binaries:

```bash
source ~/.bash_profile 
peer
```

### Configtx.yaml ownership
Change the ownership of the configtx.yaml file, as we will edit it using the API:

```bash
sudo chown ec2-user /opt/share/rca-data/configtx.yaml
```

### Fabric CLI tools pod
Many of the bash scripts are run inside a K8s pod that hosts a Fabric Tools CLI container. Start this pod:

```bash
cd ~
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-cli-org0.yaml     
```

## Step 1 - Install Node
Install Node.js. We will use v8.x.

```
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
```

```
. ~/.nvm/nvm.sh
nvm install lts/carbon
nvm use lts/carbon
```

Amazon Linux seems to be missing g++, so:

```
sudo yum install gcc-c++ -y
```

## Step 2 - Install Node.js dependencies
Install the Node.js dependencies:

```
cd ~/hyperledger-on-kubernetes/admin-api
npm install
```

## Step 3 - expose the Fabric CA so the RESTful API can access it
The API server accesses the Fabric network based on the information provided in the connection-profile folder.

Connection profiles are a construct supported by the Fabric Node SDK. The profile points to a CA (an ICA in our case), 
which is exposed via an AWS NLB. To start the NLBs, run these commands:

```bash
cd ~
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-ica-notls-org1.yaml 
kubectl apply -f k8s/fabric-nlb-ca-org1.yaml
```

## Step 4 - using the API
For information on how to run the API server and use the API, see the sample commands in the script [test.sh](./test.sh).