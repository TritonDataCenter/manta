---
title: Operator's Guide
markdown2extras: tables, code-friendly
apisections: .
---
<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2018, Joyent, Inc.
-->

# Operator's Guide for Manta, Triton's object storage and converged analytics solution

Manta, Triton's object storage and converged analytics solution, is an
internet-facing object store with in-situ Unix-based compute as a first class
operation. The user interface to Manta is essentially:

* A filesystem-like namespace, with *directories* and *objects*, accessible over
  HTTP
* *Objects* are arbitrary-size blobs of data
* Users can use standard HTTP `PUT`/`GET`/`DELETE` verbs to create and remove
  directories and objects as well as to list directories
* Users can fetch arbitrary ranges of an object, but may not *modify* an object
  except by replacing it
* Users submit map-reduce *compute jobs* that run arbitrary Unix programs on
  their objects.

Users can interact with Manta through the official Node.js CLI; the Joyent user
portal; the Node, Python, Ruby, or Java SDKs; curl(1); or any web browser.

For more information, see the official [public user
documentation](http://apidocs.joyent.com/manta/).  **Before reading this
document, you should be very familiar with using Manta, including both the CLI
tools and the compute jobs features. You should also be comfortable with all the
[reference material](http://apidocs.joyent.com/manta/) on how the system works
from a user's perspective.**


# Architecture basics

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
objects.  These are the same servers that run users' compute jobs, but we don't
call those compute nodes because that would be confusing with the Triton
terminology.

A Manta install uses:

* a headnode (see "Manta and Triton" below)
* one or more storage nodes to store user objects and run compute jobs
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
* The **jobs subsystem** (also called Marlin) is responsible for executing user
  programs on the objects stored in the storage tier.

In order to make all this work, there are several other pieces:

* The **front door** is made up of the SSL terminators, load balancers, and API
  servers that actually handle user HTTP requests.  All user interaction with
  Manta happens over HTTP (even compute jobs), so the front door handles all
  user-facing operations.
* An **authentication cache** maintains a read-only copy of the Joyent account
  database.  All front door requests are authenticated against this cache.
* A **garbage collection and auditing** system periodically compares the
  contents of the metadata tier with the contents of the storage tier to
  identify deleted objects, remove them, and verify that all other objects are
  replicated as they should be.
* A **metering** system periodically processes log files generated by the rest
  of the system to produce reports that are ultimately turned into invoices.
* A couple of **dashboards** provide visibility into what the system is doing at
  any given point.
* A **consensus layer** is used to keep track of primary-secondary relationships
  in the metadata tier.
* DNS-based **nameservices** are used to keep track of all instances of all
  services in the system.


## Services, instances, and agents

Just like with Triton, components are divided into services, instances, and
agents.  Services and instances are SAPI concepts.

A **service** is a group of **instances** of the same kind.  For example,
"jobsupervisor" is a service, and there may be multiple jobsupervisor zones.
Each zone is an instance of the "jobsupervisor" service.  The vast majority of
Manta components are service instances, and there are several different services
involved.

**Agents** are components that run in the global zone.  Manta uses one agent on
each storage node called the *marlin agent* in order to manage the execution of
user compute jobs on each storage node.

Note: Do not confuse SAPI services with SMF services.  We're talking about SAPI
services here.  A given SAPI instance (which is a zone) may have many *SMF*
services.

### Manta components at a glance

| Kind    | Major subsystem | Service          | Purpose                               | Components                                                                                             |
| ------- | --------------- | ---------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Service | Consensus       | nameservice      | Service discovery                     | ZooKeeper, [binder](https://github.com/joyent/binder) (DNS)                                            |
| Service | Front door      | loadbalancer     | SSL termination and load balancing    | stud, haproxy/[muppet](https://github.com/joyent/muppet)                                               |
| Service | Front door      | webapi           | Manta HTTP API server                 | [muskie](https://github.com/joyent/manta-muskie)                                                       |
| Service | Front door      | authcache        | Authentication cache                  | [mahi](https://github.com/joyent/mahi) (redis)                                                         |
| Service | Metadata        | postgres         | Metadata storage and replication      | postgres, [manatee](https://github.com/joyent/manta-manatee)                                           |
| Service | Metadata        | moray            | Key-value store                       | [moray](https://github.com/joyent/moray)                                                               |
| Service | Metadata        | electric-moray   | Consistent hashing (sharding)         | [electric-moray](https://github.com/joyent/electric-moray)                                             |
| Service | Storage         | storage          | Object storage and capacity reporting | [mako](https://github.com/joyent/manta-mako) (nginx), [minnow](https://github.com/joyent/manta-minnow) |
| Service | Operations      | ops              | GC, audit, and metering cron jobs     | [mola](https://github.com/joyent/manta-mola), [mackerel](https://github.com/joyent/manta-mackerel)     |
| Service | Operations      | madtom           | Web-based Manta monitoring            | [madtom](https://github.com/joyent/manta-madtom)                                                       |
| Service | Operations      | marlin-dashboard | Web-based Marlin monitoring           | [marlin-dashboard](https://github.com/joyent/manta-marlin-dashboard)                                   |
| Service | Compute         | jobsupervisor    | Distributed job orchestration         | jobsupervisor                                                                                          |
| Service | Compute         | jobpuller        | Job archival                          | [wrasse](https://github.com/joyent/manta-wrasse)                                                       |
| Service | Compute         | marlin           | Compute containers for end users      | [marlin-lackey](https://github.com/joyent/manta-marlin)                                                |
| Agent   | Compute         | marlin-agent     | Job execution on each storage node    | [marlin-agent](https://github.com/joyent/manta-marlin)                                                 |
| Agent   | Compute         | medusa           | Interactive Session Engine            | [medusa](https://github.com/joyent/manta-medusa)                                                       |


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

The storage tier is made up of Mantis Shrimp nodes.  Besides having a great deal
of physical storage in order to store users' objects, these systems have lots of
DRAM in order to support a large number of marlin *compute zones*, where we run
user programs directly on their data.

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

In addition to the "storage" zone, each storage node has some number of
**marlin zones** (or **compute zones**).  These are essentially blank zones in
which we run user programs.  We currently configure 128 of these zones on each
storage node.

## Metadata tier

The metadata tier is itself made up of three levels:

* "postgres" zones, which run instances of the postgresql database
* "moray" zones, which run a key-value store on top of postgres
* "electric-moray" zones, which handle sharding of moray requests

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

There are actually three kinds of metadata in Manta:

* Object metadata, which is sharded as described above.  This may be medium to
  high volume, depending on load.
* Storage node capacity metadata, which is reported by "minnow" instances (see
  above) and all lives on one shard.  This is extremely low-volume: a couple of
  writes per storage node per minute.
* Compute job state, which is all stored on a single shard.  This is extremely
  high volume, depending on job load.

In the us-east production deployment, shard 1 stores compute job state and
storage node capacity.  Shards 2-4 store the object metadata.

Manta supports **resharding** object metadata, which would typically be used to
add an additional shard (for additional capacity).  This operation has never
been needed (or used) in production.  Assuming the service is successful, that's
likely just a matter of time.

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

"loadbalancer" zones actually run both stud (for SSL termination) and haproxy
(for load balancing across the available "webapi" instances).  "haproxy" is
managed by a component called "muppet" that uses the DNS-based service discovery
mechanism to keep haproxy's list of backends up-to-date.

"webapi" zones run the Manta-specific API server, called **muskie**.  Muskie
handles PUT/GET/DELETE requests to the front door, including requests to:

* create and delete objects
* create, list, and delete directories
* create compute jobs, submit input, end input, fetch inputs, fetch outputs,
  fetch errors, and cancel jobs
* create multipart uploads, upload parts, fetch multipart upload state, commit
  multipart uploads, and abort multipart uploads

### Objects and directories

Requests for objects and directories involve:

* validating the request
* authenticating the user (via mahi, the auth cache)
* looking up the requested object's metadata (via electric moray)
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

### Compute jobs

Requests to manipulate compute jobs generally translate into creating
or listing job-related Moray records:

* When the user submits a request to create a job, muskie creates a new job
  record in Moray.
* When the user submits a request to add an input, muskie creates a new job
  input record in Moray.
* When the user submits a request to cancel a job or end input, muskie modifies
  the job record in Moray.
* When the user lists inputs, outputs, or errors, muskie lists job input
  records, task output records, or error records.

All of these requests operate on the shard storing all of the compute node
metadata.  These requests do not go through electric-moray.


## Compute tier (a.k.a., Marlin)

There are three core components of Marlin:

* A small fleet of **supervisors** manages the execution of jobs.  (Supervisors
  used to be called **workers**, and you may still see that terminology).
  Supervisors pick up new inputs, locate the servers where the input objects are
  stored, issue tasks to execute on those servers, monitor the execution of
  those tasks, and decide when the job is done.  Each supervisor can manage many
  jobs, but each job is managed by only one supervisor at a time.
* Job tasks execute directly on the Manta storage nodes.  Each node has an
  **agent** (i.e., the "marlin agent") running in the global zone that manages
  tasks assigned to that node and the zones available for running those tasks.
* Within each compute zone, task execution is managed by a **lackey** under the
  control of the agent.

All of Marlin's state is stored in **Moray**.  A few other components are
involved in executing jobs:

* **Muskie** handles all user requests related to jobs: creating jobs,
  submitting input, and fetching status, outputs, and errors.  To create jobs
  and submit inputs, Muskie creates and updates records in Moray.  See above for
  details.
* **Wrasse** (the jobpuller) is a separate component that periodically scans for
  recently completed jobs, archives the saved state into flat objects back in
  Manta, and then removes job state from Moray.  This is critical to keep the
  database that manages job state from growing forever.

### Distributed execution

When the user runs a "map" job, Muskie receives client requests to create the
job, to add inputs to the job, and to indicate that there will be no more job
inputs.  Jobsupervisors compete to take newly assigned jobs, and exactly one
will win and become responsible for orchestrating the execution of the job.  As
inputs are added, the supervisor resolves each object's name to the internal
uuid that identifies the object and checks whether the user is allowed to access
that object.  Assuming the user is authorized for that object, the supervisor
locates all copies of the object in the fleet, selects one, and issues a task to
an *agent* running on the server where that copy is stored.  This process is
repeated for each input object, distributing work across the fleet.

The agent on the storage server accepts the task and runs the user's script in
an isolated compute zone.  It records any outputs emitted as part of executing
the script.  When the task has finished running, the agent marks it completed.
The supervisor *commits* the completed task, marking its outputs as final job
outputs.  When there are no more unprocessed inputs and no uncommitted tasks,
the supervisor declares the job done.

If a task fails for a retryable reason, it will be retried a few times,
preferably on different servers.  If it keeps failing, an error is produced.

Multi-phase map jobs are similar except that the outputs of each first-phase map
task become inputs to a new second-phase map task, and only the outputs of the
second phase become outputs of the job.

Reducers run like mappers, except that the input for a reducer is not completely
known until the previous phase has already completed, and reducers can read an
arbitrary number of inputs so the inputs themselves are dispatched as individual
records and a separate end-of-input must be issued before the reducer can
complete.

### Local execution

The agent on each storage server maintains a fixed set of compute zones in which
user scripts can be run.  When a map task arrives, the agent locates the file
representing the input object on the local filesystem, finds a free compute
zone, maps the object into the local filesystem, and runs the user's script,
redirecting stdin from the input file and stdout to a local file.  When the
script exits, assuming it succeeds, the output file is saved as an object in the
object store, recorded as an output from the task, and the task is marked
completed.  If there is more work to be done for the same job, the agent may
choose to run it in the same compute zone without doing anything to clean up
after the first one.  When there is no more work to do, or the agent decides to
repurpose the compute zone for another job, the compute zone is halted, the
filesystem rolled back to its pristine state, and the zone is booted again to
run the next task.  Since the compute zones themselves are isolated from one
another and they are fully rebooted and rolled back between jobs, there is no
way for users' jobs to see or interfere with other jobs running in the system.

### Internal communication within Marlin

The system uses a Moray/PostgreSQL shard for all communication.  There are
buckets for jobs, job inputs, tasks, task inputs (for reduce tasks), task
outputs, and errors.  Supervisors and agents poll for new records applicable to
them.  For example, supervisors poll for tasks assigned to them that have been
completed but not committed and agents poll for tasks assigned to them that have
been dispatched but not accepted.

## Multipart uploads

Multipart uploads provide an alternate way for users to upload Manta objects.
The user creates the multipart upload, uploads the object in parts, and exposes
the object in Manta by committing the multipart upload.  Generally, these
operations are implemented using existing Manta constructs:

* Parts are normal Manta objects, with a few key differences.  Users cannot use
  the GET, POST or DELETE HTTP methods on parts.  Additionally, all parts are
  co-located on the same set of storage nodes, which are selected when the
  multipart upload is created.
* All parts for a given multipart upload are stored in a parts directory, which
  is a normal Manta directory.
* Part directories are stored in the top-level `/$MANTA_USER/uploads` directory
  tree.

Most of the logic for multipart uploads is performed by Muskie, but there are
some additional features of the system only used for multipart uploads:

* the **manta_uploads** bucket in Moray stores **finalizing records** for a
  given shard.  A finalizing record is inserted atomically with the target
  object record when a multipart upload is committed.
* the mako zones have a custom **mako-finalize** operation invoked by muskie
  when a multipart upload is committed. This operation creates the target object
  from the parts and subsequently deletes the parts from disk.  This operation
  is invoked on all storage nodes that will contain the target object when the
  multipart upload is committed.

## Garbage collection, auditing, and metering

Garbage collection, auditing, and metering all run as cron jobs out of the "ops"
zone.

**Garbage collection** is the process of freeing up storage used for objects
which no longer exist.  When an object is deleted, muskie records that event in
a log and removes the metadata from Moray, but does not actually remove the
object from storage servers because there may have been other links to it.  The
garbage collection job (called "mola") processes these logs, along with dumps of
the metadata tier (taken periodically and stored into Manta), and determines
which objects can safely be deleted.  These delete requests are batched and sent
to each storage node, which moves the objects to a "tombstone" area.  Objects in
the tombstone area are deleted after a fixed interval.

**Multipart upload garbage collection** is the process of cleaning up data
associated with finalized multipart uploads.  When a multipart upload is
finalized (committed or aborted), there are several items associated with it
that need to be cleaned up, including:

* its upload directory metadata
* part object metadata
* part data on disk (if not removed during the `mako-finalize` operation)
* its finalizing metadata

Similar to the basic garbage collection job, there is a multipart upload
garbage collection job that operates on dumps of the metadata tier to determine
what data associated with multipart uploads can be safely deleted.  A separate
operation deletes these items after the job has been completed.

**Auditing** is the process of ensuring that each object is replicated as
expected.  This is a similar job run over the contents of the metadata tier and
manifests reported by the storage nodes.

**Metering** is the process of measuring how much resource each user used, both
for reporting and billing.  There's compute metering (how much compute time was
used), storage metering (how much storage is used), request metering, and
bandwidth metering.  These are compute jobs run over the compute logs (produced
by the marlin agent), the metadata dumps, and the muskie request logs.

## Manta Scalability

There are many dimensions to scalability.

In the metadata tier:

* number of objects (scalable with additional shards)
* number of objects in a directory (fixed, currently at a few million objects)

In the storage tier:

* total size of data (scalable with additional storage servers)
* size of data per object (limited to the amount of storage on any single
  system, typically in the tens of terabytes, which is far larger than
  is typically practical)

In terms of performance:

* total bytes in or out per second (depends on network configuration)
* count of concurrent requests (scalable with additional metadata shards or API
  servers)
* count of compute tasks executed per second (scalable with additional storage
  nodes)
* count of concurrent compute tasks (could be measured in tasks, CPU cores
  available, or DRAM availability; scaled with additional storage node hardware)

As described above, for most of these dimensions, Manta can be scaled
horizontally by deploying more software instances (often on more hardware).  For
a few of these, the limits are fixed, but we expect them to be high enough for
most purposes.  For a few others, the limits are not known, and we've never (or
rarely) run into them, but we may need to do additional work when we discover
where these limits are.


# Planning a Manta deployment

Before even starting to deploy Manta, you must decide:

* the number of datacenters
* the number of metadata shards
* the number of storage and non-storage compute nodes
* how to lay out the non-storage zones across the fleet

## Choosing the number of datacenters

You can deploy Manta across any odd number of datacenters in the same region
(i.e., having a reliable low-latency, high-bandwidth network connection among
all datacenters).  We've only tested one- and three-datacenter configurations.
Even-numbered configurations are not supported.  See "Other configurations"
below for details.

A single-datacenter installation can be made to survive server failure, but
obviously cannot survive datacenter failure.  The us-east deployment uses three
datacenters.

## Choosing the number of metadata shards

Recall that each metadata shard has the storage and load capacity of a single
postgres instance.  If you want more capacity than that, you need more shards.
Shards can be added later without downtime, but it's a delicate operation.  The
us-east deployment uses three metadata shards, plus a separate shard for the
compute and storage capacity data.

We recommend at least two shards so that the compute and storage capacity
information can be fully separated from the remaining shards, which would be
used for metadata.

## Choosing the number of storage and non-storage compute nodes

The two classes of node (storage nodes and non-storage nodes) usually have
different hardware configurations.

The number of storage nodes needed is a function of the expected data footprint
and (secondarily) the desired compute capacity.

The number of non-storage nodes required is a function of the expected load on
the metadata tier.  Since the point of shards is to distribute load, each
shard's postgres instance should be on a separate compute node.  So you want at
least as many compute nodes as you will have shards.  The us-east deployment
distributes the other services on those same compute nodes.

For information on the latest recommended production hardware, see [Joyent
Manufacturing Matrix](http://eng.joyent.com/manufacturing/matrix.html) and
[Joyent Manufacturing Bill of
Materials](http://eng.joyent.com/manufacturing/bom.html).

The us-east deployment uses older versions of the Tenderloin-A for service
nodes and Mantis Shrimps for storage nodes.

## Choosing how to lay out zones

Since there are so many different Manta components, and they're all deployed
redundantly, there are a lot of different pieces to think about.  (The
production deployment in us-east has 21 zones in *each* of the three
datacenters, not including the Marlin compute zones.)  So when setting up a
Manta deployment, it's very important to think ahead of time about which
components will run where!

**The `manta-adm genconfig` tool (when used with the --from-file option) can be
very helpful in laying out zones for Manta.  See the `manta-adm` manual page for
details.**  `manta-adm genconfig --from-file` takes as input a list of physical
servers and information about each one.  Large deployments that use Device 42 to
manage hardware inventory may find the
[manta-genazconfig](https://github.com/joyent/manta-genazconfig) tool useful for
constructing the input for `manta-adm genconfig`.

The most important production configurations are described below,
but for reference, here are the principles to keep in mind:

* **Storage** zones should only be co-located with **marlin** zones, and only on
  storage nodes.  Neither makes sense without the other, and we do not recommend
  combining them with other zones.  All other zones should be deployed onto
  non-storage compute nodes.
* **Nameservice**: There must be an odd number of "nameservice" zones in order
  to achieve consensus, and there should be at least three of them to avoid a
  single point of failure.  There must be at least one in each DC to survive
  any combination of datacenter partitions, and it's recommended that they be
  balanced across DCs as much as possible.
* For the non-sharded, non-ops-related zones (which is everything except
  **moray**, **postgres**, **ops**, **madtom**, **marlin-dashboard**), there
  should be at least two of each kind of zone in the entire deployment (for
  availability), and they should not be in the same datacenter (in order to
  survive a datacenter loss).  For single-datacenter deployments, they should at
  least be on separate compute nodes.
* Only one **madtom** and **marlin-dashboard** zone is considered required.  It
  would be good to provide more than one in separate datacenters (or at least
  separate compute nodes) for maintaining availability in the face of a
  datacenter failure.
* There should only be one **ops** zone.  If it's unavailable for any reason,
  that will only temporarily affect metering, garbage collection, and reports.
* For **postgres**, there should be at least three instances in each shard.
  For multi-datacenter configurations, these instances should reside in
  different datacenters.  For single-datacenter configurations, they should be
  on different compute nodes.  (Postgres instances from different shards can be
  on the same compute node, though for performance reasons it would be better to
  avoid that.)
* For **moray**, there should be at least two instances per shard in the entire
  deployment, and these instances should reside on separate compute nodes (and
  preferably separate datacenters).

Most of these constraints are required in order to maintain availability in the
event of failure of any component, server, or datacenter.  Below are some
example configurations.

## Example single-datacenter, multi-server configuration

On each storage node, you should deploy one "storage" zone.  We recommend
deploying 128 "marlin" zones for systems with 256GB of DRAM.

If you have N metadata shards, and assuming you'll be deploying 3 postgres
instances in each shard, you'd ideally want to spread these over 3N compute
nodes.  If you combine instances from multiple shards on the same host, you'll
defeat the point of splitting those into shards.  If you combine instances from
the same shard on the same host, you'll defeat the point of using replication
for improved availability.

You should deploy at least two Moray instances for each shard onto separate
compute nodes.  The remaining services can be spread over the compute nodes
in whatever way, as long as you avoid putting two of the same thing onto the
same compute node.  Here's an example with two shards using six compute nodes:

| CN1           | CN2           | CN3            | CN4          | CN5          | CN6            |
| ------------- | ------------- | -------------- | ------------ | ------------ | -------------- |
| postgres 1    | postgres 1    | postgres 1     | postgres 2   | postgres 2   | postgres 2     |
| moray 1       | moray 1       | electric-moray | moray 2      | moray 2      | electric-moray |
| jobsupervisor | jobsupervisor | medusa         | medusa       | authcache    | authcache      |
| nameservice   | nameservice   | nameservice    | webapi       | webapi       | webapi         |
| ops           | marlin-dash   | madtom         | loadbalancer | loadbalancer | loadbalancer   |
| jobpuller     | jobpuller     |                |              |              |                |

In this notation, "postgres 1" and "moray 1" refer to an instance of "postgres"
or "moray" for shard 1.


## Example three-datacenter configuration

All three datacenters should be in the same region, meaning that they share a
reliable, low-latency, high-bandwidth network connection.

On each storage node, you should deploy one "storage" zone.  We recommend
deploying 128 "marlin" zones for systems with 256GB of DRAM.

As with the single-datacenter configuration, you'll want to spread the postgres
instances for N shards across 3N compute nodes, but you'll also want to deploy
at least one postgres instance in each datacenter.  For four shards, we
recommend the following in each datacenter:

| CN1              | CN2           | CN3            | CN4          |
| ---------------- | ------------- | -------------- | ------------ |
| postgres 1       | postgres 2    | postgres 3     | postgres 4   |
| moray    1       | moray    2    | moray    3     | moray    4   |
| nameservice      | nameservice   | electric-moray | authcache    |
| ops              | jobsupervisor | jobsupervisor  | webapi       |
| webapi           | jobpuller     | loadbalancer   | loadbalancer |
| marlin-dashboard | madtom        |                |              |

In this notation, "postgres 1" and "moray 1" refer to an instance of "postgres"
or "moray" for shard 1.

## Other configurations

For testing purposes, it's fine to deploy all of Manta on a single system.
Obviously it won't survive server failure.  This is not supported for a
production deployment.

It's not supported to run Manta in an even number of datacenters since there
would be no way to maintain availability in the face of an even split.  More
specifically:

* A two-datacenter configuration is possible but cannot survive datacenter
  failure or partitioning.  That's because the metadata tier would require
  synchronous replication across two datacenters, which cannot be maintained in
  the face of any datacenter failure or partition.  If we relax the synchronous
  replication constraint, then data would be lost in the event of a datacenter
  failure, and we'd also have no way to resolve the split-brain problem where
  both datacenters accept conflicting writes after the partition.
* For even numbers N >= 4, we could theoretically survive datacenter failure,
  but any N/2 -- N/2 split would be unresolvable.  You'd likely be better off
  dividing the same hardware into N - 1 datacenters.

It's not supported to run Manta across multiple datacenters not in the same
region (i.e., not having a reliable, low-latency, high-bandwidth connection
between all pairs of datacenters).

# Deploying Manta

Before you get started for anything other than a COAL or lab deployment, be
sure to read and fully understand the section on "Planning a Manta deployment"
above.

These general instructions should work for anything from COAL to a
multi-DC, multi-compute-node deployment.  The general process is:

1. Set up Triton in each datacenter, including the headnode, all Triton
   services, and all compute nodes you intend to use.  For easier management of
   hosts, we recommend that the hostname reflect the type of server and,
   possibly, the intended purpose of the host.  For example, we use the "RA"
   or "RM" prefix for "Richmond-A" hosts and "MS" prefix for "Mantis Shrimp"
   hosts.
2. In the global zone of each Triton headnode, set up a manta deployment zone
   using:

        /usbkey/scripts/setup_manta_zone.sh

3. In each datacenter, generate a Manta networking configuration file.

    a. For COAL, from the GZ, use:

        headnode$ /zones/$(vmadm lookup alias=manta0)/root/opt/smartdc/manta-deployment/networking/gen-coal.sh > /var/tmp/netconfig.json

    b. For those using the internal Joyent Engineering lab, run this from
       the [lab.git repo](https://mo.joyent.com/docs/lab/master/):

        lab.git$ node bin/genmanta.js -r RIG_NAME LAB_NAME

       and copy that to the headnode GZ.

    c. For other deployments, see "Networking configuration" below.

4. Once you've got the networking configuration file, configure networks by
   running this in the global zone of each Triton headnode:

        headnode$ ln -s /zones/$(vmadm lookup alias=manta0)/root/opt/smartdc/manta-deployment/networking /var/tmp/networking
        headnode$ cd /var/tmp/networking
        headnode$ ./manta-net.sh CONFIG_FILE

   This step is idempotent.  Note that if you are setting up a multi-DC Manta,
   ensure that (1) your Triton networks have cross datacenter connectivity and
   routing set up and (2) the Triton firewalls allow TCP and UDP traffic cross-
   datacenter.

5. For multi-datacenter deployments, you must [link the datacenters within
   Triton](https://docs.joyent.com/private-cloud/install/headnode-installation/linked-data-centers)
   so that the UFDS database is replicated across all three datacenters.

6. For multi-datacenter deployments, you must [configure SAPI for
   multi-datacenter
   support](https://github.com/joyent/sdc-sapi/blob/master/docs/index.md#multi-dc-mode).

7. If you'll be deploying a loadbalancer on any compute nodes *other* than a
   headnode, then you'll need to create the "external" NIC tag on those CNs.
   For common single-system configurations (for dev and test systems), you don't
   usually need to do anything for this step.  For multi-CN configurations,
   you probably *will* need to do this.  See the Triton documentation for
   [how to add a NIC tag to a
   CN](https://docs.joyent.com/sdc7/nic-tags#AssigningaNICTagtoaComputeNode).

8. In each datacenter's manta deployment zone, run the following:

        manta$ manta-init -s SIZE -e YOUR_EMAIL

   **`manta-init` must not be run concurrently in multiple datacenters.**

   `SIZE` must be one of "coal", "lab", or "production".  `YOUR_EMAIL` is used
   to create an Amon contact for alarm notifications.

   This step runs various initialization steps, including downloading all of
   the zone images required to deploy Manta.  This can take a while the first
   time you run it, so you may want to run it in a screen session.  It's
   idempotent.

   A common failure mode for those without quite fast internet links is a
   failure to import the "manta-marlin" image. The manta-marlin image is the
   multi-GB image that is used for zones in which Manta compute jobs run.
   See the "Workaround for manta-marlin image import failure" section below.

9. In each datacenter's manta deployment zone, deploy Manta components.

    a. In COAL, just run `manta-deploy-coal`.  This step is idempotent.

    b. For a lab machine, just run `manta-deploy-lab`.  This step is
       idempotent.

    c. For any other installation (including a multi-CN installation), you'll
       need to run several more steps: assign shards for storage and object
       metadata with "manta-shardadm"; create a hash ring with
       "manta-create-topology.sh"; generate a "manta-adm" configuration file
       (see "manta-adm configuration" below); and finally run "manta-adm update
       config.json" to deploy those zones.  Your best bet is to examine the
       "manta-deploy-dev" script to see how it uses these tools.  See
       "manta-adm configuration" below for details on the input file to
       "manta-adm update".  Each of these steps is idempotent, but the shard and
       hash ring must be set up before deploying any zones.

10. If desired, set up connectivity to the "ops", "marlin-dashboard", and
    "madtom" zones.  See "Overview of Operating Manta" below for details.

11. For multi-datacenter deployments, set the MUSKIE\_MULTI\_DC SAPI property.
    This is required to enforce that object writes are distributed to multiple
    datacenters.  In the SAPI master datacenter:

        headnode $ app_uuid="$(sdc-sapi /applications?name=manta | json -Ha uuid)"
        headnode $ echo '{ "metadata": { "MUSKIE_MULTI_DC": true } }' | \
            sapiadm update "$app_uuid"

    Repeat the following in each datacenter.

        headnode $ manta-oneach -s webapi 'svcadm restart "*muskie*"'

12. If you wish to enable basic monitoring, run the following in each
    datacenter:

        manta-adm alarm config update

    to deploy Amon probes and probe groups shipped with Manta.  This will cause
    alarms to be opened when parts of Manta are not functioning.  Email
    notifications are enabled by default using the address provided to
    `manta-init` above.  (Email notifications only work after you have
    configured the Amon service for sending email.)  If you want to be notified
    about alarm events via XMPP, see "Changing alarm contact methods" below.

13. **In development environments with more than one storage zone on a single
    system, it may be useful to apply quotas to storage zones so that if the
    system fills up, there remains space in the storage pool to address the
    problem.**  You can do this by finding the total size of the storage pool
    using `zfs list zones` in the global zone:

        # zfs list zones
        NAME    USED  AVAIL  REFER  MOUNTPOINT
        zones  77.5G   395G   612K  /zones

    Determine how much you want to allow the storage zones to use.  In this
    case, we'll allow the zones to use 100 GiB each, making up 300 GiB, or 75%
    of the available storage.  Now, find the storage zones:

        # manta-adm show storage
        SERVICE          SH ZONENAME                             GZ ADMIN IP
        storage           1 15711409-ca77-4204-b733-1058f14997c1 172.25.10.4
        storage           1 275dd052-5592-45aa-a371-5cd749dba3b1 172.25.10.4
        storage           1 b6d2c71f-ec3d-497f-8b0e-25f970cb2078 172.25.10.4

    and for each one, update the quota using `vmadm update`.  You can apply a
    100 GiB quota to all of the storage zones on a single-system Manta using:

        manta-adm show -H -o zonename storage | while read zonename; do
            vmadm update $zonename quota=100; done

    **Note:** This only prevents Manta storage zones from using more disk space
    than you've budgeted for them.  If the rest of the system uses more than
    expected, you could still run out of disk space.  To avoid this, make sure
    that all zones have quotas and the sum of quotas does not exceed the space
    available on the system.

    **Background:** Manta operators are responsible for basic monitoring of
    components, including monitoring disk usage to avoid components running out
    of disk space.  Out of the box, Manta stops using storage zones that are
    nearly full.  This mechanism relies on storage zones reporting how full they
    are, which they determine by dividing used space by available space.
    However, Manta storage zones are typically deployed without quotas, which
    means their available space is limited by the total space in the ZFS storage
    pool.  This accounting is not correct when there are multiple storage zones
    on the same system.

    To make this concrete, consider a system with 400 GiB of total ZFS pool
    space.  Suppose there are three storage zones, each using 100 GiB of space,
    and suppose that the rest of the system uses negligible storage space.  In
    this case, there are 300 GiB in use overall, so there's 100 GiB available in
    the pool.  As a result, each zone reports that it's using 100 GiB and has
    100 GiB available, so it's 50% full.  In reality, though, the system is 75%
    full.  Each zone reports that it has 100 GiB free, but if we were to write
    just 33 GiB to each zone, the whole system would be full.

    This problem only affects deployments that place multiple storage zones on
    the same system, which is not typical outside of development.  In
    development, the problem can be worked around by applying appropriate quotas
    in each zone (as described above).

## Post-Deployment Steps

Once the above steps have been completed, there are a few steps you
should consider doing to ensure a working deployment.

### Prerequisites

If you haven't already done so, you will need to [install the Manta CLI tools](https://github.com/joyent/node-manta#installation).

### Set up a Manta Account

To test Manta with the Manta CLI tools, you will need an account
configured in Triton. You can either use one of the default configured
accounts or setup your own. The most common method is to test using the
`poseidon` account which is created by the Manta install.

In either case, you will need access to the Operations Portal. [See the
instructions here](https://docs.joyent.com/private-cloud/install/headnode-installation#adding-external-access-to-adminui-and-imgapi) on how to find the IP address of the Operations Portal from
your headnode.

Log into the Operations Portal:

 * COAL users should use login `admin` and the password [you initially setup](https://github.com/joyent/triton/blob/master/docs/developer-guide/coal-setup.md#configure-the-headnode).
 * Lab users will also use `admin`, but need to ask whoever
   provisioned your lab account for the password.

Once in, follow [these instructions](https://docs.joyent.com/private-cloud/users#portalsshkeys) to add ssh keys to the account of your choice.

### Test Manta from the CLI Tools

Once you have setup an account on Manta or added your ssh keys added to an
existing account, you can test your Manta install with the Manta CLI
tools you installed above in "Prerequisites".

There are complete instructions on how to get started with the CLI
tools [on the apidocs page](https://apidocs.joyent.com/manta/#getting-started).

Some things in that guide will not be as clear for users of custom deployments.

1. The biggest difference will be the setting of the `MANTA_URL`
   variable. You will need to find the IP address of your API
   endpoint. To do this from your headnode:

        headnode$ manta-adm show -H -o primary_ip loadbalancer

    Multiple addresses will be returned. Choose any one and set `MANTA_URL`
    to `https://$that_ip`.
2. `MANTA_USER` will be the account you setup in "Set up a Manta Account"
   section.
3. `MANTA_KEY_ID` will be the ssh key id you added in "Set up a Manta
   Account" section.
4. If the key you used is in an environment that has not installed a
   certificate signed by a recognized authority you might see `Error:
   self signed certificate` errors. To fix this, add
   `MANTA_TLS_INSECURE=true` to your environment or shell config.

A final `~/.bashrc` or `~/.bash_profile` might look something like:

    export MANTA_USER=poseidon
    export MANTA_URL=https://<your-loadbalancer-ip>
    export MANTA_TLS_INSECURE=true
    export MANTA_KEY_ID=`ssh-keygen -l -f ~/.ssh/id_rsa.pub | awk '{print $2}' | tr -d '\n'`

Lastly test the CLI tools from your development machine:

    $ echo "Hello, Manta" > /tmp/hello.txt
    $ mput -f /tmp/hello.txt ~~/stor/hello-foo
    .../stor/hello-foo          [=======================================================>] 100%      13B
    $ mls ~~/stor/
    hello-foo
    $ mget ~~/stor/hello-foo
    Hello, Manta


## Networking configuration

The networking configuration file is a per-datacenter JSON file with several
properties:

| Property          | Kind                       | Description                                                                                                                                                                                                |
| ----------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `azs`             | array&nbsp;of&nbsp;strings | list of all availability zones (datacenters) participating in Manta in this region                                                                                                                        |
| `this_az`         | string                     | string (in `azs`) denoting this availability zone                                                                                                                                                          |
| `manta_nodes`     | array&nbsp;of&nbsp;strings | list of server uuid's for *all* servers participating in Manta in this AZ                                                                                                                                  |
| `marlin_nodes`    | array&nbsp;of&nbsp;strings | list of server uuid's (subset of `manta_nodes`) that are storage nodes                                                                                                                                     |
| `admin`           | object                     | describes the "admin" network in this datacenter (see below)                                                                                                                                               |
| `manta`           | object                     | describes the "manta" network in this datacenter (see below)                                                                                                                                               |
| `marlin`          | object                     | describes the "marlin" network in this datacenter (see below)                                                                                                                                              |
| `nic_mappings`    | object                     | maps each server in `manta_nodes` to an object mapping each network name ("manta" and "marlin") to the network interface on the server that should be tagged                                               |
| `mac_mappings`    | object                     | (deprecated) maps each server uuid from `manta_nodes` to an object mapping each network name ("admin", "manta", and "marlin") to the MAC address on that server over which that network should be created. |
| `distribute_svcs` | boolean                    | control switch over boot-time networking detection performed by `manta-net.sh` (see below)                                                                                                                 |

"admin", "manta", and "marlin" all describe these networks that are built into
Manta:

* `admin`: the Triton administrative network
* `manta`: the Manta administrative network, used for high-volume communication
  between all Manta services.
* `marlin`: the network used for compute zones.  This is usually a network that
  gives out private IPs that are NAT'd to the internet so that users can
  contact the internet from Marlin jobs, but without needing their own public
  IP for each zone.

Each of these is an object with several properties:

| Property  | Kind   | Description                                                            |
| --------- | ------ | ---------------------------------------------------------------------- |
| `network` | string | Name for the Triton network object (usually the same as the network name) |
| `nic_tag` | string | NIC tag name for this network (usually the same as the network name)   |

Besides those two, each of these blocks has a property for the current
availability zone that describes the "subnet", "gateway", "vlan_id", and
"start" and "end" provisionable addresses.

`nic_mappings` is a nested object structure defining the network interface to be
tagged for each server defined in `manta_nodes`, and for each of Manta's
required networks. See below for an example of this section of the
configuration.

Note: If aggregations are used, they must already exist in NAPI, and updating
NIC tags on aggregations will require a reboot of the server in question.

The optional boolean `distribute_svcs` gives control to the operator over the
boot-time networking detection that happens each time `manta-net.sh` is executed
(which determines if the global zone SMF services should be distributed). For
example, an operator has enabled boot-time networking in a datacenter _after_
installing Manta, and subsequently would like to add some more storage nodes.
For consistency, the operator can set `distribute_svcs` to `true` in order to
force distribution of these global zone services.

Note: For global zone network changes handled by boot-time networking to
take effect, a reboot of the node must be performed. See
[Triton's virtual networking documentation](https://docs.joyent.com/private-cloud/networks/sdn/architecture#bootstrapping-networking-state-in-the-global-zone)
for more information on boot-time networking.

For reference, here's an example multi-datacenter configuration with one service
node (aac3c402-3047-11e3-b451-002590c57864) and one storage node
(445aab6c-3048-11e3-9816-002590c3f3bc):

    {
      "this_az": "staging-1",

      "manta_nodes": [
        "aac3c402-3047-11e3-b451-002590c57864",
        "445aab6c-3048-11e3-9816-002590c3f3bc"
      ],
      "marlin_nodes": [
        "445aab6c-3048-11e3-9816-002590c3f3bc"
      ],
      "azs": [
        "staging-1",
        "staging-2",
        "staging-3"
      ],

      "admin": {
        "nic_tag": "admin",
        "network": "admin",
        "staging-1": {
          "subnet": "172.25.3.0/24",
          "gateway": "172.25.3.1"
        },
        "staging-2": {
          "subnet": "172.25.4.0/24",
          "gateway": "172.25.4.1"
        },
        "staging-3": {
          "subnet": "172.25.5.0/24",
          "gateway": "172.25.5.1"
        }
      },

      "manta": {
        "nic_tag": "manta",
        "network": "manta",
        "staging-1": {
          "vlan_id": 3603,
          "subnet": "172.27.3.0/24",
          "start": "172.27.3.4",
          "end": "172.27.3.254",
          "gateway": "172.27.3.1"
        },
        "staging-2": {
          "vlan_id": 3604,
          "subnet": "172.27.4.0/24",
          "start": "172.27.4.4",
          "end": "172.27.4.254",
          "gateway": "172.27.4.1"
        },
        "staging-3": {
          "vlan_id": 3605,
          "subnet": "172.27.5.0/24",
          "start": "172.27.5.4",
          "end": "172.27.5.254",
          "gateway": "172.27.5.1"
        }
      },

      "marlin": {
        "nic_tag": "mantanat",
        "network": "mantanat",
        "staging-1": {
          "vlan_id": 3903,
          "subnet": "172.28.64.0/19",
          "start": "172.28.64.4",
          "end": "172.28.95.254",
          "gateway": "172.28.64.1"
        },
        "staging-2": {
          "vlan_id": 3904,
          "subnet": "172.28.96.0/19",
          "start": "172.28.96.4",
          "end": "172.28.127.254",
          "gateway": "172.28.96.1"
        },
        "staging-3": {
          "vlan_id": 3905,
          "subnet": "172.28.128.0/19",
          "start": "172.28.128.4",
          "end": "172.28.159.254",
          "gateway": "172.28.128.1"
        }
      },

      "nic_mappings": {
        "aac3c402-3047-11e3-b451-002590c57864": {
          "manta": {
            "mac": "90:e2:ba:4b:ec:d1"
          }
        },
        "445aab6c-3048-11e3-9816-002590c3f3bc": {
          "manta": {
            "mac": "90:e2:ba:4a:32:71"
          },
          "mantanat": {
            "aggr": "aggr0"
          }
        }
      }

The deprecated `mac_mappings` can also be used in place of `nic_mappings`. Only
one of `nic_mappings` or `mac_mappings` is supported per network configuration
file.

In a multi-datacenter configuration, this would be used to configure the
"staging-1" datacenter.  There would be two more configuration files, one
for "staging-2" and one for "staging-3".


## Workaround for manta-marlin image import failure

A common failure mode with `manta-init ...` for those without a fast internet
link is a failure to import the large "manta-marlin" image. This is a multi-GB
image used for the zones in which Manta compute jobs run. The problem is that
the large image can make it easy to hit the one hour timeout for the
[IMGAPI AdminImportRemoteImage](https://github.com/joyent/sdc-imgapi/blob/master/docs/index.md#adminimportremoteimage-post-imagesuuidactionimport-remote)
endpoint used to import Manta images. Neither this endpoint nor the
<https://updates.joyent.com> server hosting the images supports resumable
downloads.

Here is a manual workaround (run the following from the headnode global zone):

    cd /var/tmp

    # Determine the UUID of the latest "manta-marlin" image on updates.joyent.com.
    muuid=$(updates-imgadm list name=manta-marlin --latest -H -o uuid)

    # Download directly from a separate manual download area in Manta.
    curl -kO https://us-east.manta.joyent.com/Joyent_Dev/public/Manta/manta-marlin-image/$muuid.imgmanifest

    # First ensure that the origin (i.e. parent) image is installed
    origin=$(json -f $muuid.imgmanifest origin)
    [[ -z "$origin" ]] \
        || sdc-imgadm get $origin >/dev/null \
        || sdc-imgadm import $origin -S https://updates.joyent.com

    # If that failed, then the separate download area doesn't have a recent
    # image. Please log an issue.
    [[ $? -ne 0 ]] && echo log an issue at https://github.com/joyent/manta/issues/

    # If the following is interrupted, then re-run the same command to resume:
    curl -kO -C - https://us-east.manta.joyent.com/Joyent_Dev/public/Manta/manta-marlin-image/$muuid.file.gz

    # Verify the download checksum
    [[ $(json -f $muuid.imgmanifest | json files.0.sha1) \
        == $(openssl dgst -sha1 $muuid.file.gz | awk '{print $2}') ]] \
        || echo "error downloading, please delete and retry"

    # Then install this image into the DC's IMGAPI:
    sdc-imgadm import -m $muuid.imgmanifest -f $muuid.file.gz


## manta-adm configuration

"manta-adm" is the tool we use both to deploy all of the Manta zones and then
to provision new zones, deprovision old zones, or reprovision old zones with a
new image.  "manta-adm" also has commands for viewing what's deployed, showing
information about compute nodes, and more, but this section only discusses the
configuration file format.

A manta-adm configuration file takes the form:

    {
        "COMPUTE_NODE_UUID": {
            "SERVICE_NAME": {
                "IMAGE_UUID": COUNT_OF_ZONES
            },
            "SHARDED_SERVICE_NAME": {
                "SHARD_NUMBER": {
                    "IMAGE_UUID": COUNT_OF_ZONES
                },
            }
        },
    }

The file specifies how many of each kind of zone should be deployed on each
compute node.  For most zones, the "kind" of zone is just the service name
(e.g., "storage").  For sharded zones, you also have to specify the shard
number.

After you've run `manta-init`, you can generate a sample configuration for a
single-system install using "manta-adm genconfig".  Use that to give you an
idea of what this looks like:

    $ manta-adm genconfig coal
    {
        "<any>": {
            "nameservice": {
                "197e905a-d15d-11e3-90e2-6bf8f0ea92b3": 1
            },
            "postgres": {
                "1": {
                    "92782f28-d236-11e3-9e6c-5f7613a4df37": 2
                }
            },
            "moray": {
                "1": {
                    "ef659002-d15c-11e3-a5f6-4bf577839d16": 1
                }
            },
            "electric-moray": {
                "e1043ddc-ca82-11e3-950a-ff14d493eebf": 1
            },
            "storage": {
                "2306b44a-d15d-11e3-8f87-6b9768efe5ae": 2
            },
            "authcache": {
                "5dff63a4-d15c-11e3-a312-5f3ea4981729": 1
            },
            "webapi": {
                "319afbfa-d15e-11e3-9aa9-33ebf012af8f": 1
            },
            "loadbalancer": {
                "7aac4c88-d15c-11e3-9ea6-dff0b07f5db1": 1
            },
            "jobsupervisor": {
                "7cf43bb2-d16c-11e3-b157-cb0adb200998": 1
            },
            "jobpuller": {
                "1b0f00e4-ca9b-11e3-ba7f-8723c9cd3ce7": 1
            },
            "medusa": {
                "bb6e5424-d0bb-11e3-8527-676eccc2a50a": 1
            },
            "ops": {
                "ab253aae-d15d-11e3-8f58-3fb986ce12b3": 1
            },
            "marlin": {
                "1c18ae6e-cf70-473a-a22c-f3536d6ea789": 2
            }
        }
    }

This file effectively specifies all of the Manta components except for the
platforms and Marlin agents.

You can generate a configuration file that describes your current deployment
with `manta-adm show -s -j`.

For a coal or lab deployment, your best bet is to save the output of `manta-adm
genconfig coal` or `manta-adm genconfig lab` to a file and use that.  This is
what the `manta-deploy-coal` and `manta-deploy-lab` scripts do, and you may as
well just use those.

Once you have a file like this, you can pass it to `manta-adm update`, which
will show you what it will do in order to make the deployment match the
configuration file, and then it will go ahead and do it.  For more information,
see "manta-adm help update".

# Upgrading Manta components

## Manta services upgrades

There are two distinct methods of updating instances: you may deploy additional
instances, or you may reprovision existing instances.

With the first method (new instances), additional instances are provisioned
using a newer image. This approach allows you to add additional capacity without
disrupting extant instances, and may prove useful when an operator needs to
validate a new version of a service before adding it to the fleet.

With the second method (reprovision), this update will swap one image out for a
newer image, while preserving any data in the instance's delegated dataset. Any
data or customizations in the instance's main dataset, i.e. zones/UUID, will be
lost. Services which have persistent state (manatee, mako, redis) must use this
method to avoid discarding their data. This update moves the service offline for
15-30 seconds. If the image onto which an image is reprovisioned doesn't work,
the instance can be reprovisioned back to its original image.

This procedure uses "manta-adm" to do the upgrade, which uses the reprovisioning
method for all zones other than the "marlin" zones.

### Prerequisites

1. Figure out which image you want to install. You can list available images by
   running updates-imgadm:

        headnode$ updates-imgadm list name=manta-jobsupervisor | tail

    Replace manta-jobsupervisor with some other image name, or leave it off to
    see all images. Typically you'll want the most recent one. Note the uuid of
    the image in the first column.

2. Figure out which zones you want to reprovision. In the headnode GZ of a given
   datacenter, you can enumerate the zones and versions for a given manta\_role
   using:

        headnode$ manta-adm show jobsupervisor

   You'll want to note the VM UUIDs for the instances you want to update.

### Procedure

Run this in each datacenter:

1. Download updated images.  The supported approach is to re-run the
   `manta-init` command that you used when initially deploying Manta inside the
   manta-deployment zone.  For us-east, use:

        $ manta-init -e manta+us-east@joyent.com -s production -c 10

   **Do not run `manta-init` concurrently in multiple datacenters.**

2. Inside the Manta deployment zone, generate a configuration file representing
   the current deployment state:

        $ manta-adm show -s -j > config.json

3. Modify the file as desired.  See "manta-adm configuration" above for details
   on the format.  In most cases, you just need to change the image uuid for
   the service that you're updating.  You can get the latest image for a
   service with the following command:

        $ sdc-sapi "/services?name=[service name]&include_master=true" | \
            json -Ha params.image_uuid

4. Pass the updated file to `manta-adm update`:

        $ manta-adm update config.json

   **Do not run `manta-adm update` concurrently in multiple datacenters.**

5. Update the alarm configuration as needed.  See "Amon Alarm Updates" below for
   details.


## Marlin agent upgrades

Run this procedure for each datacenter whose Marlin agents you want to upgrade.

1. Find the build you want to use using `updates-imgadm` in the global-zone
   of the headnode.

        headnode$ updates-imgadm list name=marlin

2. Fetch the desired tarball to /var/tmp on the headnode.  The file will be
   named `<UUID>-file.gz`.

        headnode$ uuid=<UUID>
        headnode$ cd /var/tmp
        headnode$ updates-imgadm get-file -O "$uuid"

3. Copy the tarball to each of the storage nodes:

        headnode$ manta-oneach -G -s storage \
            -d /var/tmp -g "/var/tmp/${uuid}-file.gz"

4. Apply the update to all shrimps with:

        headnode$ manta-oneach -G -s storage \
            "/opt/smartdc/agents/bin/apm install /var/tmp/${uuid}-file.gz"

5. Verify that agents are online with:

        headnode$ manta-oneach -G -s storage 'svcs marlin-agent'

6. Make sure most of the compute zones become ready. For this, you can use the
   dashboard or run this periodically:

        headnode$ manta-oneach -G -s storage mrzones

Note: The "apm install" operation will restart the marlin-agent service, which
has the impact of aborting any currently-running tasks on that system and
causing them to be retried elsewhere. They will be retried up to twice, and
Marlin will avoid retrying in the same AZ if possible. (Of course, if you're not
careful, it's possible to update the agents in a way that causes multiple
retries for the same tasks, but as long as you don't bounce each agent more than
once, this alone should not induce errors.)


## Compute zone ("marlin" zone) updates

Compute zones are a little different than most of the other Manta components
because they don't directly run a software service.  Instead, these are the
zones where users' compute jobs run.  For users' convenience, these zones
typically contain a large amount of software preinstalled from pkgsrc.  The main
reason to update these zones is to upgrade that package set to a newer base
image, giving users access to newer versions of all the preinstalled software.

Manta supports multiple different versions of the compute zone image being
available to end users simultaneously.  One image is configured as the default.
End users can request other available images on a per-job-phase basis.  While
[user documentation recommends that users always specify which image they want
to
use](https://apidocs.joyent.com/manta/jobs-reference.html#compute-instance-images-image-property),
most users do not use this option, so most jobs end up using the default image.

Because the software in compute zones is directly exposed to end users,
updates to these zones typically need to be coordinated with end users.
Different operators may have different needs:

* Public cloud operators may want to roll out a new image and make it available
  to end users for a while _without_ making that new image the default image.
  This allows bleeding-edge customers to experiment with the new image and
  provide feedback.  After promoting the new image to the default, operators may
  also want the old image to remain available for a while to allow slower
  customers to migrate on their own time (within some window).
* In deployments where operators and users are more tightly-coupled, operators
  may elect to avoid these grace periods and just update the default to the new
  image immediately.

In order to support these use-cases, the compute zone update process is a
multi-stage approach.  The approach allows both operators and end users to
validate each step in order to avoid having to rollback.  But in the event that
a serious issue goes undetected, the upgrade can also be rolled back quickly.
The update process works broadly as follows:

* The operator uses the "manta-adm" tool to deploy a large number of compute
  zones using the new image to each storage node.  Because there can be hundreds
  of compute zones in even modest Manta deployments, it can take many minutes
  (even hours or days, depending on the size of the deployment) to deploy all
  the new zones.  Older compute zones are not affected by the deployment of
  newer zones, and the newer zones are not used at this point because the
  default image has not been changed.
* If the operator wants to make the new zones available to end users at this
  point without making the new image the default, then they will likely need to
  update the configuration of the webapi zones.  (The webapi maintains its own
  configuration of supported images to allow operators to limit which zones are
  available at any given time.)  This step is not necessary if users don't
  intend to request the new image explicitly, but this does allow both operators
  and users to validate the new image before committing to it for new jobs.
* When ready to make the new image the default for all new jobs, the operator
  modifies the Marlin agent configuration.  At this point, all new jobs that
  don't request a specific image will start using the new image.  Users can
  continue using the older image by explicitly requesting it.
* When the operator is ready to stop supporting the older image, they can use
  the "manta-adm" tool to remove all instances of zones using the older image.

At any point before the old zones are deprovisioned, the upgrade can be rolled
back by simply changing the default image back.


### Compute zone update procedure

The above procedure outline really only involves a few kinds of steps:

* using "manta-adm" to provision or deprovision compute zones,
* updating the Marlin agent configuration to change the default zone image, and
* updating the webapi configuration to change the available zone images.

Let's consider a specific example, where we're updating a system from compute
zone image `1757ab74-b3ed-11e2-b40f-c7adac046f18` to compute zone image
`bb9264e2-f134-11e3-9ec7-478da02d1a13`:

1. Import the new compute zone image into the datacenter.  If upgrading to the
   current image used for new Manta deployments, "manta-init" can be used to
   download and import the new image.  Otherwise, import it explicitly with
   "sdc-imgadm import", as in `sdc-imgadm import
   bb9264e2-f134-11e3-9ec7-478da02d1a13 -S https://updates.joyent.com`.
2. Use `manta-adm show -s -j > config.json` to generate a configuration file
   describing the zones currently deployed in the datacenter.  This file should
   have a number of "marlin" blocks that look like this:

        "marlin": {
            "1757ab74-b3ed-11e2-b40f-c7adac046f18": 128
        },

   This example reflects that there are 128 compute zones using the older image
   on that storage node.  There will be one of these blocks for each storage
   node.
3. Update the configuration file: for each of these "marlin" blocks, add a
   second entry for the new image.  We suggest making the number of new zones
   match the number of old zones. (There will be twice as many zones on each
   server, but only half of them will generally be used.)  These blocks will
   thus look like this:

        "marlin": {
            "1757ab74-b3ed-11e2-b40f-c7adac046f18": 128,
            "bb9264e2-f134-11e3-9ec7-478da02d1a13": 128
        },

   You could also use a 50/50 split (e.g., 64 old zones and 64 new zones), or
   nearly any other combination, as long as there are a sufficient number of
   both old and new zones to handle the normal workload.
4. Run `manta-adm update config.json` to apply these changes.  In our example,
   this will deploy 128 compute zones to each storage node using the new image.
   This may take a while.
5. If the operator is electing to make the new image available via the API
   before promoting that image to the default, then modify the "images" property
   of the file
   "/opt/smartdc/muskie/node\_modules/marlin/jobsupervisor/etc/config.coal.json"
   inside each webapi zone.  Note that this change will need to be reapplied if
   the webapi zone is updated or if new webapi zones are deployed.  At this
   point, end users can use the new image, but only by specifying the `--image`
   property to `mjob create`.
6. When the operator is ready to promote the new image to the default image for
   new jobs, modify the "zoneDefaultImage" property in the file
   "/opt/smartdc/marlin/etc/agentconfig.json" and restart the marlin agent.
   This needs to be done on all storage nodes.  Otherwise, user jobs may run in
   a combination of older and newer images, which can lead to surprising and
   incorrect results.  If at any point you want to roll back this upgrade,
   simply set the "zoneDefaultImage" back to the previous value and restart the
   agents again.
7. When the operator is confident they don't need the old image any more,
   modify the "manta-adm" configuration file to remove the old image entirely,
   then use "manta-adm update" to apply that.  In our example, the "marlin"
   blocks will now look like this:

        "marlin": {
            "bb9264e2-f134-11e3-9ec7-478da02d1a13": 128
        },

This procedure could be streamlined with feature requests
[MANTA-2778](https://smartos.org/bugview/MANTA-2778) and
[MANTA-2779](https://smartos.org/bugview/MANTA-2779).

Note: the "manta-adm" tool takes care of internal constraints, including the
fact that compute zones cannot be reprovisioned.  (Instead, new zones are
provisioned and older ones are deprovisioned.)


## Manta deployment zone upgrades

Since the Manta deployment zone is actually a Triton component, use `sdcadm` to
update it:

    headnode$ sdcadm self-update --latest
    headnode$ sdcadm update manta

## Amon Alarm Updates

Manta's Amon probes are managed using the `manta-adm alarm` subcommand.  The set
of configured probes and probe groups needs to be updated whenever the set of
probes delivered with `manta-adm` itself changes (e.g., if new probes were
added, or bugs were fixed in existing probes) or when new components are
deployed or old components are removed.  In all cases, **it's strongly
recommended to address and close any open alarms**.  If the update process
removes a probe group, any alarms associated with that probe group will remain,
but without much information about the underlying problem.

To update the set of probes and probe groups deployed, use:

    headnode$ sdc-login manta
    manta$ manta-adm alarm config update

This command is idempotent.


## Triton zone and agent upgrades

Triton zones and agents are upgraded exactly as they are in non-Manta installs.

Note that the Triton agents include the Marlin agent.  If you don't want to
update the Marlin agent with the Triton agents, you'll need to manually exclude
it.


## Platform upgrades

Platform updates for compute nodes (including the headnode) are exactly the same
as for any other Triton compute node.  Use the `sdcadm platform` command to
download platform images and assign them to compute nodes.

Platform updates require rebooting CNs.  Note that:

* Rebooting the system hosting the ZooKeeper leader will trigger a new
  leader election.  This should have minimal impact on service.
* Rebooting the primary peer in any Manatee shard will trigger a Manatee
  takeover.  Write service will be lost for a minute or two while this happens.
* Other than the above constraints, you may reboot any number of nodes
  within a single AZ at the same time, since Manta survives loss of an
  entire AZ.  If you reboot more than one CN from different AZs at the same
  time, you may lose availability of some services or objects.


## SSL Certificate Updates

The certificates used for the front door TLS terminators can be updated.

1. Verify your PEM file.  Your PEM file should contain the private key and the
   certificate chain, including your leaf certificate.  It should be in the
   format:

        -----BEGIN RSA PRIVATE KEY-----
        [Base64 Encoded Private Key]
        -----END RSA PRIVATE KEY-----
        -----BEGIN CERTIFICATE-----
        [Base64 Encoded Certificate]
        -----END CERTIFICATE-----
        -----BEGIN DH PARAMETERS-----
        [Base64 Encoded dhparams]
        -----END DH PARAMETERS-----

   You may need to include the certificate chain in the PEM file.  The chain
   should be a series of CERTIFICATE sections, each section having been signed
   by the next CERTIFICATE.  In other words, the PEM file should be ordered by
   the PRIVATE KEY, the leaf certificate, zero or more intermediate
   certificates, the root certificate, and then DH parameters as the very last
   section.

   To generate the DH parameters section, use the command:

        $ openssl dhparam <bits> >> ssl_cert.pem

   Replace `<bits>` with at least the same number of bits as are in your RSA
   private key (if you are unsure, 2048 is probably safe).

2. Take a backup of your current certificate, just in case anything goes wrong.

        headnode$ sdc-sapi /services?name=loadbalancer | \
            json -Ha metadata.SSL_CERTIFICATE \
            >/var/tmp/manta_ssl_cert_backup.pem
        headnode$ mv /var/tmp/manta_ssl_cert_backup.pem \
            /zones/$(vmadm lookup alias=~manta)/root/var/tmp/.

3. Copy your certificate to the Manta zone after getting your certificate on
   your headnode:

        headnode$ mv /var/tmp/ssl_cert.pem \
            /zones/$(vmadm lookup alias=~manta)/root/var/tmp/.

4. Replace your certificate in the loadbalancer application.  Log into the manta
   zone:

        headnode$ sdc-login manta
        manta$ /opt/smartdc/manta-deployment/cmd/manta-replace-cert.js \
            /var/tmp/ssl_cert.pem

5. Restart your loadbalancers:

        # Verify your new certificate is in place
        headnode$ manta-oneach -s loadbalancer 'cat /opt/smartdc/muppet/etc/ssl.pem`

        # Restart stud
        headnode$ manta-oneach -s loadbalancer 'svcadm restart stud'

        # Verify no errors in the log
        headnode$ manta-oneach -s loadbalancer 'cat `svcs -L stud`'

        # Verify the loadbalancer is serving the new certificate
        headnode$ manta-oneach -s loadbalancer \
            'echo QUIT | openssl s_client -host 127.0.0.1 -port 443 -showcerts'

   An invalid certificate will result in an error like this in the stud logs:

        [ Jun 20 18:01:18 Executing start method ("/opt/local/bin/stud --config=/opt/local/etc/stud.conf"). ]
        92728:error:0906D06C:PEM routines:PEM_read_bio:no start line:pem_lib.c:648:Expecting: TRUSTED CERTIFICATE
        92728:error:140DC009:SSL routines:SSL_CTX_use_certificate_chain_file:PEM lib:ssl_rsa.c:729:
        [ Jun 20 18:01:18 Method "start" exited with status 1. ]


## Changing alarm contact methods

The contacts that are notified for new alarm events are configured using SAPI
metadata on the "manta" service within the "sdc" application (_not_ the "manta"
application).  This metadata identifies one or more contacts already configured
within Amon.  See the Amon docs for how to configure these contacts.

For historical reasons, high-severity notifications are delivered to the
list of contacts called "MANTAMON\_ALERT".  Other notifications are delivered to
the list of contacts called "MANTAMON\_INFO".

Here is an example update to send "alert" level notifications to both an email
address and an XMPP endpoint and have "info" level notifications sent just to
XMPP:

    headnode$ echo '{
      "metadata": {
        "MANTAMON_ALERT": [
          { "contact": "email" },
          { "contact": "mantaxmpp", "last": true }
        ],
        "MANTAMON_INFO": [
          { "contact": "mantaxmpp", "last": true }
        ]
      }
    }' | sapiadm update $(sdc-sapi /services?name=manta | json -Ha uuid)

Note that the last object of the list must have the `"last": true` key/value.

You will need to update the alarm configuration for this change to take effect.
See "Amon Alarm Updates".


# Overview of Operating Manta

## Alarms

Manta integrates with **Amon**, the Triton alarming and monitoring system, to
notify operators when something is wrong with a Manta deployment.  It's
recommended to review Amon basics in the [Amon
documentation](https://github.com/joyent/sdc-amon/blob/master/docs/index.md).

The `manta-adm` tool ships with configuration files that specify Amon probes and
probe groups, referred to elsewhere as the "Amon configuration" for Manta.  This
configuration specifies which checks to run, on what period, how failures should
be processed to open alarms (which generate notifications), and how these alarms
should be organized.  Manta includes built-in checks for events like components
dumping core, logging serious errors, and other kinds of known issues.

Typically, the only step that operators need to take to manage the Amon
configuration is to run:

    manta-adm alarm config update

after initial setup and after other deployment operations.  See "Amon Alarm
Updates" for more information.

With alarms configured, you can use the `manta-adm alarm show` subcommand and
related subcommands to view information about open alarms.  When a problem is
resolved, you can use `manta-adm alarm close` to close it.  You can also disable
notifications for alarms using `manta-adm alarm notify` (e.g., when you do not
need more notifications about a known issue).

See the `manta-adm` manual page for more information.


## Madtom dashboard (service health)

Madtom is a dashboard that presents the state of all Manta components in a
region-wide deployment.  You can access the Madtom dashboard by pointing a web
browser to port 80 at the IP address of the "madtom" zone that's deployed with
Manta.  For the JPC deployment, this is usually accessed through an ssh tunnel
to the corresponding headnode.


## Marlin dashboard (compute activity)

The Marlin dashboard shows the state of all supervisors and agents and the last
time each was restarted; the state of all compute zones, which gives a sense of
overall system health and utilization; and information about jobs, groups, and
task streams, which represent all the work in the system.  That includes both
work that's currently executing and work that's queued up to execute.

You can access the Marlin dashboard by pointing a web browser to port 80 on
the IP address of the "marlin-dashboard" zone that's deployed with Manta.  For
the JPC deployment, this is usually accessed through an ssh tunnel to the
corresponding headnode.


## Marlin tools

Marlin has a few tools to help understand what's going on with a compute job:

* `mrjob`: list jobs and fetch details about specific jobs
* `mrerrors`: list errors from recently-executed jobs
* `mrgroups`: list activity *on a storage node* (must be run on that storage
  node)
* `mrzones`: list zones on a storage node (must be run on that storage node)
* `mrextractjob`: extracts information about a job that completed over 24 hours
  ago from a manatee database dump.

You can run "mrjob" and "mrerrors" directly from the "ops" zone.  "mrgroups" and
"mrzones" should be run from an individual storage node.  There's a lot more
information about using these tools under the various "Debugging Marlin"
sections below.

"mrextractjob" is pretty special-purpose.  For details, see "Fetching
information about historical jobs" below.


## Logs

### Historical logs

Historical logs for all components are uploaded to Manta hourly at
`/poseidon/stor/logs/COMPONENT/YYYY/MM/DD/HH`.  This works by rotating them
hourly into /var/log/manta/upload inside each zone, and then uploading the files
in that directory to Manta.

The most commonly searched logs are the muskie logs, since these contain logs
for all requests to the public API. There's one object in each
`/poseidon/stor/logs/muskie/YYYY/MM/DD/HH/` directory per muskie server
instance. If you need to look at the live logs (because you're debugging a
problem within the hour that it happened, or because Manta is currently down),
see "real-time logs" below. Either way, if you have the x-server-name from a
request, that will tell you which muskie instance handled the request so that
you don't need to search all of them.

If Manta is not up, then the first priority is generally to get Manta up, and
you'll have to use the real-time logs to do that.

### Real-time logs and log formats

Unfortunately, logging is not standardized across all Manta components.  There
are three common patterns:

* Services log to their SMF log file (usually in the
  [bunyan](https://github.com/trentm/node-bunyan) format, though startup scripts
  tend to log with bash(1) xtrace output).
* Services log to a service-specific log file in bunyan format (e.g.,
  /var/log/muskie.log).
* Services log to an application-specific log file (e.g., haproxy, postgres).

Most custom services use the bunyan format.  The "bunyan" tool is installed in
/usr/bin to view these logs.  You can also [snoop logs of running services in
more detail using bunyan's built-in DTrace
probes](http://www.joyent.com/blog/node-js-in-production-runtime-log-snooping).
If you find yourself needing to look at the *current* log file for a component
(i.e., can't wait for the next hourly upload into Manta), here's a reference for
the service's that *don't* use the SMF log file:

| Service                                     | Path                             | Format             |
| ------------------------------------------- | -------------------------------- | ------------------ |
| muskie                                      | /var/log/muskie.log              | bunyan             |
| moray                                       | /var/log/muskie.log              | bunyan             |
| mbackup<br />(the log file uploader itself) | /var/log/mbackup.log             | bash xtrace        |
| haproxy                                     | /var/log/haproxy.log             | haproxy-specific   |
| mackerel (metering)                         | /var/log/mackerel.log            | bunyan             |
| mola                                        | /var/log/mola\*.log               | bunyan             |
| zookeeper                                   | /var/log/zookeeper/zookeeper.log | zookeeper-specific |
| redis                                       | /var/log/redis/redis.log         | redis-specific     |

Most of the remaining components log in bunyan format to their service log file
(including binder, config-agent, electric-moray, jobsupervisor, manatee-sitter,
marlin-agent, and others).


## Job archives

For every job that's ever run on the system, the system records the final
"job.json" file into Manta under
`/poseidon/stor/job_archives/YYYY/MM/DD/HH/$JOBID.json`.  This can be useful for
limited analysis of jobs run as well as for debugging specific jobs run in the
past.


## Usage reports and storage capacity

Usage reports for compute, storage, and requests are generated regularly by the
metering service. Marlin jobs are kicked off via cron in the ops zone to
process Marlin logs for compute usage, metadata tier dumps for storage usage,
and muskie logs for request and bandwidth. Additionally, a summary of the three
reports is generated from the primary usage reports. These reports are saved to
Manta under the following paths:

| Usage report | Path | Frequency |
| ------------ | ---- | --------- |
| compute      | `/poseidon/stor/usage/compute/YYYY/MM/DD/HH/hHH.json` | hourly |
| request      | `/poseidon/stor/usage/request/YYYY/MM/DD/HH/hHH.json` | hourly |
| storage      | `/poseidon/stor/usage/storage/YYYY/MM/DD/00/h00.json` | daily |
| summary      | `/poseidon/stor/usage/summary/YYYY/MM/DD/dDD.json`    | daily |

Usage output from storage metering is useful for determining logical usage for
each user in Manta. For a good idea of system-wide logical storage usage, sum
up the usage for each user, e.g., with
`mget /poseidon/stor/usage/YYYY/MM/DD/HH/hHH.json |\
 json -ga storage.public.bytes storage.stor.bytes storage.jobs.bytes storage.reports.bytes |\
 awk '{sum+=$1+$2+$3+$4}END{print sum}'`

Note, however, that the logical usage can be a poor indicator of **physical**
usage. Since a Manta object ultimately lives on a ZFS filesystem with
compression, physical usage may be less than the logical usage that metering
reports indicate. Storage reports also count cross-account links once for each
account, even though there is only a single set of copies of the objects.
Metering also rounds up small objects to a minimum object size.


## Request Throttling

Manta provides a coarse request throttle intended to be used when the system is
under extreme load and is sufferring availability problems that cannot be
isolated to a single Manta component. When the throttle is enabled and muskie
has reached its configured capacity, the throttle will cause muskie to drop new
requests and notify clients their requests have been throttled by sending a
response with HTTP status code 503. The throttle is disabled by default.

Inbound request activity and throttle statistics can be observed by running

    $ /opt/smartdc/muskie/bin/throttlestat.d

in a webapi zone in which the muskie processes have the throttle enabled. The
script will output rows of a table with the following columns every second:

* `THROTTLED-PER-SEC` - The number of requests throttled in the last second.
* `AVG-LATENCY-MS` - The average number of milliseconds that requests which
completed in the last second spent in the request queue.
* `MAX-QLEN` - The maximum number of queued requests observed in the last
second.
* `MAX-RUNNING` - The maximum number of concurrent dispatched request handlers
observed in the last second.

If the throttle is not enabled, this script will print an error message
indicating a missing DTrace provider. The message will look like this:

    dtrace: failed to compile script ./throttlestat.d: line 16: probe
    description muskie-throttle*:::queue_enter does not match any probes

If the script is run when the throttle is enabled, and it continues running as
the throttle is disabled, it will subsequently appear to indicate no request
activity. This is neither an error nor a sign of service availability lapse. It
just indicates the fact that the DTrace probes being used by the script are not
firing. Care should be taken to ensure that this script is used to collect
metrics only when the throttle is enabled.

The throttle is "coarse" because its capacity is a function of all requests to
the system, regardless of their originating user, IP address, or API operation.
Any type of request can be throttled.

The request throttle is implemented on a per-process level, with each "muskie"
process in a "webapi" zone having its own throttle. The throttle exposes three
tunables:

| Tunable Name                        | Default Value | Description                           |
| ----------------------------------- | ------------- | ------------------------------------- |
|  `MUSKIE_THROTTLE_ENABLED`          | false         | whether the throttle enabled          |
|  `MUSKIE_THROTTLE_CONCURRENCY`      | 50            | number of allowed concurrent requests |
|  `MUSKIE_THROTTLE_QUEUE_TOLERANCE`  | 25            | number of allowed queued requests     |

These tunables can be modified with commands of the following form:

    $ sapiadm update $(sdc-sapi /services?name=webapi | json -Ha uuid) \
        metadata."MUSKIE_THROTTLE_ENABLED"=true

Muskies must be restarted to use the new configuration:

    $ manta-oneach -s webapi 'svcadm restart "*muskie-*"'

Requests are throttled when the muskie process has exhausted all slots available
for concurrent requests and reached its queue threshold.

### Throttle Parameter Trade-offs

In general, higher concurrency values will result in a busier muskie process
that handles more requests at once. Lower concurrency values will limit the
number of requests the muskie will handle at once. Lower concurrency values
should be set to limit the CPU load on Manta.

Higher queue tolerance values will decrease the likelihood of requests being
rejected when Manta is under high load but may increase the average latency of
queued requests. This latency increase can be the result of longer queues
inducing longer delays before dispatch.

Lower queue tolerance values will make requests more likely to be throttled
quickly under load. Lower queue tolerance values should be used when high
latency is not acceptable and the application is likely to retry on receipt of
a 503. Low queue tolerance values are also desirable if the zone is under memory
pressure.

## Multipart uploads prefix length

### Overview

The Manta multipart upload API stores the part directories of an account's
ongoing multipart uploads under the directory tree `/$MANTA_USER/uploads`.
Within the top-level directory, part directories are stored in subdirectories
based on some number of the first characters of the multipart upload's UUID.
The number of characters used to split multipart uploads is referred to as the
"prefix length".

For example, in a Manta deployment for which the prefix length is set to 3,
a multipart upload would have an upload directory that looks like this:

    /$MANTA_USER/uploads/f00/f00e51d2-7e47-4732-8edf-eb871296b343

Note that the parent directory of the parts directory, also referred to
as its "prefix directory", has 3 characters, the same as the prefix length.

The following multipart upload would have been created in a Manta deployment
with a prefix length of 1:

    /$MANTA_USER/uploads/d/d77feb78-cd7f-481f-a6c7-f653c80c7331


### Changing the prefix length

The prefix length is configurable in SAPI, represented as the
`MUSKIE_MPU_PREFIX_DIR_LEN` SAPI variable under the "webapi" service.  For
example, to change the prefix length of a deployment to 2, you could run:

    $ sapiadm update $(sdc-sapi /services?name=webapi | json -Ha uuid) \
        metadata."MUSKIE_MPU_PREFIX_DIR_LEN"=2

As with other configuration changes to the "webapi" service, you must restart
the "webapi" zones to see the configuration change.

Multipart uploads created with a different prefix length within the same Manta
deployment will continue to work after the prefix length is changed.

### Prefix length tradeoffs

The prefix length dictates the number of subdirectories allowed in the top-level
`/$MANTA_USER/uploads` directory.  Because the number of entries in a Manta
directory should be limited, this affects how many ongoing multipart uploads are
available for a given account.  Increasing the prefix length also increases the
number of requests required to list all multipart uploads under a given account.
Consequently, a smaller prefix length allows for fewer ongoing multipart uploads
for a single account, but less work to list them all; larger prefix directories
allow more ongoing multipart uploads, but require more work to list them.

For example, in a Manta deployment with a prefix length of 3, a given account
may have up to 4096 prefix directories, allowing for about 4 billion ongoing
multipart uploads for a given account.  Listing all of the multipart uploads
ongoing requires a maximum of 4096 directory listings operations.  Compare this
to a deployment with a prefix length of 1, which has a maximum of 256 prefix
directories and allows for about 256 million multipart uploads, but only up to
256 directory listings are required to list all multipart uploads under an
account.


# Debugging: general tasks

## Locating servers

All Triton compute nodes have at least two unique identifiers:

- the server UUID, provided by the system firmware and used by Triton
- the hostname, provided by operators

The global zone's "admin" network IP address should also be unique.

The `manta-adm cn` command shows information about the Triton compute nodes in
the current datacenter on which Manta components are deployed.  For example, to
fetch the server uuid and global zone IP for RM08218, use:

    # manta-adm cn -o host,server_uuid,admin_ip RM08218
    HOST     SERVER UUID                          ADMIN IP
    RM08218  00000000-0000-0000-0000-00259094c058 10.10.0.34

See the `manta-adm(1)` manual page for details.


## Locating storage IDs and compute IDs

Manta Storage CNs have additional identifiers:

- a manta compute ID, used by the jobs subsystem.
- one or more manta storage IDs, used for object metadata.  There's one storage
  ID per storage zone deployed on a server, so there can be more than one
  storage ID per CN, although this is usually only the case in development
  environments.

You can generate a table that maps hostnames to compute ID and storage IDs for
the current datacenter:

    # manta-adm cn -o host,compute_id,storage_ids storage
    HOST     COMPUTE ID               STORAGE IDS
    RM08213  12.cn.us-east.joyent.us  2.stor.us-east.joyent.us
    RM08211  20.cn.us-east.joyent.us  1.stor.us-east.joyent.us
    RM08216  19.cn.us-east.joyent.us  3.stor.us-east.joyent.us
    RM08219  11.cn.us-east.joyent.us  4.stor.us-east.joyent.us

Note that the column name is "storage\_ids" (with a trailing "s") since there
may be more than one.

See the `manta-adm(1)` manual page for details.

## Locating Manta component zones

To find a particular manta zone, log into one of the headnodes and run
`manta-adm show` to list all Manta-related zones in the current datacenter.  You
can list all of the zones in all datacenters with `manta-adm show -a`.

`manta-adm show` supports a number of other features, including summary output,
filtering by service name, grouping results by compute node, and printing
various other properties about a zone.  For more information and examples, see
the `manta-adm(1)` manual page.

## Accessing systems

| To access ...                           | do this...                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a&nbsp;headnode                         | ssh directly to the headnode.                                                                                                                                                                                                                                                                                                                                                                               |
| a&nbsp;compute&nbsp;node                | ssh to the headnode for that datacenter, then ssh to the CN's GZ ip<br />(see "manta-adm cn" above)                                                                                                                                                                                                                                                                                                         |
| a&nbsp;compute&nbsp;zone                | ssh to the headnode for that datacenter, then use `manta-login ZONETYPE` or `manta-login ZONENAME`, where ZONENAME can actually be any unique part of the zone's name.                                                                                                                                                                                                                                      |
| a&nbsp;compute&nbsp;node's&nbsp;console | ssh to the headnode for that datacenter, find the compute node's service processor IP, then:<br/>`ipmitool -I lanplus -H SERVICE_PROCESS_IP -U ADMIN -P ADMIN sol activate`<br />To exit the console, press enter, then `~.`, prefixed with as many "~"s as you have ssh sessions. (If ssh'd to the headnode, use enter, then `~~.`) If you don't use the prefix `~`s, you'll kill your ssh connection too. |
| a&nbsp;headnode's&nbsp;console          | ssh to the headnode of one of the other datacenters, then "sdc-login" to the "manta" zone. From there, use the above "ipmitool" command in the usual way with the headnode's SP IP.                                                                                                                                                                                                                         |


## Locating Object Data

This section explains how to locate persisted object data throughout Manta.
There are only two places where data is persisted:

1. In `postgres` zones: Object metadata, in a Postgres database.
1. In `storage` zones: Object contents, as a file on disk


### Locating Object Metadata

The "mlocate" tool takes a Manta object name (like "/dap/stor/cmd.tgz"), figures
out which shard it's stored on, and prints out the internal metadata for it.
You run this inside any "muskie" (webapi) zone:

    [root@204ac483 (webapi) ~]$ /opt/smartdc/muskie/bin/mlocate /dap/stor/cmd.tgz | json
    {
      "dirname": "/bc8cd146-fecb-11e1-bd8a-bb6f54b49808/stor",
      "key": "/bc8cd146-fecb-11e1-bd8a-bb6f54b49808/stor/cmd.tgz",
      "headers": {},
      "mtime": 1396994173363,
      "name": "cmd.tgz",
      "creator": "bc8cd146-fecb-11e1-bd8a-bb6f54b49808",
      "owner": "bc8cd146-fecb-11e1-bd8a-bb6f54b49808",
      "type": "object",
      "contentLength": 17062152,
      "contentMD5": "vVRjo74mJquDRsoW2HJM/g==",
      "contentType": "application/octet-stream",
      "etag": "cb1036e4-3b57-c118-cd46-961f6ebe12d0",
      "objectId": "cb1036e4-3b57-c118-cd46-961f6ebe12d0",
      "sharks": [
        {
          "datacenter": "staging-2",
          "manta_storage_id": "2.stor.staging.joyent.us"
        },
        {
          "datacenter": "staging-1",
          "manta_storage_id": "1.stor.staging.joyent.us"
        }
      ],
      "_moray": "tcp://electric-moray.staging.joyent.us:2020",
      "_node": {
        "pnode": "tcp://3.moray.staging.joyent.us:2020",
        "vnode": 7336153,
        "data": 1
      }
    }

All of these implementation details are subject to change, but for reference,
these are the pieces you need to locate the object:

* "sharks": indicate which backend storage servers contain copies of this object
* "creator": uuid of the user who created the object
* "objectId": uuid for this object in the system.  Note that an objectid is
  allocated when an object is first created.  Two objects with the same content
  do not generally get the same objectid, unless the second object was created
  with "mln".

You won't need the following fields to locate the object, but they may be useful
to know about:

* "key": the internal name of this object (same as the public name, but the
  login is replaced with the user's uuid)
* "owner": uuid of the user being billed for this link.  This can differ from
  the creator if the owner used "mln" to create their own link to an object
  created by someone else.
* "\_node"."pnode": indicates which metadata shard stores information about this
  object.
* "type": indicates whether something refers to an object or directory
* "contentLength", "contentMD5", "contentType": see corresponding HTTP headers

### Locating Object Contents

Now that you know what sharks the object is on you can pull the object contents
directly from the ops box by creating a URL with the format:

    http://[manta_storage_id]/[creator]/[objectId]

You can use "curl" to fetch this from the "ops" zone, for example.

More commonly, you'll want to look at the actual file on disk.  For that, first
map the "manta\_storage\_id" to a specific storage zone, using a command like
this to print out the full mapping:

    # manta-adm show -a -o storage_id,datacenter,zonename storage
    STORAGE ID                 DATACENTER ZONENAME
    1.stor.staging.joyent.us   staging-1  f7954cad-7e23-434f-be98-f077ca7bc4c0
    2.stor.staging.joyent.us   staging-2  12fa9eea-ba7a-4d55-abd9-d32c64ae1965
    3.stor.staging.joyent.us   staging-3  6dbfb615-b1ac-4f9a-8006-2cb45b87e4cb

Then use "manta-login" to log into the corresponding storage zone:

    # manta-login 12fa9eea
    [Connected to zone '12fa9eea-ba7a-4d55-abd9-d32c64ae1965' pts/2]
    [root@12fa9eea (storage) ~]$

The object's data will be stored at /manta/$creator\_uuid/$objectid:

    [root@12fa9eea (storage) ~]$ ls -l
    /manta/bc8cd146-fecb-11e1-bd8a-bb6f54b49808/cb1036e4-3b57-c118-cd46-961f6ebe12d0
    -rw-r--r-- 1 nobody nobody 17062152 Apr  8  2014
    /manta/bc8cd146-fecb-11e1-bd8a-bb6f54b49808/cb1036e4-3b57-c118-cd46-961f6ebe12d0

There will be a copy of the object at that path in each of the `sharks` listed
in the metadata record.

## Debugging: was there an outage?

When debugging their own programs, in effort to rule out Manta as the cause (or
when they suspect Manta as the cause), users sometimes ask if there was a Manta
outage at a given time.  In rare cases when there was a major Manta-wide outage
at that time, the answer to the user's question may be "yes".  More often,
though, there may have been very transient issues that went unnoticed or that
only affected some of that user's requests.

First, it's important to understand what an "outage" actually means.  Manta
provides two basic services: an HTTP-based request API and a compute service
managed by the same API.  As a result, an "outage" usually translates to
elevated error rates from either the HTTP API or the compute service.

**To check for a major event affecting the API**, locate the muskie logs for the
hour in question (see "Logs" above) and look for elevated server-side error
rates.  An easy first cut is to count requests and group by HTTP status code.
You can run this from the ops zone (or any environment configured with a Manta
account that can access the logs):

    # mfind -t o /poseidon/stor/logs/muskie/2014/11/21/22 | \
        mjob create -o
	   -m "grep '\"audit\"' | json -ga res.statusCode | sort | uniq -c" \
	   -r "awk '{ s[\$2] += \$1; } END {
	      for(code in s) { printf(\"%8d %s\n\", s[code], code); } }'"

That example searches all the logs from 2014-11-21 hour 22 (22:00 to 23:00 UTC)
for requests ("audit" records), pulls out the HTTP status code from each one,
and then counts the number of requests for each status code.  The reduce phase
combines the outputs from scanning each log file by adding the counts for each
status code and then printing out the aggregated results.  The end output might
look something like this:

      293950 200
         182 201
         179 202
      267786 204
      ...

(You can also use [Dragnet](https://github.com/joyent/dragnet) to scan logs more
quickly.)

That output indicates 294,000 requests with code 200, 268,000 requests with code
204, and so on.  In HTTP, codes under 300 are normal.  Codes from 400 to 500
(including 400, not 500) are generally client problems.  Codes over 500 indicate
server problems.  Some number of 500 errors don't necessarily indicate a problem
with the service -- it could be a bug or a transient problem -- but if the
number is high (particularly compared to normal hours), then that may indicate a
serious Manta issue at the time in question.

If the number of 500-level requests is not particularly high, then that may
indicate a problem specific to this user or even just a few of their requests.
See "Debugging API failures" below.


## Debugging API failures

Users often report problems with their own programs acting as Manta clients
(possibly using our Node client library).  This may manifest as an error message
from the program or an error reported in the program's log.  Users may ask
simply: "was there a Manta outage at such-and-such time?"  To answer that
question, see "was there an outage?" above.  If you've established that there
wasn't an outage, here's how you can get more information about what happened.

For most problems that are caused by the Manta service itself (as opposed to
client-side problems), there will be information in the Manta server logs that
will help explain the root cause.  **The best way to locate the corresponding
log entries is for clients to log the request id of failed requests and for
users to provide the request ids when seeking support.**  The request id is
reported by a server HTTP header, and it's normally logged by the Node client
library.  While it's possible to search for log entries by timestamp, account
name, Manta path, or status code, not only is it much slower, but it's also not
sufficient for many client applications that end up performing a lot of similar
operations on similar paths for the same user around the same time (e.g.,
creating a directory tree).  **For requests within the last hour, it's very
helpful to get the x-server-name header as well.**

To find the logs you need, see "Logs" above.  Once you've found the logs (either
in Manta or inside the muskie zones, depending on whether you're looking at
a historical or very recent request):

1. If you have a request id and server name, pick the log for that server name
   and grep for the request id.
1. If you have a request id, grep all the logs for that hour for that request
   id.
1. If you don't have either of these, you can try grepping for the user's
   account uuid (which you can retrieve by searching adminui for the user's
   account login) or other relevant parameters of the request.  This process is
   specific to whatever information you have.  The logs are just plaintext JSON.

You should find exactly one request matching a given request id.  The log entry
for the request itself should include a lot of details about the request and
response, including internal error messages.  For 500-level errors (server
errors), there will be additional log entries for all the debug-level logging
for that request.

Obviously, most of this requires Manta to be operating.  If it's not, that's
generally the top priority, and you can use the local log files on muskie
servers to debug that.


## Debugging Manta housekeeping operations

Manta performs a number of housekeeping operations that are based on the
contents of the metadata tier, including garbage collection, auditing, metering,
and object rebalancing.  These are documented with the
[Mola](https://github.com/joyent/manta-mola) project, particularly under
["system
crons"](https://github.com/joyent/manta-mola/blob/master/docs/system-crons.md).
In summary: a pipeline gets kicked off daily that saves database dumps of the
metadata tier into Manta itself and then uses normal Manta jobs to first unpack
these dumps and then process them for these various purposes.  If any of these
steps fails, manual intervention may be required to complete these operations.

If the pipeline has failed, it's important to figure out why.  In practice, the
most common reason is that the database dumps were not uploaded on time.  The
[manta-hk](https://github.com/joyent/manta-hk) tool is provided to help figure
this out.  Its [manual
page](https://github.com/joyent/manta-hk/blob/master/docs/man/manta-hk.md)
describes its usage.

**When this pipeline has failed, use the manta-hk tool to determine whether
database dumps were successfully uploaded, and early enough for the rest of the
pipeline to complete.**

Under the hood, manta-hk checks for database dumps that are normally uploaded to
`/poseidon/stor/manatee_backups` by the async peer of each shard.  It also
checks for the objects that normally get unpacked into the same directory, which
may look like this (though the set of objects differs based on what the shard is
being used for):

    # mls /poseidon/stor/manatee_backups/2.moray.us-east.joyent.us/2015/06/02/00
    buckets_config-2015-06-02-00-00-33.gz
    manta-2015-06-02-00-00-33.gz
    manta_delete_log-2015-06-02-00-00-33.gz
    manta_directory_counts-2015-06-02-00-00-33.gz
    medusa_sessions-2015-06-02-00-00-33.gz
    moray-2015-06-02-00-00-33.gz

When something has failed, you'll typically find one of a few situations:

* The database dumps themselves are missing.  ("manta-hk" should point this out
  explicitly, but the symptom is that there's no "moray-\*.gz" object in this
  directory, or the directory doesn't exist at all.)
* The database dumps are present, but the unpacked files are missing.  (Again,
  "manta-hk" points this out explicitly.)  If the dump is present, then this
  usually happens because the dump did not complete on-time for the unpacking
  job.  It's also possible that the unpacking job failed for some other reason.

The following sections describe how to resolve both of these situations.  Either
way, when you've resolved that problem, you'll need to rerun the rest of the
pipeline.  That's also described below.


### When a database dump is missing

Manatee takes and keeps several ZFS snapshots for the purposes of disaster
recovery.  These snapshots can be used to save a new database dump to replace
one that may have failed.

1. On any peer in the shard, use `manatee-adm peers` to see which peer is the
   async and log into that peer.
1. List the ZFS snapshots to identify the snapshot you want to use to regenerate
   the dump. This command is useful to generate human-readable timestamps:

        for i in $(zfs list -H -t snapshot | tail -100 | cut -f1); do node -e "console.log(\"$i\", new Date(+\"$i\".split('@')[1]).toISOString())"; done

1. Run the `pg_custom_dump.sh` script located in the manatee directory using the
   identified snapshot.

        /opt/smartdc/manatee/pg_dump/pg_custom_dump.sh zones/a5fa2966-0dd5-40ac-9a63-14d91343c196/data/manatee@1421885974910

When this completes, you'll need to proceed to the next section as well.


### When the database dump was not unpacked

If the database dump is present, but none of the other objects are present, then
the dump was not successfully unpacked.  You can kick off a job to do this by
running a command like this one from the "ops" zone:

    # /opt/smartdc/mola/bin/kick_off_pg_transform.js -b /poseidon/stor/manatee_backups/2.moray.us-east.joyent.us/2015/06/02/00/moray-2015-06-02-00-00-37.gz 2>&1 | bunyan

The argument for the "-b" option is the name of the database dump object in
Manta.  You'll need to run this command for each dump that you want to unpack
(i.e., for each shard).


### Running the rest of the pipeline

If you had to manually trigger a database dump or a dump unpacking job, then
it's likely that the daily metering, garbage collection, audit, and cruft jobs
will have failed.  Garbage collection, auditing, and cruft jobs are not
time-sensitive, and generally do not need to be re-run by hand because you can
wait for the next day's run to complete.  If you want to re-run them by hand,
see the documentation in the Mola subproject.

The metering jobs, however, should generally be re-run by hand.  Rerun a
metering job using the "meter" command inside the "ops" zone, specifying a
specific date.  Metering scripts poll for job completion in order to create the
"latest" link once the job is done. If the "latest" link is not necessary, you
can interrupt the metering script after job input has been closed.

    /opt/smartdc/mackerel/bin/meter -j "storage" -d "2015-06-02" 2>&1 | bunyan
    /opt/smartdc/mackerel/bin/meter -j "request" -d "2015-06-02T05:00:00" 2>&1 | bunyan
    /opt/smartdc/mackerel/bin/meter -j "compute" -d "2015-06-02T07:00:00" 2>&1 | bunyan
    /opt/smartdc/mackerel/bin/meter -j "accessLogs" -d "2015-06-02T11:00:00" 2>&1 | bunyan
    /opt/smartdc/mackerel/bin/meter -j "summarizeDaily" -d "2015-06-02" 2>&1 | bunyan

Note that the "summarizeDaily" job depends on the output of the "storage",
"request" and "compute" jobs from the previous day. If any of the previous
day's jobs were incomplete, the "summarizeDaily" job will have to be re-run
after the previous day's metering data has been generated using the above steps.

## Authcache (mahi) issues

Please see the docs included in the mahi repository.

# Debugging Marlin: distributed state

The "mrjob" and "mrerrors" tools summarize Marlin state by reading it directly
from Moray.  This is usually the first step towards figuring out what's going on
with Marlin overall or with a particular job.  You should be able to run these
tools directly from the "ops" zone, but you can also set them up by cloning the
marlin.git repo and running "npm install" to build the tools.  Some examples
below use the Moray client tools, which should also be available if you follow
the above procedure.


## List running jobs

Use `mrjob list -s running`:

    ops$ mrjob list -s running
    JOBID                                LOGIN          S NOUT NERR NRET NDISP NCOMM
    b1f8c8ce-8afe-445e-8846-484ac908ebd0 jason          R    0    0    0     1     0

## List recently completed jobs

Use `mrjob list -t 60`, where "60" is the number of seconds back to look:

    ops$ mrjob list -t 60
    JOBID                                LOGIN          S NOUT NERR NRET NDISP NCOMM
    ed4eff3c-5e2e-4fcb-ad67-3ac09629056f jason          D    1    0    0   485   485

## Fetch details about a job

Use `mrjob get`:

    ops$ mrjob get a2922490-c8de-e4b3-abbc-f3367464b651
           Job a2922490-c8de-e4b3-abbc-f3367464b651
      Job name interactive compute job
          User thoth (aed35417-4c53-4d6c-a127-fd8a6e55723b)
         State running
    Supervisor dd55ea98-9dc9-4b57-84ab-380ba5252fed
       Created 2014-01-16T22:22:49.173Z (1h10m12.679s ago)
      Progress 1 inputs read, 1 tasks dispatched, 0 tasks committed
       Results 0 outputs, 0 errors, 0 retries
       Pending 0 uncommitted done, 0 intermediate objects
       Phase 0 map

You can use `-p` to get details about what the job runs in each phase:

    ops$ mrjob get -p a2922490-c8de-e4b3-abbc-f3367464b651
           Job a2922490-c8de-e4b3-abbc-f3367464b651
      Job name interactive compute job
          User thoth (aed35417-4c53-4d6c-a127-fd8a6e55723b)
         State running
    Supervisor dd55ea98-9dc9-4b57-84ab-380ba5252fed
       Created 2014-01-16T22:22:49.173Z (1h11m00.527s ago)
      Progress 1 inputs read, 1 tasks dispatched, 0 tasks committed
       Results 0 outputs, 0 errors, 0 retries
       Pending 0 uncommitted done, 0 intermediate objects
       Phase 0 map
         asset /poseidon/public/medusa/agent.sh
         asset /thoth/stor/medusa-config-fa937d4b-f699-4f1b-bea5-69147fa97977.json
         asset /thoth/stor/thoth/analyzers/.thoth.87707.1389910968.355
          exec "/assets/poseidon/public/medusa/agent.sh"

See `mrjob --help` for more options.

If the job completed more than 24 hours ago, then mrjob may report an error
like:

    ops$ mrjob get 43a9949b-4fab-4037-a32a-371146ac44f9
    mrjob: failed to fetch job: failed to fetch job: marlin_jobs_v2::43a9949b-4fab-4037-a32a-371146ac44f9 does not exist

That's because jobs are removed from the live database about 24 hours after they
complete.  In that case, see "Fetching information about older jobs".

## List job inputs, outputs, retries, and errors (as a user would see them)

All of these are capped at 1000 results by default.

`mrjob inputs JOBID`: list input objects for a job (capped at 1000)

`mrjob outputs JOBID`: list output objects from a job (capped at 1000)

`mrjob errors JOBID`: list retries from a job (capped at 1000)

`mrjob retries JOBID`: list retries from a job (capped at 1000)

## Fetch summary of errors for a job

Use `mrerrors -j JOBID`.  The output includes internal error messages and
retried errors, which are not exposed to end users.

## List tasks not-yet-completed for a given job (and see where they're running)

Use `mrjob where` to list uncompleted tasks and see where they're running:

    ops$ mrjob where e493ab87-fcf0-e991-8b82-8f649696d197
    TASKID                               PH       NIN SERVER
    6ce64b78-691b-4703-970a-de2fb84b69f1  0         - 1.cn.us-east.joyent.us
         map: /dap/stor/mdb.log

Note that physical storage nodes in Manta are identified by mantaComputeId
rather than server\_uuid or hostname.  You need to translate this to figure out
which physical server that corresponds to.

## See the history of a given task

You may find a task through `mrjob get` or `mrjob where` and want to know its
history: what inputs or previous-phase tasks caused this task to be created?  Is
it a retry of a previous task?  How many times was it retried, and on which
hosts?  `mrjob taskhistory` helps answer these questions.

The point of this tool is to show two things: how a given input moved through
multiple phases in Marlin, and how individual tasks are retried.  The goal is
that given any taskid, it will find predecessors in previous phases,
predecessors in the same phase (retries), successors in the same phase
(retries), and successors in subsequent phases.  The main thing it doesn't do
is go *through* reduce phases, because that's usually counter-productive and in
general it's not possible to correlate inputs with outputs across a reduce
phase.

Here's an example usage.  I ran this job (note the phases):


    ops$ mrjob get -p ea784e03-a735-cd29-d913-b1b9cb5f0503
           Job ea784e03-a735-cd29-d913-b1b9cb5f0503
          User dap (ddb63097-4093-4a74-b8e8-56b23eb253e0)
         State done
    Supervisor eff884b4-f678-4069-8522-1bbe2e4fcb90
       Created 2014-01-17T19:22:02.326Z (16m38.446s ago)
          Done 2014-01-17T19:22:35.110Z (32.784s total)
      Archived 2014-01-17T19:22:38.064Z (16m02.708s ago)
      Progress 100 inputs read, 242 tasks dispatched, 242 tasks committed
       Results 15 outputs, 0 errors, 12 retries
       Phase 0 map
          exec "wc"
       Phase 1 map
          exec "wc"
       Phase 2 reduce (15)
          exec "wc"
       Phase 3 map
          exec "wc"


So it's 100 inputs -> map -> map -> 15 reducers -> map.  Because Marlin is
currently disabled on 9.stor in production, there were retries in both map
phases and reduce phases, so this is a good example to show what
`mrjob taskhistory` does.  I used `mrjob get -t` to find some of these tasks,
although if a job was currently stuck, you could also use `mrjob where`.

Here's a normal history for one of the first phase tasks:


    ops$ mrjob taskhistory 33b7f617-141e-4673-8056-a27a6f511b60
    2014-01-17T19:22:02.814Z  jobinput   318ed0ad-8aed-4f74-af90-a7cfefc87880
        /dap/stor/datasets/cmd/cmd/acct/acctcms.c

    2014-01-17T19:22:03.746Z  map task   33b7f617-141e-4673-8056-a27a6f511b60
                                         (attempt 1, host 11.cn.us-east.joyent.us)
        /dap/stor/datasets/cmd/cmd/acct/acctcms.c

    2014-01-17T19:22:04.142Z  taskoutput b9bb82de-416d-4ac3-a962-09f75a140932
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/acct/acctcms.c.0.33b7f617-141e-4673-8056-a27a6f511b60

    2014-01-17T19:22:08.663Z  map task   1b370599-90b3-4c03-a388-c8967798d396
                                         (attempt 1, host 25.cn.us-east.joyent.us)

    2014-01-17T19:22:09.078Z  taskoutput c98b68d1-1b76-4adf-845c-f7392d860694
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/acct/acctcms.c.1.1b370599-90b3-4c03-a388-c8967798d396

    2014-01-17T19:22:13.398Z  taskinput  1d4cf4de-9c4c-4841-b801-0595f69b2ff0
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/acct/acctcms.c.1.1b370599-90b3-4c03-a388-c8967798d396

    2014-01-17T19:22:02.447Z  reducer    015f6dbb-8bb3-4b07-b806-12bdf46fd8a8
                                         (attempt 1, host 11.cn.us-east.joyent.us)
                                         4 inputs

This shows the jobinput that created the task, the output from the task that
created the next map task, the output from that task that becamse a taskinput
for the reducer, and the reducer.  For each task, it shows the host assigned to
run it.  You'd get the exact same output if you specified tasks
1b370599-90b3-4c03-a388-c8967798d396 or 015f6dbb-8bb3-4b07-b806-12bdf46fd8a8.

Here's an example where one of the early phase map tasks failed and had to be
retried:


    ops$ mrjob taskhistory a322ebe6-3279-40ee-8c7e-88130def17b4
    2014-01-17T19:22:03.220Z  jobinput   5f72c373-9155-459e-9032-0ac18ecaef6a
        /dap/stor/datasets/cmd/cmd/addbadsec/addbadsec.c

    2014-01-17T19:22:03.660Z  map task   a322ebe6-3279-40ee-8c7e-88130def17b4
                                         (attempt 1, host 9.cn.us-east.joyent.us)
        /dap/stor/datasets/cmd/cmd/addbadsec/addbadsec.c

    2014-01-17T19:22:06.411Z  error      bb08a232-75d6-4b59-a80c-3f369f84d64a
                                         InternalError
                                         internal error: agent timed out

    2014-01-17T19:22:07.551Z  map task   e4c80edb-5302-4f6f-af19-336be9834e92
                                         (attempt 2, host 26.cn.us-east.joyent.us)
        /dap/stor/datasets/cmd/cmd/addbadsec/addbadsec.c

    2014-01-17T19:22:07.679Z  taskoutput c79dc94d-5800-4e59-b808-998c94024c2f
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/addbadsec/addbadsec.c.0.e4c80edb-5302-4f6f-af19-336be9834e92

    2014-01-17T19:22:12.279Z  map task   c6cbe67f-2c9d-4c50-ae0c-53590303f544
                                         (attempt 1, host 19.cn.us-east.joyent.us)

    2014-01-17T19:22:12.529Z  taskoutput 70275969-c92f-4700-96c2-9564158be0b2
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/addbadsec/addbadsec.c.1.c6cbe67f-2c9d-4c50-ae0c-53590303f544

    2014-01-17T19:22:15.271Z  taskinput  22b96b55-86f2-43a1-9271-9a9334726a61
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/addbadsec/addbadsec.c.1.c6cbe67f-2c9d-4c50-ae0c-53590303f544

    2014-01-17T19:22:02.447Z  reducer    6e009faa-a0d8-478a-9b66-ae82852fbf45
                                         (attempt 1, host 25.cn.us-east.joyent.us)
                                         7 inputs

In this case, we see the map task we asked about, the error it produced, and the map retry task below it on a different host.

Here's what happens when we select a reducer that failed:

    ops$ mrjob taskhistory 3ac67932-75ba-4ce0-891e-1b295949a3be
    2014-01-17T19:22:02.447Z  reducer    3ac67932-75ba-4ce0-891e-1b295949a3be
                                         (attempt 1, host 9.cn.us-east.joyent.us)
                                         input stream open

    2014-01-17T19:22:06.424Z  error      c3923a5f-93ea-425e-92c3-694b6bf08b3d
                                         InternalError
                                         internal error: agent timed out

    2014-01-17T19:22:07.542Z  reducer    c98bd373-6c08-4032-b405-bf0a0e18f820
                                         (attempt 2, host 12.cn.us-east.joyent.us)
                                         9 inputs

We don't see any of the previous or subsequent phase tasks because
"taskhistory" doesn't cross reduce phases.  (That would usually degenerate to
showing everything in the job, which isn't useful here.)

Here's a particularly complicated case.  The input went through two normal map
phases, then became a taskinput to the *second* attempt for a reducer.  We
still show the first reducer here in the output, but it shows up before the
taskinput, indicating that the first reducer failed logically before this
object was assigned to the reducer, so it was assigned directly to the second
attempt:

    ops$ mrjob taskhistory 94851372-49b9-48fd-b5ca-b51b330561ab
    2014-01-17T19:22:03.024Z  jobinput   237d6925-75e4-4a0a-9186-cd214b510e6a
        /dap/stor/datasets/cmd/cmd/acct/acctwtmp.c

    2014-01-17T19:22:03.633Z  map task   4906e7b9-c65e-4655-95d0-5bdcbda62b39
                                         (attempt 1, host 26.cn.us-east.joyent.us)
        /dap/stor/datasets/cmd/cmd/acct/acctwtmp.c

    2014-01-17T19:22:04.164Z  taskoutput 41dd8fac-2923-42ec-a893-43318596472b
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/acct/acctwtmp.c.0.4906e7b9-c65e-4655-95d0-5bdcbda62b39

    2014-01-17T19:22:07.380Z  map task   94851372-49b9-48fd-b5ca-b51b330561ab
                                         (attempt 1, host 293.cn.us-east.joyent.us)

    2014-01-17T19:22:07.604Z  taskoutput 5cbb34ab-a0f4-4144-9629-629d323cc1f0
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/acct/acctwtmp.c.1.94851372-49b9-48fd-b5ca-b51b330561ab

    2014-01-17T19:22:02.447Z  reducer    660f7838-4055-49b3-8376-dec9648ec2a5
                                         (attempt 1, host 9.cn.us-east.joyent.us)
                                         input stream open

    2014-01-17T19:22:06.397Z  error      4263bcc0-3a5e-433b-9460-b5970044cb51
                                         InternalError
                                         internal error: agent timed out

    2014-01-17T19:22:12.279Z  taskinput  686236b8-1de2-4ef6-aa6b-e4f908c2497a
        /dap/jobs/ea784e03-a735-cd29-d913-b1b9cb5f0503/stor/dap/stor/datasets/cmd/cmd/acct/acctwtmp.c.1.94851372-49b9-48fd-b5ca-b51b330561ab

    2014-01-17T19:22:07.539Z  reducer    318b47e5-a234-4fa0-b11e-e80701cfc90d
                                         (attempt 2, host 9.cn.us-east.joyent.us)
                                         input stream open

    2014-01-17T19:22:11.437Z  error      681faf97-2ae5-4938-89a8-d422e7156d11
                                         InternalError
                                         internal error: agent timed out

    2014-01-17T19:22:12.689Z  reducer    721187a7-5df1-4ce1-9c3b-9e54ffd71cce
                                         (attempt 3, host 20.cn.us-east.joyent.us)
                                         6 inputs

## Using the Moray tools to fetch detailed state

Sometimes it's necessary to dig into the Moray state directly because "mrjob"
doesn't have a subcommand to fetch exactly what you want.  Please file tickets
for such things, but in the meantime, you can use the Moray client tools to
extract state directly.  The Moray client tools should be available on your
PATH if you've set up the Marlin tools.

## Figuring out which jobsupervisor is managing a job

You can find the jobsupervisor that's managing a job with:

    ops$ getobject marlin_jobs_v2 994703de-0c5c-49e8-ba98-8361d1624ae1 | \
        json value.worker
    4fdcffe8-30ef-476e-8266-279a241c76c0

where 994703de-0c5c-49e8-ba98-8361d1624ae1 is the jobid.

The returned value is the zonename of the jobsupervisor that *normally* manages
the job.  In most cases, this is also the jobsupervisor that's currently
managing the job.  However, it's possible for one jobsupervisor to take over for
another.  You can check this with:

    ops$ findobjects marlin_health_v2 instance=4fdcffe8-30ef-476e-8266-279a241c76c0 | \
        json value
    {
      "component": "worker",
      "instance": "4fdcffe8-30ef-476e-8266-279a241c76c0",
      "generation": "2013-07-02T16:23:36.810Z"
    }

This case indicates that the supervisor is functioning normally.  If one
supervisor takes over for another, you'll see an "operatedBy" field with the
uuid of the supervisor that's taken over for this supervisor.

# Debugging Marlin: storage nodes

## Figuring out what's running

mrjob only shows overall system state.  Once a task is issued to a server, you
have to contact the agent running on that server to figure out the status.  The
dashboard shows running groups and streams, but you can get more information by
logging into the box and running the "mrgroups" and "mrzones" tools.
Continuing the above example, 25.cn.us-east.joyent.us corresponds to MS08214 in
us-east-1, so we can log into that box and run `mrgroups`:

    [root@MS08214 (us-east-1) ~]# mrgroups
    JOBID                                PH NTASKS RUN SHARE  LOGIN
    4ff04c4d-4540-483d-94ca-d515320d2b9d  0      0   1      1 dap
    946587d1-3ef6-46d5-b139-186d59813f9d  3      1   0      1 poseidon

"Groups" refer to a bunch of tasks from the same job and phase.  A two-phase
job will have two groups on each physical server where it's running.  Each
group may have multiple "streams" associated with it, each corresponding to a
compute zone where tasks are running.  We can see these with:

    [root@MS08214 (us-east-1) ~]# mrgroups -s
    JOBID       PH ZONE                                 LAST START
    4ff04c4d...  0 1118c00b-4729-4c18-a289-f54afe2d9e9d 2013-07-02T22:16:17.746Z
    946587d1...  3 4836fd7b-d80d-4b2d-8519-8955ca5621ff 2013-07-02T22:20:30.068Z

In this simple case, each of the two jobs running on this box has one group,
and each group has one zone.  But in general:

* On a given box, you can have many groups for each job -- one for each phase.
* On a given box, for a given group, you can have many streams -- one for each
  zone that's been assigned to that group.

You can even see exactly what processes the user's job is running:

    [root@MS08214 (us-east-1) ~]# mrgroups -sv
    JOBID       PH ZONE                                 LAST START
    4ff04c4d...  0 1118c00b-4729-4c18-a289-f54afe2d9e9d 2013-07-02T22:16:17.746Z
      90397 ./node lib/agent.js
        90403 /bin/bash --norc

This is useful when a user complains of a hung job or something and you want to
go see exactly what it's doing.  The full procedure is:

* Use "mrjob" or "findobjects" to find the task of interest (usually, one of
  the only running tasks) and figure out which machine it's running on.
* ssh to the machine it's running on.
* Run `mrgroups -sv` to view running streams on that box and the processes
  they're running
* Use truss, DTrace, or whatever other tools you usually use for inspecting
  process state -- with the usual caveats about interfering with production
  systems.

The user task's stdout and stderr are saved to /var/tmp/marlin\_task inside the
zone.  These are the stdout and stderr files that will be saved to Manta when
the task completes, so do not modify or remove them!


## Figuring out what ran in the past

After the job has completed, all we save is the lackey log (see above).  That's
currently saved for a few days in the global zone, under
/var/smartdc/marlin/log/zones.  Files are named JOBID.PHASENUM.UUID.  The usual
way to find the right one is to find the taskId that you're debugging as
described above, and then:

    shrimp-gz$ grep -l TASKID /var/smartdc/marlin/log/zones/JOBID.*

That usually returns pretty quickly, and you can view the file with bunyan(1).

Lackey logs are not currently rotated up to Manta.  They are removed after a
few days.


# Debugging Marlin: anticipated frequent issues

## Users want more information about job progress

The "mjob get" output for a job includes a count of tasks issued and tasks
completed.  This can be used to measure progress.  If you've got a 100-object
map job where each input produces one output, there will be 100 tasks issued,
and when they all complete, the job is done.  If you tack on a second phase to
that job with count=2 reducers, there will be 102 tasks, and so on.

In general, the user can figure out how many tasks a job *should* have, but
Manta can't necessarily infer this in many cases.  That's because each task can
emit any number of output objects.  So if you have a two-phase map-map job and
feed in 100 inputs, you could emit 1, 2, 5, or 100 outputs from *each* task in
the first phase, and Manta has know way to know.  That's why the only progress
Manta provides is number of tasks issued and number of tasks completed, from
which a user may be able to compute their own measure of progress.


## Users observe non-zero count of errors from "mjob get"

See "Fetch summary of errors for a job" above.  Most error messages should be
pretty self-explanatory, but some of the more complicated ones are described
below.


## Users observe non-zero count of retries from "mjob get"

Besides the "tasks issued", "tasks completed", and error counters, the "mjob
get" output for a job also shows a count of retries.  These aren't generally
actionable for users except to explain latency.

Retries represent internal failures that the system believes may be transient.
There are currently three causes:

* An agent crashed.  This is the most common.  When an agent crashes, all tasks
  that were running or queued on that system are retried, preferably on other
  systems.  There may be a latency hit for restarting or requeueing the task,
  but it shouldn't impact correctness.
* An agent failed to heartbeat for a full minute, possibly a result of a system
  panic, network partition, or excessive load.  The same thing happens as for an
  agent crash.
* The user hits a condition where Marlin allocated a large number of zones to
  the job, but later decided to forcibly take some of those zones back.

You can find out exactly what caused the retries using "mrerrors -j JOBID".  See
"Fetch summary of errors for a job" above.

## User observes job in "queued" state

Jobs enter the "queued" state when they're submitted, but should move to
"running" very quickly, even if Manta's compute resources are all tied up.  If
jobs remain in state "queued" for more than a minute, there are several things
to check:

* Run a simple no-op job, like "mjob create -m wc &lt; /dev/null".  That job
  should complete within a second or two without dispatching any tasks.  If it
  does, there's likely something invalid about the user's job that the system
  failed to handle properly.  Check the corresponding jobsupervisor's log (see
  "Figuring out which jobsupervisor is managing a job").
* If that test job remains queued for a minute, check that the jobsupervisor
  services are healthy (namely, that the SMF service is running, not in
  maintenance).  If they're maintenance, try clearing one.  If it comes up, it
  should pick up your test job and run it.
* If any jobsupervisors are healthy but all jobs are still queued, check the
  supervisor logs for recent errors (with "bunyan -lerror").  It's likely that
  they're not able to connect to the Marlin Moray shard, in which case the next
  step is to check whether Moray is working.


## Job hung (not making forward progress)

A job is making forward progress if any of the counters shown by "mjob get" are
incremented over time.  If the counters stay steady, there may be a Marlin
issue, but there may also be a user error or simply a long-running task.

* The first thing to check is whether the user has ended the input stream.
  "mjob get" will report "inputDone": true once the input stream has been ended.
  If the input stream is not ended, Marlin is waiting for the user to submit
  inputs.
* Check if there are any tasks outstanding.  See "List tasks not-yet-completed
  for a given job", and then investigate with "Figuring out what's running".
* If nothing's running, check that the jobsupervisor responsible for this job is
  healthy.  See "Figuring out which jobsupervisor is managing a job".


## Poor job performance

Alongside "mrjob" and "mrerrors" is a tool called "mrjobreport" which prints out
a summary of time spent processing a job.  This can be used to tell where time
was spent: dispatching tasks, queued behind other tasks, executing, or
committing the results.  It can also identify the slowest tasks.  You can then
look at the lackey log from those jobs to figure out why they took so long.

For smaller jobs, you can also use "mrjob log JOBID", which prints out a log of
everything that happened for a job.  You can use this to find long periods where
nothing happened.


## Error: User Task Error (for unknown reason)

User task errors usually indicate that the user's script either exited with a
non-zero status, or one of the user's processes dumped core.  The error message
should generally be pretty clear, and where appropriate should have a link to
the stderr and core file.  (Stderr is not saved for successful tasks.)

If a user can't figure out why their bash script exited with non-zero status,
check if they're running afoul of bash's pipeline exit semantics.  From bash(1):

    The  return  status of a pipeline is the exit status of the last com-
    mand, unless the pipefail option is enabled.  If pipefail is enabled,
    the  pipeline's  return  status  is the value of the last (rightmost)
    command to exit with a non-zero status, or zero if all commands  exit
    successfully.

Users likely want to be setting pipefail, which you can do using "set -o
pipefail" right in the bash script.


## Error: Task Init Error

There are several common causes of TaskInitErrors, and the error message should
generally be clear in each case:

* an asset failed to be downloaded (the HTTP status code will be included in
  the error message)
* the user had an "init" script which either returned a non-zero exit status or
  dumped core
* Requested image is not available: this is supposed to be emitted when the user
  asks for an image that is not supported using the "image" property of a job.
  If the user did not ask for any image, see below.
* Not enough memory available: the user asked for more memory than the default,
  and all of the memory on the system they were assigned to was spoken for.
  The task may succeed later.  We should be keeping track of these stats so
  that we can see if we need to allocate more memory to Marlin.
* Not enough disk available: same as memory, but for disk.

Note that the memory and disk errors are different from the similar
UserTaskErrors "user task ran out of memory" and "user task ran out of local
disk space", which mean that the task actually did run, but bumped up against
the requested limits.  The user should ask for more memory or disk,
respectively.

More esoteric errors indicate more serious Marlin issues:

* "Requested image is not available," and the user did not request any
  particular image.  We've seen this in cases where the Marlin agent was enabled
  on a node *other* than a Manta storage node (e.g., a CN hosting the metadata
  services).  Audit that the only instances of marlin-agent enabled in the whole
  fleet are the ones on the Manta storage nodes (shrimps).


## Error: Internal Error

Users should never see internal errors.  Transient ones are generally retried,
and persistent ones often represent serious issues.  Use "mrerrors -j JOBID" to
see the details, including the internal error message.

The most common cause is "lackey timeout".  This can be a result of user error
(e.g., if the user pstops the lackey, or kills it, possibly by trying to halt
the zone), or it can indicate that the lackey crashed.  Look for core files in
the zone and file a bug.  You can also look in the lackey log to see why it
crashed.

One error we've seen is ": not connected: ".  This is issued by a jobsupervisor
when attempting to locate an object, but when it fails to contact the
electric-moray service.  Check supervisor health, look for errors in the log,
and check whether electric-moray is online.


## Zones not resetting

There have been a few bugs where Marlin zone resets hang.  For a single zone,
this just reduces capacity, usually by an immeasurable amount.  In some cases,
this ends up affecting all zones on a system, in which case forward progress for
nearly all jobs can be impacted.  These situations are always bugs, and if
possible they should be root-caused so they can be fixed.  There are open
tickets for improving the system's resilience to this kind of problem.

When you suspect a particular zone's reset is hung (e.g., because it's been
resetting for at least 10 minutes), log into the GZ of that system and look at
processes in the Marlin agent service.  Here's what a normal service looks like:

    [root@RA10146 (staging-1) ~]# svcs -p marlin-agent
    STATE          STIME    FMRI
    online         Sep_15   svc:/smartdc/agent/marlin-agent:default
                   Sep_15      27668 node
                   Sep_15      28118 node

The marlin agent normally comprises two node processes, and their STIME
indicates when they started.  If you see a number of other processes that have
been running for several minutes, that's generally a sign that things are in
bad shape.  Here's an example:

    [root@RM08211 (us-east-2) ~]# svcs -p marlin-agent
    STATE          STIME    FMRI
    online         Dec_20   svc:/smartdc/agent/marlin-agent:default
                   16:54:16    15450 vmadm
                    9:47:17    20230 zfs
                   Dec_20      95665 node
                   Dec_20      95666 node

This output shows that the "zfs" process has been hung for at least 7 hours.
At that point, the next step in root cause analysis would be to understand why
the "zfs" process is hung using the usual tools (ps(1), pstack(1), pfiles(1),
mdb(1), and so on).  The details depend on the specific bug you've found.

This is just an example.  The hung process may be something other than "zfs".

For some pathologies, a zone reset may be hung without an associated process.
This can happen when a zone fails to boot properly.  In this case, use the Kang
output from the Marlin agent to see what stage of boot is hung.  See "Kang
state" below.  For example, you may see a zone's kang state that looks like
this:

        "070fbff6-1579-4147-a539-b43b3aa54306": {
          "zonename": "070fbff6-1579-4147-a539-b43b3aa54306",
          "state": "uninit",
          "pipeline": {
            "operations": [
              {
                "funcname": "maZoneCleanupServer",
                "status": "ok"
              },
              ...
              {
                "funcname": "maZoneReadyBoot",
                "status": "ok",
                "err": null,
                "result": ""
              },
              {
                "funcname": "maZoneReadyWaitBooted",
                "status": "pending"
              },

The "Boot" stage, which issues the command to boot the zone, has completed
successfully.  The "WaitBooted" stage is "pending".  This output indicates that
Marlin is waiting for the zone to boot up.  It's worth checking that Marlin
really is watching the zone's state (and hasn't somehow forgotten about it).
The easiest way to do that is to use a D script to watch processes that the
agent forks, like this:

    # dtrace -n 'exec-success/ppid == 95665 || ppid == 95666/{ printf("%s", curpsinfo->pr_psargs); }'
    dtrace: description 'exec-success' matched 1 probe
    CPU     ID                    FUNCTION:NAME
      8  14952         exec_common:exec-success svcs -H -z 070fbff6-1579-4147-a539-b43b3aa54306 -ostate milestone/multi-user:de
     19  14952         exec_common:exec-success svcs -H -z 070fbff6-1579-4147-a539-b43b3aa54306 -ostate milestone/multi-user:de

(You'll need to replace the two ppid conditions with the two Marlin agent
processes on your system.)  We can see from this output that Marlin *is*
checking the status of that zone as expected, so the problem is that the zone
isn't coming up.  Again, the next step depends on the specific bug you've run
into.


# Debugging Marlin: Zones

## Clearing Disabled Zones

On occasion, a compute zone may transition to the "disabled" state.  These zones
appear red on the Marlin dashboard and mrzones will report the same:

    [root@RM08211 (us-east-2) ~]# mrzones
       5 busy
       1 disabled
     122 ready
       1 uninit

Use `mrzones -x` to determine the reason for the zone being disabled:

    [root@RM08211 (us-east-2) ~]# mrzones -x
    3cf7ccc4-4da2-4a0a-b111-ef4e0c2e04cc (since 2014-07-25T03:00:28.001Z)
        zone not ready: command "zfs rollback zones/3cf7ccc4-4da2-4a0a-b111-ef4e0c2e04cc@marlin_init" failed with stderr: cannot open 'zones/3cf7ccc4-4da2-4a0a-b111-ef4e0c2e04cc@marlin_init': dataset does not exist : child exited with status 1

Alternatively, the Marlin Dashboard lists the disabled zones and the cause under
the "Disabled Zones" tab on the bottom section.  Common problems and solutions
are listed below.

**zone not ready: command "zfs rollback zones/[zonename]@marlin_init" failed with
 stderr: cannot open 'zones/zonename@marlin_init': dataset does not exist :
 child exited with status 1**

This is an aborted zfs create/destroy.  The solution is to `manta-undeploy`
the zone and `manta-deploy` a new one.

**zone failed (lackey timed out)**

Usually a lackey timeout can be fixed by re-registering the zone with
the marlin agent.  From the global zone where the disabled zone is, run:

    mrzone [zonename]

Alternatively, you can `manta-undeploy` and `manta-deploy` a new one on that
compute node.




# Controlling Marlin

Occasionally it may be necessary or desirable to modify the running Marlin
system.

## Cancel a running job

Use `mrjob cancel JOBID`, which produces no output on success.  This is a last
resort option for jobs that have run amok.  Any time this is necessary, there's
likely an underlying software bug that needs to be filed and fixed.

## Deleting a job

In rare instances (always involving a serious Marlin bug), the presence of a job
may disrupt the system so much that cancelling it is not tenable or not
sufficient to stabilize the system.  In such cases, it's possible to delete the
job, which removes all records associated with the job from Moray.

If the job has already been completed and archived (has "timeArchiveDone" set),
deleting a job has only a small user-facing impact: the user will no longer be
able to fetch inputs, outputs, errors, and so on from the "live" API.  They will
be able to fetch them through the archived objects (in.txt, out.txt, and so on).
See the user-facing REST API documentation for details.  This transition happens
anyway for all jobs after a few hours; deleting an archived job only has the
effect of making this transition happen immediately.

**If the job has not been completed or has not been archived, deleting the job
will result in data loss for the user.**  In particular, the inputs, outputs,
errors, and so on will all be lost permanently.  **This can also have an
unpredictable impact on the rest of Marlin, which is not designed to have state
removed while a job is running.**  This operation should be used with extreme
care, and likely only in emergencies.

To delete a job, use `mrjob delete JOBID`.  Be sure to have read the above
caveats.

## Quiescing a supervisor

It's possible to *quiesce* a supervisor, which causes that supervisor to
continue processing whatever jobs it's working on, but to avoid picking up new
jobs.  This is useful when the supervisor is being removed from service (as
during some upgrades), or in cases where the supervisor has become clogged due
to a bug but is still picking up new jobs (that are then becoming hung).

The "mrsup" command can be used to both quiesce and unquiesce a supervisor.
These commands produce no output on success, but cause entries to be written to
the supervisor log.  The quiesce state is not persistent, so if the supervisor
crashes or restarts for another reason, it will start picking up new jobs when
it comes up again.





# Advanced deployment notes

These notes are intended primarily for developers.

## Size Overrides

Application and service configs can be found under the `config` directory in
manta-deployment.git.  For example:

    config/application.json
    config/services/jobsupervisor/service.json
    config/services/webapi/service.json

Sometimes it is necessary to have size-specific overrides for these services
within these configs that apply during setup.  The size-specific override
is in the same directory as the "normal" file and has `.[size]` as a suffix.
For example, this is the service config and the production override for the
jobsupervisor:

    config/services/jobsupervisor/service.json
    config/services/jobsupervisor/service.json.production

The contents of the override are only the *differences*.  Taking the above
example:

    $ cat config/services/jobsupervisor/service.json
    {
      "params": {
        "networks": [ "manta", "admin" ],
        "ram": 256
      }
    }
    $ cat config/services/jobsupervisor/service.json.production
    {
      "params": {
        "ram": 16384,
        "quota": 100
      }
    }

You can see what the merged config with look like with the
`./bin/manta-merge-config` command.  For example:

    $ ./bin/manta-merge-config -s coal jobsupervisor
    {
      "params": {
        "networks": [
          "manta",
          "admin"
        ],
        "ram": 256
      }
    }
    $ ./bin/manta-merge-config -s production jobsupervisor
    {
      "params": {
        "networks": [
          "manta",
          "admin"
        ],
        "ram": 16384,
        "quota": 100
      }
    }

Note that after setup, the configs are stored in SAPI.  Any changes to these
files will *not* result in accidental changes in production (or any other
stage).  Changes must be made via the SAPI api (see the SAPI docs for details).


## Development tools

Downloading the images take a long time, so in the manta-deployment repository
there's the tools/install_marlin_image.sh script.  This script:

    manta$ ./tools/install_marlin_image.sh <machine>

will download the latest marlin image from updates.joyent.com, save it on that
machine on which the script is run, and copy it to the machine's IMGAPI.  On
subsequent runs, this script will copy the image from the local machine and
avoid downloading it again from updates.joyent.com.  Because the manta-compute
image is larger than all other images combined, using install_marlin_image.sh
will shorten the development cycle.

To update the manta-deployment zone on a machine with changes you've made to
sdc-manta:

    sdc-manta.git$ ./tools/update_manta_zone.sh <machine>

To see which manta zones are deployed, use manta-adm show:

    headnode$ manta-adm show

To tear down an existing manta deployment, use manta-factoryreset:

    manta$ manta-factoryreset

## Configuring NAT for Marlin compute zones

Recall that while we want users to be able to access the internet from Marlin
zones, we don't want to give each zone a public IP.  In production, we've
configured a hardware NAT on the private network that the compute zones use, but
in development, this connectivity is usually absent.  As a result, among other
things, mlogin(1) doesn't work.

If you want to set up NAT for your marlin compute zones in development, you can
do so by creating a NAT zone.  The following procedure is inspired by the
analogous [SmartOS
procedure](http://wiki.smartos.org/display/DOC/NAT+using+Etherstubs).

First, create a VMAPI CreateVM payload that looks like this:

    {
        "uuid": "49f6a6d6-82df-11e3-bb95-4f10bd8af0dd",
        "owner_uuid": "66bc8d77-2024-4a88-ba2a-e5e85e565059",
        "brand": "joyent",
        "ram": 256,
        "image_uuid": "01b2c898-945f-11e1-a523-af1afbe22822",
        "networks": [ {
                "name": "external",
                "primary": true
        }, {
                "name": "mantanat"
        } ],

        "alias": "forwarder",
        "hostname": "forwarder",
        "server_uuid": "00000000-0000-0000-0000-002590943378"
    }

**Be sure to make the following changes:**

* **uuid** should be a randomly-generated uuid (e.g., from the uuid(1) command)
* **owner_uuid** should be poseidon's uuid (i.e., from "sdc-ldap search
  objectclass=sdcperson")
* **server_uuid** should be your development server's uuid (e.g., "sdc-cnapi
  /servers | json -Ha uuid")

The **image_uuid** can be any reasonable SmartOS image.  The above example
uses smartos-1.6.3, since it's currently guaranteed to be available.

Once you've made those changes, you can create the VM with:

    $ sdc-vm create -f YOURFILE.json

Once the VM is provisioned, you'll want to explicitly enable IP spoofing in the
zone.  Construct an "update" file like this one:

    {
            "update_nics": [ {
                    "mac": "90:b8:d0:5f:bc:e4",
                    "allow_ip_spoofing": "1"
            }, {
                    "mac": "90:b8:d0:c4:87:54",
                    "allow_ip_spoofing": "1"
            } ]
    }

**Be sure to update the two "mac" properties based on the MACs assigned to the
zone you created above.**  See "vmadm get YOUR_VM_UUID | json nics".


## Configuration

Manta is deployed as a single SAPI application.  Each manta service (moray,
postgres, storage, etc.) has a corresponding SAPI service.  Every zone which
implements a manta service had a corresponding SAPI instance.

Within the config/ and manifests/ directories, there are several subdirectories
which provide the SAPI configuration used for manta.

    config/application.json     Application definition
    config/services             Service definitions
    manifests                   Configuration manifests
    manifests/applications      Configuration manifests for manta application

There's no static information for certain instances.  Instead, manta-deploy will
set a handful of instance-specific metadata (e.g. shard membership).


### Configuration Updates

Once Manta has been deployed there will be cases where the service manifests
must be changed.  Only changing the manifest in this repository isn't
sufficient.  The manifests used to configure running instances (new and old) are
the ones stored in SAPI.  The service templates in the zone are **not used after
initial setup**.  To update service templates in a running environment (coal or
production, for example):

1) Verify that your changes to configuration are backward compatible or that the
   updates will have no effect on running services.

2) Get the current configuration for your service:

    headnode$ sdc-sapi /services?name=[service name]

If you can't find your service name, look for what you want with the following
command:

    headnode$ sdc-sapi /services?application_uuid=$(sdc-sapi /applications?name=manta | \
      json -gHa uuid) | json -gHa uuid name

Take note of the service uuid and make sure you can fetch it with:

    headnode$ sdc-sapi /services/[service uuid]

3) Identify the differences between the template in this repository and what is
   in SAPI.

4) Update the service template in SAPI.  If it is a simple, one-parameter
   change, and the value of the key is a string type, it can be done like this:

    headnode$ sapiadm update [service uuid] json.path=value
    #Examples:
    headnode$ sapiadm update 8386d8f5-d4ff-4b51-985a-061832b41179 \
      params.tags.manta_storage_id=2.stor.us-east.joyent.us
    headnode$ sapiadm update update 0b48c067-01bd-41ca-9f70-91bda65351b2 \
      metadata.PG_DIR=/manatee/pg/data

If you require a complex type (an object or array) or a value that is not a
string, you will need to hand-craft the differences and `|` to `sapiadm`.  For
example:

    headnode$ echo '{ "metadata": { "PORT": 5040 } }' | \
      sapiadm update fde6c6ed-eab6-4230-bb39-69c3cba80f15

Or if you want to "edit" what comes back from sapi:

    headnode$ sapiadm get [service uuid] | json params >/tmp/params.json
    #Edit params.txt to wrap the json structure in { "params": ... }
    headnode$ cat /tmp/params.json | json -o json-0 | sapiadm update [service uuid]

5) Once the service in SAPI has been modified, make sure to get it to verify
   what SAPI has is what it should be.


## Shard Management

A shard is a set of moray buckets, backed by >1 moray instances and >=3
Postgres instances.  No data is shared between any two shards.  Many other manta
services may said to be "in a shard", but more accurately, they're using a
particular shard.

There are three pieces of metadata which define how shards are used:

    INDEX_MORAY_SHARDS          Shards used for the indexing tier
    MARLIN_MORAY_SHARD          Shard used for marlin job records
    STORAGE_MORAY_SHARD         Shard used for minnow (manta_storage) records

Right now, marlin uses only a single shard.

Currently, the hash ring topology for electric-moray is created once during
Manta setup and stored as an image in a Triton imgapi.  The image uuid and
imgapi endpoint are stored in the following sapi parameters:

    HASH_RING_IMAGE             The hash ring image uuid
    HASH_RING_IMGAPI_SERVICE    The imageapi that stores the image.

In a cross-datacenter deployment, the HASH_RING_IMGAPI_SERVICE may be in
another datacenter.  This limits your ability to deploy new electric-moray
instances in the event of DC failure.

This topology is **independent** of what's set in manta-shardadm. **WARNING
UNDER NO CIRCUMSTANCES SHOULD THIS TOPOLOGY BE CHANGED ONCE MANTA HAS BEEN
DEPLOYED, DOING SO WILL RESULT IN DATA CORRUPTION**

See manta-deploy-lab for hash-ring generation examples.

The manta-shardadm tool lists shards and allows the addition of new ones:

    manta$ manta-shardadm
    Manage manta shards

    Usage:
        manta-shardadm [OPTIONS] COMMAND [ARGS...]
        manta-shardadm help COMMAND

    Options:
        -h, --help      Print help and exit.
        --version       Print version and exit.

    Commands:
        help (?)        Help on a specific sub-command.
        list            List manta shards.
        set             Set manta shards.

In addition, the -z flag to manta-deploy specifies a particular shard for that
instance.  In the case of moray and postgres, that value defines which shard
that instance participates in.  For all other services, that value defines which
shard an instance will consume.

Note that deploying a postgres or moray instance into a previously undefined
shard will not automatically update the set of shards for the indexing tier.
Because of the presence of the electric-moray proxy, adding an additional shard
requires coordination with all existing shards, lest objects and requests be
routed to an incorrect shard (and thereby inducing data corruption).  If you
find yourself adding additional capacity, deploy the new shard first, coordinate
with all existing shards, then use manta-shardadm to add the shard to list of
shards for the indexing tier.


## Working with a Development VM that talks to COAL

Some people set up a distinct SmartOS VM that is a stable dev environment and
point it at COAL.  Since the manta networking changes, you'll need to setup your
zone(s) with a NIC on the `10.77.77.X` network.  Fortunately this is easy, so
get on your dev VM's GZ, and run:

    dev-gz$ nictagadm add manta $(ifconfig e1000g0 | grep ether | awk '{print $2}')`
    dev-gz$ echo '{ "add_nics": [ { "ip": "10.77.77.250", "netmask": "255.255.255.0", "nic_tag": "manta" } ] }' | vmadm update <VM>

Then reboot the zone.


# Advanced Marlin Reference

The information in this section may be useful once you're familiar with Marlin
internals.  These are internal implementation details intended to help
*understand* the system.  It is completely unsupported to make any changes to
the system outside of using a documented tool or following a Joyent support
procedure.  **Everything in this section is subject to change without
notice!**

## Internal state

As mentioned above, all of Marlin's state is stored using JSON records in Moray
using several buckets:

* **marlin\_jobs\_v2**: When the user creates a job, muskie creates a record in
  this bucket.  The global job state is stored in this record, and is
  periodically updated by the supervisor as execution progresses.
* **marlin\_jobinputs\_v2**: As users submit inputs, muskie creates records in
  this bucket.
* **marlin\_tasks\_v2**: Supervisors poll for new jobinputs, locate the
  corresponding objects, and assign work to agents by writing new records into
  this bucket.  Agents poll for new tasks assigned to them in this bucket and
  then execute them.
* **marlin\_taskinputs\_v2**: For reduce tasks, which operate on many objects,
  the supervisor writes a separate record in this bucket for each input object.
* **marlin\_taskoutputs\_v2**: As tasks emit outputs, the agent writes records
  into this bucket.  If the job has a subsequent phase, these outputs will
  become tasks or inputs for the next phase.  Otherwise, they'll be marked job
  outputs.
* **marlin\_errors\_v2**: When supervisors or agents emit errors (including
  retryable errors), they write records into this bucket.
* **marlin\_health\_v2**: Unlike the other buckets, where each record is
  associated with a particular job, this bucket is only used by supervisors and
  agents to report health.  There's one record per supervisor and per agent.
  See "Health checking" below.

This design may seem unnecessarily indirect in some cases, but it keeps each
record small so that we can support streaming arbitrary numbers of objects
through the system.

The schema for these buckets is not documented or stable, but you can find the
latest version (with comments) on
[github](https://github.com/joyent/manta-marlin/blob/master/common/lib/schema.js).


## Heartbeats, failures, and health checking

Supervisors and agents heartbeat periodically by writing records into the
**marlin_health_v2** bucket.  Heartbeats are monitored by all supervisors.

The most common failure mode is a restart (crash).  Since the supervisor state
is entirely reconstructible from what's in Moray, supervisor restarts are pretty
straightforward.  For simplicity, agents always reset the world and start from a
clean state when they come up.  Supervisors detect agent restarts and abort and
re-issue all outstanding tasks for that agent.

The other main failure mode is a hang or partition, manifested as a failure to
heartbeat for an extended period.  If this happens to a supervisor, another
supervisor takes over the failed supervisor's jobs.  When the failed one comes
back, it coordinates to take over its work.  If an agent disappears for an
extended period, supervisors treat this much like a restart, by failing
outstanding tasks and re-issuing them on other servers.

Lackeys heartbeat periodically by making HTTP requests to the agent.  On
failure, the agent fails the task.

If wrasse fails, archiving is delayed, but this has little effect on users.
Wrasse recovers from restarts by rerunning any archives that were in progress.

Muskie instances are totally stateless.  Restarts are trivially recoverable, and
extended failures and partitions cause requests to be vectored to other
instances.


## Kang state

Jobsupervisors and agents export Kang entry points that describe their internal
state.  For agents, the HTTP server runs on port 9080, and you can get this
state with:

    headnode$ curl -si http://GZ_IP_ADDRESS:9080/kang/snapshot | json

For jobsupervisors, you can get this with:

    headnode$ curl -si http://ZONE_IP_ADDRESS/kang/snapshot | json

This API is undocumented and unstable.  It's the same one that feeds the
marlin dashboard.


## Fetching information about historical jobs

Jobs are *archived* once they complete.  This process saves the job's public
json representation and the full lists of inputs, outputs, and errors into the
job's directory (`/$MANTA_USER/jobs/$JOBID`).  The job's json representation is
also saved into `/poseidon/stor/job_archives/YYYY/MM/DD/HH`.  For more on the
user-facing implications of archiving, see the [public
docs](http://apidocs.joyent.com/manta/jobs-reference.html#job-completion-and-archival).

About 24 hours after a job is archived, all of its records are removed from the
database.  This is necessary to keep the jobs database from growing without
bound.  At that point, none of the usual tools will work on that job, including
`mrjob`, `mrjobreport`, `mrerrors -j`, and so on.

However, because we dump copies of the jobs database into Manta itself hourly,
you can still get all the information about the job.  The `mrextractjob` tool
takes a database dump directory (in Manta), a jobid, and a destination
directory.  It scans the database dump and extracts all records related to the
job.

In summary, to get details about a job that has already been removed from the
database:

1. Starting with the jobid, you'll need to figure out which hour's database dump
   the job's details will be stored in.  You should use the database dump
   labeled after the job's "done" time, but within 24 hours of job completion.

    a. If you don't know what date and time the job completed, but you know
       which account ran the job, then you can fetch the job's user-facing JSON
       file with:

        $ mget /$MANTA_USER/jobs/$JOBID/job.json

       You should probably do this as `poseidon` in the `ops` zone, which will
       avoid logging the request in the user's usage data (and charging the user
       for it).

    b. If you don't know what date and time the job completed or even which user
       ran it, or if the user already removed the job's directory, you can still
       find the job's JSON file under `/poseidon/stor/job_archives`.  You'll run
       something like:

        $ mfind -t d -n $JOBID /poseidon/stor/job_archives

       This will take a long time.  The more you can narrow it down (by
       searching subdirectories of "job_archives"), the faster it will be.
       Assuming this returns a result, look for the job.json file inside that
       directory, which will have the job's completion time in it.

2. At this point, you should have the jobid *and* the job's completion time,
   which will tell you which database dump the job's records will be in.  For
   example, if the job completed at 2014-05-05T11:07:05.519Z, you'll look at the
   dump for 2014/05/06/00 (the first dump after the completion time).  All of
   the dumps are stored in `/poseidon/stor/manatee_backups`, under the shard
   designated as the jobs shard.  For the us-east Manta deployment, the jobs
   shard is 1.moray.us-east.joyent.us.  Putting all this together, the database
   dumps we care about would be in:

        /poseidon/stor/manatee_backups/1.moray.us-east.joyent.us/2014/05/06/00

   Next, you'll run `mrextractjob` (from the `ops` zone).  You can run it with
   no arguments for details, but basically you'll run something like this:

        $ mrextractjob \
            /poseidon/stor/manatee_backups/1.moray.us-east.joyent.us/2014/05/06/00 \
            /poseidon/stor/debug-fe4c6e2a \
            fe4c6e2a-bc78-4c94-d4cd-c9f6a8931855

   You should replace `/poseidon/stor/debug-fe4c6e2a` with whatever directory in
   Manta you want the extracted job files to go.

   This command should output something like this:

        19f3d2fa-0dde-436f-a719-e250596298b9
        added 6 inputs to 19f3d2fa-0dde-436f-a719-e250596298b9
        mls -l "/dap/stor/debug-fe4c6e2a":
        -rwxr-xr-x 1 dap             0 May 29 17:00 errors.json
        -rwxr-xr-x 1 dap           694 May 29 17:00 jobinputs.json
        -rwxr-xr-x 1 dap          2875 May 29 17:00 jobs.json
        -rwxr-xr-x 1 dap             0 May 29 17:00 taskinputs.json
        -rwxr-xr-x 1 dap           955 May 29 17:00 taskoutputs.json
        -rwxr-xr-x 1 dap          2050 May 29 17:00 tasks.json

   In this case, 19f3d2fa-0dde-436f-a719-e250596298b9 is the jobid for the Manta
   job that was used to extract the job we're interested in, which is
   fe4c6e2a-bc78-4c94-d4cd-c9f6a8931855.  Now, the errors, job inputs,
   taskinputs, task outputs, tasks, and the raw job record are available in
   those directories.  Unfortunately, there's not great tooling for summarizing
   extracted jobs (i.e., there's no analog to `mrjob log` or `mrjobreport`), but
   you can use the `json` and `daggr` tools to pick apart these records.



# .
