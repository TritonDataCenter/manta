---
title: Manta-NFS
markdown2extras: wiki-tables, code-friendly
---

# Manta-NFS

Manta NFS lets you mount all or some of your Manta directories as
directories in your file system.

`manta-nfs` implements a [NFS vers. 3](http://tools.ietf.org/html/rfc1813)
server that uses
[Joyent Manta](http://www.joyent.com/products/manta) as the backing store.
The server implements all NFS functionality, although some OS-level commands,
such as `chmod`, will have no effect since Manta does not support that concept.
The server is implemented in [node.js](http://nodejs.org/) and **requires**
v0.10.x.

If node isn't installed on your machine,
follow the instructions for
[installing Manta](http://apidocs.joyent.com/manta/#getting-started).



# Quick Start

This quick start works best on Mac OS X,
or in another environment where you already have Manta running.
If you run into problems, see the section for your operating system below.

First, make sure that your version of node is 0.10.0 or later,
and install manta-nfs.

    $ node -v
    v0.10.26
    $ npm install -g manta-nfs



Next, check that you have the
[Manta environment variables set up](http://apidocs.joyent.com/manta/#setting-up-your-environment).

    $ env | grep MANTA
    MANTA_USER=mantauser
    MANTA_KEY_ID=3e:37:9b:11:a6:dc:21:be:1a:fd:95:b6:73:ea:42:9e
    MANTA_URL=https://us-east.manta.joyent.com

Start the manta-nfs server. The server writes log output,
so it's best to run it in its own terminal session.

    $ sudo -E node $NODE_PATH/manta-nfs/server.js
    . . .
    {"name":"server.js","hostname":"mac.local","pid":32960,"level":30,"msg":"nfsd: listening on: tcp://127.0.0.1:2049","time":"2014-04-04T23:46:17.632Z","src":{"file":"/usr/local/lib/node_modules/manta-nfs/server.js","line":270,"func":"onRunning"},"v":0}

Create mount points in your local filesystem.
For example, if you wanted to mount your entire Manta storage as a directory
named `~/mnt`, use these commands. On Linux systems, use the `-o nolock`
option with the `mount` command.

    $ mkdir -p ~/mnt
    $ sudo mount 127.0.0.1:/mantauser ~/mnt
    $ ls ~/mnt
    jobs    public  reports stor

Now you can use the directory `/mnt` to work with your Manta objects
as if they were files in the file system.

You can list the contents:

    $ cd ~/mnt
    $ ls -l public/
    total 2
    drwxr-xr-x  3 nobody  nobody     0 Apr  6 20:12 dirfoo
    -rw-r--r--  1 nobody  nobody   345 Mar 10 14:58 essentialsoftware.txt

You can make copies of objects and copy objects from one directory to another:

    $ cp stor/shakespeare.tar.gz public/
    $ ls public/
    dirfoo      essentialsoftware.txt       shakespeare.tar.gz

You can copy directories recursively:

    $ cp -r dirfoo mydir

You *cannot* move or rename directories.
You can use it to rename objects.

    $ mv stor/books/ public/
    mv: rename stor/books/ to public/books/: Is a directory
    $ mv config.xml configuration.xml

Other commands that you cannot use on Manta objects include:

* chmod
* chown
* ln
* mkfifo
* mv (directories)
* touch (to change file attributes)

You *can* use the `touch` command to force an object
in your manta-nfs mount to sync up with the object in Manta.



# How Manta-NFS Works

The manta-nfs server caches Manta objects locally.
Cached operations are fast, but a cache miss is slower than
accessing Manta directly.


Be careful if you access Manta objects through
different mechanisms (Manta CLI, Manta REST API, etc) or
from different locations.
If you write an object using one mechanism, such as manta-nfs,
and immediately read it using another, such as the Manta CLI,
you probably won't see the same data.
The manta-nfs server caches Manta objects locally
for a period of time before writing them back to Manta.
Likewise, if you update
an existing object using the Manta CLI,
the manta-nfs server may have a stale copy in its
local cache for some time.
In this case you can wait for the server to notice the object has
changed, or you can force the server to refresh its cached copy by `touch`ing the file.

  * Don't run more than one instance of the server for the same Manta user.
  * Don't write to the same object using NFS and Manta CLI.
  * Reading the same object from NFS and Manta CLI is OK.

The reliability of the cached objects depends entirely
on the file system of your local machine.

There are certain NFS operations that are not supported because Manta
itself does not support the underlying concept. These are:

  * Changing the owner uid or gid of a file
  * Changing the mtime or atime of a file
  * Changing or setting the mode of a file
  * Creating a file exclusively (O_EXCL - will happen only in the cache)
  * Making devices, sockets or FIFOs
  * Renaming or moving directories
  * Symlinks and hardlinks





# Running Manta-NFS as a Service

This section tells you how to run Manta-NFS as a service
that starts when your machine boots. The steps
to do this vary from operating system to operating system.

You can find files mentioned in this section
(launchd, SMF, rc)
in the [manta-nfs repo on GitHub](https://github.com/joyent/manta-nfs).


## Writing a Configuration File

In the QuickStart, we used the Manta environment variables
to tell manta-nfs which Manta account and which credentials
to use. When running as a service, it's best to provide
this information in a configuration file.

The minimal configuration file is:

    {
        "manta": {
            "keyFile": "/Users/mantauser/.ssh/id_rsa",
            "keyId": "03:71:24:1c:b6:64:51:9e:9d:6b:06:bf:4f:7c:19:dc",
            "url": "https://us-east.manta.joyent.com",
            "user": "mantauser"
        }
    }

The `keyfile` field is the location of your SSH private key.
The `keyId` field is the signature of your public SSH key.

You can find a fully commented example of all the sections and fields
that are legal in a configuration file in `etc/example.json`.

## Testing the Configuration and Environment

The sections that follow give more detailed instructions
about what you need, such as additional packages,
to run manta-nfs under different operating
systems.

If you want to give your setup a test, you can use this command:

    $ sudo node server.js -f /usr/local/manta-nfs/etc/manta-nfs.json > logfile 2>&1 &

You should specify the location of your config file,
and on SmartOS, use `pfexec` instead of `sudo`.

## Darwin (OS X)

The `svc/launchd/com.joyent.mantanfs.plist` file provides an example
configuration for launchd(8). Edit the file and provide the
correct paths to 'node', 'server.js' and your configuration file.

Note that this configuration will bring the service up only if an interface
other than `lo` has an IPV4/IPV6 address.  However the reverse is not true, and
launchd will not bring down the service if the network goes away.

Place the config files in `/usr/local/manta-nfs/etc/manta-nfs.json`.

Run the following to load and start the service:

    sudo cp svc/launchd/com.joyent.mantanfs.plist /System/Library/LaunchDaemons/
    sudo launchctl load /System/Library/LaunchDaemons/com.joyent.mantanfs.plist

## SmartOS

In order to mount from the host, the system's 'rpcbind' must be running.  The
server's built-in portmapper cannot be used. If the svc is not already enabled,
enable it.

    # svcadm enable network/rpc/bind

If you intend to serve external hosts, you must also ensure that the bind
service is configured to allow access. To check this:

    # svccfg -s bind listprop config/local_only

If this is set to true, you need to change it to false.

    # svccfg -s bind setprop config/local_only=false
    # svcadm refresh bind

Due to a mis-design in the SmartOS mount code, mounting will fail on older
platforms. If you see the following, you know your mount code is incorrect.

    nfs mount: 127.0.0.1: : RPC: Program not registered
    nfs mount: retrying: /home/foo.bar/mnt

You will either need to run on a newer platform or you can use this
[fixed NFS mount command](http://us-east.manta.joyent.com/jjelinek/public/mount)
explicitly. e.g.

    pfexec ./mount 127.0.0.1:/foo.bar/public /home/foo/mnt

For unmounting, you can use this
[fixed umount command](http://us-east.manta.joyent.com/jjelinek/public/umount)
explicitly.

On SmartOS the uid/gid for 'nobody' is 60001.

The `svc/smf/manta-nfs.xml` file provides an example configuration for
smf(5). If necessary, edit the file and provide the correct paths to 'node',
'server.js' and your configuration file.

Run the following to load and start the service:

    svccfg -v import svc/smf/manta-nfs.xml

## Linux

There is no lock manager included in manta-nfs, so you must disable locking
when you mount under Linux.

    mount -o nolock 127.0.0.1:/foo.bar/public /home/foo/mnt



Some distributions (e.g. Ubuntu or Centos) may not come pre-installed with
the `/sbin/mount.nfs` command which is needed to perform a mount, while others
(e.g. Fedora) may be ready to go. On Ubuntu, install the `nfs-common` package.

    apt-get install nfs-common

On Centos, install the `nfs-utils` package.

    yum install nfs-utils

Installing these packages also installs and starts `rpcbind`.
However, manta-nfs will not be able to register with it.
To work around this, you can do one of these things:

  * Stop the system's `rpcbind` and let manta-nfs uses its
    built in portmapper. The commands to do this vary from system
    to system. On Ubuntu, for instance, you can use

        $ stop portmap
        $ stop rpcbind

  * If `rpcbind` has its own package, you can uninstall that package.


  * Run the system's rpcbind in 'insecure' mode using the -i option.
    The place where you do this varies among the different Linux distributions.

    On systems using 'upstart' you can add the option in
    `/etc/init/portmap.conf`.

    On systems using 'systemd' you can add the
    option in `/etc/sysconfig/rpcbind`.

    On systems that use traditional
    rc files you must edit `/etc/init.d/rpcbind` and add the option to the
    invocation of rpcbind in the script.

On Linux the uid/gid for 'nobody' is 65534.

To setup the server as a service, so that it runs automatically when the
system boots, you need to hook into the system's service manager. Linux offers
a variety of dfferent service managers, depending upon the distribution.

  * rc files

    The traditional Unix rc file mechanism is not really a service manager but
    it does provide a way to start or stop services when the system is booting
    or shutting down.

    The `svc/rc/mantanfs` file is a shell script that will start up the server.
    Make a copy of this file into `/etc/init.d`. If necessary, edit the file and
    provide the correct paths to 'node', 'server.js' and your configuration
    file.

    Symlink the following names to the 'mantanfs' file:

        ln -s /etc/rc3.d/S90mantanfs -> ../init.d/mantanfs
        ln -s /etc/rc4.d/S90mantanfs -> ../init.d/mantanfs
        ln -s /etc/rc5.d/S90mantanfs -> ../init.d/mantanfs
        ln -s /etc/rc0.d/K90mantanfs -> ../init.d/mantanfs
        ln -s /etc/rc1.d/K90mantanfs -> ../init.d/mantanfs
        ln -s /etc/rc2.d/K90mantanfs -> ../init.d/mantanfs
        ln -s /etc/rc6.d/K90mantanfs -> ../init.d/mantanfs

    The script directs the server log to '/var/log/mantanfs.log'.

  * Systemd

    See this [wiki](https://fedoraproject.org/wiki/Systemd) for more details
    on configuring and using systemd.  Also see the `systemd.unit(5)` and
    `systemd.service(5)` man pages.

    The `svc/systemd/mantanfs.service` file provides an example configuration
    for systemd. Make a copy of this file into /lib/systemd/system. If
    necessary, edit the file and provide the correct paths to 'node',
    'server.js' and your configuration file.

    Run the following to start the service:

        systemctl start mantanfs.service

    Since systemd has its own logging, you must use the 'journalctl' command to
    look at the logs.
```
        journalctl _SYSTEMD_UNIT=mantanfs.service
```
  * Upstart

    See this [cookbook](http://upstart.ubuntu.com/cookbook/) for more details
    on configuring and using upstart.

    The `svc/upstart/mantanfs.conf` file provides an example configuration for
    upstart. Make a copy of this file into /etc/init. If necessary, edit the
    file and provide the correct paths to 'node', 'server.js' and your
    configuration file.

    Run the following to start the service:

        initctl start mantanfs

    The server log should be available as '/var/log/upstart/mantanfs.log'.


## Windows

Because of the POSIX dependencies in the server, the code does not currently
build on Windows. However, the Windows NFS client can be used with a server
running on a Unix-based host. Before you can use NFS you may need to set it up
on your Windows system. The procedure varies by which version of Windows
is in use. See the documentation for your release for the correct procedure
to install NFS.

Once NFS is installed, you simply mount from the server as usual. Substitute
the server's IP address and the correct user name in the following example:

    C:\>mount \\192.168.0.1\foo\public *
    Z: is now successfully connected to \\192.168.0.1\foo\public

    The command completed successfully.

Windows will assign an unused drive letter for the mount. In this example the
drive letter was Z:.

Windows Explorer has the same limitation as Darwin's Finder when creating a
new folder. The new folder will initially be created by Explorer with the name
`New folder`, but you will not be able to rename it. Instead, you must use
a terminal window and the command line to create directories with the correct
name.


# Manta-NFS on Linux - distribution-specific instructions

* Update and install some required packages

Ubuntu:
```
# apt-get -y update
# apt-get -y install npm nfs-common
# ln -s /usr/bin/nodejs /usr/bin/node
```
CentOS:
```
# yum -y update
# curl --silent --location https://rpm.nodesource.com/setup | bash -
# yum install -y gcc-c++ make nodejs nfs-utils
```
## Install the Manta CLI tools and manta-nfs
```
# npm install manta-nfs -g
# npm install manta -g
```
## Set up SSH keys and environment and test Manta connectivity

These next steps assume a default path for SSH keys. You can use other paths, but you'll need to modify them appropriately.

* Copy your public and private SSH keys to `/root/.ssh/id_rsa.pub` and `/root/.ssh/id_rsa` respectively.
* Append your Manta variable exports to `/root/.bashrc`, for example:

```
export MANTA_URL=https://us-east.manta.joyent.com
export MANTA_USER=john.smith
export MANTA_KEY_ID=b9:71:88:f4:c1:62:cf:b4:7c:cc:3b:00:d7:ff:21:46
```
Now, log out and back in again, or source `.bashrc`.

* Test Manta connectivity with the `mls` command:

```
# mls /$MANTA_USER
jobs/
public/
reports/
stor/
```
* Build the manta-nfs configuration file so it can start without the environment:

```
# cat <<EOF >/etc/manta-nfs.json
{
    "manta": {
        "keyFile": "/root/.ssh/id_rsa",
        "keyId": "$MANTA_KEY_ID",
        "url": "$MANTA_URL",
        "user": "$MANTA_USER"
    }
}
EOF
```
# Configuring services

These steps are quite different depending on distribution.

## CentOS 6

* Reboot to ensure all services are running normally.
* Start manta-nfs in the background:

```
# node /usr/lib/node_modules/manta-nfs/server.js &
```
* Mount your Manta share.

On LX, use:
```
# mount -o nfslock,nfsvers=3 127.0.0.1:/$MANTA_USER /mnt
```
On KVM, use:

```
# mount 127.0.0.1:/$MANTA_USER /mnt
```
* Verify manta-nfs is functioning correctly with:

```
# ls /mnt
```
* Copy the mantanfs init script and open in your favorite text editor:

```
# cp /usr/lib/node_modules/manta-nfs/svc/rc/mantanfs /etc/init.d
# vi /etc/init.d/mantanfs
```

* Modify the `SERVER` definition from `/usr/local/bin/server.js` to `/usr/lib/node_modules/manta-nfs/server.js`
* Modify the `CONFIG` definition from `/usr/local/etc/manta-nfs.json` to `/etc/manta-nfs.json`
* Under the `Default-Stop` line, add:

```
# chkconfig: 345 24 76' /etc/init.d/mantanfs
```
* In the `start()` function, add a line between the `echo` and the `return` lines:

```
sleep 5
```
* Make sure the script is executable:

```
# chmod 755 /etc/init.d/mantanfs
```

* Ensure the service will start at boot-time:

```
# chkconfig --add mantanfs
```
* Unmount the share:

```
# umount /mnt
```
* Add a record to `/etc/fstab` so the share mounts at boot time:

On LX, use:
```
# echo "127.0.0.1:/$MANTA_USER /mnt nfs nolock,nfsvers=3 0 0" >>/etc/fstab
```
On KVM, use:
```
# echo "127.0.0.1:/$MANTA_USER /mnt nfs defaults 0 0" >>/etc/fstab
```

* Reboot and test your share is mounted at boot-time.

## CentOS 7

* Start `rpcbind` with:

```
# systemctl start rpcbind.service
```
* Start manta-nfs in the background:

```
# node /usr/lib/node_modules/manta-nfs/server.js &
```
* Mount your Manta share and test:

```
# mount -o vers=3 127.0.0.1:/$MANTA_USER /mnt
# ls /mnt
```
* Unmount the share and stop manta-nfs:

```
# umount /mnt
# pkill node
```
* Copy the manta-nfs systemd script and open in your favorite text editor:

```
# cp  /usr/lib/node_modules/manta-nfs/svc/systemd/mantanfs.service /etc/systemd/system
# vi /etc/systemd/system/mantanfs.service
```

* Modify both occurrences of server.js from `/usr/local/bin/server.js` to `/usr/lib/node_modules/manta-nfs/server.js`
* Modify both occurrences of manta-nfs.json from `/usr/local/etc/manta-nfs.json` to `/etc/manta-nfs.json`
* In the `[Unit]` section, add the line `Before=remote-fs-pre.target`
* In the `[Service]` section, add the lines:

```
ExecStartPre=/usr/sbin/rpcinfo
ExecStartPost=/bin/sleep 5
```
* Add another section on the end of the file:

```
[Install]
WantedBy=remote-fs-pre.target
```

* Reload systemd:

```
# systemctl daemon-reload
```
* Start manta-nfs:

```
# systemctl start mantanfs.service
```
* Again, mount and test your share:

```
# mount -o vers=3 127.0.0.1:/$MANTA_USER /mnt
# ls /mnt
# umount /mnt
```
* Configure manta-nfs to start at boot-time:

```
# systemctl enable mantanfs.service
```
* Add a record to `/etc/fstab` so the share mounts at boot time:

```
# echo "127.0.0.1:/$MANTA_USER /mnt nfs vers=3 0 0" >>/etc/fstab
```
* Reboot and test your share is mounted at boot-time.

## Ubuntu 15.04
* Start manta-nfs in the background:

```
# node /usr/lib/node_modules/manta-nfs/server.js &
```
* Create a mount point, mount your Manta share and test:

```
mkdir /manta
mount -o vers=3 127.0.0.1:/$MANTA_USER /manta
ls /manta
```

* Umount the share and stop manta-nfs:

```
umount /manta
pkill node
```
* Copy the manta-nfs systemd script and open in your favorite text editor:

```
cp  /usr/local/lib/node_modules/manta-nfs/svc/systemd/mantanfs.service /etc/systemd/system
vi /etc/systemd/system/mantanfs.service
```

* Modify both occurrences of server.js from `/usr/local/bin/server.js` to `/usr/local/lib/node_modules/manta-nfs/server.js`
* Modify both occurrences of manta-nfs.json from `/usr/local/etc/manta-nfs.json` to `/etc/manta-nfs.json`
* In the `[Unit]` section, add the line `Before=remote-fs-pre.target`
* In the `[Service]` section, add the lines:

```
ExecStartPre=/usr/sbin/rpcinfo
ExecStartPost=/bin/sleep 5
```
* Add another section on the end of the file:

```
[Install]
WantedBy=remote-fs-pre.target
```
* Reload systemd:

```
# systemctl daemon-reload
```
* Start manta-nfs:

```
# systemctl start mantanfs.service
```
* Again, mount and test your share:

```
# mount -o vers=3 127.0.0.1:/$MANTA_USER /mnt
# ls /mnt
# umount /mnt
```
* Configure manta-nfs to start at boot-time:

```
# systemctl enable mantanfs.service
```
* Add a record to `/etc/fstab` so the share mounts at boot time:

```
# echo "127.0.0.1:/$MANTA_USER /mnt nfs vers=3 0 0" >>/etc/fstab
```
* Reboot and test your share is mounted at boot-time.
