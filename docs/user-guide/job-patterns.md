---
title: Job Examples and Patterns
markdown2extras: wiki-tables, code-friendly
---

# Job Examples and Patterns

Often, the best way to understand a new tool is to see examples in action.  This
document shows some common techniques and ways you might approach some tasks.


# Example Jobs

These are fully worked examples that you can try yourself. They use public data and contain the complete commands that you need to run the example.

If you're looking for real-world systems, see the [front page](index.html).

* [Total word count](example-total-word-count.html)<br />
  Counts the number of words across a number of plaintext files

* [Word frequency count](example-word-freq-count.html)<br />
  Finds the 30 most frequently used words across a number of plaintext files
  and prints the number of times the word appears.

* [Line count by file extension](example-line-count-by-extension.html)<br/>
  Lists the number of files with a particular extension and totals the number
  of lines in each file type.

* [Generate index](example-word-index.html)<br />
  Produces an index that lists the file and line number of every word in a set of plaintext object.

* [Image conversion](example-image-convert.html)<br />
  Takes a number of image objects in PNG format and converts them to GIF images.


* [Video transcoding](example-video-transcode.html)<br />
  Converts a number of video objects in H.264 format and converts them to webm format.


* [ETL (extract, transform, load)](example-etl-manta-log.html)<br />
  Generates a Postgres database from your own Manta access logs.


# Common Techniques

## Shell Quoting

Quoting jobs on the command line can be annoying, particularly when writing
`awk` or `perl` one-liners, which tend to use variables like `$1` that must not
be interpreted by either the local shell or the shell in the compute environment.

One way to avoid quoting problems is to store the script as an [asset](index.html#running-jobs-using-assets)
and invoke it from your job. Another way is to store the script as a local
file and use bash shell expansion.

Instead of writing this:

    $ mjob create -m "awk '{ print \$1 }'"

You can throw the unescaped script in a local file called `myscript.awk`, and write:

    $ mjob create -m "$(cat myscript.awk)"

## Uploading a directory tree

First, upload a tarball into the service, then run "muntar" inside a job to expand it.
For example, to copy /etc to ~~/stor/backup/etc:

    $ cd /
    $ tar czf /var/tmp/backup.tar.gz etc
    $ mput -f /var/tmp/backup.tar.gz ~~/stor/backup.tar.gz
    $ echo ~~/stor/backup.tar.gz | \
        mjob create -o -m gzcat -m 'muntar -f $MANTA_INPUT_FILE ~~/stor'

The resulting output will be a list of all of the objects created while
extracting the tarball.


## Concatenating output

It may be a little counter-intuitive, but you can concatenate a bunch of objects
together with a single "cat" reduce phase.

For example, single-phase map jobs that run a single Unix command (e.g., `grep`)
produce one output object for each input object, but sometimes it's desirable to
combine these, which you can do with just "cat" as a reduce phase:

    $ mjob create -m "grep pattern" -r cat

This job runs "grep pattern" on all the input objects and produces one output object
with the concatenated results.

Note that by combining all the individual grep outputs, you won't get labels
saying which input each line came from.  If you want that, see "Grepping files"
below.


## Grepping files

You can grep files for "pattern" with just:

    $ mjob create -m "grep pattern"

but you'll get one output for each input object.  As described above, if you
want to combine them, you can add a "cat" reduce phase:

    $ mjob create -m "grep pattern" -r cat

The problem with this is that the matching lines from all files will be combined
in one file with no labels, so you won't know what came from where.  GNU grep
provides an option for labeling the stdin stream, and combined with "-H" (which
tells it to print the name of the file in the first place), you can get more
useful output:

    $ mjob create -m 'grep -H --label=$MANTA_INPUT_OBJECT pattern' -r cat


## Producing a list of output objects as a single file

If your job produces lots of output objects, you can create a single object
that lists them all by appending a map phase that echoes the object name followed
by a "cat" reduce phase.  For example, this job may create tons of output objects:

    $ mjob create -m wc

You can have the job emit a single object that *lists* all the results of the
previous phases using:

    $ mjob create -m wc -m 'echo $MANTA_INPUT_OBJECT' -r cat
