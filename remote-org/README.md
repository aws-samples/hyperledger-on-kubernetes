# Hyperledger Fabric on Kubernetes - Part 3: Create a new remote organisation with its own CA

Configure and start a new Hyperledger Fabric organisation in one account, and join it to an existing Fabric network 
running in another account. Then add a peer to the new organisation and join an existing channel. Do this in such a way
that we mimic a proper Fabric network, i.e. the new Fabric organisation uses its own CA and manages its own keys, certs
and identities.

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
* Copy a minimal subset of public certs/keys from the new org to the main Fabric network
* In the main Fabric network, an admin user generates a new config block for the new org and updates the channel config
with the new config. This will enable the new org to join an existing channel
* Copy the genesis block of the channel to the new org. Peers in the new org will use this to join the channel
* In the new org, start the peers and join the channel

The tasks above are carried out by different parties. Some tasks are carried out by the admin of the Fabric orderer
organisation, and other tasks are carried out by the admin of the new organisation. Each of the steps below will make it 
clear which party carries out which steps.

## Getting Started

### Step 0: Create a Kubernetes cluster - New Fabric Org
You need an EKS cluster to start. The EKS cluster should be in a different account to the main EKS cluster you created in
Part 1, and could also be in a different region. 

The easiest way to do this is to create an EKS cluster using the eksctl tool. In the same 
VPC as EKS you'll also need an EFS drive (for the Fabric cryptographic material) and an EC2 bastion host, which you'll
use to create and manage the Fabric network. Open the [EKS Readme](../eks/README.md) in this repo and follow the instructions. 
Once you are complete come back to this README.

### Pre-requisites
* SSH into the EC2 bastion you created in the new AWS account
* Navigate to the `hyperledger-on-kubernetes` repo
* Edit the file `remote-org/scripts/env-remote-org.sh`. Update the following fields:
    * Set PEER_ORGS to the name of your new organisation. Example: PEER_ORGS="org7"
    * Set PEER_DOMAINS to the domain of your new organisation. Example: PEER_DOMAINS="org7"
    * Set PEER_PREFIX to any name you choose. This will become the name of your peer on the network. 
      Try to make this unique within the network. Example: PEER_PREFIX="michaelpeer"
* Make sure the other properties in this file match your /scripts/env.sh

In the new AWS account:
* Edit the file `remote-org/step1-mkdirs.sh`, and add the new org and domain to the two ENV variables at the 
top of the file

In the new AWS account:
* Edit the file `remote-org/scripts/copy-tofrom-S3.sh`, and add the new org to the ENV variable at the 
top of the file

In the original AWS account with the main Fabric network:
* Edit the file `remote-org/step3-create-channel-config.sh`, and add the new org and domain to the two ENV variables at the 
top of the file

### Step 1 - make directories - New Fabric Org
On the EC2 bastion in the new org.

Run the script:

```bash
./remote-org/step1-mkdirs.sh
```

This creates directories on EFS and copies the ./scripts directory to EFS

### Step 1a - copy env.sh
After completing step 1, copy the file `env.sh` from the EFS drive in your main Fabric network (see /opt/share/rca-scripts/env.sh) 
to the same location in the EFS drive in your new org. This file contains the configuration of the Fabric network and the 
public endpoints of the Orderer Service Node. It also contains the default username/passwords for various users in the
Fabric network. In a production network you would not be sharing these via a configuration file.

You can do this using the S3 method below, or by copying and pasting the file contents, or by using the SCP. If you
choose to copy/paste the file contents, be careful of the line feeds. Cloud9 seems to update multi-line strings, such as
long keys, by adding line feeds. 

To copy using S3:

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyEnvToS3
```

On the EC2 bastion in the new org.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyEnvFromS3
```

### Step 2 - Create the public certs/keys for the new org and copy to Fabric network - New Fabric Org
On the EC2 bastion in the new org.

Run the script:

```bash
./remote-org/step2-register-new-org.sh
```

This will start a root CA, and optionally start an intermediate CA. It will then register the new organisation with the CA
and generate the certs/keys for the new org. The keys will be stored in EFS, which is mapped as /opt/share in both your
EC2 bastion and your Kubernetes worker nodes (this is done in Part 1, when you built the EKS cluster).

Once the script completes, check the logs of the register pod in EKS to confirm it has registered and enrolled the appropriate
identities:

```bash
kubectl logs register-org-org7-85cbf5997b-ggmkr -n org7
```

You'll see a lot of output, but you should not see any errors. The final log entries should look something like this:

```bash
POST https://ica-org7.org7:7054/enroll
{"hosts":["register-org-org7-85cbf5997b-ggmkr"],"certificate_request":"-----BEGIN CERTIFICATE REQUEST-----\nMIIBXTCCAQQCAQAwYjELMAkGA1UEBhMCVVMxFzAVBgNVBAgTDk5vcnRoIENhcm9s\naW5hMRQwEgYDVQQKEwtIeXBlcmxlZGdlcjEPMA0GA1UECxMGRmFicmljMRMwEQYD\nVQQDEwphZG1pbi1vcmc3MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEhQ983WS3\nZKgHq7qDK0Z09T4lkp+WVpZnrtneTdTQH5NljN9+JAXS8noS4wtoiiCVGZR6lPUw\n6ldU9G2EmcDPcqBAMD4GCSqGSIb3DQEJDjExMC8wLQYDVR0RBCYwJIIicmVnaXN0\nZXItb3JnLW9yZzctODVjYmY1OTk3Yi1nZ21rcjAKBggqhkjOPQQDAgNHADBEAiB+\nSH9HIaQOXGIIv2nMCLt9ayHoe5X4/lwKyuiKDABiXAIgZBEcPg5O1VyBbIYNhi7k\nSS3AFRLzy58Kym7TWqavhcM=\n-----END CERTIFICATE REQUEST-----\n","profile":"","crl_override":"","label":"","NotBefore":"0001-01-01T00:00:00Z","NotAfter":"0001-01-01T00:00:00Z","CAName":""}
2018/08/27 10:08:49 [DEBUG] Received response
statusCode=201 (201 Created)
2018/08/27 10:08:49 [DEBUG] Response body result: map[Cert:LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM3ekNDQXBhZ0F3SUJBZ0lVVm1SaVEvblN2Q01GOEZTMWlFYVVNSmhqVzlnd0NnWUlLb1pJemowRUF3SXcKWmpFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1kyeHBaVzUwTVJjd0ZRWURWUVFERXc1eVkyRXRiM0puCk55MWhaRzFwYmpBZUZ3MHhPREE0TWpjeE1EQTBNREJhRncweE9UQTRNamN4TURBNU1EQmFNRzh4Q3pBSkJnTlYKQkFZVEFsVlRNUmN3RlFZRFZRUUlFdzVPYjNKMGFDQkRZWEp2YkdsdVlURVVNQklHQTFVRUNoTUxTSGx3WlhKcwpaV1JuWlhJeEhEQU5CZ05WQkFzVEJtTnNhV1Z1ZERBTEJnTlZCQXNUQkc5eVp6RXhFekFSQmdOVkJBTVRDbUZrCmJXbHVMVzl5Wnpjd1dUQVRCZ2NxaGtqT1BRSUJCZ2dxaGtqT1BRTUJCd05DQUFTRkQzemRaTGRrcUFlcnVvTXIKUm5UMVBpV1NuNVpXbG1ldTJkNU4xTkFmazJXTTMzNGtCZEx5ZWhMakMyaUtJSlVabEhxVTlURHFWMVQwYllTWgp3TTl5bzRJQkZ6Q0NBUk13RGdZRFZSMFBBUUgvQkFRREFnZUFNQXdHQTFVZEV3RUIvd1FDTUFBd0hRWURWUjBPCkJCWUVGT3E5STFZeFZOUTFQQVFjaVZRRTBVMmp6cGFqTUI4R0ExVWRJd1FZTUJhQUZQWnA3MEJWZ3ZyYVBRdmsKV1pBMk1NSVF4bmJOTUMwR0ExVWRFUVFtTUNTQ0luSmxaMmx6ZEdWeUxXOXlaeTF2Y21jM0xUZzFZMkptTlRrNQpOMkl0WjJkdGEzSXdnWU1HQ0NvREJBVUdCd2dCQkhkN0ltRjBkSEp6SWpwN0ltRmlZV011YVc1cGRDSTZJblJ5CmRXVWlMQ0poWkcxcGJpSTZJblJ5ZFdVaUxDSm9aaTVCWm1acGJHbGhkR2x2YmlJNkltOXlaekVpTENKb1ppNUYKYm5KdmJHeHRaVzUwU1VRaU9pSmhaRzFwYmkxdmNtYzNJaXdpYUdZdVZIbHdaU0k2SW1Oc2FXVnVkQ0o5ZlRBSwpCZ2dxaGtqT1BRUURBZ05IQURCRUFpQXBmVCs2UE04QlBUTEExVTlTekZLenFBMzBXa1lHYXlPNFpEZmJoT055CnR3SWdUOWZkY3ozWDJsS2MxSHFZdVFGdFBVYURpSXZhb3FYWElKQzNiRHlyeHhNPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg== ServerInfo:map[CAName:ica-org7.org7 CAChain:LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNNakNDQWRtZ0F3SUJBZ0lVT2pTakZyeDdQK2o2ODdiZStnUHp0R2djU2NZd0NnWUlLb1pJemowRUF3SXcKWlRFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puCk55NXZjbWMzTUI0WERURTRNRGd5TnpFd01ETXdNRm9YRFRJek1EZ3lOakV3TURnd01Gb3daakVMTUFrR0ExVUUKQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRS0V3dEllWEJsY214bApaR2RsY2pFUE1BMEdBMVVFQ3hNR1kyeHBaVzUwTVJjd0ZRWURWUVFERXc1eVkyRXRiM0puTnkxaFpHMXBiakJaCk1CTUdCeXFHU000OUFnRUdDQ3FHU000OUF3RUhBMElBQkl1by9EVTVYNERhSDk1VURwTVF4M0hvMkF1OE03MmwKemszUnRmZ0l1SWc3WjY5MFJ3NGlVY21KeDFZUDRRTEVqTVlpWmkzWnByVG0yczh1U3dVKzVvaWpaakJrTUE0RwpBMVVkRHdFQi93UUVBd0lCQmpBU0JnTlZIUk1CQWY4RUNEQUdBUUgvQWdFQU1CMEdBMVVkRGdRV0JCVDJhZTlBClZZTDYyajBMNUZtUU5qRENFTVoyelRBZkJnTlZIU01FR0RBV2dCVHoyODlPeUw0ek1RWVR2Y1NhbmxybWQ0ZE4Kb3pBS0JnZ3Foa2pPUFFRREFnTkhBREJFQWlBUUozL3hOaVdYQmdEQ0hsbmRYTDhwZG90MUErQWIwUCtlcUlXMgpmRnExZHdJZ1hZaUh1VjFyM1J6SjkwRTdwWlByMTQrenZpdTdRL25VSHlKcy83RVlsY2s9Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNFVENDQWJlZ0F3SUJBZ0lVUzBPNVF4eC9lNExMWVRmOUU3b2F5ckZFdCtjd0NnWUlLb1pJemowRUF3SXcKWlRFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puCk55NXZjbWMzTUI0WERURTRNRGd5TnpFd01ETXdNRm9YRFRNek1EZ3lNekV3TURNd01Gb3daVEVMTUFrR0ExVUUKQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRS0V3dEllWEJsY214bApaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puTnk1dmNtYzNNRmt3CkV3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFQnBhQnRRN0lIUlJ3TlYrWkVoRlJFYW9mQis4QWMzVk4KS3A1THBBYjIxN2syYnZ4dVN4S2N5ZW10QVY0S1kzdnEyMkFySG53VEtPc3lQQmc0QW9QY0g2TkZNRU13RGdZRApWUjBQQVFIL0JBUURBZ0VHTUJJR0ExVWRFd0VCL3dRSU1BWUJBZjhDQVFFd0hRWURWUjBPQkJZRUZQUGJ6MDdJCnZqTXhCaE85eEpxZVd1WjNoMDJqTUFvR0NDcUdTTTQ5QkFNQ0EwZ0FNRVVDSVFDRzkwa1F4NHFUazdsZnk3VFYKbWk2eFFPcStwNmFSKzMwVFhqRFM4dGJBNkFJZ1N3QkFBUkM2TUR3UUV5UGRyV3JtTWNRSEpWdzVKSHNneGkrRAphQnhCZEtZPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg== Version:]]
2018/08/27 10:08:49 [DEBUG] newEnrollmentResponse admin-org7
2018/08/27 10:08:49 [INFO] Stored client certificate at /data/orgs/org7/admin/msp/signcerts/cert.pem
2018/08/27 10:08:49 [INFO] Stored root CA certificate at /data/orgs/org7/admin/msp/cacerts/ica-org7-org7-7054.pem
2018/08/27 10:08:49 [INFO] Stored intermediate CA certificates at /data/orgs/org7/admin/msp/intermediatecerts/ica-org7-org7-7054.pem
##### 2018-08-27 10:08:49 Finished registering organisation org7
```

To join a new Fabric organisation to an existing Fabric network, you need to copy the public certificates for the new org
to the existing network. The certificates of interest are the admincerts, cacerts and tlscacerts found in the new
org's msp folder. This folder is located on the EFS drive here: /opt/share/rca-data/orgs/<org name>/msp

Copy the certificate and key information from the new org to the Fabric network in the main Kubernetes cluster, as follows:

* SSH into the EC2 bastion you created in the new AWS account, which is hosting the new organisation
* In the home directory, execute `sudo tar cvf org7msp.tar  /opt/share/rca-data/orgs/org7/msp`, to zip up the org's msp
directory. Replace 'org7' with your org name
* Exit the SSH, back to your local laptop or host
* Copy the tar file to your local laptop or host using (replace with your directory name, EC2 DNS and keypair):
  `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key-account1.pem ec2-user@ec2-34-228-23-44.compute-1.amazonaws.com:/home/ec2-user/org7msp.tar /Users/edgema/Documents/apps/hyperledger-on-kubernetes/org7msp.tar`
* Copy the tar file to your SSH EC2 host in your original AWS account (the one hosting the main Fabric network) using (replace with your directory name, EC2 DNS and keypair): 
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key.pem org7msp.tar ec2-user@ec2-18-236-169-96.us-west-2.compute.amazonaws.com:/home/ec2-user/org7msp.tar`
* SSH into the EC2 bastion in your original Kubernetes cluster in your original AWS account
* `cd /`
* `sudo tar xvf ~/org7msp.tar` - this should extract they certs for the new org onto the EFS drive, at /opt/share

### Step 2a - Copy the orderer pem file - Fabric Orderer Org
Copy the orderer cert pem file from the original EC2 bastion to the new EC2 bastion. The pem file should be in the same
directory on both - i.e. on the EFS drive accessible to the Kubernetes clusters.

You can either use scp for this, or just copy and paste the contents (I use 'vi' to make sure there are no issues with carriage returns/line feeds in the file)

/opt/share/rca-data/org0-ca-chain.pem

### Step 3 - Update channel config to include new org - Fabric Orderer Org
On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.

* Edit the file `./remote-org/step3-create-channel-config.sh`, and add the new org and domain to the two ENV variables at the 
top of the file
* Run the script `./remote-org/step3-create-channel-config.sh`. 

### Step 4 - Sign channel config created in step 3 - Fabric Orderer Org
On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.

* Run the script `./remote-org/step4-sign-channel-config.sh`.
 
You may need to run this against multiple organisations, depending on how your Fabric network is structured. The channel
config must be signed by the orgs specified in the channel update policy.

### Step 5 - Update channel config created in step 3 - Fabric Orderer Org
On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.

* Run the script `./remote-org/step5-update-channel-config.sh`.

This updates the channel with the new channel config.

### Step 6 - Start the new peer - New Fabric Org
On the EC2 bastion in the new org.

Run the script `./remote-org/step6-start-new-peer.sh`. 

### Step 7 - copy the channel genesis block to the new org - Fabric Orderer Org
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

### Step 8 - Join the channel - New Fabric Org
On the EC2 bastion in the new org.

Run the script `./remote-org/step8-join-channel.sh`. 
