# TODO

* Improve the section on creating the Kubernetes cluster, especially the section on how to use the Heptio authenticator
and configure this for use on the bastion host
* Installation instructions for Node on Windows

# Hyperledger Fabric on Kubernetes

This workshop builds remote Hyperledger Fabric peers in other AWS accounts/regions, connects them to the Fabric orderer 
organisation, installs the 'marbles' chaincode, and allows workshop participants to have fun swapping marbles. Each workshop 
participant will run their own Fabric peer in their own AWS account, and see the Fabric state via a local Node.js application 
that connects to their own local peer and reads their own local copy of the ledger.

The workshop gives participants the experience of building their own Kubernetes cluster before running a Fabric CA and
Fabric peers as pods in Kubernetes. Once the peer is running, the participants will follow the steps to connect it to a
channel, install chaincode, test the channel connection, then run a Node.js application that connects to the peer node
and displays the peers ledger state in a colourful UI.

## The Architecture
![Marbles Workshop Architecture](WorkshopArchitecture.jpg?raw=true "Marbles Workshop Architecture")

* You will interact with Hyperledger Fabric using the Marbles application, which is a Node.js application that you will
run locally on your laptop. During this workshop you will configure and run this application.
* The Marbles application will connect to a Fabric peer running in your own AWS account, in any region you choose. During
this workshop you will configure and run the Fabric peer.
* The Marbles application also connects to an Orderer service, which orders the transactions and groups them into blocks.
* The Orderer service will run in the facilitators AWS account, in a region he/she chooses.

This represents a typical Hyperledger network, where the Orderer is owned either by a joint-venture, a consortium or some other
legal entity, and each member of the network runs their peers independently, connected to the Orderer.

## Workshop pre-requisites
You're going to interact with Fabric and the Kubernetes cluster from a bastion host that mounts an EFS drive. EFS is 
required to store the crypto material used by Fabric, and you'll need to copy the appropriate certs/keys to/from the EFS drive.
The pre-requisites are as follows:

* An AWS account where you can create a Kubernetes cluster (either your own Kubernetes cluster or EKS)
* It's preferable that you have some basic Kubernetes experience
* Git installed locally. See https://git-scm.com/downloads
* Node JS installed. You'll need version > 6.10.1, but it must be 6.x.x. See https://nodejs.org/en/download/. If you have a different 
version, you can uninstall it (on Mac), and install the correct version using homebrew:

```bash
brew uninstall node --force
brew install node@6
```

Then do:

```bash
echo 'export PATH="/usr/local/opt/node@6/bin:$PATH"' >> ~/.bash_profile
source ~/.bash_profile
```

Check the node version:

```bash
$ node -v
v6.14.3
$ npm -v
3.10.10
```

* npm installed locally on your laptop. It should have been installed together with node in the step above. If not, see https://www.npmjs.com/get-npm
* AWS CLI installed - either on your laptop or on the Cloud9 server you create in Step 1 - with the appropriate AWS API credentials 
pointing to the account and region where you will deploy Kubernetes. You can use 
[~/.aws/credentials file](https://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html) 
or [environment variables](https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html). For more information 
read the [AWS documentation](https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html).

## Getting Started
We create the Kubernetes cluster first, in Step 1. This has the advantage that we can deploy the EC2 bastion (created in Step 2)
into the same VPC as the Kubernetes cluster, and mount EFS into the Kubernetes cluster. The disadvantage is that we must
configure kubectl on the EC2 bastion to connect to the Kubernetes cluster via the config in ~/.kube/config - see Step 3. 
It's a small price to pay, so we'll stick with this approach for now. 
 
### Step 1: Create a Kubernetes cluster
You need a K8s cluster to start. The easiest way to do this is to create an EKS cluster using the eksctl tool. Open
the `eks` folder in this repo and follow the instructions in the README.

### Step 2: Create an EC2 instance and EFS 
You will need an EC2 bastion, which you will use to start and interact with the Fabric network. You will also need an EFS volume for 
storing common scripts and the certificates used by Fabric. The EFS volume must be accessible from both the EC2 bastion and 
the worker nodes in the Kubernetes cluster. Follow the steps below, which will create the EFS and make it available to the K8s cluster.

On your laptop or Cloud9 instance, clone this repo into any directory you choose. After Step 2 you can delete the repo again. You only need 
it for creating the EC2 bastion and the EFS drive:

```bash
git clone https://github.com/aws-samples/hyperledger-on-kubernetes
cd hyperledger-on-kubernetes
```

In the repo directory, check the parameters in efs/deploy-ec2.sh and update them as follows:
* The VPC and Subnet should be those of your existing K8s cluster worker nodes. You can find these in the AWS VPC console.
Look for the VPC with a name based on the name of your EKS cluster. If you created your cluster in us-west-2 there are
three subnets.
* Keyname is the AWS EC2 keypair you used for your EKS cluster. You'll use the same keypair to access the EC2 bastion created by deploy-ec2.sh
* VolumeName is the name assigned to your EFS volume. There is no need to change this
* Region should match the region where your K8s cluster is deployed
* If your AWS CLI already points to the account & region your Kubernetes cluster was created, you can go ahead and run the 
command below. If you are using AWS CLI profiles, add a --profile argument to your `aws cloudformation deploy` statement
in efs/deploy-ec2.sh

Once all the parameters are set, in a terminal window, run 

```bash
./efs/deploy-ec2.sh 
```

Check the CloudFormation console for completion. Once the CFN stack is complete, SSH to the EC2 bastion instance using the keypair 
above. 

### Step 3: Prepare the EC2 instance for use
The EC2 instance you created in Step 2 should already have kubectl and the AWS CLI installed. However, kubectl will have no
context and will not be pointing to a kubernetes cluster, and AWS CLI will have no credentials. We need to point kubectl to 
the K8s cluster we created in Step 1, and we need to provide credentials for AWS CLI.

To provide AWS CLI credentials, we'll copy them either from our Mac or Cloud9 - i.e. whichever we used to create the EKS cluster.

We'll do the same for the kube config file, i.e. copy the contents of the kube config file from 
your Mac or Cloud9 instance. If you followed the default steps in Step 1, you will have a kube config file called
./kubeconfig.eks-fabric.yaml, in the same directory you were in when you created the EKS cluster. We want to copy this
file to the EC2 bastion instance.

To copy the kube config, do the following:
* On your laptop or Cloud9 instance, open ./kubeconfig.eks-fabric.yaml  and copy all the contents
* SSH into the EC2 instance created above. You can find the DNS or IP address in the EC2 console: 

```bash
ssh ec2-user@ec2-34-216-209-127.us-west-2.compute.amazonaws.com -i eks/eksctl-keypair.pem
```

* Then create the kube config file:

```bash
mkdir /home/ec2-user/.kube
cd /home/ec2-user/.kube
vi config
```
* hit the letter 'i' and paste the kube config contents you copied above. Hit the escape key, then shift-zz to save and exit vi

To copy the AWS CLI config and credentials files, do the following:
* On your laptop or Cloud9 instance, open ~/.aws/config and copy all the contents
* SSH into the EC2 instance created above: 

```bash
ssh ec2-user@ec2-34-216-209-127.us-west-2.compute.amazonaws.com -i eks/eksctl-keypair.pem
```

* Then create the AWS CLI config file:

```bash
mkdir /home/ec2-user/.aws
cd /home/ec2-user/.aws
vi config
```

* hit the letter 'i' and paste the AWS CLI config contents you copied above. Hit the escape key, then shift-zz to save and exit vi

Do the same for the credentials file. It should also be copied to the .aws directory.

To check that this works execute:

```bash
kubectl get nodes
```

you should see the nodes belonging to your new K8s cluster. You may see more nodes, depending on the size of the Kubernetes
cluster you created:

```bash
$ kubectl get nodes
NAME                            STATUS    ROLES     AGE       VERSION
ip-172-20-37-228.ec2.internal   Ready     master    48d       v1.9.6
ip-172-20-60-179.ec2.internal   Ready     node      48d       v1.9.6
ip-172-20-67-10.ec2.internal    Ready     node      48d       v1.9.6
```

### Step 4: Clone this repo to your EC2 instance
On the EC2 instance created in Step 2 above, in the home directory, clone this repo:

```bash
cd
git clone https://github.com/aws-samples/hyperledger-on-kubernetes
```

This repo contains the scripts you'll use to setup your Fabric peer.

### Step 5: Configure the EFS server URL
On the EC2 instance created in Step 2 above, in the newly cloned hyperledger-on-kubernetes directory, update the script 
'gen-fabric.sh' so that the EFSSERVER variable contains the full URL of the EFS server created in 
Step 2. Do the following:

In the AWS EFS console, obtain the full EFS URL for your new EFS. The URL should look something like this: 
EFSSERVER=fs-12a33ebb.efs.us-west-2.amazonaws.com

Then, back on the EC2 instance:

```bash
cd
cd hyperledger-on-kubernetes
vi gen-fabric.sh
```

Look for the line starting with `EFSSERVER=`, and replace the URL with the one you copied from the EFS console. Using
vi you can simply move the cursor over the first character after `EFSSERVER=` and hit the 'x' key until the existing
URL is deleted. Then hit the 'i' key and ctrl-v to paste the new URL. Hit escape, then shift-zz to save and exit vi. 
See, you're a vi expert already.

### Step 6: Get the Fabric crypto information
Before creating your Fabric peer you'll need the certificate and key information for the organisation the peer belongs
to. The steps below are a quick and dirty way of obtaining this info - not recommended for production use, but it will
save us plenty of time fiddling around with keys, certificates and certificate authorities. 

A quick method of setting up a remote peer for an existing org involves copying the existing crypto material. We've made
this information available in an S3 bucket - you just need to download it and copy it to your EFS as follows:

* SSH into the EC2 instance you created in Step 2
* Download the crypto information:

```bash
cd
curl https://s3-us-west-2.amazonaws.com/mcdg-blockchain-workshop/opt.tar -o opt.tar
ls -l
```

* Extract the crypto material (you may need to use 'sudo'. Ignore the 'permission denied' error message, if you receive one):

```bash
cd /
rm -rf /opt/share
tar xvf ~/opt.tar 
ls -lR /opt/share
```

You should see something like this (though this is only a subset):

```bash
$ ls -lR /opt/share
/opt/share:
total 36
drwxrwxr-x 3 ec2-user ec2-user 6144 Jul 17 03:54 ica-org0
drwxrwxr-x 3 ec2-user ec2-user 6144 Jul 17 04:53 ica-org1
drwxrwxr-x 3 ec2-user ec2-user 6144 Jul 17 03:54 ica-org2
drwxrwxr-x 2 ec2-user ec2-user 6144 Jul 17 03:32 orderer
drwxrwxr-x 7 ec2-user ec2-user 6144 Jul 19 13:23 rca-data
drwxrwxr-x 3 ec2-user ec2-user 6144 Jul 17 03:34 rca-org0
drwxrwxr-x 3 ec2-user ec2-user 6144 Jul 17 03:34 rca-org1
drwxrwxr-x 3 ec2-user ec2-user 6144 Jul 17 03:34 rca-org2
drwxrwxr-x 2 ec2-user ec2-user 6144 Jul 19 12:45 rca-scripts

/opt/share/ica-org0:
total 124
-rw-r--r-- 1 root root   822 Jul 17 03:34 ca-cert.pem
-rw-r--r-- 1 root root  1600 Jul 17 03:34 ca-chain.pem
-rw-r--r-- 1 root root 15944 Jul 17 03:34 fabric-ca-server-config.yaml
-rw-r--r-- 1 root root 94208 Jul 17 03:54 fabric-ca-server.db
drwxr-xr-x 5 root root  6144 Jul 17 03:34 msp
-rw-r--r-- 1 root root   912 Jul 17 03:34 tls-cert.pem
.
.
.
```

### Step 7: Edit env.sh
We've reached the final step before we get our hands on Hyperledger Fabric. In this step we prepare the configuration
file used by the scripts that configure Fabric.

* SSH into the EC2 instance you created in Step 2
* Navigate to the `hyperledger-on-kubernetes` repo

```bash
cd
cd hyperledger-on-kubernetes
vi remote-peer/scripts/env-remote-peer.sh
```
* You can choose any value for PEER_ORGS and PEER_DOMAINS, as long as it's one of the following. Select the SAME value
  for PEER_ORGS and PEER_DOMAINS, do not select PEER_ORGS=org1 and PEER_DOMAINS=org2. Options are:
    * PEER_ORGS=org1, PEER_DOMAINS=org1
    * PEER_ORGS=org2, PEER_DOMAINS=org2
* Edit the file `remote-peer/scripts/env-remote-peer.sh`. Update the following fields:
    * Set PEER_ORGS to one of the organisations in the Fabric network. Example: PEER_ORGS="org1"
    * Set PEER_DOMAINS to one of the domains in the Fabric network. Example: PEER_DOMAINS="org1"
    * Set PEER_PREFIX to any name you choose. This will become the name of your peer on the network. 
      Try to make this unique within the network - your alias would work. Example: PEER_PREFIX="michaelpeer"
* Don't change anything else.

TIP: You'll be using the peer prefix and organisation you set above in many places. It will make your life easier
if you do a search/replace in this README, replacing all 'michaelpeer' with your prefix, and all 'org' with 
the org you have selected. That way you can copy/paste the commands I provide below instead of having to edit them.

### Step 8: Register Fabric identities with the Fabric certificate authority
Before we can start our Fabric peer we must register it with the Fabric certificate authority (CA). All participants in 
a Fabric network have identities (Fabric is a private, permissioned blockchain network), and these identities are created
by a CA. This step will start Fabric CA and register our peer:

```bash
./workshop-remote-peer/start-remote-fabric-setup.sh
```

Now let's investigate the results of the previous script. In the statements below, replace 'org1' with the org you
selected in step 7:

```bash
kubectl get po -n org1 
```

You should see something similar to this. It shows us that so far, in Kubernetes, we have started a root CA (rca), 
an intermediate CA (ica), and a pod that registers peers identities (register-p).

```bash
$ kubectl get po -n org1
NAME                               READY     STATUS    RESTARTS   AGE
ica-notls-org1-66f96667c5-ftswd    1/1       Running   0          45s
ica-org1-5694787654-g5j9l          1/1       Running   0          53s
rca-org1-6c769cc569-5cfqb          1/1       Running   0          1m
register-p-org1-66bd5688b4-fhzmh   1/1       Running   0          28s
```

Look at the logs for the register pod. Replace the pod name with your own pod name, the one returned above by 'kubectl get po -n org1 ':

```bash
kubectl logs register-p-org1-66bd5688b4-fhzmh -n org1
```

You'll see something like this (edited for brevity), as the CA admin is enrolled with the intermediate CA, then the
peer user (in this case 'michaelpeer1-org1') is registered with the CA:

```bash
$ kubectl logs register-p-org1-66bd5688b4-fhzmh -n org1
##### 2018-07-22 02:52:31 Registering peer for org org1 ...
##### 2018-07-22 02:52:31 Enrolling with ica-org1.org1 as bootstrap identity ...
2018/07/22 02:52:31 [DEBUG] Home directory: /root/cas/ica-org1.org1
2018/07/22 02:52:31 [INFO] Created a default configuration file at /root/cas/ica-org1.org1/fabric-ca-client-config.yaml
2018/07/22 02:52:31 [DEBUG] Client configuration settings: &{URL:https://ica-org1-admin:ica-org1-adminpw@ica-org1.org1:7054 MSPDir:msp TLS:{Enabled:true CertFiles:[/data/org1-ca-chain.pem] Client:{KeyFile: CertFile:}} Enrollment:{ Name: Secret:**** Profile: Label: CSR:<nil> CAName: AttrReqs:[]  } CSR:{CN:ica-org1-admin Names:[{C:US ST:North Carolina L: O:Hyperledger OU:Fabric SerialNumber:}] Hosts:[register-p-org1-66bd5688b4-fhzmh] KeyRequest:<nil> CA:<nil> SerialNumber:} ID:{Name: Type:client Secret: MaxEnrollments:0 Affiliation:org1 Attributes:[] CAName:} Revoke:{Name: Serial: AKI: Reason: CAName: GenCRL:false} CAInfo:{CAName:} CAName: CSP:0xc42016df80}
2018/07/22 02:52:31 [DEBUG] Entered runEnroll
.
. 
.
2018/07/22 02:52:31 [DEBUG] Sending request
POST https://ica-org1.org1:7054/enroll
{"hosts":["register-p-org1-66bd5688b4-fhzmh"],"certificate_request":"-----BEGIN CERTIFICATE REQUEST-----\nMIIBXzCCAQYCAQAwZjELMAkGA1UEBhMCVVMxFzAVBgNVBAgTDk5vcnRoIENhcm9s\naW5hMRQwEgYDVQQKEwtIeXBlcmxlZGdlcjEPMA0GA1UECxMGRmFicmljMRcwFQYD\nVQQDEw5pY2Etb3JnMS1hZG1pbjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABC5+\n+w04ZAjYiZDBzfc779+oYekJ2TURk6KqxL2Bw6BQXt251kh9VSScLrpb7qTCPMUF\nsg7pbTzsxyaauWu/fAGgPjA8BgkqhkiG9w0BCQ4xLzAtMCsGA1UdEQQkMCKCIHJl\nZ2lzdGVyLXAtb3JnMS02NmJkNTY4OGI0LWZoem1oMAoGCCqGSM49BAMCA0cAMEQC\nIBgeEW7fya+V0+7E8EgMdTV+krDiZsouX9ZsR+C6yf5KAiBrDLMMTb7y697HrROR\nax/7/enFQc78wboYRV3fjTEnEA==\n-----END CERTIFICATE REQUEST-----\n","profile":"","crl_override":"","label":"","NotBefore":"0001-01-01T00:00:00Z","NotAfter":"0001-01-01T00:00:00Z","CAName":""}
2018/07/22 02:52:32 [DEBUG] Received response
statusCode=201 (201 Created)
2018/07/22 02:52:32 [DEBUG] Response body result: map[Cert:LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNYVENDQWdPZ0F3SUJBZ0lVUVI3ZmNXbVlHQVVnemFkSE5LWDY3cnRHOEw4d0NnWUlLb1pJemowRUF3SXcKWmpFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1kyeHBaVzUwTVJjd0ZRWURWUVFERXc1eVkyRXRiM0puCk1TMWhaRzFwYmpBZUZ3MHhPREEzTWpJd01qUTRNREJhRncweE9UQTNNakl3TWpVek1EQmFNR1l4Q3pBSkJnTlYKQkFZVEFsVlRNUmN3RlFZRFZRUUlFdzVPYjNKMGFDQkRZWEp2YkdsdVlURVVNQklHQTFVRUNoTUxTSGx3WlhKcwpaV1JuWlhJeER6QU5CZ05WQkFzVEJtTnNhV1Z1ZERFWE1CVUdBMVVFQXhNT2FXTmhMVzl5WnpFdFlXUnRhVzR3CldUQVRCZ2NxaGtqT1BRSUJCZ2dxaGtqT1BRTUJCd05DQUFRdWZ2c05PR1FJMkltUXdjMzNPKy9mcUdIcENkazEKRVpPaXFzUzlnY09nVUY3ZHVkWklmVlVrbkM2NlcrNmt3anpGQmJJTzZXMDg3TWNtbXJscnYzd0JvNEdPTUlHTApNQTRHQTFVZER3RUIvd1FFQXdJSGdEQU1CZ05WSFJNQkFmOEVBakFBTUIwR0ExVWREZ1FXQkJTc0M1K3JGUXFMCkM3aFM2T1A2Q3NtRVI3Y1kvekFmQmdOVkhTTUVHREFXZ0JSdlVPRlNVc3p2YXRvQVhkYThSSUxiZ0lFamFqQXIKQmdOVkhSRUVKREFpZ2lCeVpXZHBjM1JsY2kxd0xXOXlaekV0TmpaaVpEVTJPRGhpTkMxbWFIcHRhREFLQmdncQpoa2pPUFFRREFnTklBREJGQWlFQStDdms1alpIbXd4cFRZL3NWazdnam5yN2p3UUYvdUd6WUpXQ29LY2VUcklDCklFc0o3Y0xJZWUzVVBwdFhKMjZCdml0a2Z1NUpWb2dTaFIxcVNFM2FTN1lmCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K ServerInfo:map[CAName:ica-org1.org1 CAChain:LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNNakNDQWRtZ0F3SUJBZ0lVYjV0ZlNKUFZqVUtFZ2NWckY5S3hDczFHMUprd0NnWUlLb1pJemowRUF3SXcKWlRFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puCk1TNXZjbWN4TUI0WERURTRNRGN5TWpBeU5EY3dNRm9YRFRJek1EY3lNVEF5TlRJd01Gb3daakVMTUFrR0ExVUUKQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRS0V3dEllWEJsY214bApaR2RsY2pFUE1BMEdBMVVFQ3hNR1kyeHBaVzUwTVJjd0ZRWURWUVFERXc1eVkyRXRiM0puTVMxaFpHMXBiakJaCk1CTUdCeXFHU000OUFnRUdDQ3FHU000OUF3RUhBMElBQkpXaXlhbjNGREJiWXZyNlVZNWlwMkJMYXFJYzA2UVAKRFc4RXd4ZVphZzREbllTWDlodytLRStkTVV4QmlkaUlWaUpqUVAwOGRic3NkeVJ3Q3pGbkY4R2paakJrTUE0RwpBMVVkRHdFQi93UUVBd0lCQmpBU0JnTlZIUk1CQWY4RUNEQUdBUUgvQWdFQU1CMEdBMVVkRGdRV0JCUnZVT0ZTClVzenZhdG9BWGRhOFJJTGJnSUVqYWpBZkJnTlZIU01FR0RBV2dCVDhWUGluVXdkclU5U2dhcDYzdktRYlZuQVkKTmpBS0JnZ3Foa2pPUFFRREFnTkhBREJFQWlCdllIOXhLZlg4bGZmZlpFZnp0NUhDSDUxRWsvZDh4em4zV1NRNwpwaHRjVndJZ0kwRHdtaVVVSmZVZDVpSXUrU0lyMXNDT3VvQ1JjZ0ZsMjNaMENReENSc2M9Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNFVENDQWJlZ0F3SUJBZ0lVZXRScVMzbW9TbWZiZDBSTVc5cTBaQlJ1ZU1Jd0NnWUlLb1pJemowRUF3SXcKWlRFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puCk1TNXZjbWN4TUI0WERURTRNRGN5TWpBeU5EY3dNRm9YRFRNek1EY3hPREF5TkRjd01Gb3daVEVMTUFrR0ExVUUKQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRS0V3dEllWEJsY214bApaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puTVM1dmNtY3hNRmt3CkV3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFVy9sNCt4STdhODlGczRXTUorcXNuWlJUenZ1c1FrUTMKbjd2dVdGdW1aaWVjUXZINkNsR1k5UTVFbHVQdWgyTWZ5akw4elpIM2R0WWpoMFdUZ1B2aUg2TkZNRU13RGdZRApWUjBQQVFIL0JBUURBZ0VHTUJJR0ExVWRFd0VCL3dRSU1BWUJBZjhDQVFFd0hRWURWUjBPQkJZRUZQeFUrS2RUCkIydFQxS0JxbnJlOHBCdFdjQmcyTUFvR0NDcUdTTTQ5QkFNQ0EwZ0FNRVVDSVFDV3poL0d3a3dxeEUxTmgvRHoKa1VKb2N5ckh1bDdFYStoNmJxWC90ak9xR2dJZ1hNQ0N4L3BDUS9LRkhmL2xSTllDeGQySy91NUxLS3ZwejBCeQo1U1BNUCtnPQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg== Version:]]
2018/07/22 02:52:32 [DEBUG] newEnrollmentResponse ica-org1-admin
2018/07/22 02:52:32 [INFO] Stored client certificate at /root/cas/ica-org1.org1/msp/signcerts/cert.pem
2018/07/22 02:52:32 [INFO] Stored root CA certificate at /root/cas/ica-org1.org1/msp/cacerts/ica-org1-org1-7054.pem
2018/07/22 02:52:32 [INFO] Stored intermediate CA certificates at /root/cas/ica-org1.org1/msp/intermediatecerts/ica-org1-org1-7054.pem
##### 2018-07-22 02:52:32 Registering michaelpeer1-org1 with ica-org1.org1
2018/07/22 02:52:32 [DEBUG] Home directory: /root/cas/ica-org1.org1
.
. 
.
2018/07/22 02:52:32 [DEBUG] Sending request
POST https://ica-org1.org1:7054/register
{"id":"michaelpeer1-org1","type":"peer","secret":"michaelpeer1-org1pw","affiliation":"org1"}
2018/07/22 02:52:32 [DEBUG] Received response
statusCode=201 (201 Created)
2018/07/22 02:52:32 [DEBUG] Response body result: map[secret:michaelpeer1-org1pw]
2018/07/22 02:52:32 [DEBUG] The register request completed successfully
Password: michaelpeer1-org1pw
##### 2018-07-22 02:52:32 Finished registering peer for org org1
```

### Step 9: Start the peer
We are now ready to start the new peer. The peer runs as a pod in Kubernetes. Let's take a look at the pod spec before
we deploy it. Replace 'michaelpeer1' with the name of your peer, and replace 'org1' with the org you selected. If you 
are unsure, you can simply do 'ls k8s' to view the yaml files that were generated based on your selections, and find
the file start starts with 'fabric-deployment-remote-peer-'.

```bash
more k8s/fabric-deployment-workshop-remote-peer-michaelpeer1-org1.yaml
```

There are a few things of interest in the pod yaml file:

* The pod specifies 2 containers: couchdb, a key-value store which stores the Fabric world state, and the peer itself
* The peer is bootstrapped using a script, which you can view by opening 'scripts/start-peer.sh'
* The peer is exposed using a Kubernetes service

So let's deploy the peer and check the logs. You may need to wait a few seconds before 'kubectl logs' will return the log
entries, as Kubernetes downloads and starts your container:

```bash
kubectl apply -f k8s/fabric-deployment-workshop-remote-peer-michaelpeer1-org1.yaml
kubectl logs deploy/michaelpeer1-org1 -n org1 -c michaelpeer1-org1
```

You'll see a large number of log entries, which you are free to look at. The most important entries are a few
lines from the end of the log file. Look for these, and make sure there are no errors after these lines:

```bash
2018-07-22 03:05:49.145 UTC [nodeCmd] serve -> INFO 1ca Starting peer with ID=[name:"michaelpeer1-org1" ], network ID=[dev], address=[100.96.2.149:7051]
2018-07-22 03:05:49.146 UTC [nodeCmd] serve -> INFO 1cb Started peer with ID=[name:"michaelpeer1-org1" ], network ID=[dev], address=[100.96.2.149:7051]
```

If you can't find the entries, try grep:

```bash
kubectl logs deploy/michaelpeer1-org1 -n org1 -c michaelpeer1-org1 | grep 'Started peer'
```

Your peer has started, but..... it's useless at this point. It hasn't joined any channels, it can't run chaincode
and it does not maintain any ledger state. To start building a ledger on the peer we need to join a channel.

### Step 10: Join the peer to a channel
To give you a better understanding of Fabric, we are going to carry out the steps to join a peer to a channel manually.
We need to carry out the steps from within a container running in the Kubernetes cluster. We'll use the 'register'
container you started in step 8, as this runs the fabric-ca-tools image, which will provide us a CLI (command line interface)
to interact with the peer. You can confirm this by:

```bash
kubectl get po -n org1
```

Then describe the register pod using the pod name (replace the pod name below with your own):

```bash
kubectl describe po register-p-org1-66bd5688b4-rrpw6 -n org1
```

Look at the Image Id attribute. You'll see it contains something like the entry below. fabric-ca-tools provides a CLI
we can use to interact with a Fabric network:

```bash
docker-pullable://hyperledger/fabric-ca-tools@sha256:e4dfa9b12a854e3fb691fece50e4a52744bc584af809ea379d27c4e035cbf008
```

OK, so let's 'exec' into the register container (replace the pod name below with your own):

```bash
kubectl exec -it register-p-org1-66bd5688b4-rrpw6 -n org1 bash
```

Now that you are inside the container, type the following:

```bash
peer
```

This will show you the help message for the Fabric 'peer' CLI. We'll use this to join a channel, install chaincode
and invoke transactions.

Firstly, we need to join a channel. To join a channel you'll need to be an admin user, and you'll need access to the 
channel genesis block. The channel genesis block is stored on the EFS drive, and you can see it by typing:

```bash
ls -l /data
```

Look for the file titled mychannel.block. The channel genesis block provides the configuration for the channel. It's the 
first block added to a channel, and forms 'block 0' in the Fabric blockchain for that channel. As a matter of interest,
Fabric supports multiple blockchains within the same Fabric network, each blockchain associated with a Fabric channel.

Interacting with peers using the 'peer' utility requires you to set ENV variables that provide context to the 'peer' utility.
We'll use the following ENV variables to indicate which peer we want to interact with. You'll need to make the following changes:

* Change 'michaelpeer' to match the name of your peer
* Change 'org1' to the name of the org you belong to. Change it everywhere it appears

You should still be inside the register container at this point. Copy all the variables below, and paste them into your 
terminal window. If you exit the register container, and 'exec' back in later, remember to rerun these export statements.

```bash
export CORE_PEER_TLS_ENABLED=false
export CORE_PEER_TLS_CLIENTAUTHREQUIRED=false
export CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
export CORE_PEER_ID=michaelpeer1-org1
export CORE_PEER_ADDRESS=michaelpeer1-org1.org1:7051
export CORE_PEER_LOCALMSPID=org1MSP
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org1/admin/msp
```

Let's check to see whether the peer we specified in the export statement above has joined any channels:

```bash
peer channel list
```

You should see the following: 

```bash
# peer channel list
2018-07-26 03:40:45.128 UTC [channelCmd] InitCmdFactory -> INFO 001 Endorser and orderer connections initialized
Channels peers has joined:
2018-07-26 03:40:45.133 UTC [main] main -> INFO 002 Exiting.....
```

Now let's join a channel. The statement below joins the peer you specified in the ENV variables above, with the channel
defined in mychannel.block. The channel name is, conveniently, 'mychannel':

```bash
peer channel join -b /data/mychannel.block
peer channel list
```

```bash
# peer channel join -b /data/mychannel.block
2018-07-26 03:42:26.352 UTC [channelCmd] InitCmdFactory -> INFO 001 Endorser and orderer connections initialized
2018-07-26 03:42:26.493 UTC [channelCmd] executeJoin -> INFO 002 Successfully submitted proposal to join channel
2018-07-26 03:42:26.493 UTC [main] main -> INFO 003 Exiting.....
# peer channel list
2018-07-26 03:42:30.940 UTC [channelCmd] InitCmdFactory -> INFO 001 Endorser and orderer connections initialized
Channels peers has joined:
mychannel
2018-07-26 03:42:30.944 UTC [main] main -> INFO 002 Exiting.....
```

You should see that your peer has now joined the channel. 

### Step 11: Confirm peer has joined channel
To confirm the peer has joined the channel you'll need to check the peer logs. If there are existing blocks on the channel 
you should see them replicating to the new peer. Look for messages in the log file such as `Channel [mychannel]: Committing block [14385] to storage`.
To view the peer logs, exit the 'register' container (by typing 'exit' on the command line). This will return you to 
your EC2 bastion instance. Then enter (replacing the name of the peer with your own):

```bash
kubectl logs deploy/michaelpeer1-org1 -n org1 -c michaelpeer1-org1
```

### Step 12: Install the marbles chaincode
To install the marbles chaincode we'll first clone the chaincode repo to our 'register' container, then install the
chaincode to the peer. 'exec' back in to the 'register' container, rerun the export statements from Step 10, and do 
the following:

```bash
mkdir -p /opt/gopath/src/github.com/hyperledger
cd /opt/gopath/src/github.com/hyperledger
git clone https://github.com/IBM-Blockchain/marbles.git
cd marbles
mkdir /opt/gopath/src/github.com/hyperledger/fabric
```

Now install the chaincode:

```bash
peer chaincode install -n marbles-workshop -v 1.0 -p github.com/hyperledger/marbles/chaincode/src/marbles
```

The result should be similar to the one below. If it failed, make sure you run the export statements from Step 10:

```bash
# peer chaincode install -n marbles-workshop -v 1.0 -p github.com/hyperledger/marbles/chaincode/src/marbles
2018-07-26 08:57:55.684 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 001 Using default escc
2018-07-26 08:57:55.684 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 002 Using default vscc
2018-07-26 08:57:55.823 UTC [main] main -> INFO 003 Exiting.....
```

Check that it was installed. We also check if it was instantiated. It should be as it was instantiated by the facilitator
when the channel was setup:

```bash
peer chaincode list --installed
peer chaincode list --instantiated -C mychannel
```

You should see the following. You may need to try the 'instantiated' command more than once:

```bash
# peer chaincode list --installed
Get installed chaincodes on peer:
Name: marbles-workshop, Version: 1.0, Path: github.com/hyperledger/marbles/chaincode/src/marbles, Id: 7c07640a582822f8bb2364fa0ab0d204ba8b3d6b28f559027fcbdccfe65b3aae
2018-07-30 05:45:25.832 UTC [main] main -> INFO 001 Exiting.....
# peer chaincode list --instantiated -C mychannel
Get instantiated chaincodes on channel mychannel:
Name: marbles-workshop, Version: 1.0, Path: github.com/hyperledger/marbles/chaincode/src/marbles, Escc: escc, Vscc: vscc
2018-07-30 05:45:25.940 UTC [main] main -> INFO 001 Exiting.....
```

### Step 13: Creating a user
So far we have interacted with the peer node using the Admin user. This might not have been apparent, but the export 
statements we used include the following line, 'export CORE_PEER_MSPCONFIGPATH=/data/orgs/org1/admin/msp', which
sets the MSP (membership service provider) context to an admin user. Admin was used to join the channel and install the chaincode,
but to invoke transactions and query the ledger state we need a user. Users are created by fabric-ca, a tool provided for 
us by Fabric to act as a root CA and manage the registration and enrollment of identities.

Once again, 'exec' into the register container and run the export statements from Step 10. Replace 'org1' in the statements 
below to match the org you have chosen, and execute the statements.

```bash
export FABRIC_CA_CLIENT_HOME=/etc/hyperledger/fabric/orgs/org1/user
export CORE_PEER_MSPCONFIGPATH=$FABRIC_CA_CLIENT_HOME/msp
export FABRIC_CA_CLIENT_TLS_CERTFILES=/data/org1-ca-chain.pem
fabric-ca-client enroll -d -u https://user-org1:user-org1pw@ica-org1.org1:7054
```

You'll see a lengthy response that looks similar to this. Make sure you receive a 'statusCode=201' to indicate you user
was created successfully:

```bash
# fabric-ca-client enroll -d -u https://user-org1:user-org1pw@ica-org1.org1:7054
2018/07/26 05:05:34 [DEBUG] Home directory: /etc/hyperledger/fabric/orgs/org1/user
2018/07/26 05:05:34 [INFO] Created a default configuration file at /etc/hyperledger/fabric/orgs/org1/user/fabric-ca-client-config.yaml
2018/07/26 05:05:34 [DEBUG] Client configuration settings: &{URL:https://user-org1:user-org1pw@ica-org1.org1:7054 MSPDir:msp TLS:{Enabled:true CertFiles:[/data/org1-ca-chain.pem] Client:{KeyFile: CertFile:}} Enrollment:{ Name: Secret:**** Profile: Label: CSR:<nil> CAName: AttrReqs:[]  } CSR:{CN:user-org1 Names:[{C:US ST:North Carolina L: O:Hyperledger OU:Fabric SerialNumber:}] Hosts:[register-p-org1-66bd5688b4-rrpw6] KeyRequest:<nil> CA:<nil> SerialNumber:} ID:{Name: Type:client Secret: MaxEnrollments:0 Affiliation: Attributes:[] CAName:} Revoke:{Name: Serial: AKI: Reason: CAName: GenCRL:false} CAInfo:{CAName:} CAName: CSP:0xc4201ccba0}
2018/07/26 05:05:34 [DEBUG] Entered runEnroll
2018/07/26 05:05:34 [DEBUG] Enrolling { Name:user-org1 Secret:**** Profile: Label: CSR:&{user-org1 [{US North Carolina  Hyperledger Fabric }] [register-p-org1-66bd5688b4-rrpw6] <nil> <nil> } CAName: AttrReqs:[]  }
2018/07/26 05:05:34 [DEBUG] Initializing client with config: &{URL:https://ica-org1.org1:7054 MSPDir:msp TLS:{Enabled:true CertFiles:[/data/org1-ca-chain.pem] Client:{KeyFile: CertFile:}} Enrollment:{ Name:user-org1 Secret:**** Profile: Label: CSR:&{user-org1 [{US North Carolina  Hyperledger Fabric }] [register-p-org1-66bd5688b4-rrpw6] <nil> <nil> } CAName: AttrReqs:[]  } CSR:{CN:user-org1 Names:[{C:US ST:North Carolina L: O:Hyperledger OU:Fabric SerialNumber:}] Hosts:[register-p-org1-66bd5688b4-rrpw6] KeyRequest:<nil> CA:<nil> SerialNumber:} ID:{Name: Type:client Secret: MaxEnrollments:0 Affiliation: Attributes:[] CAName:} Revoke:{Name: Serial: AKI: Reason: CAName: GenCRL:false} CAInfo:{CAName:} CAName: CSP:0xc4201ccba0}
2018/07/26 05:05:34 [DEBUG] Initializing BCCSP: &{ProviderName:SW SwOpts:0xc4201ccc00 PluginOpts:<nil> Pkcs11Opts:<nil>}
2018/07/26 05:05:34 [DEBUG] Initializing BCCSP with software options &{SecLevel:256 HashFamily:SHA2 Ephemeral:false FileKeystore:0xc4201e07e0 DummyKeystore:<nil>}
2018/07/26 05:05:34 [INFO] TLS Enabled
2018/07/26 05:05:34 [DEBUG] CA Files: [/data/org1-ca-chain.pem]
2018/07/26 05:05:34 [DEBUG] Client Cert File:
2018/07/26 05:05:34 [DEBUG] Client Key File:
2018/07/26 05:05:34 [DEBUG] Client TLS certificate and/or key file not provided
2018/07/26 05:05:34 [DEBUG] GenCSR &{CN:user-org1 Names:[{C:US ST:North Carolina L: O:Hyperledger OU:Fabric SerialNumber:}] Hosts:[register-p-org1-66bd5688b4-rrpw6] KeyRequest:<nil> CA:<nil> SerialNumber:}
2018/07/26 05:05:34 [INFO] generating key: &{A:ecdsa S:256}
2018/07/26 05:05:34 [DEBUG] generate key from request: algo=ecdsa, size=256
2018/07/26 05:05:34 [INFO] encoded CSR
2018/07/26 05:05:34 [DEBUG] Sending request
POST https://ica-org1.org1:7054/enroll
{"hosts":["register-p-org1-66bd5688b4-rrpw6"],"certificate_request":"-----BEGIN CERTIFICATE REQUEST-----\nMIIBWzCCAQECAQAwYTELMAkGA1UEBhMCVVMxFzAVBgNVBAgTDk5vcnRoIENhcm9s\naW5hMRQwEgYDVQQKEwtIeXBlcmxlZGdlcjEPMA0GA1UECxMGRmFicmljMRIwEAYD\nVQQDEwl1c2VyLW9yZzEwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQ52A9ctKjd\n9+qQJUYlxTStSSbhY4nRWbUORUK7p5GIuesXgn79zU/YMST4BX9z6SOI97Y//cVf\nzLkq/4o5XAdIoD4wPAYJKoZIhvcNAQkOMS8wLTArBgNVHREEJDAigiByZWdpc3Rl\nci1wLW9yZzEtNjZiZDU2ODhiNC1ycnB3NjAKBggqhkjOPQQDAgNIADBFAiEA68Az\nRQcnmoKfglSrfgcRphudltiMXQlksBh3suDP25QCIGhX65Oi6X7z5RUINkurwtQs\nhWL4Igew+5UL0i2g1AyP\n-----END CERTIFICATE REQUEST-----\n","profile":"","crl_override":"","label":"","NotBefore":"0001-01-01T00:00:00Z","NotAfter":"0001-01-01T00:00:00Z","CAName":""}
2018/07/26 05:05:35 [DEBUG] Received response
statusCode=201 (201 Created)
2018/07/26 05:05:35 [DEBUG] Response body result: map[Cert:LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN4ekNDQW0yZ0F3SUJBZ0lVUlpoZFQzOFpLUDhRcVlBRFk0S2ZFeEptSXRrd0NnWUlLb1pJemowRUF3SXcKWmpFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1kyeHBaVzUwTVJjd0ZRWURWUVFERXc1eVkyRXRiM0puCk1TMWhaRzFwYmpBZUZ3MHhPREEzTWpZd05UQXhNREJhRncweE9UQTNNall3TlRBMk1EQmFNRzR4Q3pBSkJnTlYKQkFZVEFsVlRNUmN3RlFZRFZRUUlFdzVPYjNKMGFDQkRZWEp2YkdsdVlURVVNQklHQTFVRUNoTUxTSGx3WlhKcwpaV1JuWlhJeEhEQU5CZ05WQkFzVEJtTnNhV1Z1ZERBTEJnTlZCQXNUQkc5eVp6RXhFakFRQmdOVkJBTVRDWFZ6ClpYSXRiM0puTVRCWk1CTUdCeXFHU000OUFnRUdDQ3FHU000OUF3RUhBMElBQkRuWUQxeTBxTjMzNnBBbFJpWEYKTksxSkp1RmppZEZadFE1RlFydW5rWWk1NnhlQ2Z2M05UOWd4SlBnRmYzUHBJNGozdGovOXhWL011U3IvaWpsYwpCMGlqZ2ZBd2dlMHdEZ1lEVlIwUEFRSC9CQVFEQWdlQU1Bd0dBMVVkRXdFQi93UUNNQUF3SFFZRFZSME9CQllFCkZIaUNGNlJxS3pEbVBDVDZ5b1JxV29oNndCanJNQjhHQTFVZEl3UVlNQmFBRkJRS1dzRVhJeEp1MWdHQ1hrWUgKMlF1KzBGVUVNQ3NHQTFVZEVRUWtNQ0tDSUhKbFoybHpkR1Z5TFhBdGIzSm5NUzAyTm1Ka05UWTRPR0kwTFhKeQpjSGMyTUdBR0NDb0RCQVVHQndnQkJGUjdJbUYwZEhKeklqcDdJbWhtTGtGbVptbHNhV0YwYVc5dUlqb2liM0puCk1TSXNJbWhtTGtWdWNtOXNiRzFsYm5SSlJDSTZJblZ6WlhJdGIzSm5NU0lzSW1obUxsUjVjR1VpT2lKamJHbGwKYm5RaWZYMHdDZ1lJS29aSXpqMEVBd0lEU0FBd1JRSWhBTGJTRXYrT281SGNQaUMxMmM4cE5Oa1lmNTc5Y2s5eQpnZ1hsNUhWYmYyRUpBaUIrdURFZkhNT3JYY0VhK0htMXFTZS93TkZQL05NaitVSmlrc3BKbWE5WHNnPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo= ServerInfo:map[CAName:ica-org1.org1 CAChain:LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNNakNDQWRtZ0F3SUJBZ0lVY0w4V2N6dWcxUEVwbWQrZVpEeThhQ1NhWEVRd0NnWUlLb1pJemowRUF3SXcKWlRFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puCk1TNXZjbWN4TUI0WERURTRNRGN4TnpBek16QXdNRm9YRFRJek1EY3hOakF6TXpVd01Gb3daakVMTUFrR0ExVUUKQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRS0V3dEllWEJsY214bApaR2RsY2pFUE1BMEdBMVVFQ3hNR1kyeHBaVzUwTVJjd0ZRWURWUVFERXc1eVkyRXRiM0puTVMxaFpHMXBiakJaCk1CTUdCeXFHU000OUFnRUdDQ3FHU000OUF3RUhBMElBQlBoV0kzVEZjbGlsMjU3aE9SOFNDVi9obE9DK0hQZFgKRXd1NEhxZ2RjTUxJM0N5b0RxMG14SWJxTUZYWkY5blo3dUdZaWV6Mmg5ekF5YjYxVkd5bWYzNmpaakJrTUE0RwpBMVVkRHdFQi93UUVBd0lCQmpBU0JnTlZIUk1CQWY4RUNEQUdBUUgvQWdFQU1CMEdBMVVkRGdRV0JCUVVDbHJCCkZ5TVNidFlCZ2w1R0I5a0x2dEJWQkRBZkJnTlZIU01FR0RBV2dCUVNHVzJtNG9iZnhTcXpvYXEvZWhQY3FDemkKNERBS0JnZ3Foa2pPUFFRREFnTkhBREJFQWlCRlJxTXczdi9DZmI0UmpndWVjbWh6OEhUNzZad0REdmNZazFPMwpFay9FalFJZ2FBWG9Ld0EvejdGeEJaSmJ2akFTVHV2VHlwN3RGam1JVFJlUlkxUUdZclk9Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUNFVENDQWJlZ0F3SUJBZ0lVU2JIcWNjYndmZDhkdEJZajdKRldjWUNZOXdFd0NnWUlLb1pJemowRUF3SXcKWlRFTE1Ba0dBMVVFQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRSwpFd3RJZVhCbGNteGxaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puCk1TNXZjbWN4TUI0WERURTRNRGN4TnpBek16QXdNRm9YRFRNek1EY3hNekF6TXpBd01Gb3daVEVMTUFrR0ExVUUKQmhNQ1ZWTXhGekFWQmdOVkJBZ1REazV2Y25Sb0lFTmhjbTlzYVc1aE1SUXdFZ1lEVlFRS0V3dEllWEJsY214bApaR2RsY2pFUE1BMEdBMVVFQ3hNR1JtRmljbWxqTVJZd0ZBWURWUVFERXcxeVkyRXRiM0puTVM1dmNtY3hNRmt3CkV3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFZ2phM1R1a0w0QWE2QWU5Zjk0b0c1S0dNcXJmZGErRkwKNW45N1dJYlE3QVJjN0dwRWNnVVNoWjNZQ1JDdDQxd01LVUFscnNDVVlwWU1jaS9zZlNmM1NxTkZNRU13RGdZRApWUjBQQVFIL0JBUURBZ0VHTUJJR0ExVWRFd0VCL3dRSU1BWUJBZjhDQVFFd0hRWURWUjBPQkJZRUZCSVpiYWJpCmh0L0ZLck9ocXI5NkU5eW9MT0xnTUFvR0NDcUdTTTQ5QkFNQ0EwZ0FNRVVDSVFEVDZMNWxyMmwxdHRRb0V4NWYKbklzUzZMcUN3bGV4UEc4NGVYSlZPTGRWZ3dJZ1F6cld2eHdJcDRrQ2tyVTI0SmRuZnRyUEVsMWRUSTVRTzQ0VApYVy9ZWjM0PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg== Version:]]
2018/07/26 05:05:35 [DEBUG] newEnrollmentResponse user-org1
2018/07/26 05:05:35 [INFO] Stored client certificate at /etc/hyperledger/fabric/orgs/org1/user/msp/signcerts/cert.pem
2018/07/26 05:05:35 [INFO] Stored root CA certificate at /etc/hyperledger/fabric/orgs/org1/user/msp/cacerts/ica-org1-org1-7054.pem
2018/07/26 05:05:35 [INFO] Stored intermediate CA certificates at /etc/hyperledger/fabric/orgs/org1/user/msp/intermediatecerts/ica-org1-org1-7054.pem
```

Some final copying of certs is required:

```bash
mkdir /etc/hyperledger/fabric/orgs/org1/user/msp/admincerts
cp /data/orgs/org1/admin/msp/signcerts/* /etc/hyperledger/fabric/orgs/org1/user/msp/admincerts
```

From now on, the following export statement will identify you as a user:

```bash
export CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/orgs/org1/user/msp
```

as the following export statement will identity you as an admin:

```bash
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org1/admin/msp
```

### Step 14: Invoke transactions in Fabric
Let's run a query. In Fabric, a query will execute on the peer node and query the world state, which is the current
state of the ledger. World state is stored in either a CouchDB or LevelDB key-value store. The query below will
return the latest marble owners. 

When we say 'run a query', we really mean 'execute chaincode that queries the world state'. In Fabric, chaincode executes
inside a Docker container. The first time you run chaincode it may take a few seconds as the Docker container that hosts 
the chaincode is downloaded and created.

```bash
export CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/orgs/org1/user/msp
peer chaincode query -C mychannel -n marbles-workshop -c '{"Args":["read_everything"]}' 
```

```bash
# peer chaincode query -C mychannel -n marbles-workshop -c '{"Args":["read_everything"]}'
2018-07-30 05:50:16.760 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 001 Using default escc
2018-07-30 05:50:16.760 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 002 Using default vscc
Query Result: {"owners":[{"docType":"marble_owner","id":"o9999999999999999990","username":"braendle","company":"United Marbles","enabled":true},{"docType":"marble_owner","id":"o9999999999999999991","username":"edge","company":"United Marbles","enabled":true}],"marbles":[{"docType":"marble","id":"m999999999990","color":"red","size":35,"owner":{"id":"o9999999999999999990","username":"braendle","company":"United Marbles"}},{"docType":"marble","id":"m999999999991","color":"blue","size":50,"owner":{"id":"o9999999999999999991","username":"edge","company":"United Marbles"}}]}
2018-07-30 05:50:16.779 UTC [main] main -> INFO 003 Exiting.....
```

Invoking a transaction is different to running a query. Whereas a query runs locally on your own peer, a transaction
first runs locally, simulating the transaction against your local world state, then the results are sent to the 
orderer. The orderer groups the transactions into blocks and distributes them to all peer nodes. All the peers
then update their ledgers and world state with each transaction in the block.

Since the transaction is sent to the orderer, you need to provide the orderer endpoint when invoking a transaction:

```bash
export ORDERER_CONN_ARGS="-o a8a50caf493b511e8834f06b86f026a6-77ab14764e60b4a1.elb.us-west-2.amazonaws.com:7050"
peer chaincode invoke -C mychannel -n marbles-workshop -c '{"Args":["set_owner","m999999999990","o9999999999999999990", "United Marbles"]}' $ORDERER_CONN_ARGS
peer chaincode query -C mychannel -n marbles-workshop -c '{"Args":["read_everything"]}' 
```

### Step 15: Connect an application to your Fabric peer
We are going to connect the marbles client application to your peer node. This will provide you with a user interface
you can use to interact with the Fabric network. It will also provide you visibility into what is happening in the
network, and what activities are being carried out by the other workshop participants.

The Marbles client application uses the Fabric SDK and requires connectivity to three Fabric components:

* Orderer: the Orderer was created by the facilitator before the workshop started. The facilitator will provide the endpoint 
(in fact, it should have been provided for you in Step 14. See the statement 'export ORDERER_CONN_ARGS=')
* Peer: this is the peer you started in step 9. We will expose this using an NLB below (NLB because peers communicate using gRPC)
* CA: this is the CA you started in step 8. We will expose this using an ELB below (ELB because the CA server exposes a REST API)

Before we continue, there is a bug in EKS that requires us to edit an IAM policy. A missing permission in an EKS role
currently prevents the creation of load balancers, so we will edit the EKS role manually and add the permission.

In the IAM Console, in the account containing your EKS cluster, find the role starting with `EKS-eks-fabric-ServiceRol-AWS`. In
my account this is `arn:aws:iam::123456789012:role/EKS-eks-fabric-ServiceRol-AWSServiceRoleForAmazonE-1XD9JDMQKT7F9`. In
the Permissions tab, find the policy titled `EKS-eks-fabric-ServiceRole-NLB`. Select JSON, then Edit Policy. Add this
permission to the policy: "iam:CreateServiceLinkedRole". Make sure to use the same indents, and include a comma if
necessary. Review and save the policy.

Let's create the AWS Network Load Balancer (NLB) endpoints for the peer and the ca. The K8s YAML files to create these would 
have been generated for you. On your EC2 bastion instance (make sure you're on the EC2 instance, and not 'exec'd into the register
container) replace the org numbers below to match yours, and the name of the peer (i.e. michaelpeer) to match your own. 
These files should already exist in the k8s/ directory:

```bash
cd
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-nlb-ca-org1.yaml
kubectl apply -f k8s/fabric-nlb-remote-peer-michaelpeer1-org1.yaml
```

Check whether the service endpoints were created. You should see the start of a DNS endpoint in the EXTERNAL-IP column. If
you see <pending>, rerun the 'get svc' command until you see the DNS name.

```bash
$ kubectl get svc -n org1
NAME                    TYPE           CLUSTER-IP       EXTERNAL-IP        PORT(S)                         AGE
ica-org1                NodePort       100.69.223.117   <none>             7054:30820/TCP                  1h
ica-org1-nlb            LoadBalancer   100.67.187.247   a4572233e93c5...   7054:30786/TCP                  33s
michaelpeer1-org1       NodePort       100.71.189.75    <none>             7051:30751/TCP,7052:30752/TCP   1h
michaelpeer1-org1-nlb   LoadBalancer   100.64.236.245   a55e52d7d93c5...   7051:31701/TCP                  5s
rca-org1                NodePort       100.65.85.156    <none>             7054:30800/TCP                  1h
```

You can see the full endpoint using `kubectl describe`, as follows. The 'LoadBalancer Ingress' attribute shows the AWS DNS representing
the ELB endpoint for the intermediate CA, ica-org1:

```bash
$ kubectl describe svc ica-notls-org1-nlb -n org1
Name:                     ica-notls-org1-nlb
Namespace:                org1
Labels:                   <none>
Annotations:              kubectl.kubernetes.io/last-applied-configuration={"apiVersion":"v1","kind":"Service","metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":"nlb"},"name":"ica-notls-org1-nlb","...
                          service.beta.kubernetes.io/aws-load-balancer-type=nlb
Selector:                 app=hyperledger,name=ica-notls-org1,org=org1,role=ca
Type:                     LoadBalancer
IP:                       100.71.98.239
LoadBalancer Ingress:     a0a212d7b948511e8a5200a2330c2ef3-4cccceb9bd78e9cd.elb.us-east-1.amazonaws.com
Port:                     endpoint  7054/TCP
TargetPort:               7054/TCP
NodePort:                 endpoint  32693/TCP
Endpoints:                100.96.1.168:7054
Session Affinity:         None
External Traffic Policy:  Cluster
Events:
  Type    Reason                Age   From                Message
  ----    ------                ----  ----                -------
  Normal  EnsuringLoadBalancer  48s   service-controller  Ensuring load balancer
  Normal  EnsuredLoadBalancer   46s   service-controller  Ensured load balancer
```

Do the same to view the NLB endpoint for the peer. Note down the LoadBalancer Ingress for both CA and peer. You'll use
them in Step 16.

In the next step we'll configure Marbles to use these endpoints, and connect the application to the Fabric network.

### Step 16
To start, let's clone the Marbles application. On your own laptop, in any folder you choose:

```bash
git clone https://github.com/IBM-Blockchain/marbles.git
cd marbles
```

Before building, make sure you have a version of node and npm, as specified in the prerequisites at
the top of this readme.

Prepare the app. You'll need npm (node package manager) for this so make sure you have it installed. See prerequisites at
the top of this readme. You may need to use 'sudo' for the 'npm install gulp -g'. Do not use 'sudo' for the main 'npm install':

```bash
npm install gulp -g
```

If the above command fails, use 'sudo':

```bash
sudo npm install gulp -g
```

Then do:

```bash
npm install
```

To configure the connectivity between the Marbles app and the Fabric network, Marbles requires a connection profile that 
contains the connectivity endpoints. I have provided a template of this file for you in the hyperledger-on-kubernetes repo. Use cURL 
to download the files you'll need. If using the cURL method, make sure you are in the marbles directory, in the marbles repo:

```bash
cd config
curl  https://raw.githubusercontent.com/MCLDG/hyperledger-on-kubernetes/master/workshop-remote-peer/marbles/connection_profile_eks.json -o connection_profile_eks.json
curl  https://raw.githubusercontent.com/MCLDG/hyperledger-on-kubernetes/master/workshop-remote-peer/marbles/marbles_eks.json -o marbles_eks.json
```

Still in the config directory, edit connection_profile_eks.json:

* Do a global search & replace on 'org1', replacing it with the org you have chosen
* Do a global search & replace on 'michaelpeer', replacing it with your peer name
* In the 'replace' commands below, make sure you do not change the port number, nor remove the protocol (e.g. grpc://)
* Replace the orderer URL with the NLB endpoint provided by your facilitator (The same one you used in Step 14. See the 
statement 'export ORDERER_CONN_ARGS='):

```json
    "orderers": {
        "orderer3-org0.org0": {
            "url": "grpc://a8a50caf493b511e8834f06b86f026a6-77ab14764e60b4a1.elb.us-west-2.amazonaws.com:7050",
```

* Replace the peer URL (both url and eventUrl) with the endpoint you obtained in Step 15 when 
running `kubectl describe svc <your peer service name> -n org1` 

```json
    "peers": {
        "michaelpeer1-org1.org1": {
            "url": "grpc://a55e52d7d93c511e8a5200a2330c2ef3-25d11c6db68acd98.elb.us-east-1.amazonaws.com:7051",
            "eventUrl": "grpc://a55e52d7d93c511e8a5200a2330c2ef3-25d11c6db68acd98.elb.us-east-1.amazonaws.com:7052",
```

* Replace the certificateAuthorities URL with the endpoint you obtained in Step 15 when 
running `kubectl describe svc <your CA service name> -n org1` 

```json
    "certificateAuthorities": {
        "ica-org1": {
            "url": "http://a4572233e93c511e8a5200a2330c2ef3-6cd15c4b453d4003.elb.us-east-1.amazonaws.com:7054",
```

* Replace the name of the marbles chaincode

```json
            "chaincodes": [
                "marbles-workshop:v1"
            ],
```

One final change will ensure our new connection profile is used:

* In the marbles repo, edit the file `gulpfile.js`
* Around line 40, add this line:

```json
gulp.task('marbles_eks', ['env_eks', 'watch-sass', 'watch-server', 'server']);		//run with command `gulp marbles_eks` for AWS EKS container service
```

* Around line 50, add this section:

```json
// AWS EKS Container Service
gulp.task('env_eks', function () {
	env['creds_filename'] = 'marbles_eks.json';
});
```

### Step 16: Running and using the marbles application
NOTE: Marbles running locally cannot connect to the ELB port 7054 if you are running your VPN software. Please
stop the VPN before connecting.

On your laptop, in the marbles repo directory (not the config directory, which you may be in), in the root folder of 
the repo, run the following:

```bash
gulp marbles_eks
```

If this fails, ensure your VPN is not running.

In a browser, navigate to: http://localhost:32001/home. Before doing anything else, configure the UI:

* Click 'Settings' and set Story Mode ON. This will show you what Fabric is doing behind the scenes when you create
new marbles or transfer them.
* Click the magnifying glass on the left, then click on a marble to see the transactions related to that marble. 

Now go ahead and drag marbles from one owner to another, or create new marbles. Watch how the UI explains what is
happening inside Fabric. For further 'geek-level' detail, check out the terminal window where you started the marbles
app. You'll see debug statements showing the transactions being sent by the client application to the Fabric network.

Add yourself as a new marble owner. Now, for some reason, the developers of the app created a chaincode function
to do this, but did not include this function in the UI. So we'll do it the hard way.

On your EC2 bastion instance, 'exec' into the register container and enter the export statements you used in Step 10. 
Then identify yourself as a user (change org1 to match your org):

```bash
export CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/fabric/orgs/org1/user/msp
```

Execute the chaincode below to add yourself as a marble owner. Change the numbers below to some other random number (i.e. 
o9999999999999999990 and m999999999990 - just make sure you have the same or fewer digits), and change 'bob' to your 
alias (something unique). MAKE SURE you use both the 'o' and 'm' prefixes in your owner and marble names. The marbles 
app depends on them. 

If you execute both invoke statements immediately after each other, the second one will probably fail. Any idea why? 
If you have Story Mode ON, as suggested above, and you watch what happens in Fabric when you transfer a marble, it will 
give you a strong hint.

You may need to wait a few seconds between the invoke statements, and for your new owner to be reflected in the query.
There is no issue with running these statements multiple times.

```bash
export ORDERER_CONN_ARGS="-o a8a50caf493b511e8834f06b86f026a6-77ab14764e60b4a1.elb.us-west-2.amazonaws.com:7050"
peer chaincode invoke -C mychannel -n marbles-workshop -c '{"Args":["init_owner","o9999999999999999990","bob", "United Marbles"]}' $ORDERER_CONN_ARGS
peer chaincode invoke -C mychannel -n marbles-workshop -c '{"Args":["init_marble","m999999999990", "blue", "35", "o9999999999999999990", "United Marbles"]}' $ORDERER_CONN_ARGS
peer chaincode query -C mychannel -n marbles-workshop -c '{"Args":["read_everything"]}'
```

Now jump back to the UI and you should automatically see these changes to the blockchain state reflected in the app. You can
now add new marbles via the UI (or via the CLI) and transfer marbles to/from other participants.

### Step 17: Pat yourself on the back

Well done for making it this far. Let's look at what you've achieved:

* You have built a Kubernetes cluster
* On this cluster, you have deployed a Hyperledger Fabric CA and Peer, which connects into an existing Hyperledger Fabric network
* You have joined your peer to an existing channel
* You have replicated all the blocks from the existing Fabric channel to your peer, and your peer has used these blocks to
build its own copy of the ledger and world state
* You have run a UI application, connected this to your local Fabric peer, and invoked transactions on the Fabric network
via the local app and your local peer

Quite impressive!

### Step 18: Cleanup

Cleanup your Hyperledger Fabric nodes:

```bash
./workshop-remote-peer/stop-remote-fabric-setup.sh
```

Don't forget to remove your EKS cluster. Instructions can be found here:

* EKS: https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html
* Kops: https://github.com/kubernetes/kops/blob/master/docs/cli/kops_delete_cluster.md

### Debugging Fabric on Kubernetes

To debug Fabric running in Kubernetes, there are a few commands that will come in handy.

To see all pods running your Kubernetes cluster:

```bash
kubectl get po --all-namespaces
```

To see the pods running in a specific Kubernetes namespace, in this case 'org1':

```bash
kubectl get po -n org1
```

To see the logs for a specific pod, using the pod name from 'get po'. Do this first:

```bash
kubectl logs <pod name> -n org1
```

It may error, asking for a container name. It will then provide you with a list of the container names. Rerun the 
statement with a container name:

```bash
kubectl logs <pod name> -n org1 -c peer1-org1
```

To describe a pod and see its associated details:

```bash
kubectl describe po <pod name> -n org1
```






