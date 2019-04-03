<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright 2019, Joyent, Inc.
-->

# Manta: Triton's object storage and converged analytics solution

Manta, Triton's object storage and converged analytics solution, is an
open-source, HTTP-based object store that uses OS containers to enable running
arbitrary compute on data at rest (i.e., without copying data out of the object
store).  The intended use-cases are wide-ranging:

* web assets (e.g., images, HTML and CSS files, and so on), with the ability to
  convert or resize images without copying any data out of Manta
* backup storage (e.g., tarballs)
* video storage and transcoding
* log storage and analysis
* data warehousing
* software crash dump storage and analysis

Joyent operates a public-facing production [Manta
service](https://www.joyent.com/products/manta), but all the pieces required to
deploy and operate your own Manta are open source.  This repo provides
documentation for the overall Manta project and pointers to the other
repositories that make up a complete Manta deployment.

## Getting started

The fastest way to get started with Manta depends on what exactly one
wishes to do.

* To experiment with Manta, the fastest way is to start playing with [Joyent's
Manta service](https://www.joyent.com/products/manta); see the [Getting
Started](https://apidocs.joyent.com/manta/index.html#getting-started) guide in
the user documentation for details.

* To see a detailed, real example of using Manta, check out [Kartlytics: Applying Big Data Analytics to Mario Kart](http://www.joyent.com/blog/introducing-kartlytics-mario-kart-64-analytics).

* To learn about installing and operating your own Manta deployment, see the
[Manta Operator's Guide](https://joyent.github.io/manta/).

* To understand Manta's architecture, see
[Bringing Arbitrary Compute to Authoritative
Data](http://queue.acm.org/detail.cfm?id=2645649), the
[ACM Queue](http://queue.acm.org/)
article on its design and implementation.

* To understand the
[CAP tradeoffs](http://en.wikipedia.org/wiki/CAP_theorem) in Manta,
see [Dave Pacheco](https://github.com/davepacheco)'s blog entry on
[Fault Tolerence in Manta](http://dtrace.org/blogs/dap/2013/07/03/fault-tolerance-in-manta/) -- which, it must be said, received [the highest possible praise](https://twitter.com/eric_brewer/status/352804538769604609).

* For help with working on Manta and testing your changes, see the [developer
  notes](docs/dev-notes.md)

## Community

Community discussion about Manta happens in two main places:

* The *manta-discuss*
  [mailing list](https://mantastorage.topicbox.com/groups/manta-discuss).
  If you wish to send mail to the list you'll need to join, but you can view
  and search the archives online without being a member.

* In the *#manta* IRC channel on the [Freenode IRC
  network](https://freenode.net/).

You can also follow [@MantaStorage](https://twitter.com/MantaStorage) on
Twitter for updates.

## Dependencies

Manta is deployed on top of Joyent's
[Triton DataCenter](https://github.com/joyent/triton) platform (just "Triton"
for short), which is also open-source. Triton provides services for operating
physical servers (compute nodes), deploying services in containers, monitoring
services, transmitting and visualizing real-time performance data, and a bunch
more. Manta primarily uses Triton for initial deployment, service upgrade, and
service monitoring.

Triton itself depends on [SmartOS](http://smartos.org).  Manta also directly
depends on several SmartOS features, notably: ZFS pooled storage, ZFS rollback,
and
[hyprlofs](https://github.com/joyent/illumos-joyent/blob/master/usr/src/uts/common/fs/hyprlofs/hyprlofs_vfsops.c).


## Building and Deploying Manta

Manta is built and packaged with Triton DataCenter. Building the raw pieces uses
the same mechanisms as building the services that are part of Triton. When you
build a Triton headnode image (which is the end result of the whole Triton build
process), one of the built-in services you get is a [Manta
deployment](http://github.com/joyent/sdc-manta) service, which is used
to bootstrap a Manta installation.

Once you have Triton set up, follow the instructions in the
[Manta Operator's
Guide](https://joyent.github.io/manta/)
to deploy Manta.  The easiest way to play around with your own Manta
installation is to first set up a Triton cloud-on-a-laptop (COAL) installation
in VMware and then follow those instructions to deploy Manta on it.

If you want to deploy your own builds of Manta components, see "Deploying your
own Manta Builds" below.


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
  cluster using synchronous replication and automatic fail-over
* [moray](https://github.com/joyent/moray): Node-based key-value store built on
  top of manatee.  Also responsible for monitoring manatee replication topology
  (i.e., which postgres instance is the master).
* [electric-moray](https://github.com/joyent/electric-moray): Node-based service
  that provides the same interface as Moray, but which directs requests to one
  or more Moray+Manatee *shards* based on hashing the Moray key.

The storage tier is responsible for actually storing bits on disk:

* [mako](https://github.com/joyent/manta-mako): nginx-based server that receives
  PUT/GET requests from Muskie to store object data on disk.

The compute tier (also called [Marlin](https://github.com/joyent/manta-marlin))
is responsible for the distributed execution of user jobs.  Most of it is
contained in the Marlin repo, and it consists of:

* jobsupervisor: Node-based service that stores job execution state in moray and
  coordinates execution across the physical servers
* marlin agent: Node-based service (a Triton agent) that runs on each physical
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
  time
* [mola](https://github.com/joyent/manta-mola): garbage collection (removing
  files from storage servers corresponding to objects that have been deleted
  from the namespace) and audit (verifying that objects in the index tier
  exist on the storage hosts)
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

Finally, scripts used to set up these component zones live in the
[https://github.com/joyent/manta-scripts](manta-scripts) repo.

For more details on the architecture, including how these pieces actually fit
together, see "Architecture Basics" in the
[Manta Operator's
Guide](https://joyent.github.io/manta/).


## Deploying your own Manta Builds

As described above, as part of the normal Manta deployment process, you start
with the "manta-deployment" zone that's built into Triton.  Inside that zone, you
run "manta-init" to fetch the latest Joyent build of each Manta component.  Then
you run Manta deployment tools to actually deploy zones based on these builds.

The easiest way to use your own custom build is to first deploy Manta using the
default Joyent build and *then* replace whatever components you want with your
own builds.  This will also ensure that you're starting from a known-working set
of builds so that if something goes wrong, you know where to start looking.  To
do this:

1. Complete the Manta deployment procedure from the [Manta Operator's
Guide](https://joyent.github.io/manta/).
1. Build a zone image for whatever zone you want to replace.  See the
   instructions for building [SmartDataCenter](https://github.com/joyent/sdc)
   zone images using Mountain Gorilla.  Manta zones work the same way.  The
   output of this process will be a zone **image**, identified by uuid.  The
   image is comprised of two files: an image manifest (a JSON file) and the
   image file itself (a binary blob).
1. Import the image into the Triton DataCenter that you're using to deploy Manta.
   (If you've got a multi-datacenter Manta deployment, you'll need to import the
   image into each datacenter separately using this same procedure.)
    1. Copy the image and manifest files to the Triton headnode where the Manta
       deployment zone is deployed.  For simplicity, assume that the
       manifest file is "/var/tmp/my_manifest.json" and the image file is
       "/var/tmp/my_image".  You may want to use the image uuid in the filenames
       instead.
    1. Import the image using:

           sdc-imgadm import -m /var/tmp/my_manifest.json -f /var/tmp/my_image

1. Now you can use the normal Manta zone update procedure (from the [Manta
   Operator's Guide](https://joyent.github.io/manta/).
   This involves saving the current configuration to a JSON
   file using "manta-adm show -sj > config.json", updating the configuration
   file, and then applying the changes with "manta-adm update < config.json".
   When you modify the configuration file, you can use your image's uuid in
   place of whatever service you're trying to replace.

If for some reason you want to avoid deploying the Joyent builds at all, you'll
have to follow a more manual procedure.  One approach is to update the SAPI
configuration for whatever service you want (using sdc-sapi -- see
[SAPI](https://github.com/joyent/sdc-sapi)) *immediately after* running
manta-init but before deploying anything.  Note that each subsequent
"manta-init" will clobber this change, though the SAPI configuration is normally
only used for the initial deployment anyway.  The other option is to apply the
fully-manual install procedure from the
[Manta Operator's
Guide](https://joyent.github.io/manta/)
(i.e., instead of
using manta-deploy-coal or manta-deploy-lab) and use a custom "manta-adm"
configuration file in the first place.  If this is an important use case, file
an issue and we can improve this procedure.

The above procedure works to update Manta *zones*, which are most of the
components above.  The other two kinds of components are the *platform* and
*agents*.  Both of these procedures are documented in the
[Manta Operator's
Guide](https://joyent.github.io/manta/), and they work to deploy custom builds as well as the official Joyent
builds.


## Contributing to Manta

To report bugs or request features, you can submit issues to the Manta project
on Github.  If you're asking for help with Joyent's production Manta service,
you should contact Joyent support instead.

See the [Contribution Guidelines](CONTRIBUTING.md) for information about
contributing changes to the project.


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

For information on the latest recommended production hardware, see [Joyent
Manufacturing Matrix](http://eng.joyent.com/manufacturing/matrix.html) and
[Joyent Manufacturing Bill of
Materials](http://eng.joyent.com/manufacturing/bom.html).

Applications and customer stories:

* [Kartlytics: Applying Big Data Analytics to Mario
  Kart](http://www.joyent.com/blog/introducing-kartlytics-mario-kart-64-analytics)
* [A Cost-effective Approach to Scaling Event-based Data Collection and
  Analysis](http://building.wanelo.com/2013/06/28/a-cost-effective-approach-to-scaling-event-based-data-collection-and-analysis.html)
