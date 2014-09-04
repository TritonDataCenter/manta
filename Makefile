#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Files
#
DOC_FILES	 = $(shell find docs -name "*.restdown" | sed 's/docs\///;')

include ./tools/mk/Makefile.defs

#
# Repo-specific targets
#
.PHONY: all
all: docs

include ./tools/mk/Makefile.deps
include ./tools/mk/Makefile.targ
