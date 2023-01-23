---
title: SDKs and CLI Tools
markdown2extras: wiki-tables, code-friendly
---

# SDKs and CLI Tools

The Manta Storage Service uses a REST API to read, write, and delete objects
and to create jobs to process them.

There are several Software Development Kits so that you can use Manta in
a language and framework that you already know. Some of these SDKs provide
Command Line Interface (CLI) tools to help you learn the system.


# Node.js SDK and CLI

The Node.js SDK was used to develop and to test the Manta Storage Service.
It is the most robust SDK available for Manta.

The Node.js SDK includes a Command Line Interface that provides several
tools that let you work with Manta much as you would work with a Unix system.
We use this CLI for our [Getting Started](index.html) tutorial.

The documentation for Node.js SDK is [here](nodesdk.html).


You can find the Node.js SDK at [https://github.com/TritonDataCenter/node-manta](https://github.com/TritonDataCenter/node-manta).


# Python SDK and Manta Shell

The Python SDK is a community-maintained package for Manta, providing
a "manta" package and `mantash`, a shell that lets you work with Manta in
a bash-like environment.

    # Mantash single commands can be run like:
    #       mantash ls
    # Or you can enter the mantash interactive shell and run commands from
    # there. Let's do that:
    $ mantash
    [jill@us-east /jill/stor]$ ls
    [jill@us-east /jill/stor]$                      # our stor is empty
    [jill@us-east /jill/stor]$ put numbers.txt ./   # upload local file
    [jill@us-east /jill/stor]$ ls
    numbers.txt
    [jill@us-east /jill/stor]$ cat numbers.txt
    one
    two
    three
    four

You can find the Python SDK at [https://github.com/TritonDataCenter/python-manta](https://github.com/TritonDataCenter/python-manta).


# Ruby SDK

The Ruby SDK is a client for communicating with Manta.
It is effectively an HTTP(S) wrapper which handles required HTTP headers and performs some sanity checks.
The Ruby SDK seeks to expose all of Manta's features in a thin low-abstraction client.


You can find the Ruby SDK at [https://github.com/TritonDataCenter/ruby-manta](https://github.com/TritonDataCenter/ruby-manta).

# mantaRSDK

The R SDK is an interactive client in the form of an R package,
that exposes all of Manta's features, and supports R on Unix,
Linux and Windows.

Manta HTTPS authentication uses OpenSSL,
and data transfer is done using RCURL.
JSON logging of HTTPS traffic is done using the Rbunyan package,
inspired by the [bunyan](https://github.com/trentm/node-bunyan) logging module.
Code example sessions are in the package R help,
and Installation instructions on the GitHub README.md file.

You can find the mantaRSDK at
[https://github.com/TritonDataCenter/mantaRSDK](https://github.com/TritonDataCenter/mantaRSDK)
and Rbunyan at [https://github.com/TritonDataCenter/Rbunyan](https://github.com/TritonDataCenter/Rbunyan).

To learn more about mantaRSDK see
[R Users, Meet Manta; Manta Users, Meet R](http://www.tritondatacenter.com/blog/r-users-meet-joyent-manta-manta-users-meet-r).


# Java SDK

The Java SDK has feature parity with the Node.js SDK. However, if new features
are released it will be late to implement them. It supports all object operations,
HTTP signing and compute jobs.

The Java SDK is available as a [Maven](https://maven.apache.org/) module. To use
it add the following to your project's pom.xml:

	<dependency>
        <groupId>com.joyent.manta</groupId>
        <artifactId>java-manta-client</artifactId>
        <!-- replace this value with the specific version number -->
        <version>LATEST</version>
    </dependency>

You can find the source for Java SDK at [https://github.com/TritonDataCenter/java-manta](https://github.com/TritonDataCenter/java-manta).


# Hadoop FileSystem Driver

Hadoop can natively access Manta over the network. Most major Hadoop FileSystem
features are supported. This is a community driven project, so updates to it
are dependent upon community involvement. The driver is available as a
stand-alone jar file that can be dropped into a Hadoop or Apache Drill
installation.

You can download the jar directory from the [releases page](https://github.com/TritonDataCenter/hadoop-manta/releases)
on the [project's github page](https://github.com/TritonDataCenter/hadoop-manta)
or directly from Maven Central.


# PHP SDK

The PHP SDK supports all object operations and compute jobs. It is a community
driven SDK, so updates to it are dependent upon community involvement. The SDK
is available as a [Packagist package](https://packagist.org/packages/joyent/php-manta)
and can be installed using [Composer](https://getcomposer.org/):

    composer require joyent/php-manta

It has been tested in PHP 5.6, PHP 7.0 and HHVM.

You can find the source for PHP SDK at [https://github.com/TritonDataCenter/php-manta](https://github.com/TritonDataCenter/php-manta).


# Perl Module

There is a Perl module available via CPAN that supports object operations. It is
a community driven module, so updates to it are dependent upon community
involvement.
The module is available on [CPAN](http://search.cpan.org/~andrewh/Manta-Client/).

You can find the source for the Perl module at [https://github.com/TritonDataCenter/Manta-Client](https://github.com/TritonDataCenter/Manta-Client).


# Golang SDK

The Go SDK for Manta is currently in active development. It is a combination SDK
that provides support for Triton CloudAPI operations in addition to Manta API
operations.

You can find the source for the Go Manta SDK at [https://github.com/TritonDataCenter/triton-go](https://github.com/TritonDataCenter/triton-go).


# Erlang SDK

The Erlang SDK for Manta is community-maintained SDK that has support for most
file operations and jobs.

You can find the source for the Erlang SDK at [https://github.com/TritonDataCenter/erlang-manta](https://github.com/TritonDataCenter/erlang-manta).
