# TODO

* Improve the section on creating the Kubernetes cluster, especially the section on how to use the Heptio authenticator
and configure this for use on the bastion host

# Hyperledger Fabric on Kubernetes

## Facilitator pre-requisites
* In your own AWS account, you should be running a Kubernetes cluster with a Fabric network. You can start this network
by running ./start-fabric.sh. See the main README for details
* Before running ./start-fabric.sh, its advisable to edit ./start-fabric.sh and comment out the line 'startTest $HOME $REPO'.
This will run test cases. We want to run our own test case, which also installs the Marbles chaincode used by the workshop
* After ./start-fabric.sh completes and your Fabric network is running, install the chaincode and execute the test cases, and
copy the crypto material to S3. Here are the steps to do this: 
    * The Marbles chaincode used in the workshop is the version provided with the marbles app: https://github.com/IBM-Blockchain/marbles. Not the 
    version provided by fabric-samples (https://github.com/hyperledger/fabric-samples/blob/release-1.2/chaincode/marbles02/go/marbles_chaincode.go).
    To deploy this on the main Fabric cluster in the facilitators account, run the script `./start-workshop-marbles.sh`. This
    will instantiate the correct version of the marbles chaincode on the channel and run a short test against it.
    * Check the logs using 'kubectl logs <etc>' to confirm that the chaincode was installed, instantiated, and correctly invoked.
    * The script `./start-workshop-marbles.sh` will also copy all the keys and certs from the Fabric network you have just created
    and store these in S3. This will allow them to be downloaded by the workshop participants who are going to connect to your network. 
    Note that this will only work if you have the AWS CLI configured on your EC2 bastion (which you would have if you are using EKS).
    If this script indicates it's unable to copy the 'tar', you can do it manually following the steps in `./start-workshop-marbles.sh`
* Orderer connection URL must be obtained and made available to all participants
