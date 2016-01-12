---
title: How It Works
markdown2extras: wiki-tables, code-friendly
---

# Some of the underlying concepts of Manta:

1. Object immutability
2. Strong data consistency
3. Parallel tasks processing
4. Job processing workflow
5. A list of common operators
5. Administrative details

## Object Immutability 

## Strong Data Consistency

One of the [guiding principles](/storage-reference.html#guiding-principles) in
the design of Joyent Manta is strong data consistency under a network partition
condition. That is, what does the system do when a storage node seems to be
unreachable from another node? This is called a network partition of the
distributed storage system. When these rare events happen, the behavior of the
system is very important for application developers who must compensate. Should
every non-error write be presumed to be completed or is a verification read
required, significantly slowing a system? How soon will a write followed by
subsequent read get the most recently written data instead of a slightly stale
version?

In a strongly consistent system, all copies of an object are guaranteed to be
consistent and synchronized immediately upon successful acknowledgement of a
write. This generally reduces the amount of compensating logic that must be
handled in your application.

In the illustration below, two storage nodes share two copies of a data set that
is being loaded. Both copies must be synchronized at the moment one of the
object copies is written. Writes, designated by the w's are arriving at objects
nnnnin alternating fashion. The heirarchical directory structure is shown to the
right.

The writes w1-w5 arrive without incident.  The write / update request arrives,
and synchronization data flows between the two storage nodes over the
network. An HTTP 200 is returned.  For the sake of argument, the network is
severed prior to the arrival of w6.  Instead of an HTTP 200 response, the system
may respond with an HTTP 400 or 500 letting the originating client to take a
compensating action like retrying. 

The system will provide a confirmation of a successful write only after all the
default or user-specified copies have been written onto the remote machines.

# Compute on Storage

## Manta Advantages

1. Objects have compute run on them
2. A large # of objects can run compute in parallel
3. Map can output directly or into another compute reduce ("mtee") 
4. Tasks that experience errors will output an err object for review

<br/>
<img src="media/img/how-it-works-1.svg" alt="Key Advantages" width="700"/>


2. **Hierarchical Directory Structure** - Similar to the hierarchical,
parent-child directory structure in Unix, Joyent Manta can provide visibility
to the complete list of objects under a given directory. The advantage
of following the directory structure in Unix, users can easily locate
their objects and its relationship to the directory by using the
**mls** command (which functions similarly to **ls** in Unix).

3. **Multi-datacenter Replication** - Architected for availability,
	the Manta Service is deployed in multiple data centers and availability
	zones across Joyent US East. Copies of the objects are automatically
	dispersed amongst the different availability zones which means there
	is no single point of failure.
	
	This diagram illustrates Manta's concept of Consistent Writes,
	shows its Hierarchical Directory Structure,
	and how Objects are replicated between two data centers

	<img src="media/img/how-it-works-2.svg"
		 alt="Explanation of Consistent Writes, Directory Structure, Data Center Replication"
		 height="400" /><br/>


4. **Objects Immutable** - Simplifying versioning, the objects stored
in Manta are immutable which means they can be written only once. If
an object is updated, the updated one replaces the original which then
means that the stored object is always the latest. There is no need to
use timestamps to synchronize the master/slave copies or which copies
precede one another.

5. **Snaplinks** - Snaplinks is similar to a Unix hard link. A hard
link is essentially a label or name assigned to a
file. Conventionally, we think of a file as consisting of a set of
information that has a single name. However, it is possible to create
a number of different names that all refer to the same
contents. Commands executed upon any of these different names will
then operate upon the same file contents. With Snaplinks, you can even
simulate similar moving objects from one directory to another enough
moving objects from one directory to another is not allowed.

## Storage with the command line utilities

**Step 1: Storing a file in Joyent Manta**
 
	mput -f thetempest.html /username/stor/thetempest.html

**Step 2: Retrieving an object** 

	mget /username/stor/thetempest.html

**Step 3: Finding objects**

	mfind -t o

**Step 4: Running a job in Manta** 

	mfind -t o | mjob create -qo grep thou ^ wc



# How It's Built 

Joyent Manta is largely made of two parts: Storage and Compute.
Storage is built on the ZFS file system and inherits its features
(protection against data corruption, support for high storage
capacities, snapshots and copy-on-write clones, software RAID, etc.)
An orchestration system tracks objects and metadata across storage
nodes in a strongly consistent fashion.  For resiliency, Manta stores
multiple copies of objects (default: 2) across data centers and
balances read requests across those copies.

On each storage node, Manta uses RAID-Z, a software based RAID,
comparable to RAID 6 systems with block level striping and triple
parity.  In the event of storage hardware degradation, ZFS will
automatically relocate the affected data to hot standby hardware and
mark the failing device for hot-swap replacement.

High-performance compute CPUs and RAM are designed within the data
store. Manta compute jobs are made of one or more tasks that run in
parallel.  These subtasks are run in lightweight virtualization
containers.  These containers provide complete isolation within a
single Manta task.  A task is assigned to an input object during the
compute phase, its outputs are recorded as other Manta objects, and
then the container is discarded.  Manta tasks can be chained together
to provide a multi-level map/reduce system.


## Key Points


1. **Objects can Compute** - Unlike other systems that require moving
the objects out of storage for computation, Manta's compute jobs
interface works directly on the objects. As part
of the Joyent family, Manta benefits from having a highly efficient tech stack optimized
for application orchestration. Other vendors running on a
smorgasbord of technologies may have added performance overhead from having
to traversing the OS/VM tiers.

2. **Run Compute jobs in situ and in Parallel** - Another advantage of
moving the compute into storage is parallel processing. Applications
running in Manta can perform in orders of magnitude better than
systems with separate compute and storage silos. Use cases such as
text processing, video processing, machine learning algorithms
outperform others.

3. **Run Simple to Advanced MapReduce Functions** - Large
computational problems from counting, sorting, aggregating to advanced
function such as cross-correlations, pattern recognition can be
divided into multiple parts. Results from any of subdivided parts (or
**Map** step) can be become an output in Manta. And the final result
(or **Reduce** step) can be aggregated from all the outputs and
combined to obtain a final result. Or in the case of machine learning,
the final result can be derived from pattern recognition in Manta
based on a set of user-provided training data.

4. **Tasks that experience errors will output an err object for
review** - For jobs that do fail, Manta will output an err object such
as user command exited with code 1,"stderr" to let the user know that
a particular job has failed. Error messages in Manta follow
conventional Unix standards.

## Motivations for Manta

1. **On-demand service**
  Some big data projects are one-time, seasonal and/or ad hoc. Therefore
  investment of a dedicated MR cluster provides little to no economic
  value.

  [one can service smaller jobs with an on-demand service vs. a longer
  term planned one... classic IBM PC vs Mainframe.  OpEx vs CapEx]

2. **Leverage prevalent Unix/Linux skill set**
Hiring developers for Manta takes a shorter hiring cycle than for
other Big Data hires.  People with Unix/Linux proficiency are
prevalent and can be sourced, even contracted globally.

3. **Shallow Learning Curve** 
Installing Manta tools just takes a few minutes. Manta uses familiar
Unix and Linux commands. People with Unix proficiency can start using
Manta by reviewing the docs with little to no additional training

## What are the Common Use Cases for Manta?

In the client server computing, commands can be executed directly on
objects stored locally. In other cloud computing environments, objects
tend to be dispersed across nodes in the cloud. This is not the case
in Manta. Manta has an orchestration that keeps track of objects and
metadata across the storage nodes, commands can be sent into Joyent's
Manta service to execute on the objects without having to transport
the objects back to compute.

The job scheduler can queue up several tasks and run them in parallel,
executing on objects in the storage node(s) where they reside. Using
an example of log processing, a 17 GBs log file consisting of four
days of wikipedia traffic data was uploaded into Manta. The task was
to find the total number of pages requested and total number of bytes
sent. Manta performed the task by distributing the the work across 98
different tasks running in parallel. It's easy to put log data into
Joyent Manta. There's a REST API and wrapper SDK for Java, Ruby,
Python and Node.js.

Also, a Manta job can pass their completed output, analogous to
passing a baton to another job to execute their part such that the
output from the first task becomes the input into second task task.

Manta can be particularly useful in jobs where you are performing a
repetitive task on a set of objects. For example, you have several GBs
of photographs on a hard drive, you know that there are
duplicates. You could write a simple script to run checksum on each
photo. If you can find objects with the same checksum, the likelihood
that they are duplicates is high. A more sophisticated approach would
be to run an image recognition program instead of using the checksum.

A simple example is converting images from one format (say jpeg) to
another format (png).  A job is simply a series of commands against a
set of inputs. In the command below, Manta locates the emoji folder
and lists the image files (using **mfind**) in the directory named
jill/stor. It creates a job (using **mjob**) and uses the convert command
from the image processing library **ImageMagick**  to convert three
images from .jpeg to the .png format and saves the objects back to the
file.


    $ mfind /jill/stor/emoji | \
      mjob create -w -m \
      'convert $MANTA_INPUT_FILE /var/tmp/out.png && \
       mpipe ${MANTA_INPUT_OBJECT%.*}.png < /var/tmp/out.png'

The output file shows that the three picture files have been converted to the .png format (previously in .jpeg).

    $ mjob outputs 384ebf70-6802-4ff3-9b37-dab7944dbfcd
    /jill/stor/emoji/emoji-83.png
    /jill/stor/emoji/emoji-80.png
    /jill/stor/emoji/emoji-81.png


**ImageMagick** is one of the hundreds of image processing packages preloaded into Manta. 

Instead of image processing, this time we're doing video transcoding. Here we
are converting the two video files from the .avi to .webm format. Again using
**mfind**, Manta locates the videos under the directory named Jill/stor and in
parallel, creates a job (using the **mjob**) and transcode the videos from .avi
to .webm using a **ffmpeg** utility.


    $ mfind /jill/stor/videos | \
      mjob create -w -m \
      'ffmpeg -i $MANTA_INPUT_FILE /var/tmp/out.webm && \
       mpipe ${MANTA_INPUT_OBJECT%.*}.webm < /var/tmp/out.webm'


The output shows that both videos (video001 and video002) have been transcoded to .webm. 


    $ mjob outputs 7138a246-1387-4e1c-b9df-a0b0fbc4eece
    /jill/stor/videos/video001.webm
    /jill/stor/videos/video002.webm


With Manta, developers can start to dev/test their applications on demand
without building a Map/Reduce cluster. Anyone familiar with Unix can get started
with Manta in a few minutes. It is a production quality sandbox for application
developers working and computing with large datasets.

Sign up on [Joyent.com](http://my.joyent.com).



