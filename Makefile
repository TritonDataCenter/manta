#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright 2020 Joyent, Inc.
#

#
# Repo-specific targets
#
.PHONY: all
all: docs

./node_modules/.bin/doctoc:
	npm install

# Make a table of contents in Markdown docs that are setup to use it.  This
# changes those files in-place, so one should do this before commit.
.PHONY: docs
docs: | ./node_modules/.bin/doctoc
	./node_modules/.bin/doctoc --notitle --maxlevel 3 docs/developer-guide/README.md
	./node_modules/.bin/doctoc --notitle --maxlevel 3 docs/operator-guide/architecture.md
	./node_modules/.bin/doctoc --notitle --maxlevel 3 docs/operator-guide/deployment.md
	./node_modules/.bin/doctoc --notitle --maxlevel 3 docs/operator-guide/maintenance.md
