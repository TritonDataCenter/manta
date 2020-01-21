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
	./node_modules/.bin/doctoc --notitle --maxlevel 3 docs/operator-guide.md

.PHONY: docs-regenerate-examples
docs-regenerate-examples:
	docs/user-guide/examples/regenerate-all-examples.sh
