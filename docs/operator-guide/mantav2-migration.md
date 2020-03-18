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

1. Update **every "webapi" service instance to a mantav2-webapi image**. Any
   image published after 2019-12-09 will do. Then **run `mantav2-migrate
   snaplink-cleanup` from the headnode global zone of every DC**.

   Until webapis are updated, the command will error out something like this:

    ```
    [root@headnode (mydc) ~]# mantav2-migrate snaplink-cleanup
    Determining if webapi instances in this DC are at V2.

    * * * snaplink cleanup is incomplete * * *
    Snaplinks cannot be fully cleaned until all webapi instances are
    are updated to a V2 image that no longer allows new snaplinks
    to be created.

    - You must upgrade all webapi instances in this DC (mydc) to a recent enough
      V2 image (after 2019-12-09), and then re-run "mantav2-migrate
      snaplink-cleanup" to update snaplink-cleanup progress.
    * * *

    mantav2-migrate snaplink-cleanup: error: webapi upgrades are required before snaplink-cleanup can proceed
    ```

<a name="snaplink-discovery"/>

2. Discover every snaplink. This involves working through each Manta index
   shard to find all the snaplinked objects. This is done by:

    - manually running a "snaplink-sherlock.sh" script against the async manatee
      for each shard,
    - copying the generated "{region}_{shard}_sherlock.tsv.gz" file back to a
      common directory, then
    - re-running `mantav2-migrate snaplink-cleanup` to process those files.

   Until those "sherlock" files are obtained, the command will error out
   something like this:

    ```
    XXX
    ```




XXX
```
svcadm -z 53b4478c-2626-4ab7-9eb3-5221cd508bad disable svc:/manta/application/muskie:muskie-8081
svcadm -z 53b4478c-2626-4ab7-9eb3-5221cd508bad enable svc:/manta/application/muskie:muskie-8081


sdc-sapi /applications/ce061150-2f08-407d-8744-1b8996cf07c4 | json metadata.SNAPLINK_CLEANUP_PROGRESS -H | json

echo '{"metadata": {"SNAPLINK_CLEANUP_PROGRESS": "{\"infoFromDc\":{\"coal\":{\"webapiAtV2\":true}},\"driverDc\":\"coal\"}"}}' | sapiadm update ce061150-2f08-407d-8744-1b8996cf07c4

echo '{"metadata": {"SNAPLINK_CLEANUP_PROGRESS": "{\"infoFromDc\":{\"coal\":{\"webapiAtV2\":true}},\"driverDc\":\"coal\"}"}}' | sapiadm update ce061150-2f08-407d-8744-1b8996cf07c4

echo '{"action": "delete", "metadata": {"SNAPLINK_CLEANUP_PROGRESS": null}}' | sapiadm update ce061150-2f08-407d-8744-1b8996cf07c4


```

## Step 3: GCv2

XXX

## Step 4: Recommended service updates

XXX

## Step 5: Optional service updates

XXX

## Step 6: Additional clean up

XXX
