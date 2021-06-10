# Manta Developer Guide

This document has miscellaneous documentation for Manta developers, including
how components are put together during the build and example workflows for
testing changes.

Anything related to the *operation* of Manta, including how Manta works at
runtime, should go in the [Manta Operator Guide](../operator-guide) instead.

The high-level basics are documented in the [main README](../../README.md) in
this repo. That includes information on dependencies, how to build and deploy
Manta, the repositories that make up Manta, and more. This document is for more
nitty-gritty content than makes sense for the README.


## Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Development Tips](#development-tips)
- [Manta zone build and setup](#manta-zone-build-and-setup)
- [Testing changes inside an actual Manta deployment](#testing-changes-inside-an-actual-manta-deployment)
- [Zone-based components (including Manta deployment tools)](#zone-based-components-including-manta-deployment-tools)
- [Building and deploying your own zone images](#building-and-deploying-your-own-zone-images)
  - [Building with your changes](#building-with-your-changes)
  - [What if you're changing dependencies?](#what-if-youre-changing-dependencies)
- [Advanced deployment notes](#advanced-deployment-notes)
  - [Service Size Overrides](#service-size-overrides)
  - [Configuration](#configuration)
    - [Configuration Updates](#configuration-updates)
  - [Directory API Shard Management](#directory-api-shard-management)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


# Development Tips

To update the manta-deployment zone (a.k.a. the "manta0" zone) on a Triton
headnode with changes you've made to your local sdc-manta git clone:

    sdc-manta.git$ ./tools/rsync-to <headnode-ip>

To see which manta zones are deployed, use manta-adm show:

    headnode$ manta-adm show

To tear down an existing manta deployment, use manta-factoryreset:

    manta$ manta-factoryreset


# Manta zone build and setup

You should look at the instructions in the README for actually building and
deploying Manta.  This section is a reference for developers to understand how
those procedures work under the hood.

Most Manta components are deployed as *zones*, based on *images* built from a
single *repo*.  Examples are above, and include *muppet* and *muskie*.

For a typical zone (take "muppet"), the process from source code to deployment
works like this:

1. Build the repository itself.
2. Build an image (a zone filesystem template and some metadata) from the
   contents of the built repository.
3. Optionally, publish the image to updates.joyent.com.
4. Import the image into a Triton instance.
5. Provision a new zone from the imported image.
6. During the first boot, the zone executes a one-time setup script.
7. During the first and all subsequent boots, the zone executes another
   configuration script.

There are tools to automate most of this:

* The build tools contained in the `eng.git` submodule, usually found in
  `deps/eng` in manta repositories include a tool called `buildimage`
  which assembles an image containing the built Manta component.  The image
  represents a template filesystem with which instances of this
  component will be stamped out.  After the image is built, it can be uploaded
  to updates.joyent.com. Alternatively, the image can be manually imported to
  a Triton instance by copying the image manifest and image file
  (a compressed zfs send stream) to the headnode and running
  "sdc-imgadm import".
* The "manta-init" command takes care of step 4.  You run this as part of any
  deployment.  See the [Manta Operator's Guide](https://joyent.github.io/manta)
  for details.  After the first run, subsequent runs find new images in
  updates.joyent.com, import them into the current Triton instance, and mark
  them for use by "manta-deploy". Alternatively, if you have images that were
  manually imported using "sdc-imgadm import", then "manta-init" can be run
  with the "-n" flag to use those local images instead.
* The "manta-adm" and "manta-deploy" commands (whichever you choose to use) take
  care of step 5.  See the Manta Operator's Guide for details.
* Steps 6 and 7 happen automatically when the zone boots as a result of the
  previous steps.

For more information on the zone setup and boot process, see the
[manta-scripts](https://github.com/joyent/manta-scripts) repo.


# Testing changes inside an actual Manta deployment

There are automated tests in many repos, but it's usually important to test
changed components in the context of a full Manta deployment as well.  You have
a few options, but for all of them you'll need to have a local Manta deployment
that you can deploy to.

Some repos (including marlin, mola, and mackerel) may have additional
suggestions for testing them.


# Zone-based components (including Manta deployment tools)

You have a few options:

* Build your own zone image and deploy it.  This is the normal upgrade process,
  it's the most complete test, and you should definitely do this if you're
  changing configuration or zone setup.  It's probably the most annoying, but
  please help us streamline it by testing it and sending feedback.  For details,
  see below.
* Assuming you're doing your dev work in a zone on the Manta network, run
  whatever component you're testing inside that zone.  You'll have to write a
  configuration file for it, but you may be able to copy most of the
  configuration from another instance.
* Copy your code changes into a zone already deployed as part of your Manta.
  This way you don't have to worry about configuring your own instance, but
  it's annoying because there aren't great ways of synchronizing your changes.


# Building and deploying your own zone images

As described above, Manta's build and deployment model is exactly like Triton's,
which is that most components are delivered as zone images and deployed by
provisioning new zones from these images.  While the deployment tools are
slightly different than Triton's, the build process is nearly identical.  The
common instructions for building zone images are part of the [Triton
documentation](https://github.com/joyent/triton/blob/master/docs/developer-guide/building.md).

## Building with your changes

Building a repository checked out to a given git branch will include those
changes in the resulting image.

One exception, is any `agents` (for example
[`amon`](https://github.com/joyent/sdc-amon),
[`config-agent`](https://github.com/joyent/sdc-config-agent/),
[`registrar`](https://github.com/joyent/registrar), (there are others)) that
are bundled within the image.

At build-time, the build will attempt to build agents from the same branch
name as the checked-out branch of the component being built. If that branch
name doesn't exist in the respective agent repository, the build will use
the `master` branch of the agent repository.

To include agents built from alternate branches at build time, set
`$AGENT_BRANCH` in the shell environment. The build will then try to build
all required agents from that branch. If no matching branch is found for a given
agent, the build then will try to checkout the agent repository at the same
branch name as the checked-out branch of the component you're building, before
finally falling back to the `master` branch of that agent repository.

The mechanism used is described in the
[`Makefile.agent_prebuilt.defs`](https://github.com/joyent/eng/blob/master/tools/mk/Makefile.agent_prebuilt.defs),
[`Makefile.agent_prebuilt.targ`](https://github.com/joyent/eng/blob/master/tools/mk/Makefile.agent_prebuilt.targ),
and
[`agent-prebuilt.sh`](https://github.com/joyent/eng/blob/master/tools/agent_prebuilt.sh)
files, likely appearing as a git submodule beneath `deps/eng` in the
component repository.

## What if you're changing dependencies?

In some cases, you may be testing a change to a single zone that involves more
than one repository.  For example, you may need to change not just madtom, but
the node-checker module on which it depends.  One way to test this is to push
your dependency changes to a personal github clone (e.g.,
"davepacheco/node-checker" rather than "joyent/node-checker") and then commit a
change to your local copy of the zone's repo ("manta-madtom", in this case) that
points the repo at your local dependency:

    diff --git a/package.json b/package.json
    index a054b43..8ef5a35 100644
    --- a/package.json
    +++ b/package.json
    @@ -8,7 +8,7 @@
             "dependencies": {
                     "assert-plus": "0.1.1",
                     "bunyan": "0.16.6",
    -                "checker": "git://github.com/joyent/node-checker#master",
    +                "checker": "git://github.com/davepacheco/node-checker#master",
                     "moray": "git://github.com/joyent/node-moray.git#master",
                     "posix-getopt": "1.0.0",
                     "pg": "0.11.3",

This approach ensures that the build picks up your private copy of both
madtom and the node-checker dependency.  But when you're ready for the final
push, be sure to push your changes to the dependency first, and remember to
remove (don't just revert) the above change to the zone's package.json!



# Advanced deployment notes

## Service Size Overrides

Application and service configs can be found under the `config` directory in
sdc-manta.git.  For example:

    config/application.json
    config/services/webapi/service.json

Sometimes it is necessary to have size-specific overrides for these services
within these configs that apply during setup.  The size-specific override
is in the same directory as the "normal" file and has `.[size]` as a suffix.
For example, this is the service config and the production override for the
webapi:

    config/services/webapi/service.json
    config/services/webapi/service.json.production

The contents of the override are only the *differences*.  Taking the above
example:

    $ cat config/services/webapi/service.json
    {
      "params": {
        "networks": [ "manta", "admin" ],
        "ram": 768
      }
    }
    $ cat config/services/webapi/service.json.production
    {
      "params": {
        "ram": 32768,
        "quota": 100
      }
    }

You can see what the merged config with look like with the
`./bin/manta-merge-config` command.  For example:

    $ ./bin/manta-merge-config -s coal webapi
    {
      "params": {
        "networks": [
          "manta",
          "admin"
        ],
        "ram": 768
      },
      "metadata": {
        "MUSKIE_DEFAULT_MAX_STREAMING_SIZE_MB": 5120
      }
    }
    $ ./bin/manta-merge-config -s production webapi
    {
      "params": {
        "networks": [
          "manta",
          "admin"
        ],
        "ram": 32768,
        "quota": 100
      }
    }

Note that after setup, the configs are stored in SAPI.  Any changes to these
files will *not* result in accidental changes in production (or any other
stage).  Changes must be made via the SAPI api (see the SAPI docs for details).


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


## Directory API Shard Management

A shard is a set of moray buckets, backed by >1 moray instances and >=3
Postgres instances.  No data is shared between any two shards.  Many other manta
services may said to be "in a shard", but more accurately, they're using a
particular shard.

There are two pieces of metadata which define how shards are used:

    INDEX_MORAY_SHARDS          Shards used for the indexing tier
    STORAGE_MORAY_SHARD         Shard used for minnow (manta_storage) records

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

