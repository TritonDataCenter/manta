 ---
title: Object Storage Reference
markdown2extras: wiki-tables, code-friendly
---

# Object Storage Reference

The Joyent Manta Storage Service uses a REST API to read, write, and delete objects.
This document assumes that you are familiar with HTTP-based REST systems, including
HTTP requests, responses, status codes, and headers.

If you want to start with basic information on Manta object storage, read [Getting Started](index.html).

Unless otherwise specified, the semantics described here are stable, which means that you can expect that future updates will not change the
documented behavior. You should avoid relying on behavior not specified here.


# Storage Overview

The storage service is based on three concepts: object, directories, and SnapLinks.

* **Objects** consist of data and metadata you can read, write, and delete from
the storage service. The data portion is opaque. The metadata is a set of
  HTTP headers that describe the object, such as `Content-Type` and
  `Content-MD5`. An object is identified by a name.
* **Directories** are named groups of objects, as on traditional file systems.
  Every object belongs to a directory.
  The private storage directory, `/:login/stor` functions as the top level, or
  root directory.
* **SnapLinks** create a point-in-time reference to the data and
  metadata that constitutes another object.
  Unlike hard links or symbolic links in Unix, when the source object changes,
  the SnapLink does not.
  You can use SnapLinks to create arbitrary versioning schemes.


# Objects

Objects are the primary entity you store in Joyent Manta Storage Service.
Objects can be of any size, including zero bytes.
Objects consist of your raw, uninterpreted data,
as well as the metadata (HTTP headers) returned when you retrieve an object.

# Headers
There are several headers for objects that control HTTP semantics in Manta.

## Content Length

When you write an object, you must use one of two headers:

* Use `Content-Length` if you can specify the object size in bytes.
* Use `transfer-encoding: chunked` to upload objects using [HTTP chunked encoding](http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.6).

Chunked encoding lets you stream an object for storage without knowing the size of the object ahead of time.
By default, the maximum amount of data you can send this way is 5GB.
You can use the optional `max-content-length` header to specify how much space you estimate the object requires.
This estimate is only an upper bound.
The system will record how much data you *actually* transferred and record that.
Subsequent GET requests will return the actual size of the object.

## 100-continue Request Header

You can, but are not required to, use the
[`Expect: 100-continue`](http://www.w3.org/Protocols/rfc2616/rfc2616-sec8.html#sec8.2.3)
header in your write requests.
Using this header saves network bandwidth.
If the write request would fail, the system returns an error without transferring any data.
The node-manta CLI use this feature.

## Content Headers

You should always specify a `Content-Type` header,
which will be stored and returned back (HTTP content-negotiation will be handled).
If you do not specify a content type, the default is `application/octet-stream`.

If you specify a `Content-MD5` header, the system validates that the content
uploaded matches the value of the header. You must encode MD5 headers in Base64,
as described in [RFC 1864](https://www.ietf.org/rfc/rfc1864.txt).


The `durability-level` header is a value from 1 to 6
that specifies how many copies of an object the system stores.
If you do not specify a durability level, the default is 2.

## Conditional Request Headers

The system honors the standard HTTP conditional requests such as
[`If-Match`](http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.24),
[`If-Modified-Since`](http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.25),
etc.

## CORS Headers

Cross-Origin Resource Sharing [CORS](http://www.w3.org/TR/cors/) headers are
supported on a per object basis.

If `access-control-allow-origin` is sent on a `PUT`,
it can be a comma separated
list of `origin` values.
When a request is sent with the `origin` header,
the *list* of values of the stored `access-control-allow-origin` header is processed
and only the *matching* value is returned, if any. For example:

    $ echo "foo" | \
        mput -q -H 'access-control-allow-origin: foo.com,bar.com' /:login/public/foo
    $ curl -is -X HEAD -H 'origin: foo.com' http://10.2.121.5/:login/public/foo
    HTTP/1.1 200 OK
    Connection: close
    Etag: f7c79088-d70d-4725-b716-7b85a40ede6a
    Last-Modified: Fri, 17 May 2013 20:04:51 GMT
    access-control-allow-origin: foo.com
    Content-MD5: 07BzhNET7exJ6qYjitX/AA==
    Durability-Level: 2
    Content-Length: 4
    Content-Type: application/octet-stream
    Date: Fri, 17 May 2013 20:05:58 GMT
    Server: Manta
    x-request-id: 30afb030-bf2d-11e2-be7d-99e967737d07
    x-response-time: 7
    x-server-name: fef8c5b8-3483-458f-95dc-7d9172ecefd1

If no `origin` header is sent, the system assumes that the request did not originate from
a browser and the original list of values is echoed back.
While this behavior does not conform to the CORS specification,
it does allow you to administratively see
what is stored on your object.

`access-control-expose-headers` is supported as a list of HTTP headers that a
browser will expose. This list is not interpreted by the system.

`access-control-allow-methods` is supported as a list of HTTP methods that the system
will honor for this request. You can only specify HTTP operations the system
supports: HEAD, GET, PUT, DELETE.

`access-control-max-age` is supported and uninterpreted by the system.

## Cache-Control

The HTTP `cache-control` header is stored and returned by the system.
This is useful for controlling how long CDNs or a web caching agent caches a version of
an object.

## Custom Headers

You can store custom headers with your object by prefixing them with `m-`.
For example, you might use the header `m-local-user: jill` to tag an object
with the name of the user who created it.

You can use up to 4 KB of header data.

# Directories

Directories contain objects and other directories.
All objects are stored at the top level or subdirectory one of the following directories:

|| **Directory**     || **Description ** ||
|| `/:login/stor`    ||private object storage ||
|| `/:login/public`  ||public object storage ||
|| `/:login/jobs`    ||storage for objects created by jobs ||
|| `/:login/reports` ||storage for logs and reports ||

## Private Storage (/:login/stor)

As noted above, `/:login/stor` functions as the top level, or root, directory where you store
objects and create directories.
Only you can read, write, and delete data here.
You can create any number of directories, objects and SnapLinks in this directory.

While the system does not yet support discretionary
access controls on objects or directories, you can grant access to individual
objects in this namespace by using signed URLs, which are explained below.

With the exception of signed URL requests, all traffic to `/:login/stor` must be
made over a secure channel (TLS).

## Public Storage (/:login/public)

`/:login/public` is a world-readable namespace.
Only you can create and delete objects in this directory.
Read access to objects in this namespace is available through HTTP and HTTPS without
authorization headers.
Deletions and writes to this directory must made over a secure channel.

## Jobs (/:login/jobs)

`/:login/jobs` functions as the root directory for compute jobs.

When a new job is created, it gets a directory named `/:login/jobs/:id`,
where `:id` is the UUID of the job.
Once a jobs is archived, listing a job directory would return this.

    $ mls /:login/jobs/343958c6-bf07-11e2-ab36-bb9b003de5dc
    err.txt
    fail.txt
    in.txt
    job.json
    out.txt
    stor/

The contents of a job's directory is a complete snapshot of all data available over the jobs API.
You can clean this data up using `mrm -r`. You can also use `mfind` to generate a list of objects in the directory.

Only you or jobs you create can read, write, and delete data in this directory.

## Jobs Storage (/:login/jobs/:id/stor)

By default, `/:login/jobs/:id/stor` contains data created during job execution.

Since the compute framework automatically creates data here,
you will typically only be interested in the reading and deleting objects from this directory.

Note that only data emitted during the last phase of a job will have data here.

## Reports (/:login/reports)

`/:login/reports` is the location where the system delivers aggregated usage reports
and raw HTTP access logs.
Learn more about the reports directory in the [Reports Reference](reports.html) section.
Only you can manage data under `/:login/reports`.

## Working with Directories

You create a directory the same way that you create an object,
but you use the special header `Content-Type: application/json; type=directory`.

When you retrieve a directory,
the response has the `Content-Type: application/x-json-stream; type=directory` header.
The body consists of a set of JSON objects separated by newlines (`\n`).
Each object has a `type` field that indicates whether the JSON object specifies a
directory or a storage object.

Here is an example with additional newlines added for clarity.

    {
        "name": "1c1bf695-230d-490e-aec7-3b11dff8ef32",
        "type": "directory",
        "mtime": "2012-09-11T20:28:30Z"
    }

    {
        "name": "695d5de6-45f4-4156-b6b7-3a8d4af89391",
        "etag": "bdf0aa96e3bb87148be084252a059736",
        "size": 44,
        "type": "object",
        "mtime": "2012-09-11T20:28:31Z"
    }

|| Field   || Description ||
|| `type`  || Either `object` or `directory`. ||
|| `name`  || The name of the object or directory. ||
|| `mtime` || An [ISO 8601 timestamp](http://www.w3.org/TR/NOTE-datetime) of the last update time of the object or directory. ||
|| `size`  || Present only if `type` is `object`. The size of the object in bytes. ||
|| `etag`  || Present only if `type` is `object`. Used for conditional requests. ||


When you use an HTTP GET request to list a directory,
the `result-set-size` header in the response contains the *total* number of entries in the directory.
However, you will get 256 entries per request, so you will have to paginate through the result sets.
You can increase the number of entries per request to 1024.
Results are sorted lexicographically.

To get the next page of a listing, pass in the *last* name returned in the set
until the total number of entries you have processed matches `result-set-size`.


You can store CORS, `cache-control` and `m-` headers on directories, as you can
on objects. Currently, no data is supported on directories.

# SnapLinks

SnapLinks allow you to create an alternate name for a point-in-time reference
to an object. SnapLinks do not consume any extra bytes in your usage, as they
do not create a new copy of data. They simply create an extra name that points
at existing object data.

SnapLinks are useful for creating arbitrary versioning schemes in client
applications. You can create SnapLinks across directories.
You can use SnapLinks to build any form of snapshotting mechanism desired.

Because objects in the system are copy-on-write, when the object that was the target
of a SnapLink changes, the SnapLink does not change. Conceptually, SnapLinks
are like a Unix hard link that is copy on write.

As an example from the getting started guide:

    $ echo "Object One" | mput /:login/stor/foo
    $ mln /:login/stor/foo /:login/stor/bar
    $ mget /:login/stor/bar
    Object One
    $ echo "Object Two" | mput /:login/stor/foo
    $ mget /:login/stor/foo
    Object Two
    $ mget /:login/stor/bar
    Object One

When you create a SnapLink, all of the metadata is copied from the source object.
There is no way to add additional metadata.


# Storage System Architecture

This section describes some of the design principles that guide the
operation of the Joyent Manta Storage System.

## Guiding Principles

Several principles guide the design of the service:

* From the perspective of the [CAP theorem](http://en.wikipedia.org/wiki/CAP_theorem),
  the system is *strongly consistent*.
  It chooses to be strongly consistent, at
  the risk of more HTTP 500 errors than an eventually consistent system.
  This system is engineered to minimize errors in the event of network or system
  failures and to recover as quickly as possible, but more errors will occur than
  in an eventually consistent system. However, it is possible to read the writes
  immediately. The distinction between a HTTP 404 response and a HTTP 500 response is very clear:
  A 404 response *really* means your data isn't there.
  A 500 response means that it might be, but there is some sort of outage.
* When the system responds with an HTTP 200, you can be certain your data is
  durably stored on the number of servers you requested. The system is designed to
  *never* allow data loss or corruption.
* The system is designed to be secure. All writes must be performed over a
  secure channel (TLS). Most reads will be as well, unless you are specifically
  requesting to bypass TLS for browser/web channels.

## System scale

Joyent Manta Storage Service is designed to support an arbitrarily large number of objects and an
arbitrarily large number of directories. However, it bounds the number of
objects in a single directory so that list operations can be performed
efficiently.

The system does not have any limit on the size of a single object, but it may
return a "no space" error if the requested object size is larger than a single
physical server has space for. In practice, this number will be in tens of
terabytes, but network transfer times make object sizes of that magnitude
unreasonable anyway.

There is no default API rate limit imposed upon you, however the system reserves the
right to throttle requests if necessary to protect the system. For high-volume
web assets, you should use it as a content delivery network (CDN) origin.

All REST APIs are modeled as streams. They are designed to let you iterate
through result sets without consuming too much memory. For example, listing
a directory returns newline separated JSON objects as opposed to an array or
large XML document.

## Durability

By default, the system stores two copies of your object.
These two copies are placed in two different data centers.
The system relies on ZFS RAID-Z to store your objects, so the durability is actually greater than two would imply.

You are billed for exactly the number of bytes you consume in the system.
For example, if you write a 1MB object with the default number of copies (2),
you will be billed for 2MB of storage each month.
You can store anywhere from 1 to 6 copies.
When the number of copies requested is greater than one,
the system ensures that *at least* two copies are placed in two different
data centers,
and then stripes the other copies across data centers.
If any given data center is down at the time,
you may have copies unbalanced with extra replicas in fewer data centers,
but there will always be at least two data centers with your copy of data.
This allows you to still access your data in the event
of any one data center failure.
