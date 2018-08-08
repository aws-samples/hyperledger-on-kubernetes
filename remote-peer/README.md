# Hyperledger Fabric on Kubernetes - starting a remote peer

Configure and start a Hyperledger Fabric peer in one account that connects to a Fabric network in another account. The
peer belongs to one of the organisations already present in the Fabric network.

### Create a Kubernetes cluster in the new account
Repeat steps 1-7 under Getting Started in the main README in a different AWS account. You can also use a different region.

### How does a remote peer connect to a Fabric network?
A remote peer connects to the orderer service according to the following process:

* The orderer URL and port is written in the configtx.yaml file, and encoded into the genesis block of a channel
* Before a peer joins an existing channel, the genesis block (or channel config block) must be available, so that the peer can execute:
`peer channel join -b /$DATA/$CHANNEL_NAME.block`
* The peer joins the channel and receives a copy of the genesis block, which contains the orderer endpoint and the TLS
cert for the orderer. 
* The peer establishes a connection to the orderer based on this information

To establish this connection between a remote peer running in one AWS account and the orderer running in another AWS account,
I use NLB (network load balancer) to expose the gRPC endpoints of peers and orderers. 

This requires the following to be configured in order to connect a remote peer:

* AnchorPeers->Host in configtx.yaml must be an external DNS. I expose the peer using an NLB, and update this configuration
 variable with the NLB endpoint (see the script gen-channel-artifacts.sh)
* Profile-><profile name>->Orderer->Addresses in configtx.yaml must contain an external DNS for the orderer service node 
endpoint. It can contain a mix of internal and external DNS entries. I run 2x orderer service nodes, expose them using NLB, 
and update this configuration variable with the local and NLB endpoints. The peers will loop through all the endpoints 
until they find one that works. This means that peers local to the orderer and remote peers will be able to connect to 
the orderer endpoint (see the script gen-channel-artifacts.sh)
* ORDERER_HOST in k8s/fabric-deployment-orderer1-org0.yaml must be updated with the NLB endpoint as this is used as the
host URL when generating the TLS cert for the orderer, so it's important it matches the URL the orderer is listening on 
(i.e. the NLB endpoint) (see the script utilities.sh)
* The following ENV variables must be updated in the peer. These are updated in env.sh (if required), and also in the 
k8s/fabric-deployment-peer..... yaml files (see the script utilities.sh):
    * PEER_HOST
    * CORE_PEER_ADDRESS
    * CORE_PEER_GOSSIP_EXTERNALENDPOINT

Note that these steps are already done for you in the scripts. If [ $FABRIC_NETWORK_TYPE == "PROD" ] (see env.sh), the
scripts will create an NLB for the orderer and the anchor peers, and update env.sh with the NLB DNS. These details then 
find their way into configtx.yaml, and therefore into mychannel.block. See configtx.yaml, which should contain something 
similar to this:

```bash
Profiles:

  OrgsOrdererGenesis:
    Orderer:
      # Orderer Type: The orderer implementation to start
      # Available types are "solo" and "kafka"
      OrdererType: kafka
      Addresses:
        - a350740ea6df511e88a810af1c0a30f8-5dfb744db3223cc4.elb.us-west-2.amazonaws.com:7050
        - orderer1-org0.org0:7050
```

### Configure the remote peer
These steps will join a new remote peer to a channel, and connect it to the orderer service and other anchor peers so 
that the ledger state can be replicated. New peers have no state (i.e. no ledger or world state) and by default do not
belong to any channel. They do not have chaincode installed, which means they won't be able to take part in any TX. The
scripts will take care of this by creating a new peer, joining the channel and installing chaincode.

If you are creating a brand new peer you'll need the certificate and key information for the organisation the peer belongs
to. The steps below are a quick and dirty way of obtaining this info - not recommended for production use. For production use,
you should create a new organisation, generate the certs and keys for the new org, add the new organisation to the channel 
config, then start the peers for the new org. See the README under ./remote-org for details on how to do this.

However, a quick method of setting up a remote peer for an existing org involves copying the existing crypto material.
This step assumes you have setup a Kubernetes cluster in your new AWS account, with the included EFS drive, as indicated
at the top of this README.

Copy the certificate and key information from the main Kubernetes cluster, as follows:

* SSH into the EC2 instance you created in Step 2, for the original Kubernetes cluster in your original AWS account
* In the home directory, execute `sudo tar -cvf opt.tar /opt/share/`, to zip up the mounted EFS directory with all the certs and keys
* Exit the SSH, back to your local laptop or host
* Copy the tar file to your local laptop or host using (replace with your directory name, EC2 DNS and keypair):
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key.pem ec2-user@ec2-18-236-169-96.us-west-2.compute.amazonaws.com:/home/ec2-user/opt.tar opt.tar`
* Copy the local tar file to your the SSH EC2 host in your new AWS account using (replace with your directory name, EC2 DNS and keypair):
`scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key-account1.pem /Users/edgema/Documents/apps/hyperledger-on-kubernetes/opt.tar  ec2-user@ec2-34-228-23-44.compute-1.amazonaws.com:/home/ec2-user/opt.tar`
* SSH into the EC2 instance you created in the new AWS account
* `cd /`
* `sudo rm -rf /opt/share`
* `tar xvf ~/opt.tar` - this should extract all the crypto material onto the EFS drive, at /opt/share

A couple of configuration steps are required before starting the new peer:

* SSH into the EC2 instance you created in the new AWS account
* Navigate to the `hyperledger-on-kubernetes` repo
* Edit the file `remote-peer/scripts/env-remote-peer.sh`. Update the following fields:
    * Set PEER_ORGS to one of the organisations in the Fabric network. Example: PEER_ORGS="org1"
    * Set PEER_DOMAINS to one of the domains in the Fabric network. Example: PEER_DOMAINS="org1"
    * Set PEER_PREFIX to any name you choose. This will become the name of your peer on the network. 
      Try to make this unique within the network. Example: PEER_PREFIX="michaelpeer"
* Make sure the other properties in this file match your /scripts/env.sh

We are now ready to start the new peer. On the EC2 instance in the new account created above, in the repo directory, run:

```bash

./remote-peer/start-remote-peer.sh
```

This will do the following:

* Create a merged copy of env.sh on the EFS drive (i.e. in /opt/share/rca-scripts), which includes the selections you
made above (e.g. PEER_PREFIX)
* Generate a kubernetes deployment YAML for the remote peer
* Start a local certificate authority (CA). You'll need this to generate a new user for your peer
* Register your new peer with the CA
* Start the new peer

The peer will start, but will not be joined to any channels. At this point the peer has little use as it does not 
maintain any ledger state. To start building a ledger on the peer we need to join a channel.

### Join the peer to a channel
I've created a Kubernetes deployment YAML that will deploy a POD to execute a script, `test-fabric-marbles`, that will
join the peer created above to a channel (the channel name is in env.sh), install the marbles demo chaincode, and 
execute a couple of test transactions. Run the following:

```bash
kubectl apply -f k8s/fabric-deployment-test-fabric-marbles.yaml
```

This will connect the new peer to the channel. You should then check the peer logs to ensure
all the TX are being sent to the new peer. If there are existing blocks on the channel you should see them
replicating to the new peer. Look for messages in the log file such as `Channel [mychannel]: Committing block [14385] to storage`.
