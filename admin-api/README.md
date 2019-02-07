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

## Step 3 - start the Node.js API server
Start the Node.js API server in a Cloud9 terminal session. From Cloud9 SSH into the bastion and start the Node.js API server:

```bash
nvm use lts/carbon
cd ~/hyperledger-on-kubernetes/admin-api
node app.js
```

## Step 4 - start the Fabric network
If you started the Fabric network using the scripts provided in Part 1, you can skip this step. Otherwise, you can start
the Fabric network using the API server.

In a new Cloud9 session, separate from the one where you started the API server, SSH into the bastion and start the Fabric network.
In the ENV variables below, ENDPOINT and PORT point to the API server: 

```bash
export ENDPOINT=localhost
export PORT=4000
echo connecting to server: $ENDPOINT:$PORT

response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/fabric/start -H 'content-type: application/json')
echo $response
```

## Step 5 - prepare the API server
Before running any other API commands, prepare the environment for use:

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

### Expose the Fabric CA so the RESTful API can access it
The API server accesses the Fabric network based on the information provided in the connection-profile folder.

Connection profiles are a construct supported by the Fabric Node SDK. The profile points to a CA (an ICA in our case), 
which is exposed via an AWS NLB. To start the NLBs, run these commands:

```bash
cd ~
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-ica-notls-org1.yaml 
kubectl apply -f k8s/fabric-nlb-ca-org1.yaml
kubectl apply -f k8s/fabric-deployment-ica-notls-org2.yaml 
kubectl apply -f k8s/fabric-nlb-ca-org2.yaml
```

### Update the connection profile
On the bastion, in the $REPO folder where the repo is cloned, update the connection profile to point to your Fabric network. You'll need to
update the URLs for the peers, orderers and CA's. Point them to the NLB endpoints, which you can obtain as follows:

Orderer. Use the NLB endpoint for orderer3-org0-nlb:

```bash
kubectl get svc -n org0

Example:
$ kubectl get svc -n org0
NAME                TYPE           CLUSTER-IP       EXTERNAL-IP                                                                          PORT(S)          AGE
ica-org0            NodePort       10.100.4.38      <none>                                                                               7054:30200/TCP   9m
orderer1-org0       NodePort       10.100.8.16      <none>                                                                               7050:30300/TCP   7m
orderer2-org0       NodePort       10.100.74.8      <none>                                                                               7050:30305/TCP   7m
orderer2-org0-nlb   LoadBalancer   10.100.156.179   a9a4567e129ed11e9b99c0a474a321b2-086b3ae75796ae0a.elb.ap-northeast-1.amazonaws.com   7050:32756/TCP   8m
orderer3-org0       NodePort       10.100.61.128    <none>                                                                               7050:30310/TCP   7m
orderer3-org0-nlb   LoadBalancer   10.100.240.233   a9a824b3b29ed11e9b056065bcb9591f-dc6f98c3c06949eb.elb.ap-northeast-1.amazonaws.com   7050:32397/TCP   8m
rca-org0            NodePort       10.100.10.43     <none>                                                                               7054:30100/TCP   9m
```

CA and Peer for org1. Use the NLB endpoint for ica-notls-org1-nlb and peer1-org1-nlb:

```bash
kubectl get svc -n org1

Example:
$ kubectl get svc -n org1
NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP                                                                          PORT(S)                         AGE
ica-notls-org1       NodePort       10.100.178.61    <none>                                                                               7054:30207/TCP                  25s
ica-notls-org1-nlb   LoadBalancer   10.100.12.87     a081ed08029ef11e9b056065bcb9591f-4a3ec9a04266fec4.elb.ap-northeast-1.amazonaws.com   7054:30587/TCP                  24s
ica-org1             NodePort       10.100.37.188    <none>                                                                               7054:30206/TCP                  11m
peer1-org1           NodePort       10.100.74.71     <none>                                                                               7051:30401/TCP,7052:30402/TCP   9m
peer1-org1-nlb       LoadBalancer   10.100.99.130    aa8188fb929ed11e9b056065bcb9591f-c5d4f3677d637a9d.elb.ap-northeast-1.amazonaws.com   7051:31239/TCP,7052:30837/TCP   10m
peer2-org1           NodePort       10.100.232.164   <none>                                                                               7051:30403/TCP,7052:30404/TCP   9m
rca-org1             NodePort       10.100.219.125   <none>                                                                               7054:30105/TCP                  11m
```

CA and Peer for org2. Use the NLB endpoint for ica-notls-org2-nlb and peer1-org2-nlb:

```bash
kubectl get svc -n org2

Example:
$ kubectl get svc -n org2
NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP                                                                          PORT(S)                         AGE
ica-notls-org2       NodePort       10.100.116.199   <none>                                                                               7054:30213/TCP                  14s
ica-notls-org2-nlb   LoadBalancer   10.100.59.140    a7b5a182429ef11e9b056065bcb9591f-ade2770a6a095ce6.elb.ap-northeast-1.amazonaws.com   7054:31398/TCP                  14s
ica-org2             NodePort       10.100.177.191   <none>                                                                               7054:30212/TCP                  14m
peer1-org2           NodePort       10.100.183.62    <none>                                                                               7051:30406/TCP,7052:30407/TCP   12m
peer1-org2-nlb       LoadBalancer   10.100.33.70     aa85a47e629ed11e9b99c0a474a321b2-20c929c596b04ea3.elb.ap-northeast-1.amazonaws.com   7051:31345/TCP,7052:32370/TCP   13m
peer2-org2           NodePort       10.100.80.48     <none>                                                                               7051:30408/TCP,7052:30409/TCP   12m
rca-org2             NodePort       10.100.75.203    <none>                                                                               7054:30110/TCP                  14m
```

## Step 6 - using the API
For information on how to run the API server and use the API, see the sample commands in the script [test.sh](./test.sh).