TODO

Set up the OSNs and Kafka cluster so that they communicate over SSL - see http://hyperledger-fabric.readthedocs.io/en/release-1.0/kafka.html
Orderers: Adjust polling intervals and timeouts - see step 8 in above link
Kafka and ZK in a separate namespace to Orderer

Check ZK to confirm the Kafka brokers are running:

kubectl exec -it pzoo-0 -n kafka bash
cd /opt/kafka/bin
./zookeeper-shell.sh localhost:2181 <<< "ls /brokers/ids"

You should see this - the [0, 1, 2] shows 3 brokers are running:

WATCHER::

WatchedEvent state:SyncConnected type:None path:null
[0, 1, 2]