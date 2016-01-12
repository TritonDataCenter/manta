---
title: Joyent Manta Storage Service
markdown2extras: wiki-tables, code-friendly
logo-color: green
logo-font-family: google:Aldrich, Verdana, sans-serif
header-font-family: google:Aldrich, Verdana, sans-serif
---

# manta-compute-bin

[manta-compute-bin](http://joyent.github.com/manta-compute-bin) is a collection
of utilities that are on the `$PATH` in a compute job.

# Introduction

Each of these utilities aids in proceesing and moving data around within a
compute job.  Recall that each phase of a job is expressed in terms of a
Unix command.  These utilities are invoked as part of the job `exec` command.
For example, if you had the following as your `exec` line:

    grep foo | cut -f 4 | sort | uniq -c

And needed to preserve the `grep foo` output, you could use the `mtee` command
to capture that part of the pipeline to a object:

   grep foo | mtee ~~/stor/grep_foo.txt | cut -f 4 | sort | uniq -c

# Utilities

The current set of utilities:

* [`maggr`](maggr.html) - Performs key-wise aggregation on plain text
files.
* [`mcat`](mcat.html) - Emits the named object as an output for
the current task.
* [`mpipe`](mpipe.html) - Output pipe for the current task.
* [`msplit`](msplit.html) - Split the output stream for the current
task to many reducers.
* [`mtee`](mtee.html) - Capture stdin and write to both stdout and a
object.

Detailed documentation that can be found by clicking one of the command names
above.

# Testing in Compute
If you are testing changes or forked this repository, you can upload and run
your changes in Compute with something like:

   $ make bundle
   $ mput -f manta-compute-bin.tar.gz ~~/stor/manta-compute-bin.tar.gz
   $ echo ... | mjob create \
     -s ~~/stor/manta-compute-bin.tar.gz \
     -m "cd /assets/ && gtar -xzf ~~/stor/manta-compute-bin.tar.gz &&\
         cd manta-compute-bin && ./bin/msplit -n 3" \
     -r "cat" --count 3

# More documentation

Docs can be found here [http://apidocs.joyent.com/manta/](http://apidocs.joyent.com/manta/)

# Bugs

See <https://github.com/joyent/manta-compute-bin/issues>.
