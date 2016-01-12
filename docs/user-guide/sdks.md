---
title: SDKs and CLI Tools
markdown2extras: wiki-tables, code-friendly
---

# SDKs and CLI Tools

The Joyent Manta Storage Service uses a REST API to read, write, and delete objects
and to create jobs to process them.

Joyent provides several Software Development Kits so that you can use Joyent Manta in
a language and framework that you already know. Some of these SDKs provide
Command Line Interface (CLI) tools to help you learn the system.


# Node.js SDK and CLI

The Node.js SDK was used to develop and to test the Joyent Manta Storage Service.
It is the most robust SDK available for Joyent Manta.

The Node.js SDK includes a Command Line Interface that provides several
tools that let you work with Joyent Manta much as you would work with a Unix system.
We use this CLI for our [Getting Started](index.html) tutorial.

The documentation for Node.js SDK is [here](nodesdk.html).


You can find the Node.js SDK at [https://github.com/joyent/node-manta](https://github.com/joyent/node-manta).


# Python SDK and Joyent Manta Shell

The Python SDK is under active development and works with Python 2.6 and 2.7.

A unique feature of the Python SDK is `mantash`, a shell that lets you work
with Joyent Manta in a bash-like environment.


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

You can find the Python SDK at [https://github.com/joyent/python-manta](https://github.com/joyent/python-manta).


# Ruby SDK

The Ruby SDK is a client for communicating with Joyent Manta.
It is effectively an HTTP(S) wrapper which handles required HTTP headers and performs some sanity checks.
The Ruby SDK seeks to expose all of Joyent Manta's features in a thin low-abstraction client.


You can find the Ruby SDK at [https://github.com/joyent/ruby-manta](https://github.com/joyent/ruby-manta).

# mantaRSDK

The R SDK is an interactive client in the form of an R package,
that exposes all of Joyent Manta's features, and supports R on Unix,
Linux and Windows.

Manta HTTPS authentication uses OpenSSL,
and data transfer is done using RCURL.
JSON logging of HTTPS traffic is done using the Rbunyan package,
inspired by the [bunyan](https://github.com/trentm/node-bunyan) logging module.
Code example sessions are in the package R help,
and Installation instructions on the GitHub README.md file.

You can find the mantaRSDK at
[https://github.com/joyent/mantaRSDK](https://github.com/joyent/mantaRSDK)
and Rbunyan at [https://github.com/joyent/Rbunyan](https://github.com/joyent/Rbunyan).

To learn more about mantaRSDK see
[R Users, Meet Joyent Manta; Manta Users, Meet R](http://www.joyent.com/blog/r-users-meet-joyent-manta-manta-users-meet-r).


# Java SDK

The Java SDK is under development.
At present you can use it to work with objects.
Support for compute jobs is not yet implemented.

You can find the Java SDK at [https://github.com/joyent/java-manta](https://github.com/joyent/java-manta).





