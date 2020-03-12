# Manta Operator Guide

*(Note: This is the operator guide for
[Mantav2](https://github.com/joyent/manta/blob/master/docs/mantav2.md). If you
are operating a mantav1 deployment, please see the [Mantav1 Operator
Guide](https://github.com/joyent/manta/blob/mantav1/docs/operator-guide.md).)*

This operator guide is divided into a few sections:

1. an overview of the [Manta architecture](./architecture.md),
2. a guide for [deploying a new Manta](./deployment.md), and
3. [Manta maintenance information](./maintenance.md), such as performing
   upgrades, using Manta's alarming, metrics and logs.

* * *

Manta is an internet-facing object store. The user interface to Manta is
essentially:

* A *Buckets API* (similar to S3) with objects, accessible over HTTP.
* A separate filesystem-like namespace *Directory API*, with directories and
  objects, accessible over HTTP.
* *Objects* are arbitrary-size blobs of data
* Users can use standard HTTP `PUT`/`GET`/`DELETE` verbs to create, list, and
  remove buckets, directories, and objects.
* Users can fetch arbitrary ranges of an object, but may not *modify* an object
  except by replacing it.

Users can interact with Manta through the official Node.js CLI; the Node, or
Java SDKs; curl(1); or any web browser. For more information, see the [Manta
user guide](../user-guide).
