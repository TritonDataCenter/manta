#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2016, Joyent, Inc.
#

#
# Files
#

# Only care to build the operator guide for publishing directly out of
# this repo (to <http://joyent.github.io/manta/>). The other docs are
# pulled into apidocs.joyent.com.git for publishing there.
DOC_FILES	 = operator-guide/index.md

include ./tools/mk/Makefile.defs

#
# Repo-specific targets
#
.PHONY: all
all: docs

include ./tools/mk/Makefile.deps
include ./tools/mk/Makefile.targ
