RESTful API to manage the Fabric network

The RESTful API is a Node.js application that uses the Fabric SDK to interact with the Fabric network

## Debugging
To turn on debugging, enter this on the command line before starting the node app:

export HFC_LOGGING='{"debug":"console","info":"console"}'


# Pre-requisites
We need the Fabric binaries so we can run commands such as configtxgen.

```bash
cd ~
mkdir fabric-bin
cd fabric-bin/
curl -sSL http://bit.ly/2ysbOFE | bash -s 1.4.0
mv ~/fabric-bin/fabric-samples/bin/* ~/fabric-bin
rm -rf ~/fabric-bin/fabric-samples
```

Edit the file `~/.bash_profile`, and add this line towards the end, just before the export $PATH:

```bash
PATH=$PATH:$HOME/fabric-bin
export PATH
```

Source the file, and check that you can execute the Fabric binaries:

```bash
source ~/.bash_profile 
peer
```

Change the ownership of the configtx.yaml file, as we will edit it using this app:

```bash
sudo chown ec2-user /opt/share/rca-data/configtx.yaml
```

Run the Fabric CLI pod:

```bash
cd ~
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-cli-org0.yaml     
```
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
cd ~
cd hyperledger-on-kubernetes
kubectl apply -f k8s/fabric-deployment-ica-notls-org1.yaml 
kubectl apply -f k8s/fabric-nlb-ca-org1.yaml
```

## Testing

cp /opt/share/rca-data/configtx-orig.yaml /opt/share/rca-data/configtx.yaml

export HFC_LOGGING='{"debug":"console","info":"console"}'

nvm use lts/carbon

node app.js &

export ENDPOINT=localhost
export PORT=3000
echo connecting to server: $ENDPOINT:$PORT
response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/init)
echo $response

USERID=michael
echo
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/users -H 'content-type: application/x-www-form-urlencoded' -d '{"username":"'"${USERID}"'","org":"org1"}')
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx)
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx/orgs)  
echo $response

response=$(curl -s -X GET http://${ENDPOINT}:${PORT}/configtx/profiles)  
echo $response

// This should fail as the certificates do not exist for the new org
PROFILENAME=org3profile;
CHANNELNAME=org3channel;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/channelconfigs -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","channelname":"'"${CHANNELNAME}"'"}')
echo $response

// add the new org
ORG=org3;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/orgs -H 'content-type: application/json' -d '{"org":"'"${ORG}"'"}')
echo $response

// add the new profile
PROFILENAME=org3profile;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/profiles -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","orgs":["org1","org3"]}')
echo $response

// create the channel configuration transaction file
PROFILENAME=org3profile;
CHANNELNAME=org3channel;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/configtx/channelconfigs -H 'content-type: application/json' -d '{"profilename":"'"${PROFILENAME}"'","channelname":"'"${CHANNELNAME}"'"}')
echo $response

// create the channel
CHANNELNAME=org3channel;
response=$(curl -s -X POST http://${ENDPOINT}:${PORT}/channels -H 'content-type: application/json' -d '{"channelname":"'"${CHANNELNAME}"'"}')
echo $response

