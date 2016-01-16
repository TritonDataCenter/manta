mfind -n '.*.txt' /manta/public/examples/shakespeare | \
    mjob create -n "Total word count" -o -m wc -r \
    "awk '{ l += \$1; w += \$2; c += \$3 } END { print l, w, c }'"
