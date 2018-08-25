#!/usr/bin/env bash
region=us-west-2

echo Download the `kubectl` and `heptio-authenticator-aws` binaries and save to `~/bin`
mkdir ~/bin
wget https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl ~/bin/
wget https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-06-05/bin/linux/amd64/heptio-authenticator-aws && chmod +x heptio-authenticator-aws && mv heptio-authenticator-aws ~/bin/

echo Download eksctl from eksctl.io
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

echo Create a keypair
cd ~
aws ec2 create-key-pair --key-name eks-c9-keypair --query 'KeyMaterial' --output text > eks-c9-keypair.pem
chmod 400 eks-c9-keypair.pem

echo Create the EKS cluster
cd ~
if [ $region == "us-east-1" ]; then
    eksctl create cluster --ssh-public-key eks-c9-keypair --name eks-fabric --region $region --kubeconfig=./kubeconfig.eks-fabric.yaml --zones=us-east-1a,us-east-1b,us-east-1d
else
    eksctl create cluster --ssh-public-key eks-c9-keypair --name eks-fabric --region $region --kubeconfig=./kubeconfig.eks-fabric.yaml
fi

echo Check whether kubectl can access your Kubernetes cluster
kubectl --kubeconfig=./kubeconfig.eks-fabric.yaml get nodes

echo Create the EC2 bastion instance and the EFS that stores the Fabric cryptographic material
echo These will be created in the same VPC as the EKS cluster

VPCID=$(aws cloudformation describe-stacks --stack-name EKS-eks-fabric-VPC --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text)
echo -e "VPCID: $VPCID"

SUBNETS=$(aws cloudformation describe-stacks --stack-name EKS-eks-fabric-VPC --query 'Stacks[0].Outputs[?OutputKey==`SubnetIds`].OutputValue' --output text)
echo -e "SUBNETS: $SUBNETS"

# Convert SUBNETS to an array
IFS=',' read -r -a SUBNETSARR <<< "$SUBNETS"

echo Update the ../efs/deploy-ec2.sh config file
sed -e "s/{VPCID}/${VPCID}/g" -e "s/{REGION}/${region}/g" -e "s/{SUBNETA}/${SUBNETSARR[0]}/g" -e "s/{SUBNETB}/${SUBNETSARR[1]}/g" -e "s/{SUBNETC}/${SUBNETSARR[2]}/g" -i ../efs/deploy-ec2.sh

echo ../efs/deploy-ec2.sh script has been updated with your parameters
cat ../efs/deploy-ec2.sh

echo Running ../efs/deploy-ec2.sh - this will use CloudFormation to create the EC2 bastion and EFS
./efs/deploy-ec2.sh

# Prepare the EC2 bastion for use by copying the kubeconfig and aws config & credentials files from Cloud9
cd ~
scp -i eks-c9-keypair.pem  ~/kubeconfig.eks-fabric.yaml  ec2-user@ec2-52-206-72-54.compute-1.amazonaws.com:/home/ec2-user/kubeconfig.eks-fabric.yaml
scp -i eks-c9-keypair.pem  ~/.aws/config  ec2-user@ec2-52-206-72-54.compute-1.amazonaws.com:/home/ec2-user/config
scp -i eks-c9-keypair.pem  ~/.aws/credentials  ec2-user@ec2-52-206-72-54.compute-1.amazonaws.com:/home/ec2-user/credentials
