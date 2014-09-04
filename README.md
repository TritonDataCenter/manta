<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2014, Joyent, Inc.
-->

# Manta: object storage with first-class compute

Manta is an open-source, HTTP-based object store with built-in support to run
arbitrary programs on data at rest (i.e., without copying data out of the object
store).  Joyent operates a public-facing production [Manta
service](https://www.joyent.com/products/manta), but all the pieces required to
deploy and operate your own Manta are open source.  This repo provides
documentation for the overall Manta project and pointers to the other
repositories that make up a complete Manta deployment.

To start playing with Manta (e.g., to see what it does), see the [Getting
Started](https://apidocs.joyent.com/manta/index.html#getting-started) guide in
the user documentation.

To learn about installing and operating your own Manta deployment, see the Manta
Operator's Guide.

Manta is designed to store amounts of data storage and support arbitrary
computation on that data.  The intended use-cases are wide-ranging:

* web assets (e.g., images, HTML and CSS files, and so on), with the ability to
  convert or resize images without copying any data out of Manta
* backup storage (e.g., tarballs)
* video storage and transcoding
* log storage and analysis
* data warehousing
* software crash dump storage and analysis


## Dependencies

Manta is deployed on top of Joyent's
[SmartDataCenter](https://github.com/joyent/sdc) platform (SDC), which is also
open-source.  SDC is a system for operating a datacenter as a cloud.  SDC
provides services for operating physical servers (compute nodes), deploying
services in containers, monitoring services, transmitting and visualizing
real-time performance data, and a bunch more.  Manta primarily uses SDC for
initial deployment, service upgrade, and service monitoring.

SDC itself depends on [SmartOS](https://smartos.org).  Manta also depends on
several SmartOS features, notably: ZFS pooled storage, ZFS rollback, and
[hyprlofs](https://github.com/joyent/illumos-joyent/blob/master/usr/src/uts/common/fs/hyprlofs/hyprlofs_vfsops.c).

The easiest way to play around with your own Manta installation is to:

* Set up an SDC COAL (cloud-on-a-laptop) installation in VMware
* Deploy Manta atop it using the deployment instructions in the Manta Operator's
  Guide.


## Repositories

This repository is just a wrapper containing documentation about Manta.  Manta
is actually made up of several components stored in other repos.

The front door services respond to requests from the internet at large:

* [muppet](https://github.com/joyent/muppet): haproxy + stud-based SSL
  terminator and loadbalancer
* [muskie](https://github.com/joyent/manta-muskie): Node-based API server
* [mahi](https://github.com/joyent/mahi): authentication cache
* [medusa](https://github.com/joyent/manta-medusa): handles interactive (mlogin)
  sessions

The metadata tier stores the entire object namespace (not object data) as well
as information about compute jobs and backend storage system capacity:

* [manatee](https://github.com/joyent/manatee): high-availability postgres
  cluster using synchronous replication
* [moray](https://github.com/joyent/moray): Node-based key-value store built on
  top of manatee.  Also responsible for monitoring manatee replication topology
  (i.e., which postgres instance is the master).
* [electric-moray](https://github.com/joyent/electric-moray): Node-based service
  that provides the same interface as Moray, but which directs requests to one
  or more Moray+Manatee *shards* based on hashing the Moray key.

The storage tier is responsible for actually storing bits on disk:

* [mako](https://github.com/joyent/manta-mako): nginx-based server that receives
  PUT/GET requests from Muskie to store object data on disk.

The compute tier (also called [Marlin](https://github.com/joyent/manta-marlin)
is responsible for the distributed execution of user jobs.  Most of it is
contained in the Marlin repo, and it consists of:

* jobsupervisor: Node-based service that stores job execution state in moray and
  coordinates execution across the physical servers
* marlin agent: Node-based service (an SDC agent) that runs on each physical
  server and is responsible for executing user jobs on that server
* lackey: a Node-based service that runs inside each compute zone under the
  direction of the marlin agent.  The lackey is responsible for actually
  executing individual user tasks inside compute containers.
* [wrasse](https://github.com/joyent/manta-wrasse): job archiver and purger,
  which removes job information from moray after the job completes and saves
  the lists of inputs, outputs, and errors back to Manta for user reference

There are a number of services not part of the data path that are critical for
Manta's operation:

* [binder](https://github.com/joyent/binder): hosts both ZooKeeper (used for
  manatee leader election and for group membership) and a Node-based DNS server
  that keeps track of which instances of each service are online at any given
  time.
* [mola](https://github.com/joyent/manta-mola): garbage collection (removing
  files from storage servers corresponding to objects that have been deleted
  from the namespace)
* [mackerel](https://github.com/joyent/manta-mackerel): metering (computing
  per-user details about requests made, bandwidth used, storage used, and
  compute time used)
* [madtom](https://github.com/joyent/manta-madtom): real-time "is-it-up?"
  dashboard, showing the status of all services deployed
* [marlin-dashboard](https://github.com/joyent/manta-marlin-dashboard):
  real-time dashboard showing detaild status for the compute tier
* [minnow](https://github.com/joyent/manta-minnow): a Node-based service that
  runs inside mako zones to periodically report storage capacity into Moray

With the exception of the Marlin agent and lackey, each of the above components
are *services*, of which there may be multiple *instances* in a single Manta
deployment.  Except for the last category of non-data-path services, these can
all be deployed redundantly for availability and additional instances can be
deployed to increase capacity.

For more details on the architecture, including how these pieces actually fit
together, see "Architecture Basics" in the Manta Operator's Guide.


## Contributing to Manta

Manta repositories use the same [Joyent Engineering
Guidelines](https://github.com/joyent/eng) as the SDC project.  Notably:

* The #master branch should be first-customer-ship (FCS) quality at all times.
  Don't push anything until it's tested.
* All repositories should be "make check" clean at all times.
* All repositories should have tests that run cleanly at all times.

"make check" checks both JavaScript style and lint.  Style is checked with
[jsstyle](https://github.com/davepacheco/jsstyle).  The specific style rules are
somewhat repo-specific.  Style is somewhat repo-specific.  See the jsstyle
configuration file in each repo for exceptions to the default jsstyle rules.

Lint is checked with
[javascriptlint](https://github.com/davepacheco/javascriptlint).  ([Don't
conflate lint with
style!](http://dtrace.org/blogs/dap/2011/08/23/javascriptlint/).  There are gray
areas, but generally speaking, style rules are arbitrary, while lint warnings
identify potentially broken code.)  Repos sometimes have repo-specific lint
rules, but this is less common.

To report bugs or request features, submit issues to the Manta project on
Github.  If you're asking for help with Joyent's production Manta service,
you should contact Joyent support instead.  If you're contributing code, start
with a pull request.  If you're contributing something substantial, you should
contact developers on the mailing list or IRC first.


## Design principles

Manta assumes several constraints on the data storage problem:

1. There should be one *canonical* copy of data.  You shouldn't need to copy
   data in order to analyze it, transform it, or serve it publicly over the
   internet.
1. The system must scale horizontally in every dimension.  It should be possible
   to add new servers and deploy software instances to increase the system's
   capacity in terms of number of objects, total data stored, or compute
   capacity.
1. The system should be general-purpose.  (That doesn't preclude
   special-purpose interfaces for use-cases like log analysis or video
   transcoding.)
1. The system should be strongly consistent and highly available.  In terms of
   [CAP](http://en.wikipedia.org/wiki/CAP_theorem), Manta sacrifices
   availability in the face of network partitions.  (The reasoning here is that
   an AP cache can be built atop a CP system like Manta, but if Manta were AP,
   then it would be impossible for anyone to get CP semantics.)
1. The system should be transparent about errors and performance.  The public
   API only supports atomic operations, which makes error reporting and
   performance easy to reason about.  (It's hard to say anything about the
   performance of compound operations, and it's hard to report failures in
   compound operations.)  Relatedly, a single Manta deployment may span multiple
   datacenters within a region for higher availability, but Manta does not
   attempt to provide a global namespace across regions, since that would imply
   uniformity in performance or fault characteristics.

From these constraints, we define a few design principles:

1. Manta presents an HTTP interface (with REST-based PUT/GET/DELETE operations)
   as the primary way of reading and writing data.  Because there's only one
   copy of data, and some data needs to be available publicly (e.g., on the
   internet over standard protocols), HTTP is a good choice.
1. Manta is an *object store*, meaning that it only provides PUT/GET/DELETE for
   *entire objects*.  You cannot write to the middle of an object or append to
   the end of one.  This constraint makes it possible to guarantee strong
   consistency and high availability, since only the metadata tier (i.e., the
   namespace) needs to be strongly consistent, and objects themselves can be
   easily replicated for availability.
1. Users express computation in terms of shell scripts, which can make use of
   any programs installed in the default compute environment, as well as any
   objects stored in Manta.  You can store your own programs in Manta and use
   those, or you can use tools like curl(1) to fetch a program from the internet
   and use that.  This approach falls out of the requirement to be a
   general-purpose system, and imposes a number of other constraints on the
   implementation (like the use of strong OS-based containers to isolate users).
1. Users express distributed computation in terms of map and reduce operations.
   As with Hadoop and other MapReduce-based systems, this allows the system to
   identify which parts can be parallelized and which parts cannot in order to
   maximize performance.

It's easy to underestimate the problem of just reliably storing bits on disk.
It's commonly assumed that the only components that fail are disks, that they
fail independently, and that they fail cleanly (e.g., by reporting errors).  In
reality, there are a lot worse failure modes than disks failing cleanly,
including:

* disks or HBAs dropping writes
* disks or HBAs redirecting both read and write requests to the wrong physical
  blocks
* disks or HBAs retrying writes internally, resulting in orders-of-magnitude
  latency bubbles
* disks, HBAs, or buses corrupting data at any point in the data path

Manta delegates to ZFS to solve the single-system data storage problem.  To
handle these cases,

* ZFS stores block checksums *separately* from the blocks themselves.
* Filesystem metadata is stored redundantly (on separate disks).  Data is
  typically stored redundantly as well, but that's up to user configuration.
* ZFS is aware of how the filesystem data is stored across several disks.  As a
  result, when reads from one disk return data that doesn't match the expected
  checksum, it's able to read another copy and fix the original one.

For a more detailed discussion, see the ACM Queue article "Bringing Arbitrary
Compute to Authoritative Data".



## Further reading

For background on the problem space and design principles, check out ["Bringing
Arbitrary Compute to Authoritative
Data"](http://queue.acm.org/detail.cfm?id=2645649).

For background on the overall design approach, see ["There's Just No Getting
Around It: You're Building a Distributed
System"](http://queue.acm.org/detail.cfm?id=2482856).

For information about how Manta is designed to survive component failures and
maintain strong consistency, see [Fault tolerance in
Manta](http://dtrace.org/blogs/dap/2013/07/03/fault-tolerance-in-manta/).

Applications and customer stories:

* [Kartlytics: Applying Big Data Analytics to Mario
  Kart](http://www.joyent.com/blog/introducing-kartlytics-mario-kart-64-analytics)
* [A Cost-effective Approach to Scaling Event-based Data Collection and
  Analysis](http://building.wanelo.com/2013/06/28/a-cost-effective-approach-to-scaling-event-based-data-collection-and-analysis.html)
