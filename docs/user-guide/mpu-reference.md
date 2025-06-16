---
title: Multipart Uploads Reference
markdown2extras: wiki-tables, code-friendly
---
<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2018, Joyent, Inc.
    Copyright 2023 MNX Cloud, Inc.
-->

# Multipart Uploads Reference

This is the reference documentation for Manta multipart uploads. Unless
otherwise specified, the semantics described here are stable, which means that
you can expect that future updates will not change the documented behavior. You
should avoid relying on behavior not specified here.

You should be familiar with the Manta storage service before reading this
document. To learn the basics, see [Getting Started](index.html).


# Multipart Upload Overview

## Terminology

Before getting started, it's worth describing some key terms:

* End users create **multipart uploads**, which allow them to upload a Manta
  object in **parts**.
* All multipart uploads under an account have a unique **upload ID**.
  Parts are uploaded to the **parts directory** of the multipart upload.  The
  parts directory is a normal Manta directory that can be listed.  The basename
  of the parts directory's path is the multipart upload's upload ID.
* The parts directory is sometimes also referred to as the **upload directory**
  for a given multipart upload.
* Once all of the parts have been uploaded, you can **commit** the
  multipart upload, which exposes the **target object** in Manta as a normal
  Manta object.
* If you wish to complete the multipart upload without committing the target
  object, you can **abort** the multipart upload instead.
* Multipart uploads have associated state.  When the multipart upload is
  created, it is marked as being in the **created** state.  When the multipart
  upload is in the process of being committed or aborted, it is in the
  **finalizing** state.  When the commit or abort has completed, the multipart
  upload is in the **done** state.
* When a multipart upload has been committed or aborted, it is said to be
  **finalized**.

To illustrate the directory structure used for multipart uploads, consider the
following path representing a part in a multipart upload.  This path is part 0
for the multipart upload with upload ID `41141e11-845e-49d1-a2b1-84dd2a044193`.

                                         upload ID
                                             |
                                             |
                        parts directory      |
    |----------------------------------------|--------------|
    |                                        |              |
    |                                        v              |
    /:login/uploads/411/41141e11-845e-49d1-a2b1-84dd2a044193/0


## Life Cycle of a Multipart Upload

The typical life cycle of a multipart upload is as follows:

1. The end user creates the multipart upload, with the desired path of the target
   object as input.  The user may also specify headers to store on the target
   object at this point, including its durability, content length, and content
   MD5.
2. The user uploads parts for the object to the multipart upload.  The user saves
   the etag returned by the server for each part to use when committing the
   multipart upload.
3. After all parts have been uploaded, the user commits the multipart upload,
   specifying the etags of the parts of the object.  The parts must be
   consecutive and start from 0 (the first part).  When the commit has completed,
   the target object is exposed in Manta at the path the user specified when the
   multipart upload was created.
4. After the multipart upload is committed, its associated data, including the
   upload directory and the parts stored in it, are garbage collected after a
   system-wide grace period.


## API Constraints

There are several constraints on using the multipart upload API. In particular:

* Multipart uploads can have a maximum of 10000 parts.
* Parts must be at least 5 MB, with the exception of the last part.
* Parts may be uploaded in any order.
* Parts cannot be fetched as normal Manta objects, but users can verify their
  contents from response headers, including Content-Length and Content-MD5.
* When committing a multipart upload, the request must include zero or more
  consecutive parts, starting with the first part.  Multipart uploads committed
  with zero parts will create a zero-byte object at the target URI.
* The target object's URI and its associated header data (including
  `durability-level`) may only be specified when the multipart upload is
  created.  It cannot be changed later.
* The service garbage collects data resulting from a multipart upload,
  including the upload directory and the parts stored in it, when the upload
  is finalized.  State information about finalized multipart is only available
  during a system-wide grace period before the multipart upload is garbage
  collected.
* At this time, subusers of an account may not use the multipart upload API.
  This may change in future revisions.

# Useful Multipart Upload Operations

In addition to the [multipart upload REST
endpoints](api.html#multipart-uploads), there are some other useful operations
to know for managing multipart uploads.

## Listing Parts of a Multipart Upload

Part directories are normal Manta directories and can be listed.  To see all
the parts under a given multipart upload, do a ListDirectory operation on the
parts directory.

To see the fully qualified path of parts uploaded to a given multipart upload,
use `mmpu`:

    $ mmpu parts

For example:

    $ mmpu parts 38ca75c8-c138-4fbd-a99a-faa008924193
    /jhendricks/uploads/38c/38ca75c8-c138-4fbd-a99a-faa008924193/0
    /jhendricks/uploads/38c/38ca75c8-c138-4fbd-a99a-faa008924193/1

To see etags, size and other information about parts uploaded to given
multipart upload, you can do an HTTP GET of its parts directory:

    $ mget -q PARTS_DIRECTORY | json -ga

For example:

    $ mget -q /jhendricks/uploads/38c/38ca75c8-c138-4fbd-a99a-faa008924193 | json -ga
    {
      "name": "0",
      "etag": "b596212c-fa55-4eaf-9c05-99c0157c5ebe",
      "size": 5242880,
      "type": "object",
      "contentType": "application/octet-stream",
      "contentMD5": "XzY+DlipXwbL6bvGYsXftg==",
      "mtime": "2018-01-09T17:31:30.034Z",
      "durability": 2
    }
    {
      "name": "1",
      "etag": "d39f4cde-a50a-48bc-bcdd-77a8768b636b",
      "size": 1507,
      "type": "object",
      "contentType": "application/octet-stream",
      "contentMD5": "3ME/LJ1Y4NctYvhIJ7gq7g==",
      "mtime": "2018-01-09T17:30:44.951Z",
      "durability": 2
    }

Note that multipart uploads are garbage collected after they have been
finalized, so you can only list parts reliably for a multipart upload before it
has been committed or aborted.

## Listing All Multipart Uploads for an Account

To find all multipart uploads under a given account, do a recursive listing of
the top-level `/:login/uploads` directory; upload directories have a basename
that is a uuid.

Note that the organization of the `/:login/uploads` tree is subject to change,
but upload directories are all stored in the tree.

One way to list all multipart uploads is to use `mmpu`, which will perform this
listing for you:

    $ mmpu list

For example:

    $ mmpu list
    /jhendricks/uploads/176/1767fbd5-ed23-4a5b-9ebe-4e025906a163
    /jhendricks/uploads/0ab/0ab944c7-acc4-43f6-a998-93d902f33b73
    /jhendricks/uploads/ba7/ba78e9a8-e375-4648-ae8f-fe1c8b2f1973
    /jhendricks/uploads/38c/38ca75c8-c138-4fbd-a99a-faa008924193
    /jhendricks/uploads/dbf/dbf016ca-7a7d-41b9-ab84-185a692a9fc3


Note that multipart uploads are garbage collected after they have been
finalized, so you may only list multipart uploads that have not yet been garbage
collected -- either because they have not been committed or aborted, or because
they are within the system-wide grace period for garbage collection.

# Multipart Upload System Architecture

This section describes some of the design principles that guide the operation of
the Manta Multipart Upload Service.

## Guiding Principles

Several principles guide the design of the service:

* Objects created via the multipart upload API should be indistinguishable from
  "normal" Manta objects.
* Users should be able to list parts they have uploaded to a multipart upload.
* To allow the service to clean up data for multipart uploads the user does not
  want to commit as target objects, users should be able to abort multipart
  uploads.
* The system should behave safely in the face of concurrent operations on the
  same multipart upload.  For example, if one client attempts to commit a
  multipart upload, and another concurrently attempts to abort the multipart
  upload, only one client should succeed.

## System Scale

There are several relevant dimensions of scale:

* Multipart uploads themselves may have up to 10000 parts.
* An arbitrary number of multipart uploads may be ongoing for an account.  Very
  large numbers of ongoing multipart uploads may have performance implications
  for the system.  It is generally recommended to commit or abort a given
  multipart upload as soon as possible so the service may garbage collect its
  associated data.
