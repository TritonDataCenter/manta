# Manta User Guide

Manta is a highly scalable, distributed object storage service. This guide
describes how to use the service.

# Features

Some features of the service include:

* An HTTP API
* Multiple data center replication with per object replication controls
* Unlimited number of objects with no size limit per object
* Read-after-write consistency


# Documents in this User Guide

* [Libraries / SDKs](./sdks.md)
* [CLI Command Reference](./commands-reference.md)
* [Storage Reference](./storage-reference.md)
* [Role-Based Access Control Guide](./rbac.md)


# Getting Started

## User accounts, authentication, and security

To use Manta, you need a Triton account.
([Triton](https://github.com/joyent/triton) is the cloud management platform on
which a Manta runs.) If you don't already have an account, contact your
administrator. Once you have signed up, you will need to add an SSH public key
to your account. The SSH key is used to authenticate you with the Manta API.

## Install the Node.js Manta tools

The Manta node.js SDK provides a node.js library and CLI tools for using Manta
from the command-line. First install [node.js](http://nodejs.org/), then:

    npm install -g manta

Verify that it installed successfully and is on your PATH by using `mls`, one
of the Manta CLI tools:

    $ mls --version
    5.2.1

## Setting Up Your Environment

While you can specify command line switches to all of the node-manta CLI
programs, it is significantly easier for you to set them globally in your
environment. There are four environment variables that all Manta command-line
tools look for:

* `MANTA_URL` - The https API endpoint.

* `MANTA_USER` - Your account login name.

* `MANTA_KEY_ID` - The fingerprint of your SSH key. This can be calculated
   using `ssh-keygen -l ...`. For example:

    ```
    $ ssh-keygen -l -f ~/.ssh/id_rsa.pub | awk '{print $2}'
    SHA256:qJjQoXlVnG940ZGWIgIrLm2lWbRFWk7nDKKzbLMtU4I
    ```

    If the key is loaded into your ssh-agent, then `ssh-add -l` will show the
    fingerprint as well.

* `MANTA_SUBUSER` - Optional. This is only required if using [role-based access
  control](./rbac.md). A sub-user of the `MANTA_USER` account with configured
  limited access.

For example, you might have something like the following in your shell profile
file (`~/.profile`, `~/.bashrc`, etc.):

    export MANTA_URL=https://us-east.manta.example.com
    export MANTA_USER=john.smith
    export MANTA_KEY_ID=$(ssh-keygen -l -f ~/.ssh/id_rsa.pub | awk '{print $2}')


Everything works if typing `mls /$MANTA_USER/` returns the top level contents.

    $ mls /$MANTA_USER/
    public/
    stor/

The shortcut `~~` is equivalent to typing `/$MANTA_USER`. Since many operations
require full Manta paths, you'll find it useful. We will use it for the
remainder of this document.

    $ mls ~~/
    public/
    stor/


# CLI

The command-line tools for Manta's directory-style API are generally analogs
of common Unix tools: `mls` is similar to `ls`, `mmkdir` for `mkdir`,
`mrm` for `rm`. See the [Command Reference](./commands-reference.md) for docs
on each of these tools.

## Objects

Objects are the main entity you will use. An object is non-interpreted data of
any size that you read and write to the store. Objects are immutable. You cannot
append to them or edit them in place. When you overwrite an object, you
completely replace it.

By default, objects are replicated to two physical servers, but you can specify
between one and six copies, depending on your needs. You will be charged for the
number of bytes you consume, so specifying one copy is half the price of two,
with the trade-off being a decrease in potential durability and availability.

For more complete coverage of how Manta stores objects, see the
[Storage Reference](./storage-reference.md).

When you write an object, you give it a name. Object names (keys) look like Unix
file paths. This is how you would create an object named `~~/stor/hello-foo`
that contains the data in the file "hello.txt":

    $ echo "Hello, Manta" > /tmp/hello.txt
    $ mput -f /tmp/hello.txt ~~/stor/hello-foo
    .../stor/hello-foo    [==========================>] 100%      13B

    $ mget ~~/stor/hello-foo
    Hello, Manta

The service fully supports streaming uploads, so piping a file also works:

    $ curl -sL http://www.gutenberg.org/ebooks/120.txt.utf-8 | \
        mput -H 'content-type: text/plain' ~~/stor/treasure_island.txt

In the example above, we don't have a local file, so `mput` doesn't attempt to
set the MIME type. To make sure our object is properly readable by a browser, we
set the HTTP `Content-Type` header explicitly.

## "~~/stor" and "~~/public"

Now, about `~~/stor`. Your "namespace" is `/:login/stor`. This is where all of
your data that you would like to keep private is stored. You can create any
number of objects and directories in this namespace without conflicting with
other users.

In addition to `/:login/stor`, there is also `/:login/public`, which allows for
unauthenticated reads over HTTP and HTTPS. This directory is useful for
you to host world-readable files, such as media assets you would use in a CDN.

## Directories

All objects can be stored in Unix-like directories. `/:login/stor` is the top
level private directory and `/:login/public` your top-level public directory.
You can logically think of these like `/` in Unix environments. You can create
any number of directories and sub-directories, but there is a limit of one
million entries in a single directory.

Directories are useful when you want to logically group objects (or other
directories) and be able to list them. Here are a few examples of
creating, listing, and deleting directories:

    $ mmkdir ~~/stor/stuff

Without an argument, `mls` defaults to `~~/stor`:

    $ mls
    stuff/
    treasure_island.txt
    $ mls ~~/stor/stuff
    $ mls -l ~~/stor
    drwxr-xr-x 1 john.smith             0 May 15 17:02 stuff
    -rwxr-xr-x 1 john.smith        391563 May 15 16:48 treasure_island.txt
    $ mmkdir -p ~~/stor/stuff/foo/bar/baz
    $ mrmdir ~~/stor/stuff/foo/bar/baz
    $ mrm -r ~~/stor/stuff


<!--
TODO: it would be good to give an intro to `mfind`, `msign`, and others.
-->
