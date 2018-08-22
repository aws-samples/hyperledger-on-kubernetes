# Hyperledger Fabric on Kubernetes

This repo allows you to build two types of Hyperledger networks:

* A POC network, consisting of an orderer organisation and two peer organisations, running in a single Kubernetes cluster
in a single AWS account. This is suitable for POC's, or for testing/learning
* A PROD network, consisting of an orderer organisation running in one Kubernetes cluster in one AWS account, and separate
peer organisations running in separate AWS accounts. This resembles a production-ready Hyperledger network where remote
peers from different organisations connect to the network

Step 6 is where you will indicate whether you want to create a POC or PROD environment.

## Getting Started

### Step 1: Create a Kubernetes cluster
You need an EKS cluster to start. The easiest way to do this is to create an EKS cluster using the eksctl tool. Open
the [EKS Readme](../eks/README.md) in this repo and follow the instructions. Once you are complete come back to this README.

### Step 2: Create an EC2 instance and EFS 
You will need an EC2 instance, which you will SSH into in order to start and test the Fabric network. You will 
also need an EFS volume for storing common scripts and public keys. The EFS volume must be accessible from
the Kubernetes cluster. Follow the steps below, which will create the EFS and make it available to the K8s cluster.

```bash
cd
git clone https://github.com/aws-samples/hyperledger-on-kubernetes
```

Check the parameters in efs/deploy-ec2.sh and update them as follows:
* The VPC and Subnet params should be those of your existing K8s cluster worker nodes
* Keyname is an AWS EC2 keypair you own, that you have previously saved to your Mac. You'll need this to access the EC2 
instance created by deploy-ec2.sh
* VolumeName is the name assigned to your EFS volume
* Region should match the region where your K8s cluster is deployed

Once all the parameters are set, in a terminal window run ./efs/deploy-ec2.sh. Check the CFN console for completion. Once 
the CFN stack is complete, SSH to one of the EC2 instances using the keypair above. 

The EFS should be mounted in /opt/share

### Step 3: Prepare the EC2 instance for use
The EC2 instance you have created in Step 2 should already have kubectl installed. However, kubectl will have no
context and will not be pointing to any kubernetes cluster. We need to point it to the K8s cluster we created in Step 1.

The easiest method (though this should be improved) is to copy the contents of your own ~/.kube/config file from 
your Mac (or whichever device you used to create the Kubernetes cluster in Step 1). An alternative method, which I haven't
explored yet, is simply to swap steps 1 & 2, i.e. create the EC2 instance and EFS first, then create the K8s cluster
directly from the EC2 instance.

To copy the kube config, do the following:
* On your Mac, copy the contents of ~/.kube/config
* On the EC2 instance created above, do 'mkdir /home/ec2-user/.kube'
* cd /home/ec2-user/.kube
* vi config
* paste the contents you copied from your Mac

To check that this works execute:

```bash
kubectl get nodes
```

you should see the nodes belonging to your new K8s cluster:

```bash
$ kubectl get nodes
NAME                                           STATUS    ROLES     AGE       VERSION
ip-172-20-123-84.us-west-2.compute.internal    Ready     master    1h        v1.9.3
ip-172-20-124-192.us-west-2.compute.internal   Ready     node      1h        v1.9.3
ip-172-20-49-163.us-west-2.compute.internal    Ready     node      1h        v1.9.3
ip-172-20-58-206.us-west-2.compute.internal    Ready     master    1h        v1.9.3
ip-172-20-81-75.us-west-2.compute.internal     Ready     master    1h        v1.9.3
ip-172-20-88-121.us-west-2.compute.internal    Ready     node      1h        v1.9.3
```

If you are using EKS with the Heptio authenticator, you'll need to follow the instructions here
to get kubectl configured: https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html#eks-prereqs
You will also need to copy your .aws/config and .aws/credentials files 
to the EC2 instance. You'll only need the profile from these files that hosts the EKS workers.

### Step 4: Clone this repo to your EC2 instance
On the EC2 instance created in Step 2 above, in the home directory, clone this repo:

```bash
cd
git clone https://github.com/aws-samples/hyperledger-on-kubernetes
```

### Step 5: Configure the EFS server URL
On the EC2 instance created in Step 2 above, in the newly cloned hyperledger-on-kubernetes directory, update the script 
'gen-fabric.sh' so that the EFSSERVER variable contains the full URL of the EFS server created in 
Step 2. You can obtain the EFS URL from the EFS console. The URL should look something like this:

```bash
EFSSERVER=fs-12a33ebb.efs.us-west-2.amazonaws.com
```

### Step 6: Edit env.sh
On the EC2 instance created in Step 2 above, in the newly cloned hyperledger-on-kubernetes directory, update the script 
'scripts/env.sh' as follows:
 
```bash
cd
cd hyperledger-on-kubernetes/scripts
vi env.sh
```

* Set FABRIC_NETWORK_TYPE  to either "POC" or "PROD", depending on whether you want to build a POC or a PROD network.
    * A POC network, consisting of an orderer organisation and two peer organisations, running in a single Kubernetes cluster
      in a single AWS account. This is suitable for POC's, or for testing/learning
    * A PROD network, consisting of an orderer organisation running in one Kubernetes cluster in one AWS account, and separate
      peer organisations running in separate AWS accounts. This resembles a production-ready Hyperledger network where remote
      peers from different organisations connect to the network

* Change the names and domains or the peer and orderer orgs/domains to match the names you choose.
* Select either "kafka" or "solo" for the ORDERER_TYPE. Make sure you select 'kafka' if you want to build a PROD network.
This is because the remote peers need to connect to an OSN (orderer service node). With Kafka we can run multiple OSN's, 
and have one OSN that exposes an external IP for connection from the remote peer.


### Step 7: Generate the Kubernetes YAML files
On the EC2 instance created in Step 2 above:

```bash
cd
cd hyperledger-on-kubernetes
mkdir /opt/share/rca-scripts
cp scripts/* /opt/share/rca-scripts
```

then, in the home directory:

```bash
cd
cd hyperledger-on-kubernetes/fabric-main
./gen-fabric.sh
```

### Step 8: Start the fabric network
On the EC2 instance created in Step 2 above, in the home directory:

```bash
cd
cd hyperledger-on-kubernetes/fabric-main
./start-fabric.sh
```

### Step 9: Confirm the test cases ran successfully
The test cases are run by deploying 'fabric-deployment-test-fabric.yaml', which executes the script 'test-fabric.sh'.
This will run in the org1 namespace, and will act as a Fabric client.

On the EC2 instance created in Step 2 above:

```bash
kubectl get po -n org1
#look for the test-fabric pod and replace the name in the statement below.
kubectl logs test-fabric-56c5df5dbf-qnrrl -n org1
```

It can take up to 3 minutes for the test cases to run, so don't get too despondent if it seems to take a while to
query or instantiate chaincode.

The final 3 lines of the log file should look as follows:

```bash
##### 2018-04-16 09:08:01 Querying the chaincode in the channel 'mychannel' on the peer 'peer1-org1.org1' as revoked user 'user-org1' ...
##### 2018-04-16 09:08:02 Expected error occurred when the revoked user 'user-org1' queried the chaincode in the channel 'mychannel'
##### 2018-04-16 09:08:02 Congratulations! The tests ran successfully.
```

If you've completed all these steps, you will have a POC network running. If you would like to connect remote peers to 
this network, continue with the steps below.

## Where to from here?
You have a few options:

* create a remote peer in a different AWS account that belongs to an existing organisation (i.e. one of the orgs created above), 
then add this peer to the existing network. See the README in folder `remote-peer`
* create a new organisation in the existing network, and add a new peer for this organisation
* create a new organisation in the existing network, and add a new remote peer for this organisation


### Join the peer to a channel
I've created the script, 'peer-join-channel.sh' to join the peer to the channel and install the chaincode. There is a 
matching YAML in k8s-templates (k8s-templates/fabric-deployment-peer-join-channel.yaml) that will be used to generate a 
single YAML in the k8s folder (by gen-fabric.sh). This YAML is named `k8s/fabric-deployment-peer-join-channel-org1.yaml`,
and once it is deployed to K8s it will invoke 'peer-join-channel.sh' and join the remote peer to the Fabric channel.

If you want to join a different peer or org to the channel besides the one generated for you in
`k8s/fabric-deployment-peer-join-channel-org1.yaml`, simply edit this file and change the peer and domain details. Then:

```bash
kubectl apply -f k8s/fabric-deployment-peer-join-channel-org1.yaml
```

This will connect the new peer to the channel. You can then check the peer logs to ensure
all the TX are being sent to the new peer.


### Step 9: Adding a new org
Execute the script 'start-addorgs.sh'. This does the following:

* Generates a new env.sh file that includes a new org
* copies the new env file (scripts/envaddorgs.sh) as scripts/env.sh. The new file contains org1, org2 and a new org, org3
* Reruns the gen-fabric.sh to generate the templates for org3
* Reruns the same commands as start-fabric.sh, to create the org3 namespace and then start the RCA, ICA and generate the channel artifacts for org3
* Runs the process that creates a new genesis block for the channel (see scripts/addorg*):
    * Generates a new config for the new org
    * Gets the latest config block from the channel
    * Decodes the latest config block and merges in the changes for the new org config
    * Wraps the new config in an envelope
    * Signs the envelope; each peer admin must sign the envelope
    * Updates the channel to include the new config
* Creates a new endorsement policy that includes the new org. This involves:
    * Creating a new version of the chaincode
    * Install the new version of the chaincode on each peer that will endorse it
    * Upgrade the chaincode (similar to instantiate), which includes the new endorsement policy
* Starts the new peers for the new org
* Joins the new org to the channel. At this point it will sync the ledger. Once sync'd it will start endorsing/committing TX

At a more detailed level, the process works as follows:

* addorg-fabric-setup.sh runs in org1. This creates an envelope wrapping the new channel config, as a protobuf (.pb) file.
The file is signed by org1 and stored in the shared EFS drive, at: /$DATA/${NEW_ORG}_config_update_as_envelope.pb
* addorg-fabric-sign.sh runs. This runs in every org except org1, and signs the /$DATA/${NEW_ORG}_config_update_as_envelope.pb file
* addorg-fabric-join.sh runs in the new org and joins the new org to the channel
* addorg-fabric-installcc.sh runs in every org, and installs a new version of the chaincode
* addorg-fabric-upgradecc.sh runs in org1 and upgrades the chaincode, applying the new endorsement policy that allows the
new org to endorse TX

## Paths
Paths are relative to the shared EFS drive:

<share drive> is /opt/share

PVC
rca-scripts-pvc,    rca-scripts-pv, /rca-scripts
rca-org0-pvc,       rca-org0-pv,    /ca


## Ports
org0    rca     7054->30300
        ica     7054->30320 
        orderer       30340

org1    rca     7054->30400
        ica     7054->30420
        orderer       30440
        peer1         30451,30452
        peer2         30453,30454
        
org2    rca     7054->30500
        ica     7054->30520
        orderer       30540
        peer1         30551,30552
        peer2         30553,30554
        
## ENV variables
Fabric is expecting the ENV variables below to contain an array. See this code:

https://github.com/hyperledger/fabric/blob/release-1.1/orderer/common/localconfig/config.go

* ORDERER_GENERAL_TLS_ROOTCAS
* ORDERER_GENERAL_TLS_CLIENTROOTCAS

However, Kubernetes only allows ENV variables in Podspecs to be strings.

Fabric is also expecting these ENV variables to be passed in without quotes, whereas
Kubernetes won't accept boolean ENV variables without quotes. 

* ORDERER_GENERAL_TLS_CLIENTAUTHREQUIRED=true
* ORDERER_GENERAL_TLS_ENABLED=true

I worked around this by moving these ENV variables into scripts/env.sh.

## Key and cert structure
All directories are in /opt/share

### Root CA
After starting the root CA containers (rca):

PEM-encoded CA certificate files for each root CA. These are the root CA public key files.

```bash
$ ls -lt rca-data/
total 12
-rw-r--r-- 1 root root 761 Mar 28 14:17 org2-ca-cert.pem
-rw-r--r-- 1 root root 765 Mar 28 14:13 org1-ca-cert.pem
-rw-r--r-- 1 root root 761 Mar 28 14:13 org0-ca-cert.pem
```

Certificates and TLS certs for the CA

```bash
$ ls -lR /opt/share/rca-org7/
/opt/share/rca-org7/:
total 68
-rw-r--r-- 1 root root   778 Jul 17 13:59 ca-cert.pem
-rw-r--r-- 1 root root 15944 Jul 17 13:59 fabric-ca-server-config.yaml
-rw-r--r-- 1 root root 40960 Jul 17 13:59 fabric-ca-server.db
drwxr-xr-x 5 root root  6144 Jul 17 13:59 msp
-rw-r--r-- 1 root root   912 Jul 17 13:59 tls-cert.pem

/opt/share/rca-org7/msp:
total 12
drwxr-xr-x 2 root root 6144 Jul 17 13:59 cacerts
drwxr-xr-x 2 root root 6144 Jul 17 13:59 keystore
drwxr-xr-x 2 root root 6144 Jul 17 13:59 signcerts

/opt/share/rca-org7/msp/cacerts:
total 0

/opt/share/rca-org7/msp/keystore:
total 8
-rwx------ 1 root root 241 Jul 17 13:59 5b8d841f8b0ca195e18d1c6e6ea40495d6dd3ea2cff05c7b5bf95eff17da25ce_sk
-rwx------ 1 root root 241 Jul 17 13:59 c3f4735f9b1100fd60565bf1c6cfc428a13232c90230af923051be2be55e154f_sk

/opt/share/rca-org7/msp/signcerts:
total 0
```

### Intermediate CA
After starting the intermediate CA containers (ica):

PEM-encoded CA certificate files for each intermediate CA. These are the intermediate CA public key files.

```bash
$ ls -lt rca-data/
total 24
-rw-r--r-- 1 root root 1583 Mar 28 14:24 org1-ca-chain.pem
-rw-r--r-- 1 root root 1575 Mar 28 14:23 org0-ca-chain.pem
-rw-r--r-- 1 root root 1575 Mar 28 14:23 org2-ca-chain.pem
-rw-r--r-- 1 root root  761 Mar 28 14:17 org2-ca-cert.pem
-rw-r--r-- 1 root root  765 Mar 28 14:13 org1-ca-cert.pem
-rw-r--r-- 1 root root  761 Mar 28 14:13 org0-ca-cert.pem
```

Each root and intermediate CA will have its own MSP directory with certs/keys. 

```bash
$ ls -lR /opt/share/ica-org7/
/opt/share/ica-org7/:
total 72
-rw-r--r-- 1 root root   822 Jul 17 13:59 ca-cert.pem
-rw-r--r-- 1 root root  1600 Jul 17 13:59 ca-chain.pem
-rw-r--r-- 1 root root 15928 Jul 17 14:00 fabric-ca-server-config.yaml
-rw-r--r-- 1 root root 40960 Jul 17 14:00 fabric-ca-server.db
drwxr-xr-x 5 root root  6144 Jul 17 13:59 msp
-rw-r--r-- 1 root root   912 Jul 17 14:00 tls-cert.pem

/opt/share/ica-org7/msp:
total 12
drwxr-xr-x 2 root root 6144 Jul 17 13:59 cacerts
drwxr-xr-x 2 root root 6144 Jul 17 14:00 keystore
drwxr-xr-x 2 root root 6144 Jul 17 13:59 signcerts

/opt/share/ica-org7/msp/cacerts:
total 0

/opt/share/ica-org7/msp/keystore:
total 8
-rwx------ 1 root root 241 Jul 17 13:59 9e4c48cf8ad3c756d52939597d53baa8ba1e4d6155041f95a3b287e2366b871b_sk
-rwx------ 1 root root 241 Jul 17 14:00 fc13b53de6bfffee7cb3e23843a480882785c9465b25e2c890f8d0db3d364947_sk

/opt/share/ica-org7/msp/signcerts:
total 0
```

### Registering 
Fabric network users must be registered before they can use the network. Registration involves the registration of users
for three entities:

* Organisation. Certs/keys can be found in /opt/share/rca-data/orgs/<org number>
* Orderer. Certs/keys can be found in /opt/share/rca-data/orgs/org0 (assuming the orderer is org0)
* Peer. 

The 'register-org' script is run after the root and intermediate CA's are started. It does the following:

Enrolls a CA admin bootstrap ID with the CA. This is a user that is CA administrator. The certs for this user are stored internally, inside the 
container, and are not copied to a shared drive.

* client certificate at /root/cas/ica-org7.org7/msp/signcerts/cert.pem
* root CA certificate at /root/cas/ica-org7.org7/msp/cacerts/ica-org7-org7-7054.pem
* intermediate CA certificates at /root/cas/ica-org7.org7/msp/intermediatecerts/ica-org7-org7-7054.pem

The following users are then registered with the CA:
* An admin user for the organisation is registered with the CA. The id of this user is, for example, admin-org7.
* A user for the organisation is registered with the CA. The id of this user is, for example, user-org7.

Finally, the certificates for the organisation are generated and stored in the msp directory. Admincerts will be 
generated if the ADMINCERTS option is true.

The folder structure for the new org MSP looks as follows:

```bash
 sudo ls -lR /opt/share/rca-data/orgs/org7/msp
/opt/share/rca-data/orgs/org7:
total 8
drwxr-xr-x 3 root root 6144 Jul 18 03:11 admin
drwx------ 9 root root 6144 Jul 18 03:11 msp

/opt/share/rca-data/orgs/org7/admin:
total 12
-rwxr-xr-x 1 root root 6540 Jul 18 03:11 fabric-ca-client-config.yaml
drwx------ 7 root root 6144 Jul 18 03:11 msp

/opt/share/rca-data/orgs/org7/admin/msp:
total 20
drwxr-xr-x 2 root root 6144 Jul 18 03:11 admincerts
drwxr-xr-x 2 root root 6144 Jul 18 03:11 cacerts
drwxr-xr-x 2 root root 6144 Jul 18 03:11 intermediatecerts
drwx------ 2 root root 6144 Jul 18 03:11 keystore
drwxr-xr-x 2 root root 6144 Jul 18 03:11 signcerts

/opt/share/rca-data/orgs/org7/admin/msp/admincerts:
total 4
-rw-r--r-- 1 root root 1078 Jul 18 03:11 cert.pem

/opt/share/rca-data/orgs/org7/admin/msp/cacerts:
total 4
-rw-r--r-- 1 root root 778 Jul 18 03:11 ica-org7-org7-7054.pem

/opt/share/rca-data/orgs/org7/admin/msp/intermediatecerts:
total 4
-rw-r--r-- 1 root root 822 Jul 18 03:11 ica-org7-org7-7054.pem

/opt/share/rca-data/orgs/org7/admin/msp/keystore:
total 4
-rwx------ 1 root root 241 Jul 18 03:11 ee4977a001185bc87280ab4177557bc6bea22a89234dd5ed910ee2cddcc52eaa_sk

/opt/share/rca-data/orgs/org7/admin/msp/signcerts:
total 4
-rw-r--r-- 1 root root 1078 Jul 18 03:11 cert.pem

/opt/share/rca-data/orgs/org7/msp:
total 28
drwxr-xr-x 2 root root 6144 Jul 18 03:11 admincerts
drwxr-xr-x 2 root root 6144 Jul 18 03:11 cacerts
drwxr-xr-x 2 root root 6144 Jul 18 03:11 intermediatecerts
drwx------ 2 root root 6144 Jul 18 03:11 keystore
drwxr-xr-x 2 root root 6144 Jul 18 03:11 signcerts
drwxr-xr-x 2 root root 6144 Jul 18 03:11 tlscacerts
drwxr-xr-x 2 root root 6144 Jul 18 03:11 tlsintermediatecerts

/opt/share/rca-data/orgs/org7/msp/admincerts:
total 4
-rw-r--r-- 1 root root 1078 Jul 18 03:11 cert.pem

/opt/share/rca-data/orgs/org7/msp/cacerts:
total 4
-rw-r--r-- 1 root root 778 Jul 18 03:11 ica-org7-org7-7054.pem

/opt/share/rca-data/orgs/org7/msp/intermediatecerts:
total 4
-rw-r--r-- 1 root root 822 Jul 18 03:11 ica-org7-org7-7054.pem

/opt/share/rca-data/orgs/org7/msp/keystore:
total 0

/opt/share/rca-data/orgs/org7/msp/signcerts:
total 0

/opt/share/rca-data/orgs/org7/msp/tlscacerts:
total 4
-rw-r--r-- 1 root root 778 Jul 18 03:11 ica-org7-org7-7054.pem

/opt/share/rca-data/orgs/org7/msp/tlsintermediatecerts:
total 4
-rw-r--r-- 1 root root 822 Jul 18 03:11 ica-org7-org7-7054.pem
```

The 'register-orderer' script is then run. It does the following:

* Each orderer in an organisation is registered with the CA. The id of this user is, for example, orderer1-org7.

The 'register-peer' script is then run. It does the following:

* Each peer in an organisation is registered with the CA. The id of this user is, for example, peer1-org7.

### Peer TLS Certs
Upon starting a new peer, a set of TLS certs are created. We generate a separate set of certs for inbound (i.e. from the
CLI to the peer) and outbound (i.e. from the peer to other components)

```bash
$ ls -lt  /opt/share/rca-data/tls
total 16
-rwx------ 1 root root  241 Jul 17 23:54 michaelpeer1-org7-cli-client.key
-rw-r--r-- 1 root root 1066 Jul 17 23:54 michaelpeer1-org7-cli-client.crt
-rwx------ 1 root root  241 Jul 17 23:54 michaelpeer1-org7-client.key
-rw-r--r-- 1 root root 1066 Jul 17 23:54 michaelpeer1-org7-client.crt
```

The full cert/key directory structure looks as follows:

```bash
# root and intermediate CA public keys. The ca-chain.pem files contain both the root CA and intermediate CA keys
./rca-data/org0-ca-cert.pem
./rca-data/org0-ca-chain.pem
./rca-data/org2-ca-cert.pem
./rca-data/org1-ca-chain.pem
./rca-data/org1-ca-cert.pem
./rca-data/org2-ca-chain.pem

k8s
./rca-data/orgs/org0/msp/tlscacerts/ica-org0-7054.pem
./rca-data/orgs/org0/msp/intermediatecerts/ica-org0-7054.pem
./rca-data/orgs/org0/msp/admincerts/cert.pem
./rca-data/orgs/org0/msp/cacerts/ica-org0-7054.pem
./rca-data/orgs/org0/msp/tlsintermediatecerts/ica-org0-7054.pem
./rca-data/orgs/org0/admin/msp/intermediatecerts/ica-org0-7054.pem
./rca-data/orgs/org0/admin/msp/signcerts/cert.pem
./rca-data/orgs/org0/admin/msp/admincerts/cert.pem
./rca-data/orgs/org0/admin/msp/cacerts/ica-org0-7054.pem

# the root CA public keys are copied to ./rca-data
./rca-org0/tls-cert.pem
./rca-org0/ca-cert.pem
./rca-org1/tls-cert.pem
./rca-org1/ca-cert.pem
./rca-org2/tls-cert.pem
./rca-org2/ca-cert.pem

# the intermediate CA public keys are appended to the root CA public keys to create ca-chain.pem, then copied
# to ./rca-data
./ica-org0/ca-chain.pem
./ica-org0/tls-cert.pem
./ica-org0/ca-cert.pem
./ica-org1/ca-chain.pem
./ica-org1/tls-cert.pem
./ica-org1/ca-cert.pem
./ica-org2/ca-chain.pem
./ica-org2/tls-cert.pem
./ica-org2/ca-cert.pem
```

## ENV Variables

These are the ENV that each peer is started with:

##### 2018-04-15 01:56:05 Starting peer 'peer1-org2' with MSP at '/opt/gopath/src/github.com/hyperledger/fabric/peer/msp'
CORE_PEER_GOSSIP_SKIPHANDSHAKE=true
CORE_VM_DOCKER_ATTACHSTDOUT=true
CORE_PEER_TLS_CLIENTCERT_FILE=/data/tls/peer1-org2-client.crt
CORE_PEER_TLS_ROOTCERT_FILE=/data/org2-ca-chain.pem
CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/tls/server.key
CORE_PEER_GOSSIP_ORGLEADER=false
CORE_PEER_LOCALMSPID=org2MSP
CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/tls/server.crt
CORE_PEER_TLS_CLIENTROOTCAS_FILES=/data/org2-ca-chain.pem
CORE_PEER_TLS_CLIENTKEY_FILE=/data/tls/peer1-org2-client.key
CORE_PEER_TLS_ENABLED=false
CORE_PEER_TLS_CLIENTAUTHREQUIRED=true
CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/msp
CORE_PEER_ID=peer1-org2
CORE_LOGGING_LEVEL=DEBUG
CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer1-org2.org2:7051
CORE_PEER_ADDRESS=peer1-org2.org2:7051
CORE_PEER_GOSSIP_USELEADERELECTION=true

            
## TODO
* Use a DB to store metadata, such as which version of CC is installed, which peers and orgs exist, etc.
* replace the temp files created in start-addorgs.sh with an event based mechanism
* change the channel-artifacts pod to a job instead of a pod
* I've tested with orgs/domains that are the same. Use a different domain name. I'm sure in some places I'm using ORG
instead of DOMAIN. When they differ I'll probably see issues
* sort out the port numbers assigned - they are assigned in order to the ORGS or PEER_ORGS array. After adding/deleting
orgs though, the order becomes mixed up and we end up assigning port numbers to new orgs that are used by existing orgs

## TODO - handle this error
Peer attempts to join channel, fails, but still returns a successful message. Later testing shows it has not joined the channel

##### 2018-05-04 05:47:41 Peer peer1-org3.org3 is attempting to join channel 'mychannel' (attempt #1) ...
output of peer channel join is '2018-05-04 05:47:41.183 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-05-04 05:47:41.183 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-05-04 05:47:41.207 UTC [grpc] Printf -> DEBU 003 grpc: addrConn.resetTransport failed to create client transport: connection error: desc = "transport: Error while dialing dial tcp 100.66.222.193:7051: getsockopt: connection refused"; Reconnecting to {peer1-org3.org3:7051 <nil>}
2018-05-04 05:47:42.208 UTC [grpc] Printf -> DEBU 004 grpc: addrConn.resetTransport failed to create client transport: connection error: desc = "transport: Error while dialing dial tcp 100.66.222.193:7051: getsockopt: connection refused"; Reconnecting to {peer1-org3.org3:7051 <nil>}
2018-05-04 05:47:43.759 UTC [grpc] Printf -> DEBU 005 grpc: addrConn.resetTransport failed to create client transport: connection error: desc = "transport: Error while dialing dial tcp 100.66.222.193:7051: getsockopt: connection refused"; Reconnecting to {peer1-org3.org3:7051 <nil>}
Error: Error getting endorser client channel: endorser client failed to connect to peer1-org3.org3:7051: failed to create new connection: context deadline exceeded
Usage:
  peer channel join [flags]

Flags:
  -b, --blockpath string   Path to file containing genesis block

Global Flags:
      --cafile string                       Path to file containing PEM-encoded trusted certificate(s) for the ordering endpoint
      --certfile string                     Path to file containing PEM-encoded X509 public key to use for mutual TLS communication with the orderer endpoint
      --clientauth                          Use mutual TLS when communicating with the orderer endpoint
      --keyfile string                      Path to file containing PEM-encoded private key to use for mutual TLS communication with the orderer endpoint
      --logging-level string                Default logging level and overrides, see core.yaml for full syntax
  -o, --orderer string                      Ordering service endpoint
      --ordererTLSHostnameOverride string   The hostname override to use when validating the TLS connection to the orderer.
      --tls                                 Use TLS when communicating with the orderer endpoint
  -v, --version                             Display current version of fabric peer server'
##### 2018-05-04 05:47:44 Peer peer1-org3.org3 successfully joined channel 'mychannel'

## TODO - handle this error
Gossip is doing some strange. I add org3, then I delete org3. After this I see the following messages. It seems as though messages are being
gossiped from a peer that can't be identified. Or, Gossip is gossiping the network state and sending information about dead peers. Need to research
how the network state is updated to gossip - i.e. if I remove an org, how does Gossip know?

2018-05-07 08:00:00.654 UTC [endorser] ProcessProposal -> DEBU 168bd Exit: request from%!(EXTRA string=100.96.4.227:43736)
2018-05-07 08:00:00.903 UTC [peer/gossip/sa] OrgByPeerIdentity -> WARN 168be Peer Identity [0a 07 6f 72 67 33 4d 53 50 12 f5 07 2d 2d 2d 2d 2d 42 45 47 49 4e 20 43 45 52 54 49 46 49 43 41 54 45 2d 2d 2d 2d 2d 0a 4d 49 49 43 77 44 43 43 41 6d 61 67 41 77 49 42 41 67 49 55 63 47 35 45 6c 76 6b 6d 2f 44 59 2f 4e 46 65 67 71 35 4e 5a 54 79 38 57 30 66 59 77 43 67 59 49 4b 6f 5a 49 7a 6a 30 45 41 77 49 77 0a 5a 6a 45 4c 4d 41 6b 47 41 31 55 45 42 68 4d 43 56 56 4d 78 46 7a 41 56 42 67 4e 56 42 41 67 54 44 6b 35 76 63 6e 52 6f 49 45 4e 68 63 6d 39 73 61 57 35 68 4d 52 51 77 45 67 59 44 56 51 51 4b 0a 45 77 74 49 65 58 42 6c 63 6d 78 6c 5a 47 64 6c 63 6a 45 50 4d 41 30 47 41 31 55 45 43 78 4d 47 59 32 78 70 5a 57 35 30 4d 52 63 77 46 51 59 44 56 51 51 44 45 77 35 79 59 32 45 74 62 33 4a 6e 0a 4d 79 31 68 5a 47 31 70 62 6a 41 65 46 77 30 78 4f 44 41 31 4d 44 63 77 4e 7a 49 31 4d 44 42 61 46 77 30 78 4f 54 41 31 4d 44 63 77 4e 7a 4d 77 4d 44 42 61 4d 47 30 78 43 7a 41 4a 42 67 4e 56 0a 42 41 59 54 41 6c 56 54 4d 52 63 77 46 51 59 44 56 51 51 49 45 77 35 4f 62 33 4a 30 61 43 42 44 59 58 4a 76 62 47 6c 75 59 54 45 55 4d 42 49 47 41 31 55 45 43 68 4d 4c 53 48 6c 77 5a 58 4a 73 0a 5a 57 52 6e 5a 58 49 78 47 6a 41 4c 42 67 4e 56 42 41 73 54 42 48 42 6c 5a 58 49 77 43 77 59 44 56 51 51 4c 45 77 52 76 63 6d 63 78 4d 52 4d 77 45 51 59 44 56 51 51 44 45 77 70 77 5a 57 56 79 0a 4d 69 31 76 63 6d 63 7a 4d 46 6b 77 45 77 59 48 4b 6f 5a 49 7a 6a 30 43 41 51 59 49 4b 6f 5a 49 7a 6a 30 44 41 51 63 44 51 67 41 45 41 71 7a 79 37 44 6e 34 4e 78 45 4d 46 67 34 7a 4a 63 34 30 0a 2f 57 2b 36 31 6d 6a 50 6a 50 6b 42 6a 42 33 31 61 31 48 36 7a 6c 48 6c 66 75 32 75 73 69 42 52 6f 67 55 6c 30 77 79 65 56 76 67 30 7a 52 6d 4b 71 54 4e 34 68 75 62 68 62 7a 59 35 4a 78 4e 69 0a 4c 4b 4f 42 36 6a 43 42 35 7a 41 4f 42 67 4e 56 48 51 38 42 41 66 38 45 42 41 4d 43 42 34 41 77 44 41 59 44 56 52 30 54 41 51 48 2f 42 41 49 77 41 44 41 64 42 67 4e 56 48 51 34 45 46 67 51 55 0a 42 6c 46 4a 36 6e 2f 53 4c 6a 41 76 64 37 35 45 6c 4b 44 52 4d 61 58 53 2f 34 34 77 48 77 59 44 56 52 30 6a 42 42 67 77 46 6f 41 55 61 2b 67 76 66 6f 69 36 4f 74 59 39 6b 42 5a 73 6c 6f 6e 41 0a 4b 45 41 70 6a 32 34 77 4a 67 59 44 56 52 30 52 42 42 38 77 48 59 49 62 63 47 56 6c 63 6a 49 74 62 33 4a 6e 4d 79 30 33 5a 44 67 31 4e 7a 64 6a 5a 6a 52 6d 4c 58 52 75 63 6d 74 6f 4d 46 38 47 0a 43 43 6f 44 42 41 55 47 42 77 67 42 42 46 4e 37 49 6d 46 30 64 48 4a 7a 49 6a 70 37 49 6d 68 6d 4c 6b 46 6d 5a 6d 6c 73 61 57 46 30 61 57 39 75 49 6a 6f 69 62 33 4a 6e 4d 53 49 73 49 6d 68 6d 0a 4c 6b 56 75 63 6d 39 73 62 47 31 6c 62 6e 52 4a 52 43 49 36 49 6e 42 6c 5a 58 49 79 4c 57 39 79 5a 7a 4d 69 4c 43 4a 6f 5a 69 35 55 65 58 42 6c 49 6a 6f 69 63 47 56 6c 63 69 4a 39 66 54 41 4b 0a 42 67 67 71 68 6b 6a 4f 50 51 51 44 41 67 4e 49 41 44 42 46 41 69 45 41 35 32 78 4f 2f 5a 45 6d 73 5a 2b 36 48 69 6c 66 6f 65 48 68 70 51 6f 6f 49 6f 7a 62 56 4c 6b 2f 5a 6a 4b 52 55 62 65 72 0a 6b 75 73 43 49 46 58 58 32 68 79 59 6a 79 6d 55 56 45 52 36 37 71 37 31 6d 31 32 78 49 32 30 46 61 64 71 31 4c 7a 67 37 38 70 4e 4a 6b 6f 4d 2b 0a 2d 2d 2d 2d 2d 45 4e 44 20 43 45 52 54 49 46 49 43 41 54 45 2d 2d 2d 2d 2d 0a] cannot be desirialized. No MSP found able to do that.
2018-05-07 08:00:00.907 UTC [gossip/gossip] func3 -> WARN 168bf Failed determining organization of [26 58 18 29 202 180 156 78 216 93 10 161 163 196 179 107 97 154 194 136 34 119 134 210 92 50 30 83 103 141 253 117]
2018-05-07 08:00:01.394 UTC [blocksProvider] DeliverBlocks -> DEBU 168c0 [mychannel] Adding payload locally, buffer seqNum = [209], peers number [3]

## Done
* Script the start/stop of the fabric network. Include in the script ways to check that each component starts/stops
as expected before moving on to the next stage - done. See start-fabric.sh
* Script the creation of the deployment.yamls so that they are created based on the number of orderers/peers
defined in env.sh, rather than being hardcoded - done. See gen-fabric.sh
* Use Kafka as orderer instead of solo - I have setup this, but could not get it to work. See troublshooting section
* Add a new org as a member of the network
* In start-addorgs.sh, we should also add the new org as an endorser. This requires a change to the endorsement
   policy, which necessitates a 'peer chaincode upgrade'. This will execute system chaincode
   and add a new block to the channel reflecting the addition of the new org to the endorsement policy.
   http://hyperledger-fabric.readthedocs.io/en/release-1.1/channel_update_tutorial.html

## Humble beginnings            
This repo started life as a port of the Hyperledger Fabric Samples fabric-ca component, found in the Fabric Samples, here:

See: https://github.com/hyperledger/fabric-samples/tree/v1.1.0/fabric-ca
