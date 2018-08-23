# Troubleshooting

## Temp commands to use during troubleshooting

switching to user
=================
export USER_NAME=user-org1
export USER_PASS=${USER_NAME}pw
export FABRIC_CA_CLIENT_HOME=/etc/hyperledger/fabric/orgs/org1/user
export CORE_PEER_MSPCONFIGPATH=$FABRIC_CA_CLIENT_HOME/msp
export FABRIC_CA_CLIENT_TLS_CERTFILES=/data/org1-ca-chain.pem
fabric-ca-client enroll -d -u https://$USER_NAME:$USER_PASS@ica-org1.org1:7054
   
   
kubectl delete -f k8s/fabric-deployment-peer1-org1.yaml
kubectl apply -f k8s/fabric-deployment-peer1-org1.yaml
kubectl delete -f k8s/fabric-deployment-peer-join-channel-org1.yaml
kubectl apply -f k8s/fabric-deployment-peer-join-channel-org1.yaml   
kubectl get deploy -n org1
kubectl logs deploy/join-channel -n org1
kubectl logs deploy/peer1-org1 -n org1 -c peer1-org1


cd hyperledger-on-kubernetes/
git pull
cd ..
sudo cp hyperledger-on-kubernetes/scripts/* /opt/share/rca-scripts/
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-setup-addorg-fabric-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-setup-addorg-fabric-org1.yaml
sleep 10
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-sign-addorg-fabric-org2.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-sign-addorg-fabric-org2.yaml
kubectl get po -n org2
  
cd /opt/share/hyperledger-on-kubernetes
git pull
cd ..
sudo cp hyperledger-on-kubernetes/scripts/* rca-scripts/


kubectl delete -f hyperledger-on-kubernetes/orderer/fabric-deployment-test-fabric.yaml
sudo cp hyperledger-on-kubernetes/scripts/* rca-scripts/
kubectl apply -f hyperledger-on-kubernetes/orderer/fabric-deployment-test-fabric.yaml
kubectl get po -n org1

export FABRIC_CA_CLIENT_HOME=/data/orgs/org1/admin
export FABRIC_CA_CLIENT_TLS_CERTFILES=/data/org1-ca-chain.pem

export CORE_PEER_TLS_CLIENTCERT_FILE=/data/tls/peer1-org1-client.crt
export CORE_PEER_TLS_CLIENTKEY_FILE=/data/tls/peer1-org1-client.key
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_CLIENTAUTHREQUIRED=true
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=/data/org1-ca-chain.pem
export CORE_PEER_TLS_ROOTCERT_FILE=/data/org1-ca-chain.pem
export CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
export CORE_PEER_ID=peer1-org1
export CORE_PEER_ADDRESS=peer1-org1.org1:7051
export CORE_PEER_LOCALMSPID=org1MSP

export CORE_PEER_TLS_CLIENTCERT_FILE=/data/tls/peer2-org1-client.crt
export CORE_PEER_TLS_CLIENTKEY_FILE=/data/tls/peer2-org1-client.key
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_CLIENTAUTHREQUIRED=true
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=/data/org1-ca-chain.pem
export CORE_PEER_TLS_ROOTCERT_FILE=/data/org1-ca-chain.pem
export CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
export CORE_PEER_ID=peer2-org1
export CORE_PEER_ADDRESS=peer2-org1.org1:7051
export CORE_PEER_LOCALMSPID=org1MSP

export CORE_PEER_TLS_CLIENTCERT_FILE=/data/tls/michaelpeer1-org1-client.crt
export CORE_PEER_TLS_CLIENTKEY_FILE=/data/tls/michaelpeer1-org1-client.key
export CORE_PEER_TLS_ENABLED=false
export CORE_PEER_TLS_CLIENTAUTHREQUIRED=false
export CORE_PEER_TLS_CLIENTROOTCAS_FILES=/data/org1-ca-chain.pem
export CORE_PEER_TLS_ROOTCERT_FILE=/data/org1-ca-chain.pem
export CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
export CORE_PEER_ID=michaelpeer1-org1
export CORE_PEER_ADDRESS=michaelpeer1-org1.org1:7051
export CORE_PEER_LOCALMSPID=org1MSP
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org1/admin/msp
export CORE_LOGGING_GRPC=DEBUG

Set context to user:
export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/msp

Set context to admin:
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org1/admin/msp
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org2/admin/msp
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org3/admin/msp

export CORE_PEER_ENDORSER_ENABLED=true
export CORE_CHAINCODE_STARTUPTIMEOUT=20

************
CANNOT GET THE INSANTIATE to work. Inside the test-fabric container, execute the exports above, then the instantiate below
Seems to work if I'm in the PEER container.
*********************

Org1
----
peer channel create --logging-level=DEBUG -c mychannel -f /data/channel.tx -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt
peer chaincode list -C mychannel --installed -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt
peer chaincode instantiate -C mychannel -n mycc -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR('org1MSP.member','org2MSP.member')" -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt
peer channel fetch newest -c mychannel -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt
peer channel fetch config mfile  -c mychannel -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt
peer chaincode invoke -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt -C mychannel -n mycc -c '{"Args":["invoke","a","b","10"]}'

Org2
-----
peer chaincode list -C mychannel --installed -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org2-cli-client.key --certfile /data/tls/peer1-org2-cli-client.crt
peer chaincode list -C mychannel --instantiated -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org2-cli-client.key --certfile /data/tls/peer1-org2-cli-client.crt
peer chaincode instantiate -C mychannel -n mycc -v 1.0 -c '{"Args":["init","a","100","b","200"]}' -P "OR('org1MSP.member','org2MSP.member')" -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org2-cli-client.key --certfile /data/tls/peer1-org2-cli-client.crt
peer chaincode query -C mychannel -n mycc -c '{"Args":["query","a"]}'

peer channel signconfigtx -f /data/org3_config_update_as_envelope.pb
peer channel update -f /data/org3_config_update_as_envelope.pb -c mychannel -o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org2-cli-client.key --certfile /data/tls/peer1-org2-cli-client.crt


## Start the fabric network

cd /opt/share/hyperledger-on-kubernetes
git pull
cd ..
cd /opt/share

mkdir rca-org0
mkdir rca-org1
mkdir rca-org2
mkdir ica-org0
mkdir ica-org1
mkdir ica-org2
mkdir rca-data
mkdir rca-scripts
mkdir orderer

sudo cp hyperledger-on-kubernetes/scripts/* rca-scripts/

kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-org0.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-org2.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-org0.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-org2.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-org0.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-org2.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-org0.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-org2.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-pvc-orderer-org0.yaml
sleep 5
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-org0.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-org2.yaml
#make sure the svc starts, otherwise subsequent commands may fail
sleep 10
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-org0.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-org2.yaml
sleep 10
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-register-identities.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-channel-artifacts.yaml
sleep 20
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-orderer-org0.yaml
sleep 10
kubectl get po -n org0
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer1-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer2-org1.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer1-org2.yaml
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer2-org2.yaml
sleep 30
kubectl get po -n org1
kubectl get po -n org2
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-test-fabric.yaml

## Start the individual steps

cd /opt/share/hyperledger-on-kubernetes
git pull
cd ..
sudo cp hyperledger-on-kubernetes/scripts/* rca-scripts/

kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-create-channel.yaml
sleep 10
kubectl apply -f hyperledger-on-kubernetes/k8s/fabric-deployment-create-channel.yaml
kubectl get po -n org1


## Cleanup
cd /opt/share

kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-test-fabric.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer2-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer1-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer2-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-peer1-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-orderer1-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-register-orderer-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-register-peer-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-register-peer-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-channel-artifacts.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-ica-org2.yaml
sleep 5
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-deployment-rca-org2.yaml
sleep 5
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-scripts-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-data-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-rca-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-org0.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-org1.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-ica-org2.yaml
kubectl delete -f hyperledger-on-kubernetes/k8s/fabric-pvc-orderer-org0.yaml

cd /opt/share

sudo rm -rf rca-org0/*
sudo rm -rf rca-org1/*
sudo rm -rf rca-org2/*
sudo rm -rf ica-org0/*
sudo rm -rf ica-org1/*
sudo rm -rf ica-org2/*
sudo rm -rf rca-data/*
sudo rm -rf rca-scripts/*
sudo rm -rf orderer/*

kubectl get po -n org0

## Issues experienced

### In test-fabric-sh, could not instantiate chaincode:

The peer logs show the following. The reason they show the logs for the Chaincode Docker container (name starting dev-peer1)
is because I set this ENV in the peer deployment.yaml: CORE_VM_DOCKER_ATTACHSTDOUT=true. See below for details.

```bash
2018-04-15 02:49:15.774 UTC [dockercontroller] createContainer -> DEBU 3db Create container: dev-peer1-org2-mycc-1.0
2018-04-15 02:49:15.828 UTC [dockercontroller] createContainer -> DEBU 3dc Created container: dev-peer1-org2-mycc-1.0-c4f6f043734789c3ff39ba10d25a5bf4bb7da6be12264d48747f9a1ab751e9fe
2018-04-15 02:49:15.984 UTC [dockercontroller] Start -> DEBU 3dd Started container dev-peer1-org2-mycc-1.0
2018-04-15 02:49:15.984 UTC [container] unlockContainer -> DEBU 3de container lock deleted(dev-peer1-org2-mycc-1.0)
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3df 2018-04-15 02:49:19.100 UTC [shim] userChaincodeStreamGetter -> ERRO 001 context deadline exceeded
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e0 error trying to connect to local peer
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e1 github.com/hyperledger/fabric/core/chaincode/shim.userChaincodeStreamGetter
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e2 	/opt/gopath/src/github.com/hyperledger/fabric/core/chaincode/shim/chaincode.go:111
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e3 github.com/hyperledger/fabric/core/chaincode/shim.Start
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e4 	/opt/gopath/src/github.com/hyperledger/fabric/core/chaincode/shim/chaincode.go:150
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e5 main.main
2018-04-15 02:49:19.100 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e6 	/chaincode/input/src/github.com/hyperledger/fabric-samples/chaincode/abac/go/abac.go:202
2018-04-15 02:49:19.101 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e7 runtime.main
2018-04-15 02:49:19.101 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e8 	/opt/go/src/runtime/proc.go:195
2018-04-15 02:49:19.101 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3e9 runtime.goexit
2018-04-15 02:49:19.101 UTC [dev-peer1-org2-mycc-1.0] func2 -> INFO 3ea 	/opt/go/src/runtime/asm_amd64.s:2337
2018-04-15 02:49:19.141 UTC [dockercontroller] func2 -> INFO 3eb Container dev-peer1-org2-mycc-1.0 has closed its IO channel
2018-04-15 02:49:19.703 UTC [deliveryClient] StartDeliverForChannel -> DEBU 3ec This peer will pass blocks from orderer service to other peers for channel mychannel
```

It seems the Chaincode container cannot establish comms with the peer. I thought this would be resolved by the following,
but these assumptions were incorrect:


* Setting CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:7052
* Configuring the Docker daemon on the Kubernetes nodes so that is uses the Kubernetes DNS to do a lookup. I assumed
that because the Chaincode container is a Docker container, managed outside of K8s by Docker, that it would use
the Docker daemon settings to do a DNS lookup.

The way to solve this was to use this ENV, which I found in the IBM Fabric on K8s config files:
https://github.com/IBM-Blockchain/ibm-container-service/blob/master/cs-offerings/kube-configs/blockchain-couchdb.yaml

          - name: CORE_PEER_ADDRESSAUTODETECT
            value: "true"

The difference the above ENV makes can be seen in the peer log file snippets below. 

Prior to setting the ENV, the -peer-address argument is a URL.
```bash
2018-04-15 02:49:15.767 UTC [chaincode] launchAndWaitForRegister -> DEBU 3cb chaincode mycc:1.0 is being launched
2018-04-15 02:49:15.767 UTC [chaincode] getLaunchConfigs -> DEBU 3cc Executable is chaincode
2018-04-15 02:49:15.767 UTC [chaincode] getLaunchConfigs -> DEBU 3cd Args [chaincode -peer.address=peer1-org2.org2:7052]
2018-04-15 02:49:15.767 UTC [chaincode] getLaunchConfigs -> DEBU 3ce Envs [CORE_CHAINCODE_ID_NAME=mycc:1.0 CORE_PEER_TLS_ENABLED=false CORE_CHAINCODE_LOGGING_LEVEL=info CORE_CHAINCODE_LOGGING_SHIM=warning CORE_CHAINCODE_LOGGING_FORMAT=%{color}%{time:2006-01-02 15:04:05.000 MST} [%{module}] %{shortfunc} -> %{level:.4s} %{id:03x}%{color:reset} %{message}]
2018-04-15 02:49:15.767 UTC [chaincode] getLaunchConfigs -> DEBU 3cf FilesToUpload []
2018-04-15 02:49:15.767 UTC [chaincode] launch -> DEBU 3d0 start container: mycc:1.0(networkid:dev,peerid:peer1-org2)
2018-04-15 02:49:15.767 UTC [chaincode] launch -> DEBU 3d1 start container with args: chaincode -peer.address=peer1-org2.org2:7052
2018-04-15 02:49:15.767 UTC [chaincode] launch -> DEBU 3d2 start container with env:
	CORE_CHAINCODE_ID_NAME=mycc:1.0
	CORE_PEER_TLS_ENABLED=false
	CORE_CHAINCODE_LOGGING_LEVEL=info
	CORE_CHAINCODE_LOGGING_SHIM=warning
	CORE_CHAINCODE_LOGGING_FORMAT=%{color}%{time:2006-01-02 15:04:05.000 MST} [%{module}] %{shortfunc} -> %{level:.4s} %{id:03x}%{color:reset} %{message}
```

After setting the ENV, the -peer-address argument is an IP address.

```bash
2018-04-15 03:03:35.652 UTC [chaincode] launchAndWaitForRegister -> DEBU 6fd chaincode mycc:1.0 is being launched
2018-04-15 03:03:35.652 UTC [chaincode] getLaunchConfigs -> DEBU 6fe Executable is chaincode
2018-04-15 03:03:35.652 UTC [chaincode] getLaunchConfigs -> DEBU 6ff Args [chaincode -peer.address=100.96.6.20:7052]
2018-04-15 03:03:35.652 UTC [chaincode] getLaunchConfigs -> DEBU 700 Envs [CORE_CHAINCODE_ID_NAME=mycc:1.0 CORE_PEER_TLS_ENABLED=false CORE_CHAINCODE_LOGGING_LEVEL=info CORE_CHAINCODE_LOGGING_SHIM=warning CORE_CHAINCODE_LOGGING_FORMAT=%{color}%{time:2006-01-02 15:04:05.000 MST} [%{module}] %{shortfunc} -> %{level:.4s} %{id:03x}%{color:reset} %{message}]
2018-04-15 03:03:35.652 UTC [chaincode] getLaunchConfigs -> DEBU 701 FilesToUpload []
2018-04-15 03:03:35.653 UTC [chaincode] launch -> DEBU 702 start container: mycc:1.0(networkid:dev,peerid:peer1-org1)
2018-04-15 03:03:35.653 UTC [chaincode] launch -> DEBU 703 start container with args: chaincode -peer.address=100.96.6.20:7052
2018-04-15 03:03:35.653 UTC [chaincode] launch -> DEBU 704 start container with env:
	CORE_CHAINCODE_ID_NAME=mycc:1.0
	CORE_PEER_TLS_ENABLED=false
	CORE_CHAINCODE_LOGGING_LEVEL=info
	CORE_CHAINCODE_LOGGING_SHIM=warning
	CORE_CHAINCODE_LOGGING_FORMAT=%{color}%{time:2006-01-02 15:04:05.000 MST} [%{module}] %{shortfunc} -> %{level:.4s} %{id:03x}%{color:reset} %{message}
```
### In test-fabric-sh, could not query chaincode:


```
##### 2018-04-14 06:09:54 Querying chaincode in the channel 'mychannel' on the peer 'peer1-org1.org1' ...
....2018-04-14 06:09:58.771 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-04-14 06:09:58.771 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-04-14 06:09:58.771 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 003 Using default escc
2018-04-14 06:09:58.771 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 004 Using default vscc
2018-04-14 06:09:58.771 UTC [chaincodeCmd] getChaincodeSpec -> DEBU 005 java chaincode disabled
2018-04-14 06:09:58.771 UTC [msp/identity] Sign -> DEBU 006 Sign: plaintext: 0A8E090A6708031A0C08B6B6C6D60510...6D7963631A0A0A0571756572790A0161
2018-04-14 06:09:58.771 UTC [msp/identity] Sign -> DEBU 007 Sign: digest: 8957AD38B15663C26DC5CEA6B1413B9D7E44934E4CA515F57DC0FA62BA12AA26
Error: Error endorsing query: rpc error: code = Unknown desc = error executing chaincode: timeout expired while starting chaincode mycc:1.0(networkid:dev,peerid:peer1-org1,tx:9501b39da023acbc9287bba5342b37856cd623e24a678ebfb31fb41daf78462e) - <nil>
```

At this point chaincode has been instatiating by peer1-org2, and is being queried on peer1-org1.

If I kubectl exec into peer1-org2, I can query fine:

```
export CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/msp

peer chaincode query -C mychannel -n mycc -c '{"Args":["query","a"]}'
2018-04-14 06:39:48.945 UTC [msp] GetLocalMSP -> DEBU 001 Returning existing local MSP
2018-04-14 06:39:48.945 UTC [msp] GetDefaultSigningIdentity -> DEBU 002 Obtaining default signing identity
2018-04-14 06:39:48.945 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 003 Using default escc
2018-04-14 06:39:48.945 UTC [chaincodeCmd] checkChaincodeCmdParams -> INFO 004 Using default vscc
2018-04-14 06:39:48.945 UTC [chaincodeCmd] getChaincodeSpec -> DEBU 005 java chaincode disabled
2018-04-14 06:39:48.945 UTC [msp/identity] Sign -> DEBU 006 Sign: plaintext: 0A8A090A6708031A0C08B4C4C6D60510...6D7963631A0A0A0571756572790A0161
2018-04-14 06:39:48.945 UTC [msp/identity] Sign -> DEBU 007 Sign: digest: B5E8D57F24B64F2C3DBF60FB8C4F77228522B2FC5286606A31CBB6F9B5AC095C
Query Result: 100
2018-04-14 06:39:48.954 UTC [main] main -> INFO 008 Exiting.....
```

Note, context must be et to 'user' for query, and to 'admin' for instantiating chaincode.

Set context to admin:
export CORE_PEER_MSPCONFIGPATH=/data/orgs/org1/admin/msp


### Cannot see logs of Chaincode Docker container

Add this ENV to the peer deployment.yaml. This will merge the Chaincode Docker container logs into the peer logs:

          - name: CORE_VM_DOCKER_ATTACHSTDOUT
            value: "true"
            
Note: remove this prior to PROD as it can expose sensitive info in the peer logs

### Orderer crashes when using Kafka

I could not get the Kafka orderer working - as soon as the peer tried to create a channel it would fail. I also
used Kafka from repo : https://github.com/Yolean/kubernetes-kafka.git with tag: v4.1.0

https://jira.hyperledger.org/browse/FAB-6250

In Orderer logs:

```bash
[sarama] 2017/09/20 17:41:46.014480 config.go:329: ClientID is the default of 'sarama', you should consider setting it to something application-specific.
fatal error: unexpected signal during runtime execution
[signal SIGSEGV: segmentation violation code=0x1 addr=0x47 pc=0x7f5ec665b259]

runtime stack:
runtime.throw(0xc72896, 0x2a)
/opt/go/src/runtime/panic.go:566 +0x95
runtime.sigpanic()
/opt/go/src/runtime/sigpanic_unix.go:12 +0x2cc

```

This turned out to be an issue with DNS. Fixed by adding the following ENV to peers and orderer:

```
          - name: GODEBUG
            value: "netdns=go"
```

### Error when running 'peer channel fetch config'
```bash
##### 2018-04-23 02:32:34 Fetching the configuration block into '/tmp/config_block.pb' of the channel 'mychannel'
##### 2018-04-23 02:32:34 peer channel fetch config '/tmp/config_block.pb' -c 'mychannel' '-o orderer1-org0.org0:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt'
2018-04-23 02:32:34.461 UTC [main] main -> ERRO 001 Fatal error when initializing core config : error when reading core config file: Unsupported Config Type ""
```

It's completely non-intuitive, nor is it documented anywhere, but this command reads 'core.yaml'. I discovered this by
checking the code, here: https://github.com/hyperledger/fabric/blob/13447bf5ead693f07285ce63a1903c5d0d25f096/peer/main.go, line 88.

This requires FABRIC_CFG_PATH=/etc/hyperledger/fabric, which is where core.yaml is located.

I had it pointing to FABRIC_CFG_PATH=/data, which is where configtx.yaml is located.

### Error when running start-load.sh.

Logs in the load-fabric show the following:

##### 2018-05-04 13:30:59 Querying chaincode in the channel 'mychannel' on the peer 'peer1-org1.org1' ...
2018-05-04 13:31:01.005 UTC [main] main -> ERRO 001 Cannot run peer because error when setting up MSP of type bccsp from directory /etc/hyperledger/fabric/orgs/org1/user/msp: Setup error: nil conf reference
.2018-05-04 13:31:02.031 UTC [main] main -> ERRO 001 Cannot run peer because error when setting up MSP of type bccsp from directory /etc/hyperledger/fabric/orgs/org1/user/msp: Setup error: nil conf reference
.2018-05-04 13:31:03.058 UTC [main] main -> ERRO 001 Cannot run peer because error when setting up MSP of type bccsp from directory /etc/hyperledger/fabric/orgs/org1/user/msp: Setup error: nil conf reference

I guess this has something to do with how the user identity is setup in switchToUserIdentity. It sets up keys in
the folder: /etc/hyperledger/fabric/orgs/org1/user/msp, but I guess some are missing. I worked around this by
changing it to switchToAdminIdentity just before calling chaincodeQuery

### Error in Orderer
2018-06-12 03:27:38.279 UTC [common/deliver] deliverBlocks -> WARN 9b3 [channel: mychannel] Rejecting deliver request for 192.168.171.1:39054 because of consenter error
2018-06-12 03:27:38.279 UTC [common/deliver] Handle -> DEBU 9b4 Waiting for new SeekInfo from 192.168.171.1:39054

and

2018-06-12 03:27:35.225 UTC [cauthdsl] deduplicate -> ERRO 92e Principal deserialization failure (the supplied identity is not valid: x509: certificate signed by unknown authority (possibly because of "x509: ECDSA verification failure" while trying to verify candidate authority certificate "rca-org2-admin")) for identity 0a076f7267324d5


This is caused by starting a new Fabric network, and it connecting to an existing Kafka cluster. This could either
be a Kafka cluster that wasn't stopped, or where the PV and PVC were not deleted. To resolve this, stop the Kafka
cluster and delete all the related PV and PVC

### Remote peer in another AWS account, can't connect to Orderer due to cert mismatch
fa5563726379.elb.us-west-2.amazonaws.com:7050 orderer1-org0.org0:7050 orderer2-org0.org0:7050 a6ae290186ef211e88a810af1c0a30f8-c3e639e28eedaf94.elb.us-west-2.amazonaws.com:7050]
2018-06-13 12:05:09.165 UTC [deliveryClient] try -> WARN 426 Got error: Could not connect to any of the endpoints: [a6abc67696ef211e8834f06b86f026a6-58fdfa5563726379.elb.us-west-2.amazonaws.com:7050 orderer1-org0.org0:7050 orderer2-org0.org0:7050 a6ae290186ef211e88a810af1c0a30f8-c3e639e28eedaf94.elb.us-west-2.amazonaws.com:7050] , at 4 attempt. Retrying in 8s
2018-06-13 12:05:20.167 UTC [ConnProducer] NewConnection -> ERRO 427 Failed connecting to orderer1-org0.org0:7050 , error: context deadline exceeded
2018-06-13 12:05:20.425 UTC [ConnProducer] NewConnection -> ERRO 428 Failed connecting to a6ae290186ef211e88a810af1c0a30f8-c3e639e28eedaf94.elb.us-west-2.amazonaws.com:7050 , error: remote error: tls: bad certificate

2018-06-13 12:12:31.370 UTC [deliveryClient] try -> WARN 42d Got error: Could not connect to any of the endpoints: [a6abc67696ef211e8834f06b86f026a6-58fdfa5563726379.elb.us-west-2.amazonaws.com:7050 orderer1-org0.org0:7050 a6ae290186ef211e88a810af1c0a30f8-c3e639e28eedaf94.elb.us-west-2.amazonaws.com:7050 orderer2-org0.org0:7050] , at 5 attempt. Retrying in 16s
2018-06-13 12:12:50.371 UTC [ConnProducer] NewConnection -> ERRO 42e Failed connecting to orderer2-org0.org0:7050 , error: context deadline exceeded
2018-06-13 12:12:50.536 UTC [ConnProducer] NewConnection -> ERRO 42f Failed connecting to a6abc67696ef211e8834f06b86f026a6-58fdfa5563726379.elb.us-west-2.amazonaws.com:7050 , error: x509: certificate is valid for orderer1-org0.org0, not a6abc67696ef211e8834f06b86f026a6-58fdfa5563726379.elb.us-west-2.amazonaws.com
2018-06-13 12:12:53.537 UTC [ConnProducer] NewConnection -> ERRO 430 Failed connecting to a6ae290186ef211e88a810af1c0a30f8-c3e639e28eedaf94.elb.us-west-2.amazonaws.com:7050 , error: context deadline exceeded
2018-06-13 12:12:56.538 UTC [ConnProducer] NewConnection -> ERRO 431 Failed connecting to orderer1-org0.org0:7050 , error: context deadline exceeded
2018-06-13 12:12:56.538 UTC [deliveryClient] connect -> DEBU 432 Connected to
2018-06-13 12:12:56.538 UTC [deliveryClient] connect -> ERRO 433 Failed obtaining connection: Could not connect to any of the endpoints: [orderer2-org0.org0:7050 a6abc67696ef211e8834f06b86f026a6-58fdfa5563726379.elb.us-west-2.amazonaws.com:7050 a6ae290186ef211e88a810af1c0a30f8-c3e639e28eedaf94.elb.us-west-2.amazonaws.com:7050 orderer1-org0.org0:7050]

This is fixed by updating the fabric-deployment-orderer.yaml: ORDERER_HOST - the DNS name here should be the same as the NLB or Orderer endpoint.
The TLS cert is generated based on this ENV variable. I think I can run two OSN's, one with a local DNS for local peers to connect to,
and another with an NLB DNS for connection from remote peers.

I had some issues getting this to work. Kept seeing errors such as 'bad certificate' above. I worked around this by turning off client TLS authentication
in the remote peer:

          - name: CORE_PEER_TLS_ENABLED
            value: "true"
          - name: CORE_PEER_TLS_CLIENTAUTHREQUIRED
            value: "false"
            
and the same in the orderer:

          - name: ORDERER_GENERAL_TLS_ENABLED
            value: "true"
          - name: ORDERER_GENERAL_TLS_CLIENTAUTHREQUIRED
            value: "false"
    
###   TLS issues when creating new org in new account
           
remote error: tls: bad certificate

I found some useful info here: https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=11&ved=0ahUKEwjQ6fDu4KrcAhULUN4KHS0DAw84ChAWCCkwAA&url=https%3A%2F%2Freadthedocs.org%2Fprojects%2Fhyperledger-fabric-ca%2Fdownloads%2Fpdf%2Flatest%2F&usg=AOvVaw1zI84gxZ0BXNth4sjdd2XX
See the last pages in this doc.

I used configtxgen to view the channel config, by fetching the latest config block:
peer channel  fetch config -c mychannel -o a61689643897211e8834f06b86f026a6-4a015d7a09a2998a.elb.us-west-2.amazonaws.com:7050 --tls --cafile /data/org0-ca-chain.pem --clientauth --keyfile /data/tls/peer1-org1-cli-client.key --certfile /data/tls/peer1-org1-cli-client.crt

/usr/local/bin/configtxgen -channelID mychannel -inspectBlock mychannel_config.block


I used openssl to compare the identifiers in the various certs in the MSP directory:

1023  sudo openssl x509 -in /opt/share/rca-data/org7-ca-chain.pem -noout -text
 1026  sudo openssl x509 -in /opt/share/rca-data/orgs/org7/msp/tlsintermediatecerts/ica-org7-org7-7054.pem -noout -text | grep -A1 "Subject Key Identifier"
 1027  sudo openssl x509 -in /opt/share/rca-data/orgs/org7/msp/tlscacerts/ica-org7-org7-7054.pem -noout -text | grep -A1 "Subject Key Identifier"
 1028  sudo openssl x509 -in /opt/share/rca-data/orgs/org7/msp/intermediatecerts/ica-org7-org7-7054.pem -noout -text| grep -A1 "Subject Key Identifier"
 1029  sudo openssl x509 -in /opt/share/rca-data/orgs/org7/msp/cacerts/ica-org7-org7-7054.pem -noout -text | grep -A1 "Subject Key Identifier"
