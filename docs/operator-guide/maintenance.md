# Manta Operator Maintenance

*([Up to the Manta Operator Guide front page.](./))*

This section describes how an operator can maintain a Manta deployment:
upgrading components; using Manta's alarming system, "madtom" dashboard, and
service logs; and some general inspection/debugging tasks.

## Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Upgrading Manta components](#upgrading-manta-components)
  - [Manta services upgrades](#manta-services-upgrades)
    - [Prerequisites](#prerequisites)
    - [Procedure](#procedure)
  - [Manta deployment zone upgrades](#manta-deployment-zone-upgrades)
  - [Amon Alarm Updates](#amon-alarm-updates)
  - [Triton zone and agent upgrades](#triton-zone-and-agent-upgrades)
  - [Platform upgrades](#platform-upgrades)
  - [SSL Certificate Updates](#ssl-certificate-updates)
  - [Changing alarm contact methods](#changing-alarm-contact-methods)
- [Overview of Operating Manta](#overview-of-operating-manta)
  - [Alarms](#alarms)
  - [Madtom dashboard (service health)](#madtom-dashboard-service-health)
  - [Logs](#logs)
    - [Historical logs](#historical-logs)
    - [Real-time logs and log formats](#real-time-logs-and-log-formats)
  - [Request Throttling](#request-throttling)
    - [Throttle Parameter Trade-offs](#throttle-parameter-trade-offs)
  - [Picker/Storinfo toggle](#pickerstorinfo-toggle)
- [Debugging: general tasks](#debugging-general-tasks)
  - [Locating servers](#locating-servers)
  - [Locating storage IDs](#locating-storage-ids)
  - [Locating Manta component zones](#locating-manta-component-zones)
  - [Accessing systems](#accessing-systems)
  - [Locating Object Data](#locating-object-data)
    - [Locating Object Metadata](#locating-object-metadata)
    - [Locating Object Contents](#locating-object-contents)
  - [Debugging: was there an outage?](#debugging-was-there-an-outage)
  - [Debugging API failures](#debugging-api-failures)
  - [Authcache (mahi) issues](#authcache-mahi-issues)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


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
method for all zones.

### Prerequisites

1. Figure out which image you want to install. You can list available images by
   running updates-imgadm:

        headnode$ channel=$(sdcadm channel get)
        headnode$ updates-imgadm list -C $channel name=mantav2-webapi

    Replace mantav2-webapi with some other image name, or leave it off to
    see all images. Typically you'll want the most recent one. Note the uuid of
    the image in the first column.

2. Figure out which zones you want to reprovision. In the headnode GZ of a given
   datacenter, you can enumerate the zones and versions for a given manta\_role
   using:

        headnode$ manta-adm show webapi

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

5. HAProxy should automatically pick up the new certificate.  To confirm:

        # Verify your new certificate is in place
        headnode$ manta-oneach -s loadbalancer 'cat /opt/smartdc/muppet/etc/ssl.pem`

        # Verify the loadbalancer is serving the new certificate
        headnode$ manta-oneach -s loadbalancer \
            'echo QUIT | openssl s_client -host 127.0.0.1 -port 443 -showcerts'


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
  `/var/log/$service.log`).
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
| muskie                                      | /var/svc/log/\*muskie\*.log      | bunyan             |
| moray                                       | /var/log/moray.log               | bunyan             |
| mbackup<br />(the log file uploader itself) | /var/log/mbackup.log             | bash xtrace        |
| haproxy                                     | /var/log/haproxy.log             | haproxy-specific   |
| zookeeper                                   | /var/log/zookeeper/zookeeper.log | zookeeper-specific |
| redis                                       | /var/log/redis/redis.log         | redis-specific     |

Most of the remaining components log in bunyan format to their service log file
(including binder, config-agent, electric-moray, manatee-sitter, and others).



## Request Throttling

Manta provides a coarse request throttle intended to be used when the system is
under extreme load and is suffering availability problems that cannot be
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

## Picker/Storinfo toggle

There are two options for webapi to obtain storage node information - "picker"
and "storinfo". Both of them query the moray shard that maintains the storage
node `statvfs` data, keep a local cache and periodically refresh it, and
select storage nodes for object write requests.

Storinfo is an optional service which is separate from webapi. If storinfo is
not deployed you should configure webapi to use the local picker function by
setting the `WEBAPI_USE_PICKER` SAPI variable to `true` under the "webapi"
service:

    $ sdc-sapi /services/$(sdc-sapi /services?name=webapi | json -Ha uuid) \
        -X PUT -d '{"action": "update", "metadata": {"WEBAPI_USE_PICKER": true}}'


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


## Locating storage IDs

Manta Storage CNs have additional identifiers known as storage IDs. The one or
more manta storage IDs are used for object metadata.  There's one storage
ID per storage zone deployed on a server, so there can be more than one
storage ID per CN, although this is usually only the case in development
environments.

You can generate a table that maps hostnames to storage IDs for
the current datacenter:

    # manta-adm cn -o host,storage_ids storage
    HOST     STORAGE IDS
    RM08213  2.stor.us-east.joyent.us
    RM08211  1.stor.us-east.joyent.us
    RM08216  3.stor.us-east.joyent.us
    RM08219  4.stor.us-east.joyent.us

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
  allocated when an object is first created.

You won't need the following fields to locate the object, but they may be useful
to know about:

* "key": the internal name of this object (same as the public name, but the
  login is replaced with the user's uuid)
* "owner": uuid of the user being billed for this link.
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

In HTTP, codes under 300 are normal.  Codes from 400 to 500 (including 400, not
500) are generally client problems.  Codes over 500 indicate server problems.
Some number of 500 errors don't necessarily indicate a problem with the service
-- it could be a bug or a transient problem -- but if the number is high
(particularly compared to normal hours), then that may indicate a
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


## Authcache (mahi) issues

Please see the docs included in the mahi repository.
