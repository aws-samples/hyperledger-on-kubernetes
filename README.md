# Hyperledger Fabric on Kubernetes

This repo helps you to build a Hyperledger Fabric network on Kubernetes - either AWS EKS or standard Kubernetes installed on
AWS using Kops or some other tool.

The repo consists of different parts. You should navigate to the part that contains the task you want to implement and 
follow the steps in the README in that section. Part 1 is a pre-requisite for all other parts, i.e. you will need the
main Fabric orderer to be running before you start Parts 2, 3 or 4. You can run any combination of Parts 2, 3 and 4 - they
do not depend on each other, so you are free to run all of them, none of them, or any combination of them.

* [Part 1:](fabric-main/README.md) Create the main Fabric orderer network
* [Part 2:](remote-peer/README.md) Add a remote peer, running in a different AWS account/region, sharing the certificate authority (CA) of the main Fabric orderer network
* [Part 3:](remote-org/README.md) Add a new organisation, with its own CA, and its own peers running in a different AWS account/region
* [Part 4:](workshop-remote-peer/README.md) Run the Fabric workshop, where participants add their own remote peers, running in their own AWS accounts
