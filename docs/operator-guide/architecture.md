# Manta Architecture

*([Up to the Manta Operator Guide front page.](./))*

This section discusses the basics of the Manta architecture.


## Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Design constraints](#design-constraints)
- [Basic terminology](#basic-terminology)
- [Manta and Triton (SDC)](#manta-and-triton-sdc)
- [Components of Manta](#components-of-manta)
- [Services, instances, and agents](#services-instances-and-agents)
  - [Manta components at a glance](#manta-components-at-a-glance)
- [Consensus and internal service discovery](#consensus-and-internal-service-discovery)
- [External service discovery](#external-service-discovery)
- [Storage tier](#storage-tier)
- [Metadata tier](#metadata-tier)
  - [Postgres, replication, and sharding](#postgres-replication-and-sharding)
  - [Other shards](#other-shards)
  - [Moray](#moray)
  - [Electric-moray](#electric-moray)
- [The front door](#the-front-door)
  - [Objects and directories](#objects-and-directories)
- [Garbage Collection](#garbage-collection)
- [Metering](#metering)
- [Manta Scalability](#manta-scalability)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


## Design constraints

**Horizontal scalability.**  It must be possible to add more hardware to scale
any component within Manta without downtime.  As a result of this constraint,
there are multiple instances of each service.

**Strong consistency.**  In the face of network partitions where it's not
possible to remain both consistent and available, Manta chooses consistency.  So
if all three datacenters in a three-DC deployment become partitioned from one
another, requests may fail rather than serve potentially incorrect data.

**High availability.**  Manta must survive failure of any service, physical
server, rack, or even an entire datacenter, assuming it's been deployed
appropriately.  Development installs of Manta can fit on a single system, and
obviously those don't survive server failure, but several production deployments
span three datacenters and survive partitioning or failure of an entire
datacenter without downtime for the other two.

## Basic terminology

We use **nodes** to refer to physical servers.  **Compute nodes** mean the same
thing they mean in Triton, which is any physical server that's not a head node.
**Storage nodes** are compute nodes that are designated to store actual Manta
objects.

A Manta install uses:

* a headnode (see "Manta and Triton" below)
* one or more storage nodes to store user objects
* one or more non-storage compute nodes for the other Manta services.

We use the term *datacenter* (or DC) to refer to an availability zone (or AZ).
Each datacenter represents a single Triton deployment (see below).  Manta
supports being deployed in either 1 or 3 datacenters within a single *region*,
which is a group of datacenters having a high-bandwidth, low-latency network
connection.


## Manta and Triton (SDC)

Manta is built atop Triton (formerly known as SmartDataCenter).  A
three-datacenter deployment of Manta is built atop three separate Triton
deployments.  The presence of Manta does not change the way Triton is deployed
or operated.  Administrators still have AdminUI, APIs, and they're still
responsible for managing the Triton services, platform versions, and the like
through the normal Triton mechanisms.


## Components of Manta

All user-facing Manta functionality can be divided into a few major subsystems:

* The **storage tier** is responsible for storing the physical copies of user
  objects on disk.  Storage nodes store objects as files with random uuids.  So
  within each storage node, the objects themselves are effectively just large,
  opaque blobs of data.
* The **metadata tier** is responsible for storing metadata about each object
  that's visible from the public Manta API.  This metadata includes the set of
  storage nodes on which the physical copy is stored.


In order to make all this work, there are several other pieces. For example:

* The **front door** is made up of the SSL terminators, load balancers, and API
  servers that actually handle user HTTP requests.  All user interaction with
  Manta happens over HTTP, so the front door handles all user-facing operations.
* An **authentication cache** maintains a read-only copy of the Joyent account
  database.  All front door requests are authenticated against this cache.
* A **garbage collection** system removes objects marked for deletion.
* A **consensus layer** is used to keep track of primary-secondary relationships
  in the metadata tier.
* DNS-based **nameservices** are used to keep track of all instances of all
  services in the system.


## Services, instances, and agents

Just like with Triton, components are divided into services, instances, and
agents.  Services and instances are SAPI concepts.

A **service** is a group of **instances** of the same kind. For example,
"webapi" is a service, and there may be multiple webapi zones. Each zone is an
instance of the "webapi" service. The vast majority of Manta components are
service instances, and there are several different services involved.

Note: Do not confuse SAPI services with SMF services.  We're talking about SAPI
services here.  A given SAPI instance (which is a zone) may have many *SMF*
services.

### Manta components at a glance

| Kind    | Major subsystem    | Service                  | Purpose                                | Components                                                                                             |
| ------- | ------------------ | ------------------------ | -------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Service | Consensus          | nameservice              | Service discovery                      | ZooKeeper, [binder](https://github.com/joyent/binder) (DNS)                                            |
| Service | Front door         | loadbalancer             | SSL termination and load balancing     | haproxy, [muppet](https://github.com/joyent/muppet)                                                    |
| Service | Front door         | webapi                   | Manta HTTP Directory API server        | [muskie](https://github.com/joyent/manta-muskie)                                                       |
| Service | Front door         | authcache                | Authentication cache                   | [mahi](https://github.com/joyent/mahi) (redis)                                                         |
| Service | Garbage Collection | garbage-deleter          | Deleting storage for objects           | [garbage-deleter (bin)](https://github.com/joyent/manta-mako/blob/master/bin/garbage-deleter.js), [garbage-deleter (lib)](https://github.com/joyent/manta-mako/blob/master/lib/garbage-deleter.js) |
| Service | Garbage Collection | garbage-dir-consumer     | Manta Directory API garbage collection | [garbage-dir-consumer (bin)](https://github.com/joyent/manta-garbage-collector/blob/master/bin/garbage-dir-consumer.js), [garbage-dir-consumer (lib)](https://github.com/joyent/manta-garbage-collector/blob/master/lib/garbage-dir-consumer.js) |
| Service | Garbage Collection | garbage-uploader         | Send GC instructions to storage zones  | [garbage-uploader (bin)](https://github.com/joyent/manta-garbage-collector/blob/master/bin/garbage-uploader.js), [garbage-uploader (lib)](https://github.com/joyent/manta-garbage-collector/blob/master/lib/garbage-uploader.js) |
| Service | Metadata           | postgres                 | Directory metadata storage             | postgres, [manatee](https://github.com/joyent/manta-manatee)                                           |
| Service | Metadata           | moray                    | Directory key-value store              | [moray](https://github.com/joyent/moray)                                                               |
| Service | Metadata           | electric-moray           | Directory consistent hashing (sharding)| [electric-moray](https://github.com/joyent/electric-moray)                                             |
| Service | Metadata           | storinfo                 | Storage metadata cache and picker      | [storinfo](https://github.com/joyent/manta-storinfo)                                                   |
| Service | Storage            | storage                  | Object storage and capacity reporting  | [mako](https://github.com/joyent/manta-mako) (nginx), [minnow](https://github.com/joyent/manta-minnow) |
| Service | Operations         | madtom                   | Web-based Manta monitoring             | [madtom](https://github.com/joyent/manta-madtom)                                                       |
| Service | Operations         | ops                      | Operator workspace                     |                                                                                                        |

\* _experimental features_


## Consensus and internal service discovery

In some sense, the heart of Manta (and Triton) is a service discovery mechanism
(based on ZooKeeper) for keeping track of which service instances are running.
In a nutshell, this works like this:

1. Setup: There are 3-5 "nameservice" zones deployed that form a ZooKeeper
   cluster.  There's a "binder" DNS server in each of these zones that serves
   DNS requests based on the contents of the ZooKeeper data store.
2. Setup: When other zones are deployed, part of their configuration includes
   the IP addresses of the nameservice zones.  These DNS servers are the only
   components that each zone knows about directly.
3. When an instance starts up (e.g., a "moray" zone), an SMF service called the
   *registrar* connects to the ZooKeeper cluster (using the IP addresses
   configured with the zone) and publishes its own IP to ZooKeeper.  A moray
   zone for shard 1 in region "us-east" publishes its own IP under
   "1.moray.us-east.joyent.us".
4. When a client wants to contact the shard 1 moray, it makes a DNS request for
   1.moray.us-east.joyent.us using the DNS servers in the ZooKeeper cluster.
   Those DNS servers returns *all* IPs that have been published for
   1.moray.us-east.joyent.us.
5. If the registrar in the 1.moray zone dies, the corresponding entry in the
   ZooKeeper data store is automatically removed, causing that zone to fall out
   of DNS.  Due to DNS TTLs of 60s, it may take up to a minute for clients to
   notice that the zone is gone.

Internally, most services work this way.

## External service discovery

Since we don't control Manta clients, the external service discovery system is
simpler and more static.  We manually configure the public
`us-east.manta.joyent.com` DNS name to resolve to each of the loadbalancer
public IP addresses.  After a request reaches the loadbalancers, everything uses
the internal service discovery mechanism described above to contact whatever
other services they need.

## Storage tier

The storage tier is made up of Mantis Shrimp nodes that have a great deal of
of physical storage in order to store users' objects.

Each storage node has an instance of the **storage** service, also called a
"mako" or "shark" (as in: a *shard* of the storage tier).  Inside this zone
runs:

* **mako**: an nginx instance that supports simple PUT/GET for objects.  This is
  not the front door; this is used *internally* to store each copy of a user
  object.  Objects are stored in a ZFS delegated dataset inside the storage
  zone, under `/manta/$account_uuid/$object_uuid`.
* **minnow**: a small Node service that periodically reports storage capacity
  data into the metadata tier so that the front door knows how much capacity
  each storage node has.


## Metadata tier

The metadata tier is itself made up of three levels:

* "postgres" zones, which run instances of the postgresql database
* "moray" zones, which run key-value stores on top of postgres
* "electric-moray" zones, which handle sharding of metadata requests

### Postgres, replication, and sharding

All object metadata is stored in PostgreSQL databases.  Metadata is keyed on the
object's name, and the value is a JSON document describing properties of the
object including what storage nodes it's stored on.

This part is particularly complicated, so pay attention!  The metadata tier is
**replicated for availability** and **sharded for scalability**.

It's easiest to think of sharding first.  Sharding means dividing the entire
namespace into one or more *shards* in order to scale horizontally.  So instead
of storing objects A-Z in a single postgres database, we might choose two shards
(A-M in shard 1, N-Z in shard 2), or three shards (A-I in shard 1, J-R in shard
2, S-Z in shard 3), and so on.  Each shard is completely separate from the
others.  They don't overlap at all in the data that they store.  The shard
responsible for a given object is determined by consistent hashing on the
*directory name* of the object.  So the shard for "/mark/stor/foo" is determined
by hashing "/mark/stor".

Within each shard, we use multiple postgres instances for high availability.  At
any given time, there's a *primary peer* (also called the "master"), a
*secondary peer* (also called the "synchronous slave"), and an *async peer*
(sometimes called the "asynchronous slave").  As the names suggest, we configure
synchronous replication between the primary and secondary, and asynchronous
replication between the secondary and the async peer.  **Synchronous**
replication means that transactions must be committed on both the primary and
the secondary before they can be committed to the client.  **Asynchronous**
replication means that the asynchronous peer may be slightly behind the other
two.

The idea with configuration replication in this way is that if the primary
crashes, we take several steps to recover:

1. The shard is immediately marked read-only.
2. The secondary is promoted to the primary.
3. The async peer is promoted to the secondary.  With the shard being read-only,
   it should quickly catch up.
4. Once the async peer catches up, the shard is marked read-write again.
5. When the former primary comes back online, it becomes the asynchronous peer.

This allows us to quickly restore read-write service in the event of a postgres
crash or an OS crash on the system hosting the primary.  This process is managed
by the "manatee" component, which uses ZooKeeper for leader election to
determine which postgres will be the primary at any given time.

It's really important to keep straight the difference between *sharding* and
*replication*.  Even though replication means that we have multiple postgres
instances in each shard, only the primary can be used for read/write operations,
so we're still limited by the capacity of a single postgres instance.  That's
why we have multiple shards.

<!-- XXX graphic -->

### Other shards

There are actually two kinds of metadata in Manta:

* Object metadata, which is sharded as described above.  This may be medium to
  high volume, depending on load.
* Storage node capacity metadata, which is reported by "minnow" instances (see
  above) and all lives on one shard.  This is extremely low-volume: a couple of
  writes per storage node per minute.

### Moray

For each metadata shard (which we said above consists of three PostgreSQL
databases), there's two or more "moray" instances.  Moray is a key-value store
built on top of postgres.  Clients never talk to postgres directly; they always
talk to Moray.  (Actually, they generally talk to electric-moray, which proxies
requests to Moray.  See below.)  Moray keeps track of the replication topology
(which Postgres instances is the primary, which is the secondary, and which is
the async) and directs all read/write requests to the primary Postgres instance.
This way, clients don't need to know about the replication topology.

Like Postgres, each Moray instance is tied to a particular shard.  These are
typically referred to as "1.moray", "2.moray", and so on.

### Electric-moray

The electric-moray service sits in front of the sharded Moray instances and
directs requests to the appropriate shard.  So if you try to update or fetch the
metadata for `/mark/stor/foo`, electric-moray will hash `/mark/stor` to find the
right shard and then proxy the request to one of the Moray instances operating
that shard.

## The front door

The front door consists of "loadbalancer" and "webapi" zones.

"loadbalancer" zones run haproxy for both SSL termination and load balancing
across the available "webapi" instances.  "haproxy" is managed by a component
called "muppet" that uses the DNS-based service discovery mechanism to keep
haproxy's list of backends up-to-date.

"webapi" zones run the Manta-specific API server, called **muskie**.  Muskie
handles PUT/GET/DELETE requests to the front door, including requests to:

* create and delete objects
* create, list, and delete directories


### Objects and directories

Requests for objects and directories involve:

* validating the request
* authenticating the user (via mahi, the auth cache)
* looking up the requested object's metadata (via electric-moray)
* authorizing the user for access to the specified resource

For requests on directories and zero-byte objects, the last step is to update or
return the right metadata.

For write requests on objects, muskie then:

* Constructs a set of candidate storage nodes that will be used to store the
  object's data, where each storage node is located in a different datacenter
  (in a multi-DC configuration).  By default, there are two copies of the data,
  but users can configure this by setting the durability level with the
  request.
* Tries to issue a PUT with 100-continue to each of the storage nodes in the
  candidate set.  If that fails, try another set.  If all sets are exhausted,
  fail with 503.
* Once the 100-continue is received from all storage nodes, the user's data is
  streamed to all nodes.  Upon completion, there should be a 204 response from
  each storage node.
* Once the data is safely written to all nodes, the metadata tier is updated
  (using a PUT to electric-moray), and a 204 is returned to the client.  At this
  point, the object's data is recorded persistently on the requested number of
  storage nodes, and the metadata is replicated on at least two index nodes.

For read requests on objects, muskie instead contacts each of the storage nodes
hosting the data and streams data from whichever one responds first to the
client.


## Garbage Collection

**Garbage collection** consists of several components in the `garbage-collector`
and `storage` zones and is responsible for removing the storage used by objects
which have been removed from the metadata tier.

When an object is deleted from the metadata tier, the objects on disk are not
immediately removed, nor are all references in the metadata tier itself. The
original record is moved into a new deletion record which includes the
information required to delete the storage backing the now-deleted object. The
garbage collection system is responsible for actually performing the cleanup.

Processes in the `garbage-collector` zone include:

 * `garbage-dir-consumer` -- consumes deletion records from the
   `manta_fastdelete_queue` bucket (created when an object is deleted through
   the Manta Directory API). The records found are written to local
   `instructions` files in the `garbage-collector` zone.

 * `garbage-uploader` -- consumes the locally queued `instructions` and uploads
   them to the appropriate `storage` zone for processing.

On the `storage` zones, there's an additional component of garbage collection:

 * `garbage-deleter` -- consumes `instructions` that were uploaded by
   `garbage-uploader` and actually deletes the no-longer-needed object files in
   `/manta` of the storage zone.  Once the storage is deleted, the completed
   instructions files are also deleted.

Each of these services in both zones, run as their own SMF service and has their
own log file in `/var/svc/log`.


## Metering

**Metering** is the process of measuring how much resource each user used. It
is not a full-fledged usage reporting feature at this time but the operator
can still obtain the total object counts and bytes used per user by aggregating
the metrics from individual storage zones. In each storage zone, the usage
metrics are reported by a daily cron job that generates a `mako_rollup.out`
text file under the `/var/tmp/mako_rollup` directory. 


## Manta Scalability

There are many dimensions to scalability.

In the metadata tier:

* number of objects (scalable with additional shards)
* number of objects in a directory (fixed, currently at a million objects)

In the storage tier:

* total size of data (scalable with additional storage servers)
* size of data per object (limited to the amount of storage on any single
  system, typically in the tens of terabytes, which is far larger than
  is typically practical)

In terms of performance:

* total bytes in or out per second (depends on network configuration)
* count of concurrent requests (scalable with additional metadata shards or API
  servers)

As described above, for most of these dimensions, Manta can be scaled
horizontally by deploying more software instances (often on more hardware).  For
a few of these, the limits are fixed, but we expect them to be high enough for
most purposes.  For a few others, the limits are not known, and we've never (or
rarely) run into them, but we may need to do additional work when we discover
where these limits are.
