<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright 2020 Joyent, Inc.
-->

# Manta: a scalable, distributed object store

Manta is an open-source, scalable, HTTP-based object store. All the pieces
required to deploy and operate your own Manta are open source. This repo
provides documentation for the overall Manta project and pointers to the other
repositories that make up a complete Manta deployment.

## Getting started

The fastest way to get started with Manta depends on what exactly one
wishes to do.

* To use Manta see the [Getting Started](./docs/user-guide/#getting-started)
  section of the User Guide.

* To learn about installing and operating your own Manta deployment, see the
  [Manta Operator Guide](./docs/operator-guide/).

* To understand Manta's architecture, see [Bringing Arbitrary Compute to
  Authoritative Data](http://queue.acm.org/detail.cfm?id=2645649), the [ACM
  Queue](http://queue.acm.org/) article on its design and implementation.

* To understand the [CAP tradeoffs](http://en.wikipedia.org/wiki/CAP_theorem) in Manta,
  see [Fault Tolerence in Manta](http://dtrace.org/blogs/dap/2013/07/03/fault-tolerance-in-manta/) --
  which received [some notable praise](https://twitter.com/eric_brewer/status/352804538769604609).

* For help with working on Manta and building and testing your changes,
  see the [developer guide](docs/developer-guide)

## Community

Community discussion about Manta happens in two main places:

* The *manta-discuss*
  [mailing list](https://mantastorage.topicbox.com/groups/manta-discuss).
  If you wish to send mail to the list you'll need to join, but you can view
  and search the archives online without being a member.

* In the *#manta* IRC channel on the [Freenode IRC
  network](https://freenode.net/).


## Dependencies

Manta is composed of a number of services that deploy on top of Joyent's
[Triton DataCenter](https://github.com/joyent/triton) platform (just "Triton"
for short), which is also open-source. Triton provides services for operating
physical servers (compute nodes), deploying services in containers, monitoring
services, transmitting and visualizing real-time performance data, and a bunch
more. Manta primarily uses Triton for initial deployment, service upgrade, and
service monitoring.

Triton itself depends on [SmartOS](http://smartos.org).  Manta also directly
depends on several SmartOS features, notably ZFS.


## Building and Deploying Manta

Manta service images are built and packaged using the same mechanisms as
building the services that are part of Triton. Once you have Triton set up,
follow the instructions in the [Manta Operator Guide](./docs/operator-guide/)
to deploy Manta.  The easiest way to play around with your own Manta
installation is to first set up a Triton cloud-on-a-laptop (COAL) installation
in VMware and then follow those instructions to deploy Manta on it.

If you want to deploy your own builds of Manta components, see "Deploying your
own Manta Builds" below.


## Repositories

This repository is just a wrapper containing documentation about Manta.  Manta
is made up of several components from many repositoies. This section highlights
some of the more important ones.

A full list of repositories relevant to Manta is maintained in a [repo manifest
file](./tools/jr-manifest.json) in this repo. To more conveniently list those
repos, you can use the [`jr` tool](https://github.com/joyent/joyent-repos#jr).

The front door services respond to requests from the internet at large:

* [muppet](https://github.com/joyent/muppet): the haproxy-based "loadbalancer"
  service
* [muskie](https://github.com/joyent/manta-muskie): the node.js-based "webapi"
  service, this is Manta's "Directory API"
* [buckets-api](https://github.com/joyent/manta-buckets-api): Node.js-based
  "buckets-api" service, this is Manta's "Buckets API"

The metadata tiers for the Directory and Buckets APIs store the entire object
namespace (not object data) as well as backend storage system capacity:

* [manatee](https://github.com/joyent/manatee): the "postgres" service, a
  high-availability postgres cluster using synchronous replication and automatic
  fail-over
* [moray](https://github.com/joyent/moray): Node-based key-value store built on
  top of manatee.  Also responsible for monitoring manatee replication topology
  (i.e., which postgres instance is the master).
* [electric-moray](https://github.com/joyent/electric-moray): Node-based service
  that provides the same interface as Moray, but which directs requests to one
  or more Moray+Manatee *shards* based on hashing the Moray key.
* [buckets-mdapi](https://github.com/joyent/manta-buckets-mdapi): a Rust-based
  API for managing all metadata for the Buckets API
* [buckets-mdplacement](https://github.com/joyent/manta-buckets-mdplacement): a
  Rust-based API for handling routing of Buckets API objects to appropriate
  nodes in the storage tier.

The storage tier is responsible for actually storing bits on disk:

* [mako](https://github.com/joyent/manta-mako): the "storage" service, a
  nginx-based server that receives PUT/GET requests from the front door services
  to store object data on disk
* [minnow](https://github.com/joyent/manta-minnow): a Node-based agent that
  runs inside storage instances to periodically report storage capacity to the
  metadata tier

There are a number of services not part of the data path that are critical for
Manta's operation. For example:

* [binder](https://github.com/joyent/binder): hosts both ZooKeeper (used for
  manatee leader election and for group membership) and a Node-based DNS server
  that keeps track of which instances of each service are online at any given
  time
* [mahi](https://github.com/joyent/mahi): The "authcache" service for handling authn/authz.

Most of the above components are *services*, of which there may be multiple
*instances* in a single Manta deployment. Except for the last category of
non-data-path services, these can all be deployed redundantly for availability
and additional instances can be deployed to increase capacity.

For more details on the architecture, including how these pieces actually fit
together, see the [Architecture](./docs/operator-guide/architecture.md) section
of the Operator Guide.


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

1. Complete the Manta deployment procedure from the operator guide.
2. Build a zone image for whatever zone you want to replace.  See the
   instructions for building [Triton](https://github.com/joyent/triton)
   zone images.  Manta zones work the same way.  The output of this process
   will be a zone **image**, identified by uuid.  The image is comprised of
   two files: an image manifest (a JSON file) and the image file itself
   (a binary blob).
3. Import the image into the Triton DataCenter that you're using to deploy Manta.
   (If you've got a multi-datacenter Manta deployment, you'll need to import the
   image into each datacenter separately using this same procedure.)
    1. Copy the image and manifest files to the Triton headnode where the Manta
       deployment zone is deployed.  For simplicity, assume that the
       manifest file is "/var/tmp/my_manifest.json" and the image file is
       "/var/tmp/my_image".  You may want to use the image uuid in the filenames
       instead.
    2. Import the image using:

           sdc-imgadm import -m /var/tmp/my_manifest.json -f /var/tmp/my_image

4. Now you can use the normal Manta zone update procedure (from the operator
   guide). This involves saving the current configuration to a JSON
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
fully-manual install procedure from the Operator Guide (i.e., instead of
using manta-deploy-coal or manta-deploy-lab) and use a custom "manta-adm"
configuration file in the first place.  If this is an important use case, file
an issue and we can improve this procedure.

The above procedure works to update Manta *zones*, which are most of the
components above.  The other two kinds of components are the *platform* and
*agents*.  Both of these procedures are documented in the Operator Guide,
and they work to deploy custom builds as well as the official Joyent builds.


## Contributing to Manta

To report bugs or request features, you can submit issues to the Manta project
on Github.  If you're asking for help with Joyent's production Manta service,
you should contact Joyent support instead.

See the [Contribution Guidelines](./CONTRIBUTING.md) for information about
contributing changes to the project.


## Design principles

Manta assumes several constraints on the data storage problem:

1. There should be one *canonical* copy of data.  You shouldn't need to copy
   data in order to analyze it, transform it, or serve it publicly over the
   internet.
2. The system must scale horizontally in every dimension.  It should be possible
   to add new servers and deploy software instances to increase the system's
   capacity in terms of number of objects, total data stored, or compute
   capacity.
3. The system should be general-purpose.
4. The system should be strongly consistent and highly available.  In terms of
   [CAP](http://en.wikipedia.org/wiki/CAP_theorem), Manta sacrifices
   availability in the face of network partitions.  (The reasoning here is that
   an AP cache can be built atop a CP system like Manta, but if Manta were AP,
   then it would be impossible for anyone to get CP semantics.)
5. The system should be transparent about errors and performance.  The public
   API only supports atomic operations, which makes error reporting and
   performance easy to reason about.  (It's hard to say anything about the
   performance of compound operations, and it's hard to report failures in
   compound operations.)  Relatedly, a single Manta deployment may span multiple
   datacenters within a region for higher availability, but Manta does not
   attempt to provide a global namespace across regions, since that would imply
   uniformity in performance or fault characteristics.

From these constraints, we define some design principles:

1. Manta presents an HTTP interface (with REST-based PUT/GET/DELETE operations)
   as the primary way of reading and writing data.  Because there's only one
   copy of data, and some data needs to be available publicly (e.g., on the
   internet over standard protocols), HTTP is a good choice.
2. Manta is an *object store*, meaning that it only provides PUT/GET/DELETE for
   *entire objects*.  You cannot write to the middle of an object or append to
   the end of one.  This constraint makes it possible to guarantee strong
   consistency and high availability, since only the metadata tier (i.e., the
   namespace) needs to be strongly consistent, and objects themselves can be
   easily replicated for availability.

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

## Further reading

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
