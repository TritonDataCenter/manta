<!--
    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
-->

<!--
    Copyright (c) 2016, Joyent, Inc.
-->

# Manta Contribution Guidelines

The Manta project uses [cr.joyent.us](https://cr.joyent.us) for code review of
all changes.  Any registered GitHub user can submit changes through this system.
If you want to contribute a change, please see the [cr.joyent.us user
guide](https://github.com/joyent/joyent-gerrit/blob/master/docs/user/README.md).
If you're making a substantial change, you probably want to contact developers
on the mailing list or IRC first.  If you have any trouble with the contribution
process, please feel free to contact developers [on the mailing list or
IRC](README.md#community).

See the (work-in-progress) [developer guide](docs/dev-notes.md) for useful
information about building and testing the software.

Manta repositories use the same [Joyent Engineering
Guidelines](https://github.com/joyent/eng/blob/master/docs/index.md) as
the SDC project.  Notably:

* The #master branch should be first-customer-ship (FCS) quality at all times.
  Don't push anything until it's tested.
* All repositories should be "make check" clean at all times.
* All repositories should have tests that run cleanly at all times.

"make check" checks both JavaScript style and lint.  Style is checked with
[jsstyle](https://github.com/davepacheco/jsstyle).  The specific style rules are
somewhat repo-specific.  See the jsstyle configuration file in each repo for
exceptions to the default jsstyle rules.

Lint is checked with
[javascriptlint](https://github.com/davepacheco/javascriptlint).  ([Don't
conflate lint with
style!](http://dtrace.org/blogs/dap/2011/08/23/javascriptlint/)  There are gray
areas, but generally speaking, style rules are arbitrary, while lint warnings
identify potentially broken code.)  Repos sometimes have repo-specific lint
rules, but this is less common.
