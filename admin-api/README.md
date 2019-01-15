RESTful API to manage the Fabric network

The RESTful API is a Node.js application that uses the Fabric SDK to interact with the Fabric network

# Pre-requisites

## Step 1 - Install Node
On the Fabric client node.

Install Node.js. We will use v8.x.

```
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
```

```
. ~/.nvm/nvm.sh
nvm install lts/carbon
nvm use lts/carbon
```

Amazon Linux seems to be missing g++, so:

```
sudo yum install gcc-c++ -y
```

## Step 2 - Install dependencies
On the Fabric client node.

```
cd ~/non-profit-blockchain/ngo-rest-api
npm install
```


The app accesses the Fabric network based on the information provided in the connection-profile folder.

Connection profile points to a CA (an ICA in our case), which is exposed via an NLB. To start these, run these commands:

```bash
cd
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-ica-notls-org1.yaml 
kubectl apply -f k8s/fabric-nlb-ca-org1.yaml
```

## Register a user

export ENDPOINT=localhost
export PORT=3000
echo connecting to server: $ENDPOINT:$PORT
echo
echo '---------------------------------------'
echo Registering a user
echo '---------------------------------------'
echo 'Register User'
USERID=$(uuidgen)
echo
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/users -H 'content-type: application/x-www-form-urlencoded' -d "username=${USERID}&orgName=Org1")
echo $response
response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/init -H 'content-type: application/x-www-form-urlencoded')
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/listNetwork -H 'content-type: application/x-www-form-urlencoded')
echo $response
