# Hyperledger Fabric on Kubernetes Workshop

## Facilitator pre-requisites
* In your own AWS account, you should be running a Kubernetes cluster with a Fabric network. You can start this network
by following the steps here: [Part 1:](../fabric-main/README.md) 
* After completing Part 1 your Fabric network should be running and the Marbles chaincode should have been installed,
instantiated and tested. Now you'll need to copy the crypto material to S3. Here are the steps to do this: 
    * SSH into your EC2 bastion
    * In the repo directory, in the workshop-remote-peer sub-directory, edit the script `./facilitator/copy-crypto-to-S3.sh` 
    and update the following variables:
        * region - the region where you have installed EKS
        * S3BucketName - a unique bucket name that will be created in your account, with public access to the crypto material
    * The script `./facilitator/copy-crypto-to-S3.sh` will copy all the keys and certs from the Fabric network you created in Part 1
    and store these in S3. This will allow them to be downloaded by the workshop participants who are going to connect to your network. 
    Note that this will only work if you have the AWS CLI configured on your EC2 bastion (which you would have if you are using EKS).
    If this script indicates it's unable to copy the 'tar', you can do it manually following the steps in `./facilitator/copy-crypto-to-S3.sh`
* The Orderer connection URL must be obtained and made available to all participants. I suggest you get the Orderer endpoint,
as exposed by NLB, and then update the README.md in this directory (the README used by the workshop participants) so that
each place the orderer endpoint is used it points to the correct DNS. You can use `kubectl get svc -n org0` to obtain the
orderer endpoint, and `kubectl describe` to see the details of a specific service.
