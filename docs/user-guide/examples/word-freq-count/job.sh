COUNT=30; mfind /manta/public/examples/shakespeare | \
    mjob create -n "Word frequency count" -o \
        -m "tr -cs A-Za-z '\n' | tr A-Z a-z | sort | uniq -c" \
        -r "awk '{ x[\$2] += \$1 }
                 END { for (w in x) { print x[w] \" \" w } }' |
            sort -rn | sed ${COUNT}q"
