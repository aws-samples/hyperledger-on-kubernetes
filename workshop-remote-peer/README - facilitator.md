# Hyperledger Fabric on Kubernetes Workshop

## Facilitator pre-requisites
* In your own AWS account, you should be running a Kubernetes cluster with a Fabric network. You can start this network
by following the steps here: [Part 1:](../fabric-main/README.md) 
* After completing Part 1 your Fabric network should be running and the Marbles chaincode should have been installed,
instantiated and tested. Now you'll need to copy the crypto material to S3. Here are the steps to do this: 
    * SSH into the EC2 bastion you created in Part 1
    * In the repo directory, in the workshop-remote-peer sub-directory, edit the script `./facilitator/copy-crypto-to-S3.sh` 
    and update the following variables:
    
        ```bash
        cd
        cd hyperledger-on-kubernetes/
        vi workshop-remote-peer/facilitator/copy-crypto-to-S3.sh
        ```
        * region - the region where you have installed EKS
        * S3BucketName - a unique bucket name. The bucket will be created in your account, with public access to the crypto material. The
        script should still run successfully if the bucket already exists in your account.
        
        ```bash
        ./workshop-remote-peer/facilitator/copy-crypto-to-S3.sh
        ```
        
    * The script `./facilitator/copy-crypto-to-S3.sh` will copy all the keys and certs from the Fabric network you created in Part 1
    and store these in S3. This will allow them to be downloaded by the workshop participants who are going to connect to your network. 
    Note that this will only work if you have the AWS CLI configured on your EC2 bastion (which you would have if you are using EKS).
    If this script indicates it's unable to copy the 'tar', you can do it manually following the steps in `./facilitator/copy-crypto-to-S3.sh`
* The Orderer connection URL must be obtained and made available to all participants. There is an issue here to be aware of:
there are multiple orderers and you must select the correct orderer endpoint - i.e. orderer3. 

orderer1: local endpoint for peers running in the same Kubernetes cluster
orderer2: remote endpoint with TLS enabled, for remote peers
orderer3: remote endpoint with TLS disabled, for workshop peers

I suggest you get the Orderer endpoint for orderer3, as exposed by NLB, and then update the README.md in this directory 
(the README in workshop-remote-peer used by the workshop participants) so that
each place the orderer endpoint is used it points to the correct DNS. You can use `kubectl get svc -n org0` to obtain the
orderer endpoint, and `kubectl describe` to see the details of a specific service.

```bash
kubectl get svc -n org0
kubectl describe svc orderer3-org0-nlb -n org0
```

## Fabric CA Issues
If you see the following error, make sure the Fabric CA name specified in the connection profile is equal to the name
of the FABRIC_CA_SERVER_CA_NAME ENV variable in the K8s deployment yaml. This could be set to ica-notls-%ORG%.%DOMAIN% or
ica-%ORG%.%DOMAIN% (this will be ica-notls-org1.org1 once updated).

In this example, I am calling Fabric CA from the REST API using the details provided in the connection profile. The
NLB is connecting to the Fabric CA that is NOT running TLS, and the name of this CA is different (ica-notls-org1.org1).

```bash
$ curl -s -X POST http://localhost:3000/users -H "content-type: application/x-www-form-urlencoded" -d 'username=michael&orgName=Org1'                                                                                         
{"success":false,"message":"failed Error: Enrollment failed with errors [[{\"code\":19,\"message\":\"CA 'ica-org1.org1' does not exist\"}]]"}
```

One way to find the CA Name is to cURL the endpoint:

```bash
$ curl http://aac6dcc94449b11e9970d0a8c01b4fef-45111686d8f2dc4f.elb.us-east-1.amazonaws.com:7054/api/v1/cainfo
{"result":{"CAName":"ica-notls-org1.org1","CAChain":"LS0tLS1CRUdJTiBDRVJUSUZJt...VktLS0tLQo=","Version":"1.4.0-rc1"}
,"errors":[],"messages":[],"success":true}[ec2-user@ip-192-168-43-124 ~]$ 
```