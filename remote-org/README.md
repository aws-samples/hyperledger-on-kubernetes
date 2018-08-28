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

## TODO
Step 2 currently uses the env.sh file to provide configuration for the new org. This file also contains details of 
the orderer org, which results in step 2 generating and creating Kubernetes pods for org0 and the new org. We do not
need org0. It would be better if we do not generate anything for org0 in the account for the new org.

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

#### Copy using S3
We will be copying from the existing network to the new organisation, and from the new organisation to the existing network.
We'll use two S3 buckets for this, each owned and writable by different accounts, but read-only to everyone else.

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh createS3BucketForOrderer
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

On the EC2 bastion in the new org.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh createS3BucketForNewOrg
./remote-org/scripts/copy-tofrom-S3.sh copyCertsToS3
```

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyCertsFromS3
```

### Step 2a - Copy the orderer pem file - Fabric Orderer Org
Copy the orderer cert pem file from the original EC2 bastion to the new EC2 bastion. The pem file should be in the same
directory on both - i.e. on the EFS drive accessible to the Kubernetes clusters. The new organisation will need the
orderer certs when it connects to the orderer endpoint.

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyOrdererPEMToS3
```

On the EC2 bastion in the new org.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyOrdererPEMFromS3
```

### Step 3 - Update channel config to include new org - Fabric Orderer Org
This step generates a new channel config for the new org. It does this by fetching the current channel config,
generating a new channel config, then comparing the new and old configs to create a 'diff'. The 'diff' will be applied
to the channel in step 5, after it has been signed by the network members in step 4.

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.

* Edit the file `./remote-org/step3-create-channel-config.sh`, and add the new org and domain to the two ENV variables at the 
top of the file

```bash
cd
cd hyperledger-on-kubernetes
vi remote-org/step3-create-channel-config.sh
```
* Run the script `./remote-org/step3-create-channel-config.sh`. 

```bash
./remote-org/step3-create-channel-config.sh
```

Check the results:

```bash
kubectl logs job/addorg-fabric-setup -n org1
```

You should see something like this:

```bash
File '/data/updateorg' exists - peer 'org1' admin creating a new org 'org7'
##### 2018-08-28 01:49:59 cloneFabricSamples
Cloning into 'fabric-samples'...
##### 2018-08-28 01:49:59 cloned FabricSamples
Switched to a new branch 'release-1.1'
Branch release-1.1 set up to track remote branch release-1.1 from origin.
##### 2018-08-28 01:49:59 checked out version 1.1 of FabricSamples
##### 2018-08-28 01:49:59 cloneFabric
##### 2018-08-28 01:49:59 Generating the channel config for new org 'org7'
/usr/local/bin/configtxgen
##### 2018-08-28 01:49:59 Printing the new Org configuration for 'org7' at '/data'
2018-08-28 01:49:59.755 UTC [common/tools/configtxgen] main -> INFO 001 Loading configuration
##### 2018-08-28 01:49:59 Fetching the configuration block into '/tmp/config_block.pb' of the channel 'mychannel'
##### 2018-08-28 01:49:59 peer channel fetch config '/tmp/config_block.pb' -c 'mychannel' '-o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt'
2018-08-28 01:49:59.902 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-08-28 01:49:59.902 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-08-28 01:49:59.930 UTC [channelCmd] InitCmdFactory -> INFO 003 Endorser and orderer connections initialized
2018-08-28 01:49:59.930 UTC [msp] GetLocalMSP -> DEBU 004 Returning existing local MSP
2018-08-28 01:49:59.930 UTC [msp] GetDefaultSigningIdentity -> DEBU 005 Obtaining default signing identity
2018-08-28 01:49:59.931 UTC [msp] GetLocalMSP -> DEBU 006 Returning existing local MSP
2018-08-28 01:49:59.931 UTC [msp] GetDefaultSigningIdentity -> DEBU 007 Obtaining default signing identity
2018-08-28 01:49:59.931 UTC [msp/identity] Sign -> DEBU 008 Sign: plaintext: 0A9B090A3708021A0608C7D492DC0522...411BA59C3E6D12080A020A0012020A00 
2018-08-28 01:49:59.931 UTC [msp/identity] Sign -> DEBU 009 Sign: digest: FD6A53DB0F7C7B659DD417B87BC8331D9197D534F1E1626AE3EAC492D495369D 
2018-08-28 01:49:59.934 UTC [channelCmd] readBlock -> DEBU 00a Received block: 18
2018-08-28 01:49:59.934 UTC [msp] GetLocalMSP -> DEBU 00b Returning existing local MSP
2018-08-28 01:49:59.934 UTC [msp] GetDefaultSigningIdentity -> DEBU 00c Obtaining default signing identity
2018-08-28 01:49:59.937 UTC [msp] GetLocalMSP -> DEBU 00d Returning existing local MSP
2018-08-28 01:49:59.937 UTC [msp] GetDefaultSigningIdentity -> DEBU 00e Obtaining default signing identity
2018-08-28 01:49:59.938 UTC [msp/identity] Sign -> DEBU 00f Sign: plaintext: 0A9B090A3708021A0608C7D492DC0522...499E120C0A041A02080512041A020805 
2018-08-28 01:49:59.938 UTC [msp/identity] Sign -> DEBU 010 Sign: digest: DC48000A1AA4E8502B934D9CCA0761401F0E546B018BCACCBBA69579E2F36144 
2018-08-28 01:49:59.942 UTC [channelCmd] readBlock -> DEBU 011 Received block: 5
2018-08-28 01:49:59.942 UTC [main] main -> INFO 012 Exiting.....
##### 2018-08-28 01:49:59 fetched config block
##### 2018-08-28 01:49:59 About to start createConfigUpdate
##### 2018-08-28 01:49:59 Creating config update payload for the new organization 'org7'
##### 2018-08-28 01:49:59 configtxlator_pid:50
##### 2018-08-28 01:49:59 Sleeping 5 seconds for configtxlator to start...
2018-08-28 01:49:59.960 UTC [configtxlator] startServer -> INFO 001 Serving HTTP requests on 0.0.0.0:7059
/tmp /data
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 77422    0 51163  100 26259  2528k  1297k --:--:-- --:--:-- --:--:-- 2629k
##### 2018-08-28 01:50:05 Checking whether org 'org7' exists in the channel config
##### 2018-08-28 01:50:05 About to execute jq '.channel_group.groups.Application.groups | contains({org7})'
##### 2018-08-28 01:50:05 Org 'org7' does not exist in the channel config
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 50439    0 15319  100 35120   324k   744k --:--:-- --:--:-- --:--:--  762k
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 64487    0 19834  100 44653   422k   951k --:--:-- --:--:-- --:--:--  969k
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 40341    0  4702  100 35639   103k   783k --:--:-- --:--:-- --:--:--  790k
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 14088    0  9386  100  4702  1919k   961k --:--:-- --:--:-- --:--:-- 2291k
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 12675    0  4728  100  7947  1845k  3101k --:--:-- --:--:-- --:--:-- 3880k
total 160
-rw-r--r-- 1 root root  7947 Aug 28 01:50 org7_config_update_as_envelope.json
-rw-r--r-- 1 root root  4728 Aug 28 01:50 org7_config_update_as_envelope.pb
-rw-r--r-- 1 root root  9386 Aug 28 01:50 org7_config_update.json
-rw-r--r-- 1 root root 44653 Aug 28 01:50 org7_updated_config.json
-rw-r--r-- 1 root root 35120 Aug 28 01:50 org7_config.json
-rw-r--r-- 1 root root 51163 Aug 28 01:50 org7_config_block.json
##### 2018-08-28 01:50:05 Created config update payload for the new organization 'org7', in file /data/org7_config_update_as_envelope.pb
/data
##### 2018-08-28 01:50:05 Congratulations! The config file for the new org 'org7' was successfully added by peer 'org1' admin. Now it must be signed by all org admins
##### 2018-08-28 01:50:05 After this pod completes, run the pod which contains the script addorg-fabric-sign.sh
```

You should also check that the channel config file has been created. Look for the file titled: `<org>_config_update_as_envelope.pb`.
If you are interested in seeing human readable versions of the channel config, I save each of the stages in a directory,
in this case titled: `addorg-org7-20180828-0150`. Here you can see JSON versions of the original channel config and the
diff between new and current configs.

```bash
$ ls -lt /opt/share/rca-data
total 104
drwxr-xr-x 2 root     root      6144 Aug 28 01:50 addorg-org7-20180828-0150
-rw-r--r-- 1 root     root      4728 Aug 28 01:50 org7_config_update_as_envelope.pb
-rw-r--r-- 1 root     root       316 Aug 28 01:49 channel.tx
-rw-r--r-- 1 root     root     19340 Aug 28 01:49 genesis.block
```

### Step 4 - Sign channel config created in step 3 - Fabric Orderer Org
The channel config generated in step 3 must now be signed by the network members. A channel config update is really just
another transaction in Fabric, known as a 'configuration transaction', and as such it must be endorsed by network members 
in accordance with the modification policy for the channel. The default modification policy for the channel Application group
is MAJORITY, which means a majority of admins need to sign the config update. 

To allow admins in different organisations to sign the channel config you will need to pass the
channel config file to each member in the network, one-by-one, and have them sign the channel config. Each member signature
must be applied in turn so that we end up with a package that has the signatures of all endorsing members. Alternatively,
you could send the channel config to all members simuntaneously and wait to receive signed responses, but then you would
have to extract the signatures from the individual responses and create a single package which contains the config update
plus all the required signatures.

If you created the network in Part 1, you will have 2 peers running in this network, peer1 and peer2, both of whom will
sign the channel config. The script below will run 

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.

* Run the script:
 
```bash
./remote-org/step4-sign-channel-config.sh
``` 

Check the results. There will be a job per organisation, so check both org1 and org2.

```bash
$ kubectl logs job/fabric-signconf -n org1                                                                                                                                    
File '/data/updateorg' exists - peer 'org1' admin is signing new org config for new/deleted org 'org7'
##### 2018-08-28 02:34:18 cloneFabricSamples
Cloning into 'fabric-samples'...
##### 2018-08-28 02:34:18 cloned FabricSamples
Switched to a new branch 'release-1.1'
Branch release-1.1 set up to track remote branch release-1.1 from origin.
##### 2018-08-28 02:34:18 checked out version 1.1 of FabricSamples
##### 2018-08-28 02:34:18 cloneFabric
##### 2018-08-28 02:34:18 Signing the config for the new org 'org7'
##### 2018-08-28 02:34:18 Signing the configuration block of the channel 'mychannel' in config file /data/org7_config_update_as_envelope.pb
2018-08-28 02:34:18.567 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-08-28 02:34:18.567 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-08-28 02:34:18.567 UTC [channelCmd] InitCmdFactory -> INFO 003 Endorser and orderer connections initialized
2018-08-28 02:34:18.573 UTC [msp] GetLocalMSP -> DEBU 004 Returning existing local MSP
2018-08-28 02:34:18.573 UTC [msp] GetDefaultSigningIdentity -> DEBU 005 Obtaining default signing identity
2018-08-28 02:34:18.573 UTC [msp] GetLocalMSP -> DEBU 006 Returning existing local MSP
2018-08-28 02:34:18.573 UTC [msp] GetDefaultSigningIdentity -> DEBU 007 Obtaining default signing identity
2018-08-28 02:34:18.573 UTC [msp/identity] Sign -> DEBU 008 Sign: plaintext: 0AC2080A076F7267314D535012B6082D...65616465727312002A0641646D696E73 
2018-08-28 02:34:18.573 UTC [msp/identity] Sign -> DEBU 009 Sign: digest: 63320ADDE21D20AE3BE16742DC13D18BBD07E53CB54A7BFA8D88A06FA8AA05EE 
2018-08-28 02:34:18.573 UTC [msp] GetLocalMSP -> DEBU 00a Returning existing local MSP
2018-08-28 02:34:18.573 UTC [msp] GetDefaultSigningIdentity -> DEBU 00b Obtaining default signing identity
2018-08-28 02:34:18.574 UTC [msp] GetLocalMSP -> DEBU 00c Returning existing local MSP
2018-08-28 02:34:18.574 UTC [msp] GetDefaultSigningIdentity -> DEBU 00d Obtaining default signing identity
2018-08-28 02:34:18.574 UTC [msp/identity] Sign -> DEBU 00e Sign: plaintext: 0AF9080A1508021A0608AAE992DC0522...9607D7A821392D0B62A93FB9FD285653 
2018-08-28 02:34:18.574 UTC [msp/identity] Sign -> DEBU 00f Sign: digest: 6951046716259D089FEF36D7416FD7A8A43E2D1EFBBDF27DCD587F2032DA878D 
2018-08-28 02:34:18.607 UTC [main] main -> INFO 010 Exiting.....
##### 2018-08-28 02:34:18 Congratulations! The config file has been signed by peer 'org1' admin for the new/deleted org 'org7'
```

You can also check that the channel config file has increased in size. In Step 3 it was 4728 bytes, now it is 8328. This is
due to the signatures added to the file during the signing process.

```bash
$ ls -lt /opt/share/rca-data
total 108
-rw-r--r-- 1 root     root      8328 Aug 28 02:34 org7_config_update_as_envelope.pb
drwxr-xr-x 2 root     root      6144 Aug 28 01:50 addorg-org7-20180828-0150
-rw-r--r-- 1 root     root       316 Aug 28 01:49 channel.tx
-rw-r--r-- 1 root     root     19340 Aug 28 01:49 genesis.block
```

### Step 5 - Update channel config created in step 3 - Fabric Orderer Org
In this step we update the channel with the new channel config. Since the new channel config now includes details
of the new organisation, this will allow the new organisation to join the channel.

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.

* Run the script:
 
```bash
./remote-org/step5-update-channel-config.sh
``` 

Check the results:

```bash
$ kubectl logs job/fabric-updateconf -n org1
File '/data/updateorg' exists - peer 'org1' admin is updating channel config for for new/deleted org 'org7'
##### 2018-08-28 02:40:48 cloneFabricSamples
Cloning into 'fabric-samples'...
##### 2018-08-28 02:40:49 cloned FabricSamples
Switched to a new branch 'release-1.1'
Branch release-1.1 set up to track remote branch release-1.1 from origin.
##### 2018-08-28 02:40:49 checked out version 1.1 of FabricSamples
##### 2018-08-28 02:40:49 cloneFabric
##### 2018-08-28 02:40:49 Signing the config for the new org 'org7'
##### 2018-08-28 02:40:49 Updating the configuration block of the channel 'mychannel' using config file /data/org7_config_update_as_envelope.pb
2018-08-28 02:40:49.299 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-08-28 02:40:49.299 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-08-28 02:40:49.324 UTC [channelCmd] InitCmdFactory -> INFO 003 Endorser and orderer connections initialized
2018-08-28 02:40:49.330 UTC [msp] GetLocalMSP -> DEBU 004 Returning existing local MSP
2018-08-28 02:40:49.330 UTC [msp] GetDefaultSigningIdentity -> DEBU 005 Obtaining default signing identity
2018-08-28 02:40:49.331 UTC [msp] GetLocalMSP -> DEBU 006 Returning existing local MSP
2018-08-28 02:40:49.331 UTC [msp] GetDefaultSigningIdentity -> DEBU 007 Obtaining default signing identity
2018-08-28 02:40:49.331 UTC [msp/identity] Sign -> DEBU 008 Sign: plaintext: 0AC2080A076F7267314D535012B6082D...65616465727312002A0641646D696E73 
2018-08-28 02:40:49.331 UTC [msp/identity] Sign -> DEBU 009 Sign: digest: 19EBCCED6A0DFEB80ABC4E31A44E07F906ABF9A8FD50AFFA798811014CC7C6B7 
2018-08-28 02:40:49.331 UTC [msp] GetLocalMSP -> DEBU 00a Returning existing local MSP
2018-08-28 02:40:49.331 UTC [msp] GetDefaultSigningIdentity -> DEBU 00b Obtaining default signing identity
2018-08-28 02:40:49.332 UTC [msp] GetLocalMSP -> DEBU 00c Returning existing local MSP
2018-08-28 02:40:49.332 UTC [msp] GetDefaultSigningIdentity -> DEBU 00d Obtaining default signing identity
2018-08-28 02:40:49.332 UTC [msp/identity] Sign -> DEBU 00e Sign: plaintext: 0AF9080A1508021A0608B1EC92DC0522...477230D2EBED40646A93038D3F4941D2 
2018-08-28 02:40:49.332 UTC [msp/identity] Sign -> DEBU 00f Sign: digest: 49F2F741357953DE8153F052CD611C30C50799E7F5E63EE22291838BB8BB954E 
2018-08-28 02:40:49.518 UTC [channelCmd] update -> INFO 010 Successfully submitted channel update
2018-08-28 02:40:49.519 UTC [main] main -> INFO 011 Exiting.....
##### 2018-08-28 02:40:49 Congratulations! Config file has been updated on channel 'mychannel' by peer 'org1' admin for the new/deleted org 'org7'
##### 2018-08-28 02:40:49 You can now start the new peer, then join the new peer to the channel
```

### Step 6 - Start the new peer - New Fabric Org
Now that the new org has been added to the channel config, you can start a peer in the new org and join the peer to the channel.
In Step 6 we'll start the peer, in the subsequent steps we'll join it to the channel.

On the EC2 bastion in the new org.

* Run the script:
 
```bash
./remote-org/step6-start-new-peer.sh
``` 

Check the results. First check the results for the registration of the new user for the new org. Do a `kubectl get po -n <new org>
to get the pod name, then (replace the pod name below with your own. Also replace the org number to match your own):

```bash
$ kubectl logs register-p-org7-6d44b8ccd4-4vlfk   -n org7
##### 2018-08-28 02:55:33 Registering peer for org org7 ...
##### 2018-08-28 02:55:33 Enrolling with ica-org7.org7 as bootstrap identity ...
.
.
.
2018/08/28 02:55:34 [DEBUG] Sending request
POST https://ica-org7.org7:7054/register
{"id":"michaelpeer1-org7","type":"peer","secret":"michaelpeer1-org7pw","affiliation":"org1"}
2018/08/28 02:55:34 [DEBUG] Received response
statusCode=201 (201 Created)
2018/08/28 02:55:34 [DEBUG] Response body result: map[secret:michaelpeer1-org7pw]
2018/08/28 02:55:34 [DEBUG] The register request completed successfully
Password: michaelpeer1-org7pw
##### 2018-08-28 02:55:34 Finished registering peer for org org7
```

Then check that the peer started successfully. The key log entry is `Started peer with ID`:

```bash
$ kubectl logs michaelpeer1-org7-59fdf7bbc8-42n6j  -n org7 -c michaelpeer1-org7
##### 2018-08-28 02:56:14 Preparing to start peer 'michaelpeer1-org7', host 'michaelpeer1-org7.org7', enrolled via 'https://michaelpeer1-org7:michaelpeer1-org7pw@ica-org7.org7:7054' with MSP at '/opt/gopath/src/github.com/hyperledger/fabric/peer/msp'
2018/08/28 02:56:14 [DEBUG] Home directory: /opt/gopath/src/github.com/hyperledger/fabric/peer
.
.
.
2018-08-28 02:56:26.120 UTC [nodeCmd] serve -> INFO 1ca Starting peer with ID=[name:"michaelpeer1-org7" ], network ID=[dev], address=[192.168.90.14:7051]
2018-08-28 02:56:26.120 UTC [nodeCmd] serve -> INFO 1cb Started peer with ID=[name:"michaelpeer1-org7" ], network ID=[dev], address=[192.168.90.14:7051]
2018-08-28 02:56:26.120 UTC [flogging] setModuleLevel -> DEBU 1cc Module 'msp/identity' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.120 UTC [flogging] setModuleLevel -> DEBU 1cd Module 'msp' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.120 UTC [flogging] setModuleLevel -> DEBU 1ce Module 'gossip/state' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1cf Module 'gossip/election' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d0 Module 'gossip/privdata' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d1 Module 'gossip/gossip' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d2 Module 'gossip/pull' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d3 Module 'gossip/comm' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d4 Module 'gossip/service' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d5 Module 'gossip/discovery' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d6 Module 'ledgermgmt' logger enabled for log level 'INFO'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d7 Module 'cauthdsl' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d8 Module 'policies' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1d9 Module 'grpc' logger enabled for log level 'ERROR'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1da Module 'peer/gossip/sa' logger enabled for log level 'WARNING'
2018-08-28 02:56:26.121 UTC [flogging] setModuleLevel -> DEBU 1db Module 'peer/gossip/mcs' logger enabled for log level 'WARNING'
```

At this point the peer has not joined any channels, and does not have a ledger or world state.

### Step 7 - copy the channel genesis block to the new org - Fabric Orderer Org
Before the peer in the new org joins the channel, it must be able to connect to the Orderer Service Node (OSN) running
in the Orderer org. It obtains the endpoint for the OSN from the channel genesis block

The file <channel-name>.block would have been created when you first created the channel in the Orderer network. It will
be on the EFS drive, in /opt/share/rca-data. If you can't find it, you can always pull it from the channel itself 
using `peer channel fetch 0 mychannel.block`.

Copy the <channel-name>.block file from the main Fabric network to the new org, as follows:

On the EC2 bastion in the existing Fabric network, i.e. where the orderer is running.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyChannelGenesisToS3
```

On the EC2 bastion in the new org.
```bash
cd
cd hyperledger-on-kubernetes
./remote-org/scripts/copy-tofrom-S3.sh copyChannelGenesisFromS3
```


* Copy the <channel-name>.block file to your local laptop or host using (replace with your directory name, EC2 DNS and keypair):
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key.pem ec2-user@ec2-18-236-169-96.us-west-2.compute.amazonaws.com:/opt/share/rca-data/mychannel.block mychannel.block`
* Copy the local <channel-name>.block file to the EFS drive in your new AWS account using (replace with your directory name, EC2 DNS and keypair):
 `scp -i /Users/edgema/Documents/apps/eks/eks-fabric-key-account1.pem /Users/edgema/Documents/apps/hyperledger-on-kubernetes/mychannel.block  ec2-user@ec2-34-228-23-44.compute-1.amazonaws.com:/opt/share/rca-data/mychannel.block`


The certificates used when a peer connects to an orderer for channel specific tasks (such as joining a channel
or instantiating chaincode) are the certs contained in the channel config block. It should be pretty obvious that 
the certs for the new org are NOT in the genesis block as the new org did not exist when the genesis block was created. 
However, when the peer joins the channel it will read the blocks in the channel and process each config block in turn,
eventually ending up with the latest config (created in steps 3-5 above).

### Step 8 - Join the channel - New Fabric Org
On the EC2 bastion in the new org.

Run the script `./remote-org/step8-join-channel.sh`. 
