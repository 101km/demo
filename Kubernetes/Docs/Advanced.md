# Complex Deployments on Kubernetes

Non-trivial deployments sometimes require more advanced kubernetes primitives.  
Two such neccessary building blocks have been recently released as alphas. 

A third, Jobs, has already shipped. 

Kubernetes Jobs are a crucial feature for complex deployments and that pattern and others are described below.

##  PetSets

PetSets are a special type of deployment/replication-controller in that they create (and name) pods in an ordinal and therefore predictable manner.
PetSets allow some state to be sprinkled in, as long as this is done in an idempotent manner.

### MongoDB Cluster Example using Kubernetes PetSets

Mongo ReplicaSets map very conveniently to Kubernetes PetSets.

Process to [Deploy a Sharded Mongo Cluster](https://docs.mongodb.com/manual/tutorial/deploy-shard-cluster/) is as follows:

- Create the Config Server Replica Set
- Initiate the Config Server Replica Set 
- Repeat this process for the regular Replica Sets independently
- Create a mongos server (pointed at the Config Server Replica Set)
- Via the mongos server configure the cluster to use the regular Replica Sets as shards
- Expose mongos as a service to apps

#### Create and Initiate Replica Sets

Using the official Mongo docker image we launch 3 pods running the command:        

```mongod --configsvr --replSet rs0 --bind_ip 0.0.0.0```

Each pod now knows about itself that it is a special type of replica set (config server) and the name of the set is rs0.
However, to initiate the replica set the members must be made aware of each other and reach a quorum. 

```
rs.initiate(
   {
     _id: "<replSetName>",
     configsvr: true,
     members: [
       { _id : 0, host : "rs0-0.example.net:27017" },
       { _id : 1, host : "rs0-1.example.net:27017" },
       { _id : 2, host : "rs0-2.example.net:27017" }
     ]
   }
 )
```

<sub>Fig 1: config document example from the official mongo docs</sub> 

The above demonstrates it is necessary for the  host names of all members of a replica to be deducible.

A regular Kubernetes deployment would name pods `rs0-<randomsuffix>` and create them with nondeterministic order and timings.

In contrast, the usefulness of PetSets now becomes apparent. If we opt to use a PetSet named "rs0" of size 3 we get sequentially created pods named: rs0-0, rs0-1, rs0-2. Exactly what we need.


#### Kubernetes Jobs as One Shot steps of complex deployments

We now know the necessary mongo Replica Set initialization command ahead of time, we don't yet know _when_ to run it, and _what_ should execute it. A Kubernetes Job is a great choice for this sort of thing.

```
apiVersion: extensions/v1beta1
kind: Job
metadata:
  name: init
spec:
  autoSelector: true
  template:
    metadata:
      name: init
    spec:
      containers:
      - name: init
        image: mongo:3.2
        command:
        - "mongo"
        - "--host"
        - "rs0-0"
        - "--port"
        - "27017"
        - "--eval"
        - "rs.initiate({_id: 'rs0', members: [{'_id':0,host:'rs0-0:27019'},{'_id':1,host:'rs0-1:27019'},{'_id':2,host:'rs0-2:27019'}]})"
      restartPolicy: Always
```

This Kubernetes Job will start a pod using the official mongo:3.2 image, execute the mongo replica set initialization command against a group of hosts whose names are deducible because they belong to a PetSet, and exit.

Against a fresh replica set this will happen quickly and reliably. 

It would be even better to run this **only once** and **_only after_** the replica set pods are up and running. In essence, this Kubernetes Job is a One Shot step _conditional on the previous step_ successfully completing. 

## InitContainers
