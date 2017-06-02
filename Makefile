#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2017, Joyent, Inc.
#

#
# Files
#

# Only care to build the operator guide for publishing directly out of
# this repo (to <http://joyent.github.io/manta/>). The other docs are
# pulled into apidocs.joyent.com.git for publishing there. See RFD 23.
DOC_FILES	 = operator-guide.md

include ./tools/mk/Makefile.defs

#
# Repo-specific targets
#
.PHONY: all
all: docs

.PHONY: docs-regenerate-examples
docs-regenerate-examples:
	docs/user-guide/examples/regenerate-all-examples.sh

CLEAN_FILES += docs/operator-guide.{html,json} build/docs

# Update the operator guide at <http://joyent.github.io/manta/>.
.PHONY: publish-operator-guide
publish-operator-guide: docs
	@[[ -n "$(MSG)" ]] \
		|| (echo "publish-operator-guide: error: no commit MSG"; \
		echo "usage: make publish-operator-guide MSG='... commit message ...'"; \
		exit 1)
	mkdir -p tmp
	[[ -d tmp/gh-pages ]] || git clone git@github.com:joyent/manta.git tmp/gh-pages
	cd tmp/gh-pages && git checkout gh-pages && git pull --rebase origin gh-pages
	rsync -av build/docs/public/media/ tmp/gh-pages/media/
	cp build/docs/public/operator-guide.html tmp/gh-pages/index.html
	(cd tmp/gh-pages \
		&& git commit -a -m "$(MSG)" \
		&& git push origin gh-pages || true)

include ./tools/mk/Makefile.deps
include ./tools/mk/Makefile.targ
