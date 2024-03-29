# Mantav2

Starting November 2019, there will be two separate active versions of Manta:

- "**mantav1**" - a long term support branch of Manta that maintains current
  Manta features.
- "**mantav2**" - a new major version of Manta that adds (Buckets API, storage
  "rebalancer" service) and removes (jobs, snaplinks, etc.) some major
  features, and becomes the focus of future Manta development.

At this time, mantav1 is the recommended version for production usage, but
that is expected to change to mantav2 during 2020.


## What is mantav2?

"Mantav2" is a new major version of Manta. Its purpose is to focus on:

- improved API latency;
- exploring alternative storage backends that improve efficiency;
- improved operation and stability at larger scales.

It is a backward incompatible change, because it drops some API features.
Significant changes are:

- The following features of the current API (now called the "Directory API")
  are being removed.
    - jobs (a.k.a. compute jobs)
    - snaplinks
    - metering data under `/<account>/reports/...`
  Otherwise the Directory API remains a part of Manta.
- A new "Buckets API" (S3-like) is added. This is the API for which latency
  improvements are being made.
- A "rebalancer" system is added for storage tier maintenance.
- The garbage collection (GC) system is improved for larger scale.
- Improved per-account usage data for operators.

The "master" branch of Manta-related git repos is for mantav2. Mantav1
development has moved to "mantav1" branches.


## How do I know if I have mantav1 or mantav2?

A user can tell from the "Server" header in Manta API responses.
A mantav1 API responds with `Server: Manta`:

    $ curl -is $MANTA_URL/ | grep -i server
    server: Manta

and a mantav2 API responds with `Server: Manta/2`:

    $ curl -is $MANTA_URL/ | grep -i server
    server: Manta/2


An operator can tell from the `MANTAV` metadatum on the "manta" SAPI
application. If `MANTAV` is `1` or empty, this is a mantav1:

    [root@headnode (mydc1) ~]# sdc-sapi /applications?name=manta | json -H 0.metadata.MANTAV
    1

If `MANTAV` is `2`, this is a mantav2:

    [root@headnode (mydc2) ~]# sdc-sapi /applications?name=manta | json -H 0.metadata.MANTAV
    2


## How do I find the Node.js and Java clients for mantav2?

The Node.js and Java clients for mantav2 are still under development. They are
currently available in a feature branch of their respective git repositories.

#### Node.js client

The Node.js Manta client is developed in the
[joyent/node-manta](https://github.com/TritonDataCenter/node-manta) repository.

- mantav1: Currently on the ["master" branch](https://github.com/TritonDataCenter/node-manta/tree/master/)
  of joyent/node-manta, and published to npm as
  ["manta"](https://www.npmjs.com/package/manta) -- i.e. `npm install manta`.
- mantav2: Currently on the ["buckets" branch](https://github.com/TritonDataCenter/node-manta/tree/buckets/)
  of joyent/node-manta. It is not yet published to npm.

*(The intent is to eventually move mantav2 to the "master" branch and publish it
to npm as "mantav2". Mantav1 dev would move to the "mantav1" branch and continue
to publish to npm as "manta".)*


#### Java client

The Java Manta client is developed in the
[joyent/java-manta](https://github.com/TritonDataCenter/java-manta) repository.

- mantav1: Currently on the ["master" branch](https://github.com/TritonDataCenter/java-manta/tree/master/)
  of joyent/java-manta. Current release versions are 3.x.
- mantav2: Currently on the ["buckets-m1" branch](https://github.com/TritonDataCenter/java-manta/tree/buckets-m1/)
  of joyent/java-manta.

*(The intent is to eventually move mantav2 to the "master" branch and release it
as a new "4.x" major version. Mantav1 dev would move to the "3.x" branch and
continue to release as 3.x versions.)*


## Is mantav1 still supported?

Operation of a Mantav1 per the [mantav1 Operator
Guide](https://github.com/TritonDataCenter/manta/blob/mantav1/docs/operator-guide.md)
remains unchanged, other than that operators should look for images named
`mantav1-$servicename` rather than `manta-$servicename`. For example:

```
$ updates-imgadm list name=~mantav1- --latest
UUID                                  NAME               VERSION                            FLAGS  OS       PUBLISHED
...
26515c9e-94c4-4204-99dd-d068c0c2ed3e  mantav1-postgres   mantav1-20200226T135432Z-gcff3bea  I      smartos  2020-02-26T14:08:42Z
5c8c8735-4c2c-489b-83ff-4e8bee124f63  mantav1-storage    mantav1-20200304T221656Z-g1ba6beb  I      smartos  2020-03-04T22:21:22Z
```

There are "mantav1" branches of all the relevant repositories, from which
"mantav1-$servicename" images are created for Mantav1 setup and operation.
Joyent offers paid support for on premise mantav1.

While mantav1 work is done to support particular customer issues, and PRs
are accepted for mantav1 branches, the focus of current work is on mantav2.


## How do I migrate my Manta from mantav1 to mantav2?

This work is still in development. At this time a Mantav2 deployment must
start from scratch.
