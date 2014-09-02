#
# Copyright (c) 2012, Joyent, Inc. All rights reserved.
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
