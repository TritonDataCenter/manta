# Manta Operator Guide

*(Note: This is the operator guide for
[Mantav2](https://github.com/joyent/manta/blob/master/docs/mantav2.md). If you
are operating a mantav1 deployment, please see the [Mantav1 Operator
Guide](https://github.com/joyent/manta/blob/mantav1/docs/operator-guide.md).)*

This operator guide is divided into sections:

1. [Manta Architecture](./architecture.md)
2. [Deploying Manta](./deployment.md) - setting up a new Manta
3. [Operating and Maintaining Manta](./maintenance.md): performing
   upgrades, using Manta's alarming, metrics, and logs
4. [Migrating from Mantav1 to Mantav2](./mantav2-migration.md)

* * *

Manta is an internet-facing object store. The user interface to Manta is
essentially:

* A separate filesystem-like namespace *Directory API*, with directories and
  objects, accessible over HTTP.
* *Objects* are arbitrary-size blobs of data
* Users can use standard HTTP `PUT`/`GET`/`DELETE` verbs to create, list, and
  remove directories, and objects.
* Users can fetch arbitrary ranges of an object, but may not *modify* an object
  except by replacing it.

Users can interact with Manta through the official Node.js CLI; the Node, or
Java SDKs; curl(1); or any web browser. For more information, see the [Manta
user guide](../user-guide).
