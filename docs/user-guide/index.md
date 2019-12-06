---
title: Getting Started
markdown2extras: wiki-tables
---

<!--
This page is to only use the node.js CLI examples. The curl one is for the web api
-->

<!--
Standard Opening Paragraph
-->

# Manta: Triton's object storage and converged analytics solution

Manta, Triton's object storage and converged analytics solution, is a highly scalable, distributed object storage service with integrated compute that enables the creation of analytics jobs (more generally, compute jobs) which process and transform data at rest. Developers can store and process any amount of data at any time where a simple web API call replaces the need for spinning up instances. Manta compute is a complete and high performance compute environment including R, Python, node.js, Perl, Ruby, Java, C/C++, ffmpeg, grep, awk and others. Metering is by the second with zero provisioning, data movement or scheduling latency costs.

This page describes the service and how to get started.  You can also skip
straight to some [compute examples](job-patterns.html).

# Features

Some features of the service include

* REST with JSON API.
* Multiple data center replication with per object replication controls.
* Unlimited number of objects with no size limit per object.
* Read-after-write consistency.
* Arbitrary object versioning using SnapLink.
* A filesystem-like interface (directories, objects and links).
* MapReduce processing with arbitrary scripts and code without data
  transfer.

# Some Use Cases

There are a number of use cases that become possible when you have a facility for running compute jobs directly on object storage nodes.

* Running a checksum over your data to assure its integrity
* Log processing: clickstream analysis, MapReduce on logs.
* Text processing including search.
* Image processing: converting formats, generating thumbnails, resizing.
* Video processing: transcoding, extracting segments, resizing.
* Data Analysis and Mining: using standard tools like NumPy, SciPy and R.

These are all possible without having to download or move your data to other
instances.  For more examples, see the [Job Examples and
Patterns](job-patterns.html) page.


# Real-world systems

These are systems that customers and Joyent engineers have built on top of
Manta.

* [Scaling Event-based Data Collection and
  Analysis](http://building.wanelo.com/2013/06/28/a-cost-effective-approach-to-scaling-event-based-data-collection-and-analysis.html):
  Wanelo stores user analytics and analyzes behavior with Manta
* [500 regression tests in 4
  minutes](https://www.joyent.com/blog/550-regression-tests-in-4-minutes-with-joyent-manta): The Node team uses Manta to run a test case against all commits in a repository to find which one introduced a regression
* [Kartlytics](http://kartlytics.com/): Mario Kart 64 analytics
* [Image Manipulation and
  Publishing](http://www.joyent.com/blog/manta-image-content-manipulation-and-publishing-example-part-1)
  using the Getty Open Content Image Set
* [Thoth](https://github.com/joyent/manta-thoth): Joyent stores and analyzes
  core dumps and crash dumps using Manta




# Sign Up

To use Triton's object storage, you need a Triton Compute account.  If
you don't already have an account, contact your administrator.

Once you have signed up, you will need to add an SSH public key to your account. Joyent recommends using RSA keys, as the node-manta CLI programs will work with RSA keys both locally, and with the `ssh agent`. DSA keys will only work if the
private key is on the same system as the CLI, and not password-protected.

<!--
Standard Closing Paragraph
-->

# An Integral Part of the Triton Public Cloud

The Triton object storage service is just one of a family of services. Triton Public Cloud services range from instances in our standard Persistent Compute Service (metered by the hour, month, or year) to our ephemeral Manta compute service (by the second).  All are designed to seamlessly work with our Object Storage and Data Services.

<!--
From this point on, this is the same exact material as inside the portal
-->

# Getting Started

This tutorial assumes you've signed up for a Joyent account and have an RSA public SSH key added to your account. We will cover installing the node.js SDK and CLI, setting up your shell environment variables, and then working through examples of creating directories, objects, links and finally running compute jobs on your data.

The CLI is the only tool used in these examples, and the instructions assume you're doing this from a Mac OS X, SmartOS, Linux or BSD system, and know how to use SSH and a terminal application such as Terminal.app. It helps to be familiar with basic Unix facilities like the shells, pipes, stdin, and stdout.

## Using the Mac OS X installer

If you do not have node.js installed you can use the complete installer for Mac. This installer installs node.js 0.10.x, npm, node-manta and smartdc.

[OS X Installer](https://us-east.manta.joyent.com/manta/public/sdks/joyent-node-latest.pkg)

## If You Have node.js Installed

If you have at least node.js 0.8.x installed (0.10.x is recommended) you can install the CLI and SDK from an npm package. All of the examples below work with both node.js 0.8.x and 0.10.x.

    $ sudo npm install manta -g

Additionally, as the API is JSON-based, the examples will refer to the
[json](https://github.com/trentm/json) tool, which helps put JSON output in a more human readable format. You can install from npm:

    $ sudo npm install json -g

Lastly, and while optional, if you want to use verbose debug logging with the
SDK, you will want [bunyan](https://github.com/trentm/node-bunyan):

    $ sudo npm install bunyan -g

## Setting Up Your Environment

While you can specify command line switches to all of the node-manta CLI
programs, it is significantly easier for you to set them globally in your
environment.  There are four environment variables that all command line tools look for:

* `MANTA_URL` - The API endpoint
* `MANTA_USER` - Your Triton Public Cloud account login name
* `MANTA_SUBUSER` - A user who has limited access to your account.
See [Role Based Access Control and Manta](rbac.html)
* `MANTA_KEY_ID` - The fingerprint of your SSH key.

Copy all of the text below, and paste it into your `~/.bash_profile` or `~/.bashrc`.

	export MANTA_URL=https://us-east.manta.joyent.com
	export MANTA_USER=$TRITON_CLOUD_USER_NAME
	unset MANTA_SUBUSER # Unless you have subusers
    export MANTA_KEY_ID=$(ssh-keygen -E md5 -l -f ~/.ssh/id_rsa.pub | awk '{print $2}' | tr -d '\n' | cut -d: -f 2-)

An easy way to do this in Mac OS X, is to copy the text, then use the `pbpaste` command
to add the text in the clipboard to your file. like this:

    $ pbpaste >> ~/.bash_profile

Edit the `~/.bash_profile` or `~/.bashrc` file, replacing `$TRITON_CLOUD_USER_NAME` with your Triton Public Cloud username.

Run

    source ~/.bash_profile

or

    source ~/.bashrc

or restart your terminal to pick up the changes you made to `~/.bash_profile` or `~/.bashrc`.

Everything works if typing `mls /$MANTA_USER/` returns the top level contents.

    $ mls /$MANTA_USER/
      jobs/
      public/
      reports/
      stor/
      uploads/

The shortcut `~~` is equivalent to typing `/$MANTA_USER`.
Since many operations require full Manta paths,
you'll find it useful. We will use it for the remainder
of this document.

    $ mls ~~/
      jobs/
      public/
      reports/
      stor/
      uploads/


# CLI

This Getting Started guide uses command line tools that are Manta analogs of common Unix tools (e.g. mls == ls). You can find man pages for these tools in the [CLI Utilities Reference](commands-reference.html)

# Create Data

Now that you've signed up, have the CLI and have your environment variables
set, you are ready to create data. In this section we will create an object, a
subdirectory for you to place another object in, and create a SnapLink to one of
those objects. These examples are written so that you can copy from here wherever you see a $ and paste directly into Terminal.app

If you're the kind of person who likes understanding "what all this is" before going through examples, you can read about the Storage Architecture in the [Object Storage Reference](storage-reference.html). Feel free to pause here, go read that, and then come right back to this point.

## Objects

Objects are the main entity you will use. An object is non-interpreted data of
any size that you read and write to the store. Objects are immutable. You cannot
append to them or edit them in place. When you overwrite an object, you
completely replace it.

By default, objects are replicated to two physical
servers, but you can specify between one and six copies, depending on your
needs. You will be charged for the number of bytes you consume, so specifying
one copy is half the price of two, with the trade-off being a decrease in potential durability and availability.

When you write an object, you give it a name. Object names (keys)
look like Unix file paths. This is how you would create an object named
`~~/stor/hello-foo` that contains the data in the file hello.txt:

    $ echo "Hello, Manta" > /tmp/hello.txt
    $ mput -f /tmp/hello.txt ~~/stor/hello-foo
    .../stor/hello-foo    [==========================>] 100%      13B

    $ mget ~~/stor/hello-foo
    Hello, Manta

The service fully supports streaming uploads, so piping the classic
"Treasure Island" would also work:

    $ curl -sL http://www.gutenberg.org/ebooks/120.txt.utf-8 | \
        mput -H 'content-type: text/plain' ~~/stor/treasure_island.txt

In the example above, we don't have a local file, so `mput` doesn't attempt to set the MIME type. To make sure our object is properly readable by a browser, we set the HTTP `Content-Type` header explicitly.

Now, about `~~/stor`. Your "namespace" is `/:login/stor`.
This is where all of your data that you would like to keep private is stored.
In a moment we'll make some directories, but you can create any number of
objects and directories in this namespace without conflicting with other users.

In addition to `/:login/stor`, there is also `/:login/public`, which allows for
unauthenticated reads over HTTP and HTTPS. This directory is useful for
you to host world-readable files, such as media assets you would use in a CDN.

## Directories

All objects can be stored in Unix-like directories. As you have seen, `/:login/stor` is the top
level directory. You can logically think of it like `/` in Unix environments.
You can create any number of directories and sub-directories, but there is a
limit to how many entries can exist in a single directory, which is 1,000,000
entries. In addition to `/:login/stor`, there are a few other top-level
"directories" that are available to you.

||**Directory**||**Description**||
||/:login/jobs||Job reports. Only you can read and destroy them; it is written by the system only.||
||/:login/public||Public object storage. Anyone can access objects in this directory and its subdirectories. Only you can create and destroy them.||
||/:login/reports||Usage and Access log reports.  Only you can read and destroy them; it is written by the system only.||
||/:login/uploads||Multipart uploads.  Ongoing multipart uploads are stored in this directory.||
||/:login/stor||Private object storage. Only you can create, destroy, and access objects in this directory and its subdirectories.||

Directories are useful when you want to logically group objects (or other
directories) and be able to list them efficiently (including feeding all the objects
in a directory into parallelized compute jobs). Here are a few examples of
creating, listing, and deleting directories:

    $ mmkdir ~~/stor/stuff
    $ mls
    stuff/
    treasure_island.txt
    $ mls ~~/stor/stuff
    $ mls -l ~~/stor
    drwxr-xr-x 1 loginname             0 May 15 17:02 stuff
    -rwxr-xr-x 1 loginname        391563 May 15 16:48 treasure_island.txt
    $ mmkdir -p ~~/stor/stuff/foo/bar/baz
    $ mrmdir ~~/stor/stuff/foo/bar/baz
    $ mrm -r ~~/stor/stuff

## SnapLinks

SnapLinks are a concept unique to the Manta service. SnapLinks
are similar to a Unix hard-link, and because the system is "copy on write," data
changes are not reflected in the SnapLink. This property makes SnapLinks a very
powerful entity that allows you to create any number of alternate names and
versioning schemes that you like.

As a concrete example, note what the following sequence of steps creates in
the objects `foo` and `bar`:

    $ echo "Object One" | mput ~~/stor/original
    $ mln ~~/stor/original ~~/stor/moved
    $ mget ~~/stor/moved
    Object One
    $ mget ~~/stor/original
    Object One
    $ echo "Object Two" | mput ~~/stor/original
    $ mget ~~/stor/original
    Object Two
    $ mget ~~/stor/moved
    Object One

As another example, while the service does not allow a "move" operation, you can
mimic a move with SnapLinks:

    $ mmkdir ~~/stor/books
    $ mln ~~/stor/treasure_island.txt ~~/stor/books/treasure_island.txt
    $ mrm ~~/stor/treasure_island.txt
    $ mls ~~/stor
	books/
	foo
	moved
	original
    $ mls ~~/stor/books
    treasure_island.txt

# Running Compute on Data

You have now seen how to work with objects, directories, and SnapLinks. Now it is
time to do some text processing.

The jobs facility is designed to support operations on an arbitrary number
of arbitrarily large objects.  While performance considerations may dictate the
optimal object size, the system can scale to very large datasets.

You perform arbitrary compute tasks in an isolated OS instance, using MapReduce
to manage distributed processing. MapReduce is a technique for dividing work
across distributed servers, and dramatically reduces network bandwidth as the
code you want to run on objects is brought to the physical server that holds the
object(s), rather than transferring data to a processing host.

The MapReduce implementation is unique in that you are given a full
OS environment that allows you to run *any* code, as opposed to being bound to a
particular framework/language. To demonstrate this, we will compose a MapReduce
job purely using traditional Unix command line tools in the following examples.

## Upload some datasets

First, let's get a few more books into our data collection so we're processing
more than one file:

    $ curl -sL http://www.gutenberg.org/ebooks/1661.txt.utf-8 | \
        mput -H 'content-type: text/plain' ~~/stor/books/sherlock_holmes.txt
    $ curl -sL http://www.gutenberg.org/ebooks/76.txt.utf-8 | \
        mput -H 'content-type: text/plain' ~~/stor/books/huck_finn.txt
    $ curl -sL http://www.gutenberg.org/ebooks/2701.txt.utf-8 | \
        mput -H 'content-type: text/plain' ~~/stor/books/moby_dick.txt
    $ curl -sL http://www.gutenberg.org/ebooks/345.txt.utf-8 | \
        mput -H 'content-type: text/plain' ~~/stor/books/dracula.txt

Now, just to be sure you've got the same 5 files (and to learn about `mfind`),
run the following:

    $ mfind ~~/stor/books
    ~~/stor/books/dracula.txt
    ~~/stor/books/huck_finn.txt
    ~~/stor/books/moby_dick.txt
    ~~/stor/books/sherlock_holmes.txt
    ~~/stor/books/treasure_island.txt

`mfind` is powerful like Unix find, in that you specify a starting point and use
basic regular expressions to match on names. This is another way to list the
names of all the objects (`-t o`) that end in `txt`:

    $ mfind -t o -n 'txt$' ~~/stor
    ~~/stor/books/dracula.txt
    ~~/stor/books/huck_finn.txt
    ~~/stor/books/moby_dick.txt
    ~~/stor/books/sherlock_holmes.txt
    ~~/stor/books/treasure_island.txt

## Basic Example

Here's an example job that counts the number of times the word "vampire" appears
in Dracula.

    $ echo ~~/stor/books/dracula.txt | mjob create -o -m "grep -ci vampire"
    added 1 input to 7b39e12b-bb87-42a7-8c5f-deb9727fc362
    32

This command instructs the system to run `grep -ci vampire` on
`~~/stor/books/dracula.txt`.  The `-o`
flag tells `mjob create` to wait for the job to complete and then fetch
and print the contents of the **output objects**. In this example, the result is 32.

In more detail: this command creates a **job** to run the **user script**
`grep -ci vampire` on each **input object** and then submits
`~~/stor/books/dracula.txt` as the only input to the job. The name of the
job is (in this case) `7b39e12b-bb87-42a7-8c5f-deb9727fc362`. When the job completes,
the result is placed in an **output object**, which you can see with the `mjob outputs`
command:

	$ mjob outputs 7b39e12b-bb87-42a7-8c5f-deb9727fc362
	/loginname/jobs/7b39e12b-bb87-42a7-8c5f-deb9727fc362/stor/loginname/stor/books/dracula.txt.0.1adb84bf-61b8-496f-b59a-57607b1797b0

The output of the user script is in the contents of the output object:

	$ mget $(mjob outputs 7b39e12b-bb87-42a7-8c5f-deb9727fc362)
	32


You can use a similar invocation to run the same job on all of the objects under
`~~/stor/books`:

    $ mfind -t o ~~/stor/books | mjob create -o -m "grep -ci human"
	added 5 inputs to 69219541-fdab-441f-97f3-3317ef2c48c0
	13
	48
	18
	4
	6

In this example, the system runs 5 invocations of `grep`. Each of these is called a **task**. Each task produces one output, and the job itself winds up with 5 separate outputs.

When searching for strings of text you need to put them inside single quotes

    $ echo ~~/stor/books/treasure_island.txt | mjob create -o -m "grep -ci 'you would be very wrong'"
    added 1 input to 67cf98ac-063a-4e86-861a-b9a8ebc3618d
    1

### Errors

If the grep command exits with a non-zero status (as grep does when it finds
no matches in the input stream) or fails in some other way (e.g., dumps core),
You'll see an error instead of an output object.  You can get details on the
error, including a link to stdout, stderr, and the core file (if any), using the
`mjob errors` command.

    $ mfind -t o ~~/stor/books | mjob create -o -m "grep -ci vampires"
    added 5 inputs to ef797aef-6254-4936-95a0-8b73414ff2f4
    mjob: error: job ef797aef-6254-4936-95a0-8b73414ff2f4 had 4 errors

In this job, the four errors do not represent actual failures, but just
objects with no match, so we can safely ignore them and look only at the output
objects.

And this last one should have 5 "errors"

    $ mfind -t o ~~/stor/books | mjob create -o -m "grep -ci tweets"
    added 5 inputs to ae47972a-c893-433a-a55f-b97ce643ffc0
    mjob: error: job ae47972a-c893-433a-a55f-b97ce643ffc0 had 5 errors

## Multiple phases and reduce tasks

We've just described the "map" phase of traditional map-reduce computations.
The "map" phase performs the same computation on each of the input objects. The
reduce phase typically combines the outputs from the map phase to produce a
single output.

One of the earlier examples computed the number of times the word "human" appeared
in each book. We can use a simple awk script in the **reduce** phase to get
the total number the of times "human" appears in all the books.

    $ mfind -t o ~~/stor/books | \
	        mjob create -o -m "grep -ci human" -r "awk '{s+=\$1} END{print s}'"
    added 5 inputs to 12edb303-e481-4a39-b1c0-97d893ce0927
    89

This job has two **phases**: the map phase runs `grep -ci human` on each input
object, then the reduce phase runs the awk script *on the concatenated output
from the first phase*. `awk '{s+=$1} END {print s}'` sums a list of numbers, so it sums the list of numbers that come out of the first phase. You can combine several map and reduce phases. The
outputs of any non-final phases become inputs for the next phase, and the
outputs of the final phase become job outputs.

While map phases always create one task for each input, reduce phases have a
fixed number of tasks (just one by default). While map tasks get the contents of
the input object on stdin as well as in a local file, reduce tasks only get a
concatenated stream of all inputs. The inputs may be combined in any order, but
data from separate inputs are never interleaved.

In the next example, we'll also introduce an alternative `^` and `^^` to the `-m` and `-r` flags, and see the first appearance of [maggr](maggr.html).

## Run a MapReduce Job to calculate the average word count

Now we have 5 classic novels uploaded, on which we can perform some basic
data analysis using nothing but Unix utilities. Let's first just see what
the "average" length is (by number of words), which we can do using just the
standard `wc` and the `maggr` command.


    $ mfind -t o ~~/stor/books | mjob create -o 'wc -w' ^^ 'maggr mean'
	added 5 inputs to 69b747da-e636-4146-8bca-84b883ca2a8c
	134486.4

Let's break down what just happened in that magical one-liner.  First, we'll
look at the `mjob create` command.  `mjob create -o` submits a new job, and then
waits for the job to finish, then fetches and concatenates the outputs for you,
which is very useful for interactive ad-hoc queries.  `'wc -w' ^^ 'maggr mean'`
is a MapReduce definition that defines a 'map' "phase" of `wc -w`, and a reduce
"phase" of `maggr mean`. `maggr` is one of several tools we have in the compute instances that mirror similar Unix tools.

A "phase" is simply a command (or chain of commands) to execute on data. There
are two types of phases: map and reduce. Map phases run the given command on
every input object and stream the output to the next phase, which may be another
map phase, or likely a reduce phase. Reduce phases are run once, and concatenate
all data output from the previous phase.

The system runs your map-reduce
commands by invoking them in a new
[bash](http://www.gnu.org/software/bash/manual/bashref.html) shell. By default
your input data is available to your shell over `stdin`, and if you simply write
output data to `stdout`, it is captured and moved to the next phase (this is how
almost all standard Unix utilities work).

`mjob create` uses the symbols `^` and `^^` to act like the standard
Unix `|` (pipe) operator. The single `^`
character indicates that the following command is part of the map phase. The double `^^`
indicates that the following command is a reduce phase.

In this syntax, the first phase is
always a map phase. So the string `'wc -w' ^^ 'maggr mean'`, means
"execute `wc -w` on all objects given to the job" and
"then run `maggr` mean on the data output from `wc -w`."
`maggr` is  a basic math utility function that is
part of the compute environment.

The above command could also have been written
as:

	$ mfind -t o ~~/stor/books | \
	  mjob create -o 'wc -w' ^^ 'paste -sd+ | echo "($(cat -))/$(mjob inputs $MANTA_JOB_ID | wc -l)" | bc'

Which would create a mathematical string that `bc` can use that sums and then
calculates the average by dividing by the number of inputs (which is retrieved
dynamically).


## Running Jobs Using Assets

Although the compute facility provides a full Joyent SmartOS environment,
your jobs may require special software, additional configuration information, or
any other static file that is useful. You can make these available as assets,
which are objects that are copied into the compute environment when your
job is run.

For example suppose you want to do a word frequency count using  shell scripts
that contain your map and reduce logic. We can do this with two awk scripts, so let's write
them and upload them as assets.

`map.sh` outputs a mapping of word to occurrence, like `hello 10`:

    #!/usr/bin/nawk -f
    {
        for (i = 1; i <= NF; i++) {
            counts[$i]++
        }
    } END {
        for (i in counts) {
            print i, counts[i];
        }
    }

Copy the above and paste into a file named `map.sh`, or if you are on Mac OS X, you can use the command below

    $ pbpaste > map.sh

`red.sh` simply combines the output of all the map outputs:

    #!/usr/bin/nawk -f
    {
        byword[$1] += $2;
    } END {
        for (i in byword) {
            print i, byword[i]
        }
    }

Copy the above and paste into a file named `red.sh`, or if you are on Mac OS X, you can use the command below

    $ pbpaste > red.sh

To make the scripts available as assets, first store them in the service.

    $ mput -f map.sh ~~/stor/map.sh
    $ mput -f red.sh ~~/stor/red.sh

Then use the `-s` switch to specify and use them in a job:

    $ mfind -t o ~~/stor/books |
        mjob create -o -s ~~/stor/map.sh \
        -m '/assets/$MANTA_USER/stor/map.sh' \
        -s ~~/stor/red.sh \
        -r '/assets/$MANTA_USER/stor/red.sh | sort -k2,2 -n'

You'll see a trailing output like

        ...
        a 13451
        to 14979
        of 15314
        and 21338
        the 32241

If you'd like to see how long this takes

    $ time mfind -t o ~~/stor/books |
        mjob create -o -s ~~/stor/map.sh \
                -m '/assets/$MANTA_USER/stor/map.sh' \
                -s ~~/stor/red.sh \
                -r '/assets/$MANTA_USER/stor/red.sh | sort -k2,2 -n'

The time output at the end will look like

        real    0m7.942s
	    user    0m1.324s
	    sys     0m0.169s

Note that assets are made available to you in the compute environment under the
path `/assets/$MANTA_USER/stor/...`. A more
sophisticated program would likely use a list of stopwords to get rid of
common words like "and, the" and so on, which could also be mapped in as an
asset.

## Advanced Usage

This introduction gave you a basic overview of Manta storage service: how
to work with objects and how to use the system's compute environment to operate on
those objects. The system provides many more sophisticated features, including:

* Running custom programs (instead of just the built-in programs)
* Emitting multiple outputs from a task (useful for chunking up large objects)
* Controlling the names of output objects (useful for jobs with side effects,
  like creating image thumbs)
* Multiple reducers in a single phase
* Emitting objects by reference

Let take you through some simple examples
of running node.js applications directly on the object store.
We'll be using some assets that are present in the `mantademo` account.
This is also a good example how you can
run compute with and on data people have
made available in their `~~/public` directories.

We'll start with a "Hello,Manta" demo using node.js, you can see the script with an `mget`:

    $ mget /mantademo/public/hello-manta-node.js
    console.log("hello,manta!!");

Now let's create a job using the what we talked about above in the [Running Jobs Using Assets](#running-jobs-using-assets) section. We're going to start by both something that's "obvious" and won't work.

    $ mjob create -s /mantademo/public/hello-manta-node.js -m "node /mantademo/public/hello-manta-node.js"
      30706a6b-6386-495b-9657-8a572b99d4f8  [this is a unique JOB ID]

    $ mjob get 30706a6b-6386-495b-9657-8a572b99d4f8 [replace with your actual JOB ID]

        {
          "id": "30706a6b-6386-495b-9657-8a572b99d4f8",
          "name": "",
          "state": "running",
          "cancelled": false,
          "inputDone": false,
          "stats": {
                    "errors": 0,
                    "outputs": 0,
                    "retries": 0,
                    "tasks": 0,
                    "tasksDone": 0
                    },
          "timeCreated": "2013-06-16T19:47:30.610Z",
          "phases": [
                     {
                       "assets": [
                                   "/mantademo/public/hello-manta-node.js"
                                 ],
                       "exec": "node /mantademo/public/hello-manta-node.js",
                       "type": "map"
                      }
                    ],
          "options": {}
        }


The `inputDone` field is "false" because we asked `mjob` to create a map phase, which requires at least one key, but  we did not provide any keys. It's sort of an artifact of the hello world example and makes a important point.

Let's cancel this job, in fact, let's cancel all jobs so we can clean up anything we've left running from the examples above.

    $ mjob list -s running | xargs mjob cancel

This also highlights that any CLI tool is normal Unix. The following two commands are equivalent.

    $ mjob get `mjob list`

    $ mjob list | xargs mjob get

Back to the node.js example, if we pipe the `hello-manta-node.js` in as a key and do it as a map phase with the `-m` flag:

    $ echo /mantademo/public/hello-manta-node.js | mjob create -o -m "node"
      added 1 input to e7711dda-caac-412f-9355-61c8006819ae
      hello,manta!!

We can also do this as a reduce phase (using the `-r` flag). Reduce phases always run, even without keys.

    $ mjob create -o </dev/null -s /mantademo/public/hello-manta-node.js \
                  -r "node /assets/mantademo/public/hello-manta-node.js"
      hello,manta!!

The flag `-o </dev/null` is that so that we're redirecting from `/dev/null` and `mjob create` knows to not attempt to read any additional keys.

Now let's take it up one more level. You can see what's inside a simple node.js application that capitalizes all the text in an input file.

    $ mget /mantademo/public/capitalizer.js

      #!/usr/bin/env node
        process.stdin.on('data', function(d) {
          process.stdout.write(d.toString().replace(/\./g, '!').toUpperCase());
        });
        process.stdin.resume();

    $ mget /mantademo/public/manta-desc.txt

      Joyent Manta Storage Service is a cloud service that offers both a highly
      available, highly durable object store and integrated compute. Application
      developers can store and process any amount of data at any time, from any
      location, without requiring additional compute resources.

    $ echo /mantademo/public/manta-desc.txt | mjob create -o -s /mantademo/public/capitalizer.js -m 'node /assets/mantademo/public/capitalizer.js'
      added 1 input to 2aa8a0a9-92e9-47f3-8b66-acf2a22d25a8
      JOYENT MANTA STORAGE SERVICE IS A CLOUD SERVICE THAT OFFERS BOTH A HIGHLY
      AVAILABLE, HIGHLY DURABLE OBJECT STORE AND INTEGRATED COMPUTE! APPLICATION
      DEVELOPERS CAN STORE AND PROCESS ANY AMOUNT OF DATA AT ANY TIME, FROM ANY
      LOCATION, WITHOUT REQUIRING ADDITIONAL COMPUTE RESOURCES!

For more details compute jobs see the
[Compute Jobs Reference documentation](http://apidocs.joyent.com/manta/jobs-reference.html), along with the [default installed software](compute-instance-software.html) and some of our [built-in compute utilities](compute-instance-utilities.html).
