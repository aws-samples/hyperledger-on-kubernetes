RESTful API to manage the Fabric network

The RESTful API is a Node.js application that uses the Fabric SDK to interact with the Fabric network

The app accesses the Fabric network based on the information provided in the connection-profile folder.

Connection profile points to a CA (an ICA in our case), which is exposed via an NLB. To start these, run these commands:

```bash
cd
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-ica-notls-org1.yaml 
kubectl apply -f k8s/fabric-nlb-ca-org1.yaml
```
