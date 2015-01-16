<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2015, Joyent, Inc.
-->

# Manta developer notes

This document has miscellaneous documentation for Manta developers, including
how components are put together during the build and example workflows for
testing changes.

Anything related to the *operation* of Manta, including how Manta works at
runtime, should probably go in the Manta Operator's Guide instead.

The high-level basics are documented in the main README in this repo.  That
includes information on dependencies, how to build and deploy Manta, the
repositories that make up Manta, and more.  This document is for more
nitty-gritty than makes sense for the README.

## Manta zone build and setup

You should look at the instructions in the README for actually building and
deploying Manta.  This section is a reference for developers to understand how
those procedures work under the hood.

Most Manta components are deployed as *zones*, based on *images* built from a
single *repo*.  Examples are above, and include *muppet* and *muskie*.

For a typical zone (take "muppet"), the process from source code to deployment
works like this:

1. Build the repository itself.
2. Build an image (which is basically a zone filesystem template) from the
   contents of the built repository.
3. Publish the image to updates.joyent.com.
4. Import the image into an SDC instance.
5. Provision a new zone from the imported image.
6. During the first boot, the zone executes a one-time setup script.
7. During the first and all subsequent boots, the zone executes another
   configuration script.

There are tools to automate most of this (and again, for using them, see the
links above):

* Mountain Gorilla (MG), part of the [SDC](http://github.com/joyent/sdc) build
  process, takes care of steps (1) through (3).  It does this by cloning the
  repo, using a "make" target to build a tarball to be splatted down onto a bare
  zone, deploys a bare zone, splats down the tarball, and uses the SDC APIs to
  create a new image from that zone.  This image basically represents a template
  filesystem with which instances of this component will be stamped out.  After
  the image is built, it gets uploaded to updates.joyent.com.
* The "manta-init" command takes care of step 4.  You run this as part of any
  deployment.  See the [Manta Operator's Guide](https://joyent.github.io/manta)
  for details.  After the first run, basically all it does is find new images in
  updates.joyent.com, import them into the current SDC instance, and mark them
  for use by "manta-deploy".
* The "manta-adm" and "manta-deploy" commands (whichever you choose to use) take
  care of step 5.  See the Manta Operator's Guide for details.
* Steps 6 and 7 happen automatically when the zone boots as a result of the
  previous steps.

For more information on the zone setup and boot process, see the
[manta-scripts](https://github.com/joyent/manta-scripts) repo.


## Testing changes inside an actual Manta deployment

There are automated tests in many repos, but it's usually important to test
changed components in the context of a full Manta deployment as well.  You have
a few options, but for all of them you'll need to have a local Manta deployment
that you can deploy to.

Some repos (including marlin, mola, and mackerel) may have additional
suggestions for testing them.

## Zone-based components (including Manta deployment tools)

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

## Marlin agent

If you're changing the Marlin agent, either use the normal build and upgrade
process for agents (see the Manta Operator's Guide) or use the "mru" tool (see
the README in the marlin repo).

## Building and deploying your own zone images

As described above, Manta's build and deployment model is exactly like SDC's,
which is that most components are delivered as zone images and deployed by
provisioning new zones from these images.  While the deployment tools are
slightly different than SDC's, the build process is nearly identical.  The
common instructions for building zone images is part of the [SDC
documentation](https://github.com/joyent/sdc/blob/master/docs/developer-guide/building.md).  

### Building with your changes

By default, Mountain Gorilla is configured to build #master from the canonical
(github) repositories.  If you want to build from your local changes instead,
then *before* running "configure" in MG, modify targets.json.in so that the
"url" for your repo points to your copy of the repo rather than the canonical
(github) copy.  For example:

           "zookeeper-client-3.4.3"
         ],
         "repos": [
    -      {"url": "git@github.com:joyent/manta-madtom.git"}
    +      {"url": "/home/dap/manta-madtom"}
         ],
         "public": true,
         "deps": [

MG will clone this repo, so it won't pick up any uncommitted local changes.
If you change your repo, you'll need to reconfigure again to pick up the
changes.

### What if you're changing dependencies?

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

This approach ensures that the MG build picks up your private copy of both
madtom and the node-checker dependency.  Remember that this change needs to be
committed in order for MG to pick it up.  But when you're ready for the final
push, be sure to push your changes to the dependency first, and remember to
remove (don't just revert) the above change to the zone's package.json!
