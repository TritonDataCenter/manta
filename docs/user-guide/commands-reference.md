---
title: CLI Utilities Reference
markdown2extras: wiki-tables, code-friendly
---

# CLI Utilities Reference

This document lists the command line interface (CLI) tools available from the
Joyent Manta [Node.js SDK](sdks.html#nodejs-sdk-and-cli) as well as the CLI tools available to you in the
compute environment.

# Client-Side Utilities

These commands are installed locally on your machine as part of the Joyent Manta Node.js SDK.
They are also available to your jobs in the compute environment.

* [mls](mls.html) - Lists directory contents
* [mput](mput.html) - Uploads data to an object
* [mget](mget.html) - Downloads an object from the service
* [minfo](minfo.html) - show HTTP headers for a Manta object
* [mjob](mjob.html) - Creates and runs a computational job on the service
* [mfind](mfind.html) - Walks a hierarchy to find names of objects by name, size, or type
* [mlogin](mlogin.html) - Interactive session client
* [mln](mln.html) - Makes link between objects
* [mmkdir](mmkdir.html) - Make directories
* [mmpu](mmpu.html) - Create and commit objects using multipart uploads
* [mrm](mrm.html) - Remove objects or directories
* [mrmdir](mrmdir.html) - Remove empty directories
* [msign](msign.html) - Create a signed URL to a object stored in the service
* [muntar](muntar.html) - Create a directory hierarchy from a tar file
* [mchmod](mchmod.html) - Change object role tags
* [mchattr](mchattr.html) - Change object attributes

# Compute Environment Utilities

These commands are available to your jobs in the compute environment.

* [maggr](maggr.html) - Performs key-wise aggregation on plain text files.
* [mcat](mcat.html) - Emits the named object as an output for the current task.
* [mpipe](mpipe.html) - Output pipe for the current task.
* [msplit](msplit.html) - Split the output stream for the current task to many reducers.
* [mtee](mtee.html) - Capture stdin and write to both stdout and a object.

See [Compute Environment Software](compute-instance-software.html) for a
list all of the software that is preinstalled in the compute environment.
