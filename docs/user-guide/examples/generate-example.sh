#!/bin/bash

#
# Copyright 2016, Joyent, Inc.
#
# (Re)generate a Manta User Guide mjob example (as the 'manta' JPC account).
#
# Usage:
#   ./generate-example.sh EXAMPLE_DIR
#

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail


# Want all examples to have jobs (and links to related files in the 'mjob share'
# output) to the special 'manta' user.
#
# Currently we require the caller of this script to have a MANTA_KEY_ID that
# works.
export MANTA_URL=https://us-east.manta.joyent.com
export MANTA_USER=manta




#---- support stuff

function fatal
{
    echo "$0: fatal error: $*"
    exit 1
}

function errexit
{
    [[ $1 -ne 0 ]] || exit 0

    if [[ -n "$EXDIR" && -f "$EXDIR/job.err" ]]; then
        echo "'mjob create' stderr:" >&2
        awk '{ printf("    "); } NR == 1 { printf("$ "); } { print $0 };' \
            $EXDIR/job.err >&2
    fi

    fatal "error exit status $1"
}


#---- mainline

trap 'errexit $?' EXIT

START=$(date +%s)

EXDIR=$1
[[ -n "$EXDIR" ]] || fatal "EXAMPLE_DIR not given"
[[ -d "$EXDIR" ]] || fatal "EXAMPLE_DIR, $EXDIR, is not a dir"
echo "-- Regenerating example $EXDIR"

rm -f $EXDIR/job.{out,err,id} $EXDIR/index.md

echo "Run its job: $EXDIR/job.sh"
if [[ -n "$TRACE" ]]; then
    RUNOPTS="-x"
else
    RUNOPTS=
fi
bash $RUNOPTS $EXDIR/job.sh >$EXDIR/job.out 2>$EXDIR/job.err
head -1 $EXDIR/job.err | awk '{print $NF}' >$EXDIR/job.id

# Either one or both of waiting via 'mjob create -w' or 'mjob create -o'
# results in us returning before we can run 'mjob share' on that job.
# Hence let's poll until "timeArchiveDone".
jobId=$(cat $EXDIR/job.id)
while true; do
    isDone=$(mjob get "$jobId" | json -ga timeArchiveDone)
    if [[ -n "$isDone" ]]; then
        break
    fi
    sleep 1
done

echo "Create job share doc: $EXDIR/index.html"
bash $EXDIR/index.md.in >$EXDIR/index.md
mjob share -s -r $EXDIR/index.md "$(cat $EXDIR/job.id)" > $EXDIR/index.html

END=$(date +%s)
echo "Finished in $(($END - $START)) seconds"
