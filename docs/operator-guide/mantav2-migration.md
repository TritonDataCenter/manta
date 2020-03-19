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
- [Step 2: Snaplink cleanup](#step-2-snaplink-cleanup)
  - [Step 2.1: Update webapis to V2](#step-21-update-webapis-to-v2)
  - [Step 2.2: Select the driver DC](#step-22-select-the-driver-dc)
  - [Step 2.3: Discover every snaplink](#step-23-discover-every-snaplink)
  - [Step 2.4: Run delinking scripts](#step-24-run-delinking-scripts)
  - [Step 2.5: Update webapi configs and restart.](#step-25-update-webapi-configs-and-restart)
  - [Step 2.6: Tidy up "sherlock" leftovers from stage 3.](#step-26-tidy-up-sherlock-leftovers-from-stage-3)
- [Step 3: GCv2](#step-3-gcv2)
- [Step 4: Recommended service updates](#step-4-recommended-service-updates)
- [Step 5: Optional service updates](#step-5-optional-service-updates)
- [Step 6: Additional clean up](#step-6-additional-clean-up)

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


## Step 1: Manta deployment zone

The first step is to update the Manta deployment tooling (i.e. the manta
deployment zone) to a mantav2 image. Run the following **on the headnode global
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

XXX While in development use:

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

XXX
```
mantav2-migrate status
```


<a name="snaplink-cleanup" />

## Step 2: Snaplink cleanup

Mantav1 supported a feature called "snaplinks" where a new object could be
quickly created from an existing one by linking to it. These snaplinks must be
"delinked" -- i.e. changed from being metadata-tier references to a shared
storage-tier object, to being fully separate objects -- before the new
garbage-collector and rebalancer services in mantav2 can function.

Snaplink cleanup involves a few stages, some of which are manual. The
`mantav2-migrate snaplink-cleanup` command is used to coordinate the process.
(It stores cross-DC progress in the `SNAPLINK_CLEANUP_PROGRESS` SAPI metadatum.)
You will re-run that command multiple times, in each of the DCs that are part
of the Manta region, and follow its instructions.


### Step 2.1: Update webapis to V2

Update **every "webapi" service instance to a mantav2-webapi image**. Any image
published after 2019-12-09 will do. Then **run `mantav2-migrate
snaplink-cleanup` from the headnode global zone of every DC in this Manta
region**.

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

### Step 2.2: Select the driver DC

Select the driver DC. Results from subsequent phases need to be collected
in one place. Therefore, if this Manta region has multiple DCs, then you
will be asked to choose one of them on which to coordinate. This is called
the "driver DC". Any of the DCs in the Manta region will suffice.


<a name="snaplink-discovery"/>

### Step 2.3: Discover every snaplink

Discover every snaplink. This involves working through each Manta index
shard to find all the snaplinked objects. This is done by:

- manually running a "snaplink-sherlock.sh" script against the async
  postgres for each shard,
- copying the generated "{region}_{shard}_sherlock.tsv.gz" file back to a
  common directory on the driver DC, then
- re-running `mantav2-migrate snaplink-cleanup` to process those files.

Until those "sherlock" files are obtained, the command will error out
something like this:

```
[root@headnode (mydc) ~]# mantav2-migrate snaplink-cleanup
Phase 1: All webapi instances are running V2.
Driver DC: mydc (this one)


# Phase 3: Discovery

In this phase, you must run the "snaplink-sherlock.sh" tool against
the async postgres for each Manta index shard. That will generate a
"myregion_{shard}_sherlock.tsv.gz" file that must be copied back
to "/var/db/snaplink-cleanup/discovery/" on this headnode.

Repeat the following steps for each missing shard:
    https://github.com/joyent/manta/blob/master/docs/operator-guide/mantav2-migration.md#snaplink-discovery

Missing "*_sherlock.tsv.gz" for the following shards (1 of 1):
    1.moray

mantav2-migrate snaplink-cleanup: error: sherlock files must be generated and copied to "/var/db/snaplink-cleanup/discovery/" before snaplink cleanup can proceed
```

You must **do the following for each listed shard**:

- Find the postgres instance that is currently the async for that shard. (If
  this is a development Manta with no async, then the sync or primary can be
  used.) The output from the following generally can help find those
  instances, assuming there is a postgres instance for each instance in this
  DC:

    ```
    manta-adm show -a | grep ^postgres
    manta-oneach -s postgres 'manatee-adm show'
    ```

- Ensure the replication **"lag" for that async is not too long**. It is
  imperative that the lag be less than the time since all webapis were
  updated to V2.

- Determine the datacenter and server holding that instance.

- Copy the "snaplink-sherlock.sh" script to that server's global zone.

    ```
    ssh $datacenter

    server_uuid=...

    manta0_vm=$(vmadm lookup -1 tags.smartdc_role=manta)
    sdc-oneachnode -n "$server_uuid" -X -d /var/tmp \
        -g "/zones/$manta0_vm/root/opt/smartdc/manta-deployment/tools/snaplink-sherlock.sh"
    ```

- SSH to that server's global zone, and run that script with the postgres
  VM UUID as an argument. **Run this in screen or equivalent because
  this can take a long time to run.**

    ```
    ssh root@$server_ip

    cd /var/tmp
    screen
    bash ./snaplink-sherlock.sh "$postgres_async_vm_uuid"
    ```

- Copy the created "/var/tmp/{{region}}_{{shard}}_sherlock.tsv.gz" file
  back to **"/var/db/snaplink-cleanup/discovery/" on the driver DC**.
  If this Manta region has multiple DCs, this may be a different DC.

Then **re-run `mantav2-migration snaplink-cleanup` on the driver DC** to
process the sherlock files. At any point you may re-run this command to
list the remaining shards to work through.


### Step 2.4: Run delinking scripts

After the previous stage, the `mantav2-migration snaplink-cleanup` command
will generate a number of "delinking" scripts that must be manually run on
the appropriate manta service instances. With a larger Manta, expect this
to be a bit labourious.

You must do the following in order:

1. **Run each "/var/db/snaplink-cleanup/delink/\*\_stordelink.sh" script
   on the appropriate Manta storage node.** I.e. in the mako zone for
   that storage\_id. The `storage_id` is included in the filename.

   There will be *zero or one* "stordelink" scripts for each storage node.

2. Only after those are all run successfully, **run each
   "/var/db/snaplink-cleanup/delink/\*\_moraydelink.sh" script
   on a Manta moray instance for the appropriate shard.** The shard is
   included in the filename.

   It is important to complete step #1 before running the "moraydelink"
   scripts, otherwise metadata will be updated to point to object ids
   for which no storage file exists.

   There will be one "moraydelink" script for each index moray shard
   (`INDEX_MORAY_SHARDS` in Manta metadata).

3. **Re-run `mantav2-migration snaplink-cleanup` and confirm** the scripts
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

        # {region}_{storage_id}_stordelink.sh
        ls /var/db/snaplink-cleanup/delink/*_stordelink.sh

   Use the following to help locate each storage node:

        manta-adm show -a -o service,storage_id,datacenter,zonename,gz_host,gz_admin_ip | grep ^storage

2. **Only after** these have all been run, run each "*_moraydelink.sh"
   script on a moray zone for the appropriate shard. There is
   one script for each Manta index shard (1):

        # {region}_{shard}_moraydelink.sh
        ls /var/db/snaplink-cleanup/delink/*_moraydelink.sh

   Use the following to help locate a moray for each shard:

        manta-adm show -o service,shard,zonename,gz_host,gz_admin_ip | grep ^moray

When you are sure you have run all these scripts, then answer
the following to proceed. *WARNING* Be sure you have run all
these scripts successfully, otherwise lingering snaplinks in the
system can cause the garbage-collector and rebalancer systems
to lose data.

Enter "delinked" when all delink scripts have been successfully run:
```

After confirming, `mantav2-migrate snaplink-cleanup` will remove the
`SNAPLINK_CLEANUP_REQUIRED` metadatum to indicate that snaplink cleanup
is complete!

```
XXX
```

However, there are a couple more steps.


### Step 2.5: Update webapi configs and restart.

Update webapi configs and restart.

XXX

XXX what about rebal? Rebal will kill USR1 to reload config automatically.

    Correct the SNAPLINK_CLEANUP_REQUIRED var name?
    Fix this.
```
$ rg SNAPLINK
manager/src/config.rs
494:            .insert_bool("SNAPLINKS_CLEANUP_REQUIRED", true)
613:        // Change SNAPLINKS_CLEANUP_REQUIRED to false
616:            .insert_bool("SNAPLINKS_CLEANUP_REQUIRED", false)

sapi_manifests/rebalancer/template
3:    {{#SNAPLINKS_CLEANUP_REQUIRED}}
5:    {{/SNAPLINKS_CLEANUP_REQUIRED}}
```


### Step 2.6: Tidy up "sherlock" leftovers from stage 3.


Sherlock cleanup:

```
[root@headnode (coal) /var/tmp]# vmadm list alias=~^snaplink-sherlock- owner_uuid=00000000-0000-0000-0000-000000000000
UUID                                  TYPE  RAM      STATE             ALIAS
19f12a13-d124-4255-9258-1f2f51138f0c  OS    2048     stopped           snaplink-sherlock-f8bd09a5

[root@headnode (coal) /var/tmp]# zfs list -t snapshot | grep manatee@sherlock
zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-83626        5.80M      -  22.1M  -
zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-84693         248K      -  22.2M  -
zones/f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6/data/manatee@sherlock-24879         267K      -  89.5M  -
```

    XXX START HERE




XXX trent notes

```
svcadm -z 53b4478c-2626-4ab7-9eb3-5221cd508bad disable svc:/manta/application/muskie:muskie-8081
svcadm -z 53b4478c-2626-4ab7-9eb3-5221cd508bad enable svc:/manta/application/muskie:muskie-8081


sdc-sapi /applications/ce061150-2f08-407d-8744-1b8996cf07c4 | json metadata.SNAPLINK_CLEANUP_PROGRESS -H | json
sdc-sapi /applications/ce061150-2f08-407d-8744-1b8996cf07c4 | json metadata.SNAPLINK_CLEANUP_REQUIRED -H

echo '{"metadata": {"SNAPLINK_CLEANUP_PROGRESS": "{\"infoFromDc\":{\"coal\":{\"webapiAtV2\":true}},\"driverDc\":\"coal\"}"}}' | sapiadm update ce061150-2f08-407d-8744-1b8996cf07c4

echo '{"metadata": {"SNAPLINK_CLEANUP_PROGRESS": "{\"infoFromDc\":{\"coal\":{\"webapiAtV2\":true}},\"driverDc\":\"coal\"}"}}' | sapiadm update ce061150-2f08-407d-8744-1b8996cf07c4

echo '{"action": "delete", "metadata": {"SNAPLINK_CLEANUP_PROGRESS": null}}' | sapiadm update ce061150-2f08-407d-8744-1b8996cf07c4

# quick sherlock run
cd /var/tmp
manta0_vm=$(vmadm lookup -1 tags.smartdc_role=manta)
bash /zones/$manta0_vm/root/opt/smartdc/manta-deployment/tools/snaplink-sherlock.sh  f8bd09a5-769e-4dd4-b53d-ddc3a56c8ae6

# quick delink planner
gzcat <dumpFile.gz> | ./snaplink-kill-planner.js <shardId>


    [root@S12612524404885 (nightly-1) /var/tmp/joshw]# gzcat 1.moray.manta_dump.gz | ./snaplink-kill-planner.js 1.moray
    Writing files to: ./1.moray.20191217T180922267Z/
    Writing ./1.moray.20191217T180922267Z/1.moray.sh
    Writing ./1.moray.20191217T180922267Z/3.stor.nightly.joyent.us.sh
    Writing ./1.moray.20191217T180922267Z/1.stor.nightly.joyent.us.sh
    Writing ./1.moray.20191217T180922267Z/2.stor.nightly.joyent.us.sh
    Lines: 8, mdata Updates: 8
    [root@S12612524404885 (nightly-1) /var/tmp/joshw]
```


## Step 3: GCv2

XXX

## Step 4: Recommended service updates

XXX

## Step 5: Optional service updates

XXX

## Step 6: Additional clean up

XXX
