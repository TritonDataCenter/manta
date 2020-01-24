## Sample training outline

This document outlines sample topics for a training course on operating Manta.

* Docs: 
    * Manta Overview: https://github.com/joyent/manta
    * Manta Ops Guide: https://github.com/joyent/manta/blob/master/docs/manta-ops.md
    * Manatee Users Guide: https://github.com/joyent/manatee/blob/master/docs/user-guide.md
    * Manatee Troubleshooting Guide: https://github.com/joyent/manatee/blob/master/docs/trouble-shooting.md
* Architecture Review
* Using Manta
    * Get new users set up for Manta
    * `m* tools`: `mmkdir`, `mrmdir`, `mls`, `mfind`, `mput`, `mget`, `msign`, `mrm`,
    * Basic Map/reduce patterns
* Discovery/Moving around
    * `sdc-cnapi`
    * `sdc-vmapi`
    * `sdc-sapi`
    * `sdc-login`
    * `manta-login` - type, zonename, etc.
    * `manta-adm` - show, cn
* Deployments
    * `manta-adm` - `-s -j`, edit, `update -n`, `update`
    * `manta-deploy`
    * `manta-undeploy`
    * `sapiadm reprovision ...`
    * Upgrades
* Operations
    * Typical Zone setup
        * setup, `mdata:execute`, sapi_manifests, config-agent
        * svcs, svcadm, svccfg
    * Dashboards
        * Via ssh tunnels like: `ssh -o TCPKeepAlive=yes -N -n root@[Headnode] -L 5555:[MadtomAdminIp]:80`
        * Madtom: _hint: sometimes it lies_
        * Marlin Dashboard
    * Alarms
        * mantamon
    * Known issues
        * Zookeeper Leader goes down
        * Postgres needs vacuum/analyze
        * Powering down Manta
    * Command Line Tools/Where stuff is
        * General
            * `json`
            * `bunyan`
        * Zookeeper/binder
            * `zkCli.sh`
            * `dig @localhost`
        * Postgres (Manatee)
            * `manatee-adm`
            * `psql moray`
        * Moray/Electric Moray
            * `getobject`
            * `getbucket`
        * Storage
            * `/manta/[owner]/[object_id]`
            * `/manta/tombstone/[date]/[object_id]`
