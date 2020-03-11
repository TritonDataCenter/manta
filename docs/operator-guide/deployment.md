# Manta Deployment

*([Up to the Manta Operator Guide front page.](../))*


## Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Planning a Manta deployment](#planning-a-manta-deployment)
  - [Choosing the number of datacenters](#choosing-the-number-of-datacenters)
  - [Choosing the number of metadata shards](#choosing-the-number-of-metadata-shards)
  - [Choosing the number of storage and non-storage compute nodes](#choosing-the-number-of-storage-and-non-storage-compute-nodes)
  - [Choosing how to lay out zones](#choosing-how-to-lay-out-zones)
  - [Example single-datacenter, multi-server configuration](#example-single-datacenter-multi-server-configuration)
  - [Example three-datacenter configuration](#example-three-datacenter-configuration)
  - [Other configurations](#other-configurations)
- [Deploying Manta](#deploying-manta)
  - [Post-Deployment Steps](#post-deployment-steps)
    - [Prerequisites](#prerequisites)
    - [Set up a Manta Account](#set-up-a-manta-account)
    - [Test Manta from the CLI Tools](#test-manta-from-the-cli-tools)
  - [Networking configuration](#networking-configuration)
  - [manta-adm configuration](#manta-adm-configuration)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


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
  **moray**, **postgres**, **ops**, **madtom**), there
  should be at least two of each kind of zone in the entire deployment (for
  availability), and they should not be in the same datacenter (in order to
  survive a datacenter loss).  For single-datacenter deployments, they should at
  least be on separate compute nodes.
* Only one **madtom** zone is considered required.  It
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
* **garbage-collector** zones should not be configured to poll more than 6
  shards. Further, they should not be co-located with instances of other
  CPU-intensive Manta components (e.g. loadbalancer)  to avoid interference
  with the data path.

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

        sdcadm post-setup common-external-nics  # enable downloading service images
        sdcadm post-setup manta --mantav1

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
       "manta-adm create-topology"; generate a "manta-adm" configuration file
       (see "manta-adm configuration" below); and finally run "manta-adm update
       config.json" to deploy those zones.  Your best bet is to examine the
       "manta-deploy-dev" script to see how it uses these tools.  See
       "manta-adm configuration" below for details on the input file to
       "manta-adm update".  Each of these steps is idempotent, but the shard and
       hash ring must be set up before deploying any zones.

10. If desired, set up connectivity to the "ops" and
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
tools [in the User Guide](./user-guide/#getting-started).

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
