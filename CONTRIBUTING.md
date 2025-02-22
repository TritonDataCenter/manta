<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright 2019 Joyent, Inc.
    Copyright 2025 MNX Cloud, Inc.
-->

# Manta Contribution Guidelines

Thanks for using Manta and for considering contributing to it!

# Code

All changes to Manta project repositories go through code review via a GitHub
pull request.

If you're making a substantial change, you probably want to contact developers
[on the mailing list or IRC](README.md#community) first. If you have any trouble
with the contribution process, please feel free to contact developers [on the
mailing list or IRC](README.md#community).

See the [developer guide](docs/developer-guide) for useful information about
building and testing the software.

Manta repositories use the same [Joyent Engineering
Guidelines](https://github.com/TritonDataCenter/eng/blob/master/docs/index.md) as
the Triton project.  Notably:

* The #master branch should be first-customer-ship (FCS) quality at all times.
  Don't push anything until it's tested.
* All repositories should be "make check" clean at all times.
* All repositories should have tests that run cleanly at all times.

Typically each repository has `make check` to lint and check code style.
Specific code style can vary by repository.

## Issues

There are two separate issue trackers that are relevant for Manta code:

* An internal JIRA instance.

  A JIRA ticket has an ID like `MANTA-380`, where "MANTA" is the JIRA project
  name. A read-only view of many JIRA tickets is made available at
  <https://smartos.org/bugview/> (e.g.
  <https://smartos.org/bugview/MANTA-380>).

* GitHub issues for the relevant repository.

Before Manta was open sourced, Joyent engineering used a private JIRA instance.
While Joyent continues to use JIRA internally, we also use GitHub issues for
tracking -- primarily to allow interaction with those without access to JIRA.


## Code of Conduct

All persons and/or organizations contributing to, or interacting with our
repositories or communities are required to abide by the
[illumos Code of Conduct][coc].

[coc]: https://github.com/TritonDataCenter/illumos-joyent/blob/master/CODE_OF_CONDUCT.md
