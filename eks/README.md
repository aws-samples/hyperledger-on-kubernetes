# Creating an EKS cluster

This README helps you create the platform for managing and running Hyperledger Fabric. The platform consists of an
EKS cluster, an EFS drive (for the Fabric cryptographic material) and an EC2 bastion host. The EKS cluster is created
first. The EC2 bastion is then created in the same VPC as EKS, and EFS is mounted into the EKS subnets. The EFS can
be accessed from the EKS cluster as well as from the EC2 bastion.

You have a number of options when creating the Kubernetes cluster in which you'll deploy Hyperledger Fabric:
 
* The easiest option is to use eksctl to create an AWS EKS (Elastic Container Service for Kubernetes) cluster. Note that
eksctl is a moving target: initially it created an EKS cluster with worker nodes in public subnets. From v.01.9 it supports
private subnets using the `--node-private-networking` flag. For production use you'll probably want your worker 
nodes in private subnets, so you can use the eksctl feature just mentioned, or use the method below that follows the AWS
documentation to create a production-ready EKS cluster.
* You can create an EKS cluster following the instructions in the AWS documentation at: https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html
* You can use KOPS to create a cluster: https://github.com/kubernetes/kops
* Or you can use an existing Kubernetes cluster, as long as you can SSH into the worker nodes

Whichever method you choose, you will need SSH access to the Kubernetes worker nodes in order to install EFS utils. 
EFS utils is used to mount the EFS (Elastic File System) used to store the Hyperledger Fabric CA certs/keys. 
Instructions on how to do this are in the section 'Install EFS utils on each Kubernetes worker node' below.

This README will focus on creating an EKS cluster using eksctl. 

## Creating an EKS cluster using Cloud9 and eksctl

`eksctl` is a CLI for Amazon EKS that helps you easily create an Amazon EKS cluster! We will use it to create our EKS cluster.

eksctl website:  https://eksctl.io/

Follow the steps below to create your EKS cluster.

## Steps

### Step 1: Create a Kubernetes cluster
You need an EKS cluster to start. The easiest way to do this is to create an EKS cluster using the eksctl tool. Open
the [EKS Readme](../eks/README.md) in this repo and follow the instructions. Once you are complete come back to this README.


1. Spin up a [Cloud9 IDE](https://us-west-2.console.aws.amazon.com/cloud9/home?region=us-west-2) from the AWS console.
In the Cloud9 console, click 'Create Environment'
2. Provide a name for your environment, e.g. eks-c9, and click **Next Step**
3. Leave everything as default and click **Next Step**
4. Click **Create environment**. It would typically take 30-60s to create your Cloud9 IDE
5. We need to turn off the Cloud9 temporary provided IAM credentials. 

![toggle-credentials](images/toggle-credentials.png "Toggle Credentials")

6. In the Cloud9 terminal, on the command line, you'll execute `aws configure` to configure credentials. The credentials 
you enter here are the AWS access key and secret key that belong to the AWS account you will use to create your EKS cluster.
This should be the same account where you've just created your Cloud9 IDE. There are two ways to obtain the AWS access key and secret key:

* if you use the AWS CLI, on your laptop you should have an `.aws` directory. On Mac, it's under your home directory, 
i.e. `~/.aws`. This contains a credentials and config file. The credentials file contains your AWS keys. You can copy the 
AWS access key and secret key from here
* otherwise, log in to the AWS IAM console, find your user and click the `Security Credentials` tab. You can create a new access key here
and copy the AWS access key and secret key into the `aws configure` command

When running `aws configure` you'll be asked to input a region. Select a region that supports EKS. At the time of writing,
this includes us-west-2 and us-east-1.

After running `aws configure`, run `aws sts get-caller-identity` and check that the output matches the account
you'll use to create your EKS cluster, and the access key you configured in `aws configure`.

![sts](images/sts.png "STS")

7. In the Cloud9 terminal, in the home directory, clone this repo:

```bash
cd
git clone https://github.com/aws-samples/hyperledger-on-kubernetes
cd hyperledger-on-kubernetes
```

7. In the Cloud9 terminal, edit the bash script `eks/create-eks.sh` and update the region parameter to match the region in which you want to
deploy EKS.

8. In the Cloud9 terminal, run the bash script:

```bash
cd
cd hyperledger-on-kubernetes
./eks/create-eks.sh
```

It will take around 20 minutes to create your EKS cluster, so go and get a cup of coffee. 

If you need to delete the EKS cluster, run `eksctl delete cluster —name=<CLUSTER_NAME>` to trigger the deletion of the stack.

The script `create-eks.sh` also runs the script `efs/deploy-ec2.sh`. Note that this script obtains the list of subnets
created by eksctl. Since eksctl now creates public and private subnets, the script only uses the first 3 subnets in the list.
The subnets are ordered with public appearing before private - let's hope this ordering remains, otherwise we'll need
some way to identify which are the public and private subnets.

The last few statements in the `create-eks.sh` will copy the aws and kubectl config to your bastion host. It may fail 
with the error below.

```bash
Are you sure you want to continue connecting (yes/no)? yes
lost connection
```

If you see this, execute the statements manually. Just copy and paste the following into your Cloud9 terminal to 
copy across the related files.

```bash
sudo yum -y install jq
PublicDnsNameBastion=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=EFS FileSystem Mounted Instance" | jq '.Reservations | .[] | .Instances | .[] | .PublicDnsName' | tr -d '"')
PublicDnsNameEKSWorker=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=eks-fabric-default-Node" | jq '.Reservations | .[] | .Instances | .[] | .PublicDnsName' | tr -d '"')
echo public DNS of EC2 bastion host: $PublicDnsNameBastion
echo public DNS of EKS worker nodes: $PublicDnsNameEKSWorker

echo Prepare the EC2 bastion for use by copying the kubeconfig and aws config and credentials files from Cloud9
cd ~
scp -i eks-c9-keypair.pem -q ~/kubeconfig.eks-fabric.yaml  ec2-user@${PublicDnsNameBastion}:/home/ec2-user/kubeconfig.eks-fabric.yaml
scp -i eks-c9-keypair.pem -q ~/.aws/config  ec2-user@${PublicDnsNameBastion}:/home/ec2-user/config
scp -i eks-c9-keypair.pem -q ~/.aws/credentials  ec2-user@${PublicDnsNameBastion}:/home/ec2-user/credentials
```

### Step 2: Install EFS utils on each Kubernetes worker node 

EFS utils is required on each Kubernetes worker node to enable the worker to mount the EFS used to store the Hyperledger 
Fabric CA certs/keys.

The EKS worker nodes (i.e. the EC2 instances for the EKS cluster) should be easy to identify in the AWS console as the instance 
name is prefixed with your EKS cluster name, e.g. `eks-fabric-default-Node`. Clicking on each instance will show you the 
security group and the public DNS, which you'll need when you SSH into the instance.

It should no longer be necessary to manually update the security group to allow SSH - this should have been done
for you by eksctl, by passing the `--ssh-access` flag. However, if you are unable to SSH due to the security group 
not allowing SSH access, you can update it following the instructions here: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/authorizing-access-to-an-instance.html#add-rule-authorize-access

If you'll SSH from your Mac, you can update the security group to allow SSH from your IP only. If you'll SSH from Cloud9,
the quickest way is to allow SSH to all. (if someone has a more secure idea, please let me know).

To SSH into the EKS worker nodes or the EC2 bastion instance, you'll need a keypair. The keypair was created for you in Step 1.
The .pem file will be in Cloud9 in your $HOME directory. Check it as follows:

```bash
cd
ls -l eks-c9-keypair.pem
```

The public DNS for the EKS worker nodes and the EC2 bastion instance was printed to the terminal by the script you ran 
in Step 1. You can obtain the DNS from there, otherwise the EC2 instances are easy enough to identify the EC2 console.
Replace the public DNS in the statements below with the public DNS of either your EC2 bastion instance or EKS worker nodes,
and check the path to your keypair file.
 
Now SSH into each worker node and install the EFS utils:

```bash
cd
ssh ec2-52-206-72-54.compute-1.amazonaws.com -i eks-c9-keypair.pem
```

If you see a `Permission denied` message, with details indicating `Permissions 0664 for 'eks-c9-keypair.pem' are too open`,
you'll need to `chmod` your .pem file as follows:

```bash
chmod 400 eks-c9-keypair.pem
```

After SSH'ing into the worker node, run:

```bash
sudo yum install -y amazon-efs-utils
```

Type `exit` to exit the EC2 instance. Install the EFS utils on all your EKS worker nodes. If you are following the 
instructions here you should have 2 nodes.

### Step 3: Copy kubeconfig and AWS config & credentials files

Now SSH into the EC2 bastion instance created in Step 1: 

```bash
ssh ec2-52-206-72-54.compute-1.amazonaws.com -i eks-c9-keypair.pem
```

Copy the aws config & credentials files:

```bash
mkdir -p /home/ec2-user/.aws
cd /home/ec2-user/.aws
mv /home/ec2-user/config .
mv /home/ec2-user/credentials .
```

Check that the AWS CLI works:

```bash
aws s3 ls
```

You may or may not see S3 buckets, but you shouldn't receive an error.

Copy the kube config file:

```bash
mkdir -p /home/ec2-user/.kube
cd /home/ec2-user/.kube
mv /home/ec2-user/kubeconfig.eks-fabric.yaml  ./config
```

To check that this works execute:

```bash
kubectl get nodes
```

You should see the nodes belonging to your new K8s cluster. You may see more nodes, depending on the size of the Kubernetes
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
On the EC2 instance created in Step 2 above, in the newly cloned hyperledger-on-kubernetes directory, update the following
scripts so that the EFSSERVER variable contains the full URL of the EFS server created in Step 1:
 
* fabric-main/gen-fabric.sh
* workshop-remote-peer/gen-workshop-remote-peer.sh

You can find the full EFS server URL in the AWS EFS console. The URL should look something like this: 
`EFSSERVER=fs-12a33ebb.efs.us-west-2.amazonaws.com`

In each script, look for the line starting with `EFSSERVER=`, and replace the URL with the one you copied from the EFS console. Using
vi you can simply move the cursor over the first character after `EFSSERVER=` and hit the 'x' key until the existing
URL is deleted. Then hit the 'i' key and ctrl-v to paste the new URL. Hit escape, then shift-zz to save and exit vi. 
See, you're a vi expert already.

```bash
cd
cd hyperledger-on-kubernetes
vi fabric-main/gen-fabric.sh
```

Make the same update in the other file:

```bash
cd
cd hyperledger-on-kubernetes
vi workshop-remote-peer/gen-workshop-remote-peer.sh
```

The EKS cluster, EFS and the EC2 bastion are now ready for you to deploy Hyperledger Fabric. Navigate back to the section you are following:

* [Part 1:](../fabric-main/README.md) Create the main Fabric orderer network
* [Part 2:](../remote-peer/README.md) Add a remote peer, running in a different AWS account/region, sharing the certificate authority (CA) of the main Fabric orderer network
* [Part 3:](../remote-org/README.md) Add a new organisation, with its own CA, and its own peers running in a different AWS account/region
* [Part 4:](../workshop-remote-peer/README.md) Run the Fabric workshop, where participants add their own remote peers, running in their own AWS accounts

# Cleanup

Cleanup your Hyperledger Fabric nodes. There are 'stop' scripts in each of the Parts. For example, Part1 - `fabric-main` 
- has a script called `stop-fabric.sh`, which will bring down all the Fabric pods. The key components to delete
are the Kubernetes Services, especially those that create ELBs or NLBs.

Delete the ec2-cmd-client CloudFormation stack, to remove your EFS and bastion EC2 instance.

Don't forget to remove your EKS cluster. Instructions can be found here:

* eksctl: eksctl delete cluster —name=eks-fabric
* EKS: https://docs.aws.amazon.com/eks/latest/userguide/delete-cluster.html
* Kops: https://github.com/kubernetes/kops/blob/master/docs/cli/kops_delete_cluster.md

If eksctl cannot delete your EKS cluster, do the following:

* Delete the CloudFormation stack: eksctl-eks-fabric-cluster and eksctl-eks-fabric-nodegroup-0 (or similar names, 
depending on how you named your eks cluster)
* Delete the EC2 keypair you created. It will be in the EC2 console, under Key Pairs
* In the EKS console, delete the EKS cluster. This will delete the control plane (master nodes, etc.)

Finally, delete the CloudFormation stack for your Cloud9 intance. Also, in the Cloud9 console, delete the instance.

If the CloudFormation stack that deletes the eksctl-eks-fabric-cluster and eksctl-eks-fabric-nodegroup-0 fails, it might be related to network interfaces still 
present in the VPC. This could be caused by target groups belonging to an ALB, possibly created by a Kubernetes Service.
You can either delete the Kubernetes Service, or remove the ALB's and Target Groups in the AWS EC2 console.

# Appendix
## Manual steps to create EKS cluster

Step 1 of this README provides a bash script `eks/create-eks.sh`, which you use to create your EKS cluster, and provision
your EFS drive and EC2 bastion. If there are problems with the script, or if you wish to do these steps manually, they are listed
here.

In your Cloud9 terminal:

1. Download the `kubectl` and `heptio-authenticator-aws` binaries and save to `~/bin`. Check the Amazon EKS User Guide 
for [Getting Started](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html) for further information.

```
mkdir ~/bin
wget https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl ~/bin/
wget https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/heptio-authenticator-aws && chmod +x heptio-authenticator-aws && mv heptio-authenticator-aws ~/bin/
```

2. Download `eksctl` from `eksctl.io`(actually it will download from GitHub)

```
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

3. run `eksctl help`, you should be able to see the `help` messages

4. Create a keypair

You will need a keypair in the same region as you create the EKS cluster. We default this to us-west-2, so create a
keypair in us-west-2 and make sure you download the keypair to your Cloud9 environment. You can create the keypair in
any region that supports EKS - just replace the `--region` flag in the `eksctl` statement below.

Before creating the keypair from the command line, check that your AWS CLI is pointing to the right account and region. You
would have configured this in Step 6 with `aws configure`, where you entered an AWS key (which belongs to your AWS account), and a region.

See [Using Key Pairs](https://docs.aws.amazon.com/cli/latest/userguide/cli-ec2-keypairs.html) in the AWS documentation
for details on how to use the command line to create and download a keypair.

Your statement to create the keypair should look something like this:

```bash
aws ec2 create-key-pair --key-name eks-c9-keypair --query 'KeyMaterial' --output text > eks-c9-keypair.pem
chmod 400 eks-c9-keypair.pem
```

Make sure you follow the instructions to `chmod 400` your key.

5. Create the EKS cluster. 

If you are creating the cluster in us-east-1, you should pass in a list of availability zones:

```bash
eksctl create cluster --ssh-public-key <YOUR AWS KEYPAIR> --name eks-fabric --region us-east-1 --kubeconfig=./kubeconfig.eks-fabric.yaml --zones=us-east-1a,us-east-1b,us-east-1d
```

This prevents the issue below. I have only seen this issue when creating an EKS cluster in us-east-1.

```bash
2018-08-14T02:44:28Z [✖]  unable to create cluster control plane: UnsupportedAvailabilityZoneException: Cannot create cluster 'eks-fabric' because us-east-1e, the targeted availability zone, does not currently have sufficient capacity to support the cluster. Retry and choose from these availability zones: us-east-1a, us-east-1b, us-east-1d
        status code: 400, request id: f69224d4-9f6b-11e8-a5af-3d2857a10e45
```

Otherwise, if creating your EKS cluster in us-west-2 you can use this statement:

```bash
eksctl create cluster --ssh-public-key <YOUR AWS KEYPAIR> --name eks-fabric --region us-west-2 --kubeconfig=./kubeconfig.eks-fabric.yaml
```

Note that `ssh-public-key` is the name of your keypair (i.e. the value you passed to `aws ec2 create-key-pair --key-name <KEYNAME>`), 
not the path to the .pem file you saved.

Now go an get a cup of coffee. It will take around 10-25 minutes to create the EKS cluster. 

Once the cluster creation is complete, you should see something like this.

```bash
$ eksctl create cluster --ssh-public-key eks-c9-keypair --name eks-fabric --region us-west-2 --kubeconfig=./kubeconfig.eks-fabric.yaml
2018-08-12T03:47:45Z [ℹ]  setting availability zones to [us-west-2b us-west-2a us-west-2c]
2018-08-12T03:47:45Z [ℹ]  SSH public key file "eks-c9-keypair" does not exist; will assume existing EC2 key pair
2018-08-12T03:47:45Z [ℹ]  found EC2 key pair "eks-c9-keypair"
2018-08-12T03:47:45Z [ℹ]  creating EKS cluster "eks-fabric" in "us-west-2" region
2018-08-12T03:47:45Z [ℹ]  creating ServiceRole stack "EKS-eks-fabric-ServiceRole"
2018-08-12T03:47:45Z [ℹ]  creating VPC stack "EKS-eks-fabric-VPC"
2018-08-12T03:48:26Z [✔]  created ServiceRole stack "EKS-eks-fabric-ServiceRole"
2018-08-12T03:49:06Z [✔]  created VPC stack "EKS-eks-fabric-VPC"
2018-08-12T03:49:06Z [ℹ]  creating control plane "eks-fabric"
2018-08-12T03:58:27Z [✔]  created control plane "eks-fabric"
2018-08-12T03:58:27Z [ℹ]  creating DefaultNodeGroup stack "EKS-eks-fabric-DefaultNodeGroup"
2018-08-12T04:02:08Z [✔]  created DefaultNodeGroup stack "EKS-eks-fabric-DefaultNodeGroup"
2018-08-12T04:02:08Z [✔]  all EKS cluster "eks-fabric" resources has been created
2018-08-12T04:02:08Z [✔]  saved kubeconfig as "./kubeconfig.eks-fabric.yaml"
2018-08-12T04:02:13Z [ℹ]  the cluster has 0 nodes
2018-08-12T04:02:13Z [ℹ]  waiting for at least 2 nodes to become ready
2018-08-12T04:02:44Z [ℹ]  the cluster has 2 nodes
2018-08-12T04:02:44Z [ℹ]  node "ip-192-168-171-30.us-west-2.compute.internal" is ready
2018-08-12T04:02:44Z [ℹ]  node "ip-192-168-214-46.us-west-2.compute.internal" is ready
2018-08-12T04:02:45Z [ℹ]  kubectl command should work with "./kubeconfig.eks-fabric.yaml", try 'kubectl --kubeconfig=./kubeconfig.eks-fabric.yaml get nodes'
2018-08-12T04:02:45Z [✔]  EKS cluster "eks-fabric" in "us-west-2" region is ready
```

6. Check whether `kubectl` can access your Kubernetes cluster:

```bash
$ kubectl --kubeconfig=./kubeconfig.eks-fabric.yaml get nodes
NAME                                           STATUS    ROLES     AGE       VERSION
ip-192-168-171-30.us-west-2.compute.internal   Ready     <none>    5m        v1.10.3
ip-192-168-214-46.us-west-2.compute.internal   Ready     <none>    5m        v1.10.3
```

EKS is now ready, but you'll need to complete all the steps below before you can use EKS to deploy Hyperledger Fabric. 

7. Create an EC2 instance and EFS drive

You're going to interact with Fabric and the Kubernetes cluster from a bastion host that mounts an EFS drive. EFS is 
required to store the crypto material used by Fabric, and you'll need to copy the appropriate certs/keys to/from the EFS drive.
The EFS volume must be accessible from both the EC2 bastion and the worker nodes in the Kubernetes cluster. 

Follow the steps below, which will create the EFS and make it available to the K8s cluster.

On your laptop or Cloud9 instance, clone this repo into any directory you choose. After Step 2 you can delete the repo again. You only need 
it for creating the EC2 bastion and the EFS drive:

```bash
git clone https://github.com/aws-samples/hyperledger-on-kubernetes
cd hyperledger-on-kubernetes
```

For the next step you'll need the VPC ID and Subnets of your EKS cluster. You can obtain these from the AWS VPC console
(look for the VPC with a name based on the name of your EKS cluster), or by running the AWS CLI command below, 
replacing the EKS stack name with your own. There should be three subnets

```bash
aws cloudformation describe-stacks --stack-name eksctl-eks-fabric-cluster --query 'Stacks[0].Outputs' --output json  --region us-east-1         
```

In the repo directory:

```bash
vi efs/deploy-ec2.sh
```

In the repo directory, check the parameters in `efs/deploy-ec2.sh` and update them as follows:
* The VPC and Subnet should be those of your existing K8s cluster worker nodes, which you obtained above. There is no
need to map subnetA in 'efs/deploy-ec2.sh' specifically to subnet-A in AWS, as long as you map all three subnets. I.e.
if you map subnetB to the real subnetC it won't cause any issues. Map the subnets that contain your EKS worker nodes - this 
could be the public subnet or private subnet, depending on the options you used to create your EKS cluster.
* Keyname is the AWS EC2 keypair you used for your EKS cluster. It is NOT the name of the .pem file you saved locally.
You'll use the same keypair to access the EC2 bastion created by deploy-ec2.sh
* VolumeName is the name assigned to your EFS volume. There is no need to change this
* Region should match the region where your K8s cluster is deployed
* If your AWS CLI already points to the account & region your Kubernetes cluster was created, you can go ahead and run the 
command below. If you are using AWS CLI profiles, add a --profile argument to the `aws cloudformation deploy` statement
in efs/deploy-ec2.sh

Once all the parameters are set, in a terminal window, run 

```bash
./efs/deploy-ec2.sh 
```

8. Prepare the EC2 instance for use

The EC2 instance you created in Step 2 should already have kubectl and the AWS CLI installed. However, kubectl will have no
context and will not be pointing to a kubernetes cluster, and AWS CLI will have no credentials. We need to point kubectl to 
the K8s cluster we created in Step 1, and we need to provide credentials for AWS CLI.

To provide AWS CLI credentials, we'll copy them either from our Mac or Cloud9 - i.e. whichever we used to create the EKS cluster.

We'll do the same for the kube config file, i.e. copy the contents of the kube config file from 
your Mac or Cloud9 instance. If you followed the default steps in Step 1, you will have a kube config file called
./kubeconfig.eks-fabric.yaml, in the same directory you were in when you created the EKS cluster. We want to copy this
file to the EC2 bastion instance.

WARNING: I use 'scp' as I had a problem with copy/paste on Cloud9. The files we are copying contain keys; these long strings are wrapped
across multiple lines. In Cloud9, when I pasted the file contents, LF characters were added to the wrapped strings, turning
them into separate strings per line. To fix this I resorted to using 'scp' to copy the files, rather than copy/paste. Copy/paste
worked fine when copying the files from the Mac.

You should be on your Mac or your Cloud9 instance when executing the scp commands below. Navigate to the directory you were 
in when you created the EKS cluster.

To copy the kubeconfig generated by eksctl, use scp, passing in the .pem file of the keypair you created in Step 1. Replace
the DNS name below with the DNS of the EC2 instance you created in Step 2.

```bash
cd
cd environment
scp -i eks-c9-keypair.pem  ./kubeconfig.eks-fabric.yaml  ec2-user@ec2-52-206-72-54.compute-1.amazonaws.com:/home/ec2-user/kubeconfig.eks-fabric.yaml                                                                       
```

Do the same for your AWS config files:

```bash
scp -i eks-c9-keypair.pem  ~/.aws/config  ec2-user@ec2-52-206-72-54.compute-1.amazonaws.com:/home/ec2-user/config                                                                     
scp -i eks-c9-keypair.pem  ~/.aws/credentials  ec2-user@ec2-52-206-72-54.compute-1.amazonaws.com:/home/ec2-user/credentials                                                                     
```

If you performed these steps manually, you can continue from Step 2 in this README.