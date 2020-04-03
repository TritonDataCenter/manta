# Mantav2 Migration

*([Up to the Manta Operator Guide front page.](./))*

This section describes how an operator can migrate a Mantav1 deployment to
the new Mantav2 major version. See [this document](../mantav2.md) for a
description of mantav2.

## Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Overview](#overview)
- [Step 1: Manta deployment zone](#step-1-manta-deployment-zone)
- [Step 2: Disable old GC](#step-2-disable-old-gc)
  - [Disabling old jobs-based GC](#disabling-old-jobs-based-gc)
  - [Deleting obsolete "tombstone" directories](#deleting-obsolete-tombstone-directories)
  - [Accelerated GC](#accelerated-gc)
- [Step 3: Snaplink cleanup](#step-3-snaplink-cleanup)
  - [Step 3.1: Update webapis to V2](#step-31-update-webapis-to-v2)
  - [Step 3.2: Select the driver DC](#step-32-select-the-driver-dc)
  - [Step 3.3: Discover every snaplink](#step-33-discover-every-snaplink)
  - [Step 3.4: Run delinking scripts](#step-34-run-delinking-scripts)
  - [Step 3.5: Remove the obsolete ACCOUNTS_SNAPLINKS_DISABLED metadatum](#step-35-remove-the-obsolete-accounts_snaplinks_disabled-metadatum)
  - [Step 3.6: Update webapi configs and restart](#step-36-update-webapi-configs-and-restart)
  - [Step 3.7: Tidy up "sherlock" leftovers from step 3.3](#step-37-tidy-up-sherlock-leftovers-from-step-33)
  - [Step 3.8: Archive the snaplink-cleanup files](#step-38-archive-the-snaplink-cleanup-files)
- [Step 4: Deploy GCv2](#step-4-deploy-gcv2)
- [Step 5: Remove obsolete Manta jobs services and instances](#step-5-remove-obsolete-manta-jobs-services-and-instances)
- [Step 6: Recommended service updates](#step-6-recommended-service-updates)
- [Step 7: Optional service updates](#step-7-optional-service-updates)
- [Step 8: Additional clean up](#step-8-additional-clean-up)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Overview

The procedure to migrate a mantav1 to mantav2 will roughly be the following.
Specific steps will be provided later in this document.

1. Convert the **manta deployment zone** from mantav1 to mantav2. This is the
   point at which the operator is warned that this migration is not reversible
   and that mantav2 is backward incompatible.

        sdcadm self-update --latest
        sdcadm post-setup manta

2. **Snaplink cleanup**. Snaplinks must be cleaned from the system, otherwise
   the new GC and rebalancer systems cannot guarantee data integrity.

3. Deploy the **new garbage collector** (GCv2) system.

4. **Recommended service updates.** This is where obsolete mantav1 service
   instances (marlin, jobpuller, jobsupervisor, marlin-dashboard, and medusa)
   can be undeployed. As well, any or all remaining Manta services can be
   updated to their latest "mantav2-\*" images.

5. **Optional service updates.** The new rebalancer service and the services
   that make up the new Buckets API can be deployed.

6. **Additional clean up.** Some orphaned data (related to the removed jobs
   feature and to the earlier GC system) can be removed.

Other than the usual possible brief downtimes for service upgrades, this
migration procedure does not make Manta unavailable at any point.

The following instructions use **bold** to indicate the explicit steps that must
be run.


## Step 1: Manta deployment zone

The first step is to update the Manta deployment tooling (i.e. the manta
deployment zone) to a mantav2 image. **Run the following on the headnode global
zone of every datacenter in the Manta region:**

```
sdcadm self-update --latest
sdcadm post-setup manta
```

**or** if using specific image UUIDs:

```
sdcadm_image=...
manta_deployment_image=...

sdcadm self-update $sdcadm_image
sdcadm post-setup manta -i $manta_deployment_image
```

**or** (XXX) while in development use the following to get feature branch builds:

```
# MANTA-4811 and MANTA-4874
sdcadm_image=$(updates-imgadm -C experimental list name=sdcadm -j | json -c '~this.tags.buildstamp.indexOf("PR-60-")' -a uuid | tail -1)
manta_deployment_image=$(updates-imgadm list -C experimental name=mantav2-deployment version=~PR-60- --latest -H -o uuid)

sdcadm self-update -C experimental $sdcadm_image
sdcadm post-setup manta -C experimental -i $manta_deployment_image
```


The `sdcadm post-setup manta` command will warn that the migration process is
not reversible and require an interactive confirmation to proceed. The new manta
deployment image provides a `mantav2-migrate` tool that will assist with some of
the subsequent steps.


## Step 2: Disable old GC


### Disabling old jobs-based GC

The jobs-based GC (and other jobs-based tasks such as "audit" and metering)
in the Manta "ops" zone (aka "mola") are obsolete and can/should be disabled
if they aren't already. **Disable all "ops" service jobs via the following:**

```
sapiadm update $(sdc-sapi /services?name=ops | json -Ha uuid) metadata.DISABLE_ALL_JOBS=true
```

### Deleting obsolete "tombstone" directories

The old GC system used a delayed-delete mechanism where deleted files were
put in a daily "/manta/tombstone/YYYY-MM-DD" directory on each storage node.
**Optionally check the disk usage of and remove the obsolete tombstone directories
by running the following in *every datacenter* in this region:**

```
manta-oneach -s storage 'du -sh /manta/tombstone'

# Optionally:
manta-oneach -s storage 'rm -rf /manta/tombstone'
```

For example, the following shows that very little space (~2kB per storage node)
is being used by tombstone directories in this datacenter:

```
[root@headnode (mydc-1) ~]# manta-oneach -s storage 'du -sh /manta/tombstone'
SERVICE          ZONE     OUTPUT
storage          ae0096a5 2.0K  /manta/tombstone
storage          38b50a82 2.0K  /manta/tombstone
storage          cd798768 2.0K  /manta/tombstone
storage          ab7c6ef3 2.0K  /manta/tombstone
storage          12042540 2.0K  /manta/tombstone
storage          85d4b8c4 2.0K  /manta/tombstone
```

### Accelerated GC

Some Mantas may have deployed a garbage collection system called
"Accelerated GC":
[overview](https://github.com/joyent/manta/blob/mantav1/docs/operator-guide.md#accelerated-garbage-collection),
[deployment notes](https://github.com/joyent/manta/blob/mantav1/docs/operator-guide.md#deploy-accelerated-garbage-collection-components),
[operating/configuration notes](https://github.com/joyent/manta/blob/mantav1/docs/operator-guide.md#accelerated-garbage-collection-1),
[troubleshooting notes](https://github.com/joyent/manta/blob/mantav1/docs/operator-guide.md#troubleshooting-accelerated-garbage-collection).

Work through the following steps to determine if you have Accelerated GC and,
if so, to flush and disable it:


1.  Your Manta has Accelerated GC if you have deployed "garbage-collector"
    instances:

    ```
    [root@headnode (mydc-1a) ~]# manta-adm show -a garbage-collector
    SERVICE          SH DATACENTER ZONENAME
    garbage-collector  1 mydc-1a 65ad3602-959e-428d-bdee-f7915702c748
    garbage-collector  1 mydc-1a 03dae05c-2fbf-47cc-9d39-b57a362c1534
    garbage-collector  1 mydc-1a 655fe38c-4ec6-425e-bf0b-28166964308e
    ...
    ```

2.  Disable all garbage-collector SMF services to allow inflight instructions to
    drain:

    ```
    manta-oneach -s garbage-collector 'svcadm disable garbage-collector'
    ```

    Wait 5 minutes and check that all instructions have drained:

    ```
    manta-oneach -s garbage-collector 'du --inodes /var/spool/manta_gc/mako/* | sort -n | tail -3'
    ```

    The file counts should all be 1 (the subdirectory itself).

3.  **[For Manta deployment using "feeder" service only]** After 5 minutes,
    check that the feeder zone also has no inflight instructions:

    ```
    du --inodes /var/spool/manta_gc/mako/* | sort -n | tail -3
    ```

    The file counts should all be 1 (the subdirectory itself).

4.  Before upgrading a storage zone to the v2 image, check that its instruction
    directory is empty:

    -   **For Manta deployment using feeder service**

        ```
        du --inodes /var/spool/manta_gc/instructions
        ```

        The file count should be exactly 1 (the directory itself).

    -   **For Manta deployment without feeder service**

        ```
        minfo /poseidon/stor/manta_gc/mako/$(json -f /var/tmp/metadata.json -ga MANTA_STORAGE_ID) | grep result
        ```

        The result set size should be exactly 1 (the directory itself).


<a name="snaplink-cleanup" />

## Step 3: Snaplink cleanup

Mantav1 supported a feature called "snaplinks" where a new object could be
quickly created from an existing one by linking to it. These snaplinks must be
"delinked" -- i.e. changed from being metadata-tier references to a shared
storage-tier object, to being fully separate objects -- before the new
garbage-collector and rebalancer services in mantav2 can function. This section
walks through the process of removing snaplinks.

Snaplink cleanup involves a few stages, some of which are manual. The
`mantav2-migrate snaplink-cleanup` command is used to coordinate the process.
(It stores cross-DC progress in the `SNAPLINK_CLEANUP_PROGRESS` SAPI metadatum.)
You will re-run that command multiple times, in each of the DCs that are part
of the Manta region, and follow its instructions.


### Step 3.1: Update webapis to V2

Update **every "webapi" service instance to a mantav2-webapi image**. Any image
published after 2019-12-09 will do.

- First set the "WEBAPI_USE_PICKER" metadatum on the "webapi" service to
  have the new webapi instances not yet use the new "storinfo" service.
  (See [MANTA-5004](https://smartos.org/bugview/MANTA-5004) for details.)

    ```
    webapi_svc=$(sdc-sapi "/services?name=webapi&include_master=true" | json -H 0.uuid)
    echo '{"metadata": {"WEBAPI_USE_PICKER": true}}' | sapiadm update "$webapi_svc"
    ```

- Find and import the latest webapi image:

    ```
    # Find and import the latest webapi image.
    updates-imgadm -C $(sdcadm channel get) list name=mantav2-webapi
    latest_webapi_image=$(updates-imgadm -C $(sdcadm channel get) list name=mantav2-webapi -H -o uuid --latest)
    sdc-imgadm import -S https://updates.joyent.com $latest_webapi_image
    ```

- Update webapis to that new image:

    ```
    manta-adm show -js >/var/tmp/config.json
    vi /var/tmp/config.json  # update webapi instances

    manta-adm update /var/tmp/config.json
    ```

- Then **run `mantav2-migrate snaplink-cleanup` from the headnode global zone of
  every DC in this Manta region**.

Until webapis are updated, the command will error out something like this:

```
[root@headnode (mydc) ~]# mantav2-migrate snaplink-cleanup
Determining if webapi instances in this DC are at V2.


Phase 1: Update webapis to V2

Snaplinks cannot be fully cleaned until all webapi instances are
are updated to a V2 image that no longer allows new snaplinks
to be created.

- You must upgrade all webapi instances in this DC (mydc) to a recent enough
  V2 image (after 2019-12-09), and then re-run "mantav2-migrate
  snaplink-cleanup" to update snaplink-cleanup progress.

mantav2-migrate snaplink-cleanup: error: webapi upgrades are required before snaplink-cleanup can proceed
```


### Step 3.2: Select the driver DC

Select the driver DC. Results from subsequent phases need to be collected
in one place. Therefore, if this Manta region has multiple DCs, then you
will be asked to choose one of them on which to coordinate. This is called
the "driver DC". Any of the DCs in the Manta region will suffice.

If there is only a single DC in the Manta region, then it will automatically be
set as the "driver DC".


<a name="snaplink-discovery"/>

### Step 3.3: Discover every snaplink

Discover every snaplink. This involves working through each Manta index
shard to find all the snaplinked objects. This is done by manually running a
"snaplink-sherlock.sh" script against the postgres async VM for each shard,
and then copying back that script's output file. Until those "sherlock" files
are obtained, the command will error out something like this:

```
[root@headnode (mydc) ~]# mantav2-migrate snaplink-cleanup
Phase 1: All webapi instances are running V2.
Driver DC: mydc (this one)


# Phase 3: Discovery

In this phase, you must run the "snaplink-sherlock.sh" tool against
the async postgres for each Manta index shard. That will generate a
"{shard}_sherlock.tsv.gz" file that must be copied back
to "/var/db/snaplink-cleanup/discovery/" on this headnode.

Repeat the following steps for each missing shard:
    https://github.com/joyent/manta/blob/master/docs/operator-guide/mantav2-migration.md#snaplink-discovery

Missing "*_sherlock.tsv.gz" for the following shards (1 of 1):
    1.moray.coalregion.joyent.us

mantav2-migrate snaplink-cleanup: error: sherlock files must be generated and copied to "/var/db/snaplink-cleanup/discovery/" before snaplink cleanup can proceed
```

You must **do the following for each listed shard**:

- Find the postgres *VM UUID* (`postgres_vm`) that is currently the async for
  that shard, and the datacenter in which it resides. (If this is a development
  Manta with no async, then the sync or primary can be used.) The output from
  the following commands can help find those instances:

    ```
    manta-oneach -s postgres 'manatee-adm show'   # find the async
    manta-adm show -a postgres                    # find which DC it is in
    ```

- Copy the "snaplink-sherlock.sh" script to that server's global zone.

    ```
    ssh $datacenter   # the datacenter holding the postgres async VM

    postgres_vm="<the UUID of postgres async VM>"

    server_uuid=$(sdc-vmadm get $postgres_vm | json server_uuid)
    manta0_vm=$(vmadm lookup -1 tags.smartdc_role=manta)
    sdc-oneachnode -n "$server_uuid" -X -d /var/tmp \
        -g "/zones/$manta0_vm/root/opt/smartdc/manta-deployment/tools/snaplink-sherlock.sh"
    ```

- SSH to that server's global zone, and run that script with the postgres
  VM UUID as an argument. **Run this in screen or equivalent because
  this can take a long time to run.**

    ```
    manta-login -G $postgres_vm    # or 'ssh root@$server_ip'

    cd /var/tmp
    screen
    bash ./snaplink-sherlock.sh "$postgres_vm"
    ```

  See [this
  gist](https://gist.github.com/trentm/05611024c0c825cb083a475e3b60aab4) for an
  example run of snaplink-sherlock.sh.

- Copy the created "/var/tmp/{{shard}}_sherlock.tsv.gz" file
  back to **"/var/db/snaplink-cleanup/discovery/" on the driver DC**.
  If this Manta region has multiple DCs, this may be a different DC.

Then **re-run `mantav2-migrate snaplink-cleanup` on the driver DC** to
process the sherlock files. At any point you may re-run this command to
list the remaining shards to work through.


### Step 3.4: Run delinking scripts

After the previous stage, the `mantav2-migrate snaplink-cleanup` command
will generate a number of "delinking" scripts that must be manually run on
the appropriate manta service instances. With a larger Manta, expect this
to be a bit labourious.

You must do the following in order:

1.  **Run each "/var/db/snaplink-cleanup/delink/\*\_stordelink.sh" script
    on the appropriate Manta storage node.** I.e. in the mako zone for
    that storage\_id. The `storage_id` is included in the filename.

    There will be *zero or one* "stordelink" scripts for each storage node.
    Each script is idempotent, so can be run again if necessary. Each script
    will also error out if an attempt is made to run on the wrong storage node:

    ```
    [root@94b3a1ce (storage) /var/tmp]$ bash 1.stor.coalregion.joyent.us_stordelink.sh
    Writing xtrace output to: /var/tmp/stordelink.20200320T213234.xtrace.log
    1.stor.coalregion.joyent.us_stordelink.sh: fatal error: this stordelink script must run on '1.stor.coalregion.joyent.us': this is '3.stor.coalregion.joyent.us'
    ```

    A successful run looks like this:

    ```
    [root@94b3a1ce (storage) /var/tmp]$ bash 3.stor.coalregion.joyent.us_stordelink.sh
    Writing xtrace output to: /var/tmp/stordelink.20200320T213250.xtrace.log
    Completed stordelink successfully.
    ```

    Please report any errors in running these scripts.

2.  Only after those are all run successfully, **run each
    "/var/db/snaplink-cleanup/delink/\*\_moraydelink.sh" script
    on a Manta moray instance for the appropriate shard.** The shard is
    included in the filename.

    It is important to complete step #1 before running the "moraydelink"
    scripts, otherwise metadata will be updated to point to object ids
    for which no storage file exists.

    There will be one "moraydelink" script for each index moray shard
    (`INDEX_MORAY_SHARDS` in Manta metadata). Each script is idempotent, so can
    be run again if necessary. Each script will also error out if an attempt is
    made to run on the wrong shard node:

    ```
    [root@01f043b4 (moray) /var/tmp]$ bash 1.moray.coalregion.joyent.us_moraydelink.sh
    Writing xtrace output to: /var/tmp/moraydelink.20200320T211337.xtrace.log
    1.moray.coalregion.joyent.us_moraydelink.sh: fatal error: this moraydelink script must run on a moray for shard '1.moray.coalregion.joyent.us': this is '1.moray.coalregion.joyent.us'
    ```

    A successful run looks like this:

    ```
    [root@01f043b4 (moray) /var/tmp]$ bash 1.moray.coalregion.joyent.us_moraydelink.sh
    Writing xtrace output to: /var/tmp/moraydelink.20200320T214010.xtrace.log
    Completed moraydelink successfully.
    ```

    Please report any errors in running these scripts.

3.  **Re-run `mantav2-migrate snaplink-cleanup` and confirm** the scripts
    have successfully been run.

Here is an example run for this stage:

```
[root@headnode (mydc) ~]# mantav2-migrate snaplink-cleanup
Phase 1: All webapi instances are running V2.
Phase 2: Driver DC is "mydc" (this one)
Phase 3: Have snaplink listings for all (1) Manta index shards.
Created delink scripts in /var/db/snaplink-cleanup/delink.


# Phase 4: Running delink scripts

"Delink" scripts have been generated from the snaplink listings
from the previous phase. In this phase, you must:

1. Run each "*_stordelink.sh" script on the appropriate storage
   node to create a new object for each snaplink. There are 3 to run:

        # {storage_id}_stordelink.sh
        ls /var/db/snaplink-cleanup/delink/*_stordelink.sh

   Use the following to help locate each storage node:

        manta-adm show -a -o service,storage_id,datacenter,zonename,gz_host,gz_admin_ip storage

2. **Only after** these have all been run, run each "*_moraydelink.sh"
   script on a moray zone for the appropriate shard. There is
   one script for each Manta index shard (1):

        # {shard}_moraydelink.sh
        ls /var/db/snaplink-cleanup/delink/*_moraydelink.sh

   Use the following to help locate a moray for each shard:

        manta-adm show -o service,shard,zonename,gz_host,gz_admin_ip moray

When you are sure you have run all these scripts, then answer
the following to proceed. *WARNING* Be sure you have run all
these scripts successfully. If not, any lingering object that
has multiple links will have the underlying files removed
when the first link is deleted, which is data loss for the
remaining links.

Enter "delinked" when all delink scripts have been successfully run:
```


After confirming, `mantav2-migrate snaplink-cleanup` will remove the
`SNAPLINK_CLEANUP_REQUIRED` metadatum to indicate that all snaplinks have been
removed!

```
[root@headnode (mydc) ~]# mantav2-migrate snaplink-cleanup
...

Enter "delinked" when all delink scripts have been successfully run: delinked
Removing "SNAPLINK_CLEANUP_REQUIRED" metadatum.
All snaplinks have been removed!
```

However, there are a couple more steps.


### Step 3.5: Remove the obsolete ACCOUNTS_SNAPLINKS_DISABLED metadatum

Now that snaplinks have been removed, the old `ACCOUNTS_SNAPLINKS_DISABLED`
metadata is obsolete. Print the current value (for record keeping) and remove
it from the SAPI metadata:

```
manta_app=$(sdc-sapi /applications?name=manta | json -H 0.uuid)

sapiadm get "$manta_app" | json metadata.ACCOUNTS_SNAPLINKS_DISABLED

echo '{"action": "delete", "metadata": {"ACCOUNTS_SNAPLINKS_DISABLED": null}}' | sapiadm update "$manta_app"
```


### Step 3.6: Update webapi configs and restart

Now that the `SNAPLINK_CLEANUP_REQUIRED` config var has been removed, all
webapi instances need to be poked to get this new config. You must **ensure
every webapi instance restarts with updated config**.

A blunt process to do this is to run the following in every Manta DC in the
region:

```
manta-oneach -s webapi 'svcadm disable -s config-agent && svcadm enable -s config-agent && svcadm restart svc:/manta/application/muskie:muskie-*'
```

However, in a larger Manta with many webapi instances, you may want to
space those out.


### Step 3.7: Tidy up "sherlock" leftovers from step 3.3

Back in step 3.3, the "snaplink-sherlock.sh" script runs left some data
(VMs and snapshots) that should be cleaned up.

1.  **Run the following on the headnode global zone of every DC in this Manta
    region** to remove the "snaplink-sherlock-*" VMs:

    ```
    # First verify what will be removed:
    sdc-oneachnode -a 'vmadm list alias=~^snaplink-sherlock- owner_uuid=00000000-0000-0000-0000-000000000000'

    # Then remove those VMs:
    sdc-oneachnode -a 'vmadm lookup alias=~^snaplink-sherlock- owner_uuid=00000000-0000-0000-0000-000000000000 | while read uuid; do echo "removing snaplink-sherlock VM $uuid"; vmadm delete $uuid; done'
    ```

2.  **Run the following on the headnode global zone of every DC in this Manta
    region** to remove the "manatee@sherlock-*" ZFS snapshots:

    ```
    # First verify what will be removed:
    sdc-oneachnode -a "zfs list -t snapshot | grep manatee@sherlock- | awk '{print \$1}'"

    # Then remove those snapshots:
    sdc-oneachnode -a "zfs list -t snapshot | grep manatee@sherlock- | awk '{print \$1}' | xargs -n1 zfs destroy -v"
    ```


An example run looks like this:

```
[root@headnode (mydc) /var/tmp]# sdc-oneachnode -a 'vmadm lookup alias=~^snaplink-sherlock- owner_uuid=00000000-0000-0000-0000-000000000000 | while read uuid; do echo "removing snaplink-sherlock VM $uuid"; vmadm delete $uuid; done'
=== Output from 564d4042-6b0c-8ab9-ae54-c445386f951c (headnode):
removing snaplink-sherlock VM 19f12a13-d124-4255-9258-1f2f51138f0c
removing snaplink-sherlock VM 3a104161-d2cc-43e6-aeb4-462154aa7406
removing snaplink-sherlock VM 5e9e3a2a-efe6-4dbd-8c21-1bbdbf5c72d2
removing snaplink-sherlock VM 61a455fd-68a1-4b21-9676-38b191efca86
removing snaplink-sherlock VM 0364e94d-e831-430e-9393-96f85bd36702

[root@headnode (mydc) /var/tmp]#     sdc-oneachnode -a "zfs list -t snapshot | grep manatee@sherlock- | awk '{print \$1}' | xargs -n1 zfs destroy -v"
=== Output from 564d4042-6b0c-8ab9-ae54-c445386f951c (headnode):
will destroy zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-24879
will reclaim 267K
will destroy zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-39245
will reclaim 248K
will destroy zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-40255
will reclaim 252K
will destroy zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-41606
will reclaim 256K
will destroy zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-42555
will reclaim 257K
```


### Step 3.8: Archive the snaplink-cleanup files

It is probably a good idea to archive the snaplink-cleanup files for record
keeping. For example, run this on the driver DC:

```
(cd /var/db && tar czf /var/tmp/snaplink-cleanup-$(bash /lib/sdc/config.sh -json | json region_name).tgz snaplink-cleanup)
ls -l /var/tmp/snaplink-cleanup*.tgz
```

And then attach archive that tarball somewhere (perhaps attaching it to your
process ticket tracking snaplink removal, if small enough).


## Step 4: Deploy GCv2

The new garbage-collector system should be deployed.

1.  Follow [the GC deployment
    steps](https://github.com/joyent/manta-garbage-collector/tree/master/docs#deploying-the-garbage-collector).

2.  Update all "storage" service instances to a recent (2020-03-19 or later) "mantav2-storage" image.

    A direct way to do this is as follows. A production Manta operator may
    prefer to space out these storage node updates.

    ```
    # Find and import the latest storage image.
    updates-imgadm -C $(sdcadm channel get) list name=mantav2-storage
    latest_storage_image=$(updates-imgadm -C $(sdcadm channel get) list name=mantav2-storage -H -o uuid --latest)
    sdc-imgadm import -S https://updates.joyent.com $latest_storage_image

    # Update storages to that image
    manta-adm show -js >/var/tmp/config.json
    vi /var/tmp/config.json  # update storage instances
    manta-adm update /var/tmp/config.json
    ```

## Step 5: Remove obsolete Manta jobs services and instances

There are a number of Manta services that are obsoleted by mantav2 and can
(and should) be removed at this time. (Note: Remove of these services also
works before any of the above mantav2 migration steps, if they is easier.)

They services (and their instances) to remove are:

- jobpuller
- jobsupervisor
- marlin-dashboard
- medusa
- marlin
- marlin-agent (This is an agent on each server, rather than a SAPI service.)

(Internal Joyent ops should look at the appropriate [change-mgmt
template](https://github.com/joyent/change-mgmt/blob/master/change-plan-templates/mantav2/JPC/0-jobtier-remove.md)
for this procedure.)

A simplified procedure is as follows:


1. **Run the following in each Manta DC** to remove all service instances:

    ```bash
    function delete_insts {
        local svc=$1
        if [[ -z "$svc" ]]; then
            echo "delete_insts error: 'svc' is empty" >&2
            return 1
        fi
        echo ""
        echo "# delete service '$svc' instances"
        manta-adm show -Ho zonename "$svc" | xargs -n1 -I% sdc-sapi /instances/% -X DELETE
    }

    if [[ ! -f /var/tmp/manta-config-before-jobs-infra-cleanup.json ]]; then
        manta-adm show -js >/var/tmp/manta-config-before-jobs-infra-cleanup.json
    fi

    JOBS_SERVICES="jobpuller jobsupervisor marlin-dashboard medusa marlin"
    for svc in $JOBS_SERVICES; do
        delete_insts "$svc"
    done
    ```

1. **Run the following in each Manta DC** to remove the marlin agent on every server:

    ```
    sdc-oneachnode -a "apm uninstall marlin"
    ```

    Notes:
    - This can be re-run to catch missing servers. If the marlin agent
      is already removed, this will still run successfully on a server.
    - Until [MANTA-4798](https://smartos.org/bugview/MANTA-4798) is complete
      the marlin agent is still a part of the Triton "agentsshar", and hence
      will be *re-installed* when Triton agents are updated. This causes no
      harm. The above command can be re-run to re-remove the marlin agents.

2. **Run the following in one Manta DC** to clear out SAPI service entries:

    ```bash
    function delete_svc {
        local svc=$1
        if [[ -z "$svc" ]]; then
            echo "delete_svc error: 'svc' is empty" >&2
            return 1
        fi

        echo ""
        echo "# delete manta SAPI service '$svc'"
        local manta_app=$(sdc-sapi "/applications?name=manta&include_master=true" | json -H 0.uuid)
        if [[ -z "$manta_app" ]]; then
            echo "delete_svc error: could not find 'manta' app" >&2
            return 1
        fi
        local service_uuid=$(sdc-sapi "/services?name=$svc&application_uuid=$manta_app&include_master=true" | json -H 0.uuid)
        if [[ -z "$service_uuid" ]]; then
            echo "delete_svc error: could not find manta service '$svc'" >&2
            return 1
        fi
        sdc-sapi "/services/$service_uuid" -X DELETE
    }

    JOBS_SERVICES="jobpuller jobsupervisor marlin-dashboard medusa marlin"
    for svc in $JOBS_SERVICES; do
        delete_svc "$svc"
    done
    ```

## Step 6: Recommended service updates

- It is recommended that all current services be updated to the latest
  "mantav2-\*" image (the "webapi" and "storage" services have already been
  done above).
- The "storinfo" service should be deployed.
  (TODO: The operator guide, or here, should provide details for sizing/scaling
  the storinfo service.)


## Step 7: Optional service updates

At this point the services for the new "Rebalancer" system and the "Buckets API"
can be deployed.

(TODO: The operator guide and/or here should provide details for deploying
those.)


## Step 8: Additional clean up

There remain a few things that can be cleaned out of the system.
They are:

- Clean out the old GC-related `manta_delete_log` (`MANTA_DELETE_LOG_CLEANUP_REQUIRED`).
- Clean out obsolete reports files under `/:login/reports/' (`REPORTS_CLEANUP_REQUIRED`).
- Clean out archived jobs files under `/:login/jobs/` (`ARCHIVED_JOBS_CLEANUP_REQUIRED`).

However, details on how to clean those up are not yet ready (TODO). None of
this data causes any harm to the operation of mantav2.
