# Creating an EKS cluster

You have a number of options when creating the Kubernetes cluster in which you'll deploy Hyperledger Fabric:
 
* The easiest option is to use eksctl to create an AWS EKS (Elastic Container Service for Kubernetes) cluster. Note that
eksctl creates an EKS cluster with worker nodes in public subnets. For production use you'll probably want your worker 
nodes in private subnets, so use the method below to create a production-ready EKS cluster.
* You can create an EKS cluster following the instructions in the AWS documentation at: https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html
* You can use KOPS to create a cluster: https://github.com/kubernetes/kops
* Or you can use an existing Kubernetes cluster, as long as you can SSH into the worker nodes

Whichever method you choose, you will need SSH access to the Kubernetes worker nodes in order to install EFS utils. 
EFS utils is used to mount the EFS (Elastic File System) used to store the Hyperledger Fabric CA certs/keys. 
Instructions on how to do this are in the section 'Install EFS utils on each Kubernetes worker node' below.

This README will focus on creating an EKS cluster using eksctl. 

## Creating an EKS cluster using Cloud9 and eksctl

`eksctl` is a CLI for Amazon EKS that helps you easily create an Amazon EKS cluster!

eksctl website:  https://eksctl.io/

Follow the steps below to create your EKS cluster.

## Steps

1. Spin up a [Cloud9 IDE](https://us-west-2.console.aws.amazon.com/cloud9/home?region=us-west-2) from the AWS console.
In the Cloud9 console, click 'Create Environment'
2. Provide a name for your environment, e.g. eks-c9, and click **Next Step**
3. Leave everything as default and click **Next Step**
4. Click **Create environment**. It would typically take 30-60s to create your Cloud9 IDE
5. We need to turn off the Cloud9 temporarily provided IAM credentials. 

![toggle-credentials](../images/toggle-credentials.png "Toggle Credentials")

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

![sts](../images/sts.png "STS")

7. Download the `kubectl` and `heptio-authenticator-aws` binaries and save to `~/bin`. Check the Amazon EKS User Guide 
for [Getting Started](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html) for further information.

```
mkdir ~/bin
wget https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl ~/bin/
wget https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/heptio-authenticator-aws && chmod +x heptio-authenticator-aws && mv heptio-authenticator-aws ~/bin/
```

9. Download `eksctl` from `eksctl.io`(actually it will download from GitHub)

```
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

10. run `eksctl help`, you should be able to see the `help` messages

11. Create a keypair

You will need a keypair in the same region as you create the EKS cluster. We default this to us-west-2, so create a
keypair in us-west-2 and make sure you download the keypair to your Cloud9 environment. You can create the keypair in
any region that supports EKS - just replace the `--region` flag in the `eksctl` statement below.

Before creating the keypair from the command line, check that your AWS CLI is pointing to the right account and region. You
would have configured this in Step 6 with `aws configure`, where you entered an AWS key (which belongs to your AWS account), and a region.

See [Using Key Pairs](https://docs.aws.amazon.com/cli/latest/userguide/cli-ec2-keypairs.html) in the AWS documentation
for details on how to use the command line to create and download a keypair.

Make sure you following the instructions to `chmod 400` your key.

12. Create the EKS cluster. 

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

13. Check whether `kubectl` can access your Kubernetes cluster:

```bash
$ kubectl --kubeconfig=./kubeconfig.eks-fabric.yaml get nodes
NAME                                           STATUS    ROLES     AGE       VERSION
ip-192-168-171-30.us-west-2.compute.internal   Ready     <none>    5m        v1.10.3
ip-192-168-214-46.us-west-2.compute.internal   Ready     <none>    5m        v1.10.3
```

Once the cluster is created, follow the instructions in the section 'Install EFS utils on each Kubernetes worker node' below.


Now your Amazon EKS cluster is ready! 

If you need to delete this clusrer, run `eksctl delete cluster —name=<CLUSTER_NAME>` to trigger the deletion of the stack.

14. Install EFS utils on each Kubernetes worker node 

EFS utils is required on each Kubernetes worker node to enable the worker to mount the EFS used to store the Hyperledger 
Fabric CA certs/keys.

The EC2 instances should be easy to identify in the AWS console as the instance name is prefixed with your EKS cluster name, e.g.
`eks-fabric-default-Node`. Clicking on each instance will show you the security group and the public DNS, which you'll need
when you SSH into the instance.

Before we can SSH into the Kubernetes worker nodes, we need to update the security group to allow SSH ingress.

You can do this from the console following the instructions here: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/authorizing-access-to-an-instance.html#add-rule-authorize-access
If you'll SSH from your Mac, you can update the security group to allow SSH from your IP only. If you'll SSH from Cloud9,
the quickest way is to allow SSH to all. (if someone has a more secure idea, please let me know).

Now SSH into each worker node and install the EFS utils, using the keypair you created earlier, as follows. Note that this
references the .pem file, which you would have downloaded and stored on Cloud9 in Step 11:

```bash
ssh ec2-user@ec2-54-244-69-254.us-west-2.compute.amazonaws.com -i eks-c9-keypair.pem
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

15. EKS is now ready for use with Hyperledger Fabric. Navigate back to the section you are following:

* [Part 1:](fabric-main/README.md) Create the main Fabric orderer network
* [Part 2:](remote-peer/README.md) Add a remote peer, running in a different AWS account/region, sharing the certificate authority (CA) of the main Fabric orderer network
* [Part 3:](remote-org/README.md) Add a new organisation, with its own CA, and its own peers running in a different AWS account/region
* [Part 4:](workshop-remote-peer/README.md) Run the Fabric workshop, where participants add their own remote peers, running in their own AWS accounts
