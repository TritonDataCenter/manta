---
title: Compute Jobs Reference
markdown2extras: wiki-tables, code-friendly
---

# Compute Jobs Reference

This is the reference documentation for Manta compute jobs. Unless otherwise
specified, the semantics described here are stable, which means that you can
expect that future updates will not change the documented behavior. You should
avoid relying on behavior not specified here.

You should be familiar with the Manta storage service before reading this
document. To learn the basics, see [Getting Started](index.html).


# Jobs Overview

## Terminology

Before getting started, it's worth describing some key terms:

* Users submit **jobs**, which specify **user scripts** to be run on any
  number of **input objects** to produce one or more **output objects**.
* Each job is made up of one or more **phases**, each of which is either a **map
  phase** or a **reduce phase**, and each with its own user script and other
  configuration.  Outputs of one phase become inputs to the next, and the last
  phase's outputs become outputs of the job.
* **Map phases** are divided into one **task** for each input object.  Each task
  executes the user script once, on the assigned input object.
* **Reduce phases** have a fixed number of tasks (1 by default).  Like with map
  tasks, each task executes the user script once, but on the concatenated stream
  of inputs assigned to that reducer instead of one object at a time.
* Each task runs inside an isolated **compute instance** on one of the servers
  in the fleet. Compute instances are isolated from each other and the rest of
  the system, though they do have access to the internet. Map tasks have
  read-only access to a local file representing the contents of the input
  object.

## Guiding principles

Several principles guide the design of the service:

* Jobs can operate on arbitrarily large numbers of arbitrarily large
  files.  See "System Scale" below for details.
* Even at scale, simple computations can be expressed simply: operations that
  are one-liners on a single file on your laptop are one-liners to run on a
  million objects using the built-in CLI.  Many basic tasks can be accomplished
  with familiar built-in tools like "grep", "awk", "sort", and so on.
* Jobs execute quickly enough to iterate interactively and get results in real
  time.
* Error cases are debuggable. In addition to providing stderr and core files,
  the task execution environment is very close to a standard Joyent Instance,
  which allows users to develop and debug jobs outside of the service if
  desired.
* Transient failure of individual system components are not visible to users
  (except for some performance impact).  See "Failures and internal retries"
  below for details on what this means.

On a per-operation basis, jobs provide the same strong consistency that the
storage system does, but since jobs are composed of many individual operations,
it's possible to see inconsistent results if the underlying data changes while
the job is running.  See "Processing inputs" for details.

In addition, jobs gain additional availability by retrying operations in the
case of internal failures.  So while a PUT may experience a 500 error
during certain failure conditions, job tasks will generally be retried in the
face of such failures, resulting in higher success rate at the cost of increased
latency.  See "Failures and internal retries" for details.


## System Scale

In order to scale to very large data sets, there are no _hardcoded_ limits on:

* the size of any input or output object processed by the system
* the number of tasks in a job, or in any phase of a job
* the number of input objects for a job
* the number of input objects for a reduce task
* the number of output objects for any task
* the number of errors emitted by any job

In practice, object sizes are limited by the maximum size file that can be
stored on storage servers as well as the largest practical HTTP request size.

The other quantities mentioned above are intended to be limited primarily to the
physical resources available to Manta rather than architectural limits.  Task
stdout and stderr are limited to the amount of local disk space requested for
each task.  (See "Advanced output" for details and ways to emit much larger
outputs.)  The system never operates on the full set of tasks, inputs, outputs,
or errors at once, nor does it provide APIs to do so until after the job has
finished running.  In practice, input and task counts over one hundred thousand
in a single job currently can result in poor performance for other jobs.

Some dimensions of the system are explicitly limited (e.g., the total number of
reducers, and the maximum number of phases in a job), but the established limits
are intended to be sufficient for reasonable usage.  These limits are subject to
change.


# Job configuration

The job configuration is mostly in the "phases" property, which might look like
this for a typical two-phase map-reduce job:

    {
        "phases":  [ {
            /*
             * "exec" is the actual bash script to run for each task.
             * "type" is "map" by default, which means there's one task for each
             * input object.
             */
            "exec": "grep -w main"
        }, {
            /*
             * Reduce tasks have a fixed number (instead of one per object), and
             * operate on a stream of all of their inputs concatenated together.
             */
            "type": "reduce",
            "exec": "/var/tmp/stackvis/bin/stackvis",

           /*
            * Use two reducers (not commonly necessary -- here for
            * illustration).  See "Multiple reducers" below.
            */
           "count": 2,

           /*
            * Ensure that we're using a modern image (not commonly necessary --
            * here for illustration).  See "Compute instance images" below.
            */
           "image": ">=13.1.0",

            /*
             * This job uses an asset that bundles the actual program to execute
             * along with its supporting data files.  We use an "init" script to
             * unpack the tarball before any tasks run.  See "Assets" below.
             */
            "assets": [ "/:login/stor/stackvis.tgz" ],
            "init": "cd /var/tmp && tar xzf /assets/:login/stor/stackvis.tgz",

            /*
             * Request additional memory and disk resources (at additional
             * cost).  See "Resource usage" below.
             */
            "memory": 2048,      /* megabytes */
            "disk": 16           /* gigabytes */
        } ]
    }

This is a complex example to illustrate the available properties.  Most jobs
will only use a few properties, and many jobs will only use "exec".


**Phase property reference**

|| **Name** || **Summary**                || **Default** || **See section**   ||
|| `type`   || `"map"` or `"reduce"`      || `"map"`   || "Tasks and task types"             ||
|| `exec`   || script to run per task     || none      || "Task lifetime, success, and failure"    ||
|| `assets` || extra objects to make available || `[]` || "Assets"            ||
|| `init`   || script to run before tasks || no script || "Initializing compute instance"    ||
|| `memory` || requested DRAM cap (MB)    || `1024`     || "Resource usage"    ||
|| `disk`   || requested disk quota (GB)  || `8`       || "Resource usage"    ||
|| `count`  || number of reducers         || `1`       || "Multiple reducers" ||
|| `image`  || image version dependency   || `"*"`     || "Compute instance images" ||


## Tasks and task types ("type" property)

The actual work of jobs is divided into tasks, each representing one invocation
of the user script.  Tasks are executed inside operating system containers
called "compute instances" that are isolated from each other and the rest of the
service.

For map phases, there's one task per input object.  Each map task has read-only
access to a local file representing the contents of that input object, and stdin
is redirected from that object.  Map tasks run as soon as resources are
available and are not blocked on the rest of the system once they start running.

For reduce phases, the number of tasks is configured statically by the "count"
property, which defaults to `1`.  Stdin for reduce tasks is a pipe to which the
contents of *all* of the reducer's input objects will automatically be
concatenated and written.  Reduce tasks generally don't start running until
either the first input becomes available or the end-of-input is reached, and
they may block once they start until more input becomes available or
end-of-input is reached.  Reduce tasks run even when given zero inputs.  Reduce
tasks have no direct access to inputs as files, since the objects may not be
stored locally, will not all be ready when the reduce task starts running, and
are not assumed to fit on a single server.

You'll notice that unlike other map-reduce services, Joyent Manta Storage
Service tasks operate at the granularity of a complete object. If you want to
process key-value pairs or something more structured, your script is responsible
for parsing the input. Many Unix tools natively parse whitespace-delimited text
formats, many other tools are available to parse other formats (e.g., json), and
you can always use custom programs (see "Assets" below).


## Task lifetime, success, and failure ("exec" property)

A task begins when the "exec" script is invoked with "bash -c".  Stdin is
redirected either from a local file (map) or a pipe (reduce) as described above.
Stdout and stderr are always redirected to local files for capture by the
system.

The task normally ends when that shell process exits, and the result is
successful if that process exits with status 0.  If the task succeeds, any
output is forwarded on to subsequent job phases (if any) or becomes final job
output (if not).  See "Advanced output" below for details.

If the task fails (either because the process exits with non-zero status or
because it or any of its child processes dump core), output is saved but not
forwarded on.  Stderr and any core file generated are also saved.  A
UserTaskError is emitted with a reference to the saved stderr and core file.

When the user process exits, any child processes it created are killed
immediately.  It's recommended that the first child process not exit until it
has first waited for any child processes that it has created to exit.

If any of these processes dumps core, the task ends as a failure, regardless of
what other processes are still running and regardless of the exit status of the
first process.

Where possible, the system may run multiple tasks from the same job and phase
sequentially in the same compute instance, so user scripts must be able to handle
state left over from previous tasks from the same phase.


## Assets ("assets" property)

Many tasks require programs, configuration files, or data files, which can be
stored as objects but are not part of the actual data stream.  You can
download these explicitly in an "init" script, but for convenience you can also
specify objects in a per-phase "assets" array.  Assets will be downloaded
into the compute instance before any "init" script is run (and so before any "exec"
script is run as well).

## Initializing compute instances ("init" property)

It's sometimes useful to perform some expensive setup operation once per compute
instance so that the tasks that run in that instance can assume that operation has
already been done.  A good example is unpacking a tarball that contains the
program files to be executed during the task.  You can do this with an "init"
script, which is executed with "bash -c" exactly once in each compute instance
before any tasks are run.

A common pattern is to bundle a Node.js or Python program as a tarball, specify
the tarball as an asset, use an "init" script to unpack the tarball once for
each compute instance, and run an executable from the unpacked tarball in the "exec"
script, as in:

    "phases": [ {
        "assets": [ "/:login/stor/stackvis.tgz" ],
        "init": "cd /var/tmp && tar xzf /assets/:login/stor/stackvis.tgz",
        "exec": "/var/tmp/stackvis/stackvis"
    } ]

If this script fails for any of the reasons that tasks fail (see below), the
tasks that would be run in that instance may fail with a TaskInitError.

The resources used by "init" scripts are charged to an arbitrary task that will
be run in that compute instance.


## Resource usage ("memory" and "disk" properties)

There are no explicit limits on CPU usage, network utilization, or disk I/O
utilization, but use of those resources may be limited based on availability.
This may vary across different tasks in the same job or tasks in different jobs.

By default, compute instances are given caps of 1024MB for both resident set
(memory) and anonymous memory.  The "memory" property of a phase allows users to
request more of both, as either 2GB, 4GB, or 8GB.  If that memory is available,
the task gets it.  Otherwise, the task may be queued until the memory becomes
available or it may fail with a TaskInitError if the service determines that
it's unlikely to have memory available any time soon.

Similarly, by default compute instances are given caps of 8GB of disk space.  The
"disk" property of a phase allows users to request more space in GB, as either
16GB, 32GB, 64GB, 128GB, 256GB, 512GB, or 1TB.  As with memory, if the space is
available, the task gets it.  Otherwise, the task may be queued until the disk
becomes available or it may fail with a TaskInitError if the service determines
that it's unlikely to have disk available any time soon.

**Note:** each task's stdout and stderr are staged to the local disk for the
duration of the task.  For programs that emit a lot of data to stdout or stderr,
the "disk" property may need to be adjusted accordingly.

These defaults are not stable.  If you intend to depend on these values, you
should explicitly specify "1024" for memory and "8" for disk.

## Multiple reducers ("count" property)

Sometimes it's necessary to pipeline the reduce phase so that instead of
processing all input objects in one pass, the input objects are processed in
chunks across multiple passes.  For example, you may want to process half of the
inputs in each of two parallel tasks, and then process the output of that, to
avoid having to load an entire data set in memory at once.

To support multiple reducers in parallel (i.e., in the same job phase), use the
"count" property:

    "phases": [
        ... /* any number of map phases */
        , {
            "type": "reduce",
            "exec": ...,
            "count": 2
        }, {
            "type": "reduce",
            "exec": ...
        }
    ]

In this example, some number of map phases are followed by a phase with two
reducers running in parallel, followed by a final reduce stage.  The two
parallel reducers are identical except for their input and output objects.

By default, inputs are randomly assigned to reducers.  If a more sophisticated
assignment is necessary (e.g., to ensure that certain groups of inputs are
processed by the same reducer), the previous map phase can specify to which
reducer a given output object will be assigned using the "-r" flag to `mpipe`,
which must be an integer between 0 and N - 1, where N is the total number of
reducers in the next phase.  Also see documentation for "msplit".


## Compute instance images ("image" property)

Compute instances are Joyent instances based on the manta-compute image. This
image is essentially a [base image](https://docs.joyent.com/public-cloud/instances/infrastructure/images/smartos/base)
with nearly all of the available packages preinstalled.

By default, tasks run in compute instances with the most recently released image
available.  You can specify a particular range of image versions using a
semver-like value for the "image" property (e.g., "13.1.\*").  If that image is
not available, tasks for that job will fail with an InvalidArgumentError.

**You're strongly discouraged from depending on an exact version of the image,
as Joyent may frequently release minor updates to existing images and retire
older versions as long as the new one is backwards-compatible.**  Dependencies
are intended so you can tie jobs to major releases, or "at least" a particular
minor release.

If you want to test your scripts and binaries in a Manta environment,
use the [`mlogin`](mlogin.html) command from your workstation.
See [Try your job with mlogin](jobs-reference.html#try-your-job-with-mlogin)
later in this document.


## Task environment and authentication

For convenience, several environment variables are set for the "exec" script:

* `PATH`: includes paths to system software, installed packages, standard
  CLI tools, and job-specific tools like `mpipe`.  The specific paths to
  these tools are subject to change, so it's not recommended to remove
  directories from the PATH or to save the full path to tools for use in other
  jobs at a later time.
* `MANTA_URL`: set to a API endpoint valid for use in the compute instance.
  While the current implementation uses HTTP (not HTTPS), the traffic flows over
  a secure internal network.
* `MANTA_USER`: account username of the user under whom the job is running
* `MANTA_INPUT_OBJECT` (map tasks only): the name of the object being
  processed.
* `MANTA_INPUT_FILE` (map tasks only): the full path to the local file
  corresponding to the object being processed.
* `MANTA_OUTPUT_BASE`: suggested base name for output objects, automatically
  generated based on the type of task and input object(s).
* `MANTA_JOB_ID`: current jobid

You can use the normal CLI tools (e.g., mls, mput, mget), which will use
the private `MANTA_URL` endpoint.  Requests to this endpoint are implicitly
authenticated as the user under whom the job is running, though no private keys
are available inside the compute instance.  You can also use other tools that use
the `MANTA_URL` and `MANTA_USER` environment variables.

Of course, if you want to make requests as another user for which you have the
private key available, you can do so by overriding the appropriate environment
variables, including `MANTA_URL`.


# Advanced output

The task's stdout and stderr are redirected to a local file on disk.  By
default, if the task succeeds, this file is uploaded and becomes the task's sole
output, which is forwarded to the next phase in the job (if any) or else become
outputs of the job itself (if not).  Intermediate objects are not directly
exposed to you, and may never even be stored, but final outputs are always
objects.  Because the stdout and stderr are staged to disk, these are limited in
size by the amount of local disk space available, which is controlled by the
"disk" property of the task's phase.  See the documentation on the "disk"
property for details.

Several tools are available in compute instances for more sophisticated types of
output.  In addition, users can make use of advanced input using the HTTP API
directly, which allows for emitting outputs not limited by the amount of local
disk space available.  See "Using the HTTP API for advanced output" below.


## mpipe: advanced output

Synopsis:

    mpipe [-p] [-r rIdx] [-H header:value ...] [manta path]

Each invocation of mpipe reads data from stdin, potentially buffers it to local
disk, and saves it as task output.  If a Joyent Manta Storage Service path is
given, the output is saved to that path.  Otherwise, the object is stored with a
unique name in the job's directory.  If -p is given, required parent directories
are automatically created (like "mkdir -p").

If you use mpipe in a task, the task's stdout will not be captured and saved as
it is by default.

As a simple example,

    $ wc | mpipe

is exactly equivalent to just:

    $ wc

since both capture the stdout of wc and emit it as a single output object.  But
you use mpipe for several reasons:

* **Naming**: Objects created through automatic stdout capture or through mpipe
  with no arguments are automatically given unique names.  You can control the
  name yourself by specifying an argument to mpipe:

        $ wc | mpipe ~~/stor/count

  A job that creates thumbnails from images might use `MANTA_INPUT_OBJECT` to
  infer the desired path for the thumbnail (e.g.,
  `${MANTA_INPUT_OBJECT}-thumb.png`) and then use mpipe to store the output
  there.
* **Multiple outputs**: you can invoke mpipe as many times as you want from a
  single task to emit more than one object for the next phase (or as a final job
  output).  A job that chunks up daily log files into hourly ones for subsequent
  per-hour processing would use this to emit 24 outputs for each input.
* **Special headers**: You can specify headers to be set on output objects using
  the "-H" option to mpipe, which behaves exactly like the same option on the
  CLI tool `mput`.
* **Reducer routing**: Finally, in jobs with multiple reducers in a single
  phase, you can specify which reducer a given output object should be routed to
  using the "-r" option to mpipe.  See "Multiple reducers" below.

## mcat: emit objects by reference

Synopsis:

    mcat FILE ...

`mcat` emits the contents of a object as an output of the current task,
but without actually fetching the data.  For example:

    mcat ~~/stor/scores.csv

emits the object `~~/stor/scores.csv` as an input to the next phase (or
as a final job output), but *without* actually downloading it as part of the
current phase.

As with mpipe, when you use mcat, the task's stdout will not be captured and
saved as it is by default.

mcat is particularly useful when you tend to run many jobs on the same large set
of input objects.  You can store the set of objects in a separate "manifest"
object and have the first phase of your job process that with "mcat".  So
instead of this:

    $ mfind ~~/public | mjob create -m wc

which may take a long time if `mfind` returns a lot of objects, you could do
this once:

    $ mfind ~~/public > /var/tmp/inputs
    $ mput -f /var/tmp/inputs ~~/public/inputs

And then for subsequent jobs, just do this:

    $ echo ~~/public/inputs | mjob create -m "xargs mcat" -m wc

This is much quicker to kick off, since you're just uploading one object name.
The first phase invokes "mcat" on lines from ~~/public/inputs.  Each
of these lines is treated as a path, and the corresponding object becomes an
input to the second phase.

The object path is not resolved until it's processed for the next phase.  So if
you specify an object that does not exist, this will produce a
ResourceNotFoundError for the phase *after* the `mcat`.  Similarly, if you
specify an object that you don't have access to, you'll get an error in the next
phase when you try to use it.


## msplit: demux a stream for reducers

Reads content from stdin and outputs to the number of `mpipe` processes for the
number of reducers that are specified.  The field list is an optional list of
fields that are used as input to the partitioning function.  The field list
defaults to 1.  The delimiter is used to split the line to extract the key
fields.  The delimiter defaults to (tab).  For example, this will split stdin by
comma and use the 5th and 3rd fields for the partioning key, going to 4
reducers:

    $ msplit -d ',' -f 5,3 -n 4


## mtee: save stdout to an object in a stream of commands

`mtee` is like `mput`, but takes input on stdin instead of a file, and emits its
input on stdout as well, much like tee(1).

`mtee` is also similar to `mpipe`, except that the newly created object does
*not* become an output object for the current task, and using mtee does not
prevent stdout from being captured.

For example, this will capture the output of cmd to an object
`~~/stor/tee.out` and still pipe what was coming from cmd to cmd2:

    $ cmd | mtee ~~/stor/tee.out | cmd2


## Using the HTTP API for advanced output

The functionality provided by "mpipe" and "mcat" can be accessed directly using
any HTTP client.  Clients can emit output objects using normal PUT operations
using the parameters specified by the `MANTA_URL`, `MANTA_USER`, and
`MANTA_NO_AUTH` environment variables.  (See "Task environment and
authentication" for information about using these variables inside a job.) Since
the other tools buffer object contents to local disk, this approach is necessary
to emit objects whose size is not bounded by the local disk space available.
These requests are subject to the same timeouts as normal requests to the public
Manta endpoints, and they may be terminated abruptly if the data stream is idle
for more than a minute.

Job-specific behavior is controlled by several headers:

* `X-Manta-Stream`: Set this to 'stdout' to emit an output object.  This is
  equivalent to using "mpipe".  (If you don't set this header, the object is
  saved to the service as normal without marking it as an output object.  This is
  analogous to using "mput". Other values of this header are used internally
  for other types of objects, but this is not supported for use by end users.
* `X-Manta-Reducer`: Set this to an integer between 0 and the number of reducers
  in the next phase (exclusive) to indicate which reducer this output should be
  sent to.  This is analogous to the "-r" flag on "mpipe".  If unspecified and
  the next phase has multiple reducers, the output will be sent to a randomly
  selected reducer.
* `X-Manta-Reference`: If emitting the contents of an existing object by
  reference, set this to "true".  This is analogous to using `mcat`.  When using
  this header, content-length should be 0, since the content will be taken from
  the referenced object.

Since these headers are specified in a PUT, you can name your output object
whatever you want.  The `MANTA_OUTPUT_BASE` environment variable is provided as
a unique, relatively friendly base name for output objects.  See "Task
environment and authentication for details.

**These headers are only interpreted by the server located at $MANTA_URL inside
the context of a job.  You cannot use these headers outside of a job, nor
can you use them with the public API servers.**

For example,

    ... | mpipe

is analogous to `PUT $MANTA_URL/$MANTA_OUTPUT_BASE.$(uuid)` with "X-Manta-Stream: stdout".

Similarly,

    ... | mpipe -r2 /:login/stor/output.txt

is analogous to `PUT $MANTA_URL/$MANTA_USER/stor/output.txt` with
"X-Manta-Stream: stdout" and "X-Manta-Reducer: 2".

Finally,

    mcat /:login/stor/input.txt

is analogous to `PUT $MANTA_URL/$MANTA_USER/stor/input.txt` with a
content-length of 0, no content, and "X-Manta-Reference: true".


# Job execution

When a job is first submitted, its state is "queued".  Under normal conditions,
the job immediately transitions to the "running" state, but since no inputs have
been submitted, there are no map or reduce tasks running.


## Processing inputs

As job inputs are submitted (typically with `mjob create` or `mjob addinputs`),
the objects are located within the service and dispatched for the first phase.  For a
map phase, dispatching means issuing a new map task to be executed on one of the
physical servers that stores the object.  For a reduce phase, dispatching means
feeding the input to the stdin of one of the reducers.

If the input object cannot be found, a ResourceNotFoundError is emitted.  Access
control is enforced for jobs just like for GETs.  If a GET for an object would
return an error because the user doesn't have access to the object, the same
error will be emitted if the user attempts to process that object as part of the
job.

**If an object is removed while there's a job operating on it, that job may
successfully process the object or it may issue a ResourceNotFoundError.  Either
behavior is possible regardless of whether the deletion completes before,
during, or after the task that would process that object starts or finishes.**


## Executing tasks

As tasks are issued, they may begin executing or they may queue up, depending on
service load.  As they execute, they emit one or more output objects.

When any task fails, its outputs are saved along with its stderr and
up to 1 core file.  A UserTaskError is emitted that references the stderr and
core file.

When a final-phase task completes successfully, its outputs are saved and marked as job outputs.

The outputs of non-final-phase tasks are called **intermediate objects**.  When
such tasks completes successfully, these intermediate objects are dispatched to
the next phase similar to the way job inputs are dispatched: if the next phase
is a map phase, a map task is issued for each intermediate object (which may
immediately begin executing), and otherwise the intermediate object is fed as an
input to one of the reducers of the next phase (which may immediately begin
processing it).  If necessary, you can specify which reducer the output should
be sent to using mpipe.  See "Advanced output" for details.

Notably, this means that job phases are not serialized.  You can stream input to
a three-phase map job and have tasks running for all three phases.  You can have
final outputs available for some of the first inputs before you've finished
submitting all of the inputs.


## Ending input

When the user finally ends the job input stream (which happens automatically
with `mjob create` or `mjob addinputs` unless the "--open" flag is specified),
any subsequently submitted input objects will not be processed.

The job's end-of-input will be propagated to the first reduce phase, if any.
When each reducer finishes reading all of its input, it will read EOF.  As all
tasks in a given reduce phase complete, the end-of-input is propagated to the
subsequent reduce phase.  (End-of-input has no meaning for map phases.)

The input stream may automatically be ended for jobs that have no inputs added
for an extended period (many minutes).


## Job completion and archival

When all inputs of the job have been processed as described above, and all
outputs from completed tasks have been propagated, and all tasks have been
completed, then the job's state becomes "done".

Because jobs can generate an enormous amount of data, and the system cannot predict
how long you want to keep this data, the lists of inputs, outputs, and
errors of your job are automatically converted to flat objects after the
job reaches the "done" state.  Once this archival process completes, interacting
with your job starts to look exactly like interacting with directories and
objects: your job is a directory, and archived data are just regular objects.
It is your responsibility to delete all archived job data when you're through
with it; until then, you will be billed for it.

Once a job is archived, the `/jobs/:id/live/*` APIs will continue to function
for at least one hour, but at some point after that, they will start returning
404, after which only the archived objects will be available.


## Cancellation

Jobs may be cancelled any time while they are still running.  No new tasks will
be dispatched, and running tasks will be cancelled as soon as possible, which
may result in errors being reported.  The job's state will become "done", though there
may still be some tasks running at this point.

Under some conditions, job cancellation may result in intermediate objects being left
around under the job's directory.  Users should perform a recursive remove ("mrm
-r") of the job's directory to clean up these artifacts.

Cancellation is intended to be an exceptional case, and the stats, outputs,
errors, and side effects of cancelled jobs are basically undefined.


## Failures and internal retries

There are many internal operations executed as part of the job's execution,
including object lookup, saving stdout for all tasks, and fetching inputs for
reduce tasks.  Where possible, these operations are automatically retried a
small number of times, which should have no visible impact except for additional
latency.  (For example, retries saving stdout will not result in multiple
"copies" of the output.)  Errors will be emitted for operations that continue to
fail.

Some internal failures may result in tasks being executed more than once.  The
service will ensure that only one of those attempts' outputs will be used, but
you must still keep this in mind if your jobs produce side effects (e.g., write
requests to external services).  In short, any task may be executed multiple
times, even successfully.

Failures of the user script are **not ever** retried.  If the script returns
non-zero, dumps core, or fails in some other way, the task fails immediately and
is not retried.  If your script sometimes fails transiently, and you want it to
be retried, you must do this yourself at the appropriate level (which may be at
the level of the whole script, or just part of it, depending on the
application).  Built-in tools like "mpipe" automatically retry a small number of
times.


# Debugging jobs

Debugging programs that run remotely poses challenges, but Manta provides
several facilities to make this easier.


## Save debug output to Manta

By default, Manta does not save the stderr emitted by your job, but if your
program returns a non-zero exit status or dumps core, stderr is automatically
saved and made available to you.  You can use this to figure out what part of
your program failed, and why.

You can also save your own output objects with `mput`.  The `mtee` command is
also available for inserting into a pipeline (like `tee(1)`).  These approaches
are difficult to scale up, but can work well for small jobs.


## Try your job with mlogin

Since it's often easiest to debug a program by running it by hand from an
interactive shell, the Manta CLI tools include an [`mlogin`](mlogin.html) command, which starts
an interactive shell inside a Manta job, directly where your object is stored.
Here you can inspect the environment, run your program as many times as you
want, save intermediate files, use a debugger, or do whatever else you need to
debug your program.

Here's a simple example where the user (called "mantauser") interactively runs
`echo` and `wc`:

    $ mlogin /manta/public/examples/shakespeare/kinglear.txt
     * created interactive job -- 3226d090-9dde-4dc0-b59a-c80d59635c63
     * waiting for session... - established

    mantauser@manta # echo $MANTA_INPUT_FILE
    /manta/manta/public/examples/shakespeare/kinglear.txt

    mantauser@manta # wc $MANTA_INPUT_FILE
      5525  27770 157283 /manta/manta/public/examples/shakespeare/kinglear.txt

Since [`mlogin`](mlogin.html) runs in the exact same environment that normal Manta jobs run,
once your program works reliably under [`mlogin`](mlogin.html), it will work as a
non-interactive job as well.


## Try your job locally

It's easy to forget that since Manta's environment is very similar to most other
Unix-like systems (e.g., SmartOS, MacOS, and GNU/Linux), you can also test your
program by hand on your own system.  Once it works reliably there, it's likely
it will run correctly in Manta as well.


## Debugging reducers

You can use several of the above techniques for debugging the first phase of a
job, but it's not obvious how to apply them to the second phase of map-reduce
job (or even a map-map job), since the input is not available for you to use
[`mlogin`](mlogin.html) with.  One solution is to replace your reduce phase with `cat`, which
will simply copy the reducer's input as output.  Then you can [`mlogin`](mlogin.html) in to the
job's output file and debug it.  (This technique also works with multiple
reducers in a single phase.)

For example, suppose you're having trouble with this two-phase map-reduce job,
which runs `wc` in the first phase and a custom script in the second phase.

    $ mjob create \
        -m wc \
        -s /path/to/myscript -r /assets/path/to/myscript

You would replace that job with:

    $ mjob create \
        -m wc \
        -r cat

When that job completes, you'd run [`mlogin`](mlogin.html) on the *output* of that job, which
is exactly the *input* to your reducer.  (If you had multiple reducers in this
phase, there would be multiple outputs, one for each reducer, and you could
debug each one separately.)

This process is analogous to debugging a Unix pipeline on your local machine by
saving the intermediate output of the first part of the pipeline to a file
first, and debugging the second part of the pipeline using that file.
