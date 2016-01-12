mfind -t o -n '.*.txt' /manta/public/examples/shakespeare | \
    mjob create -w \
     -s /manta/public/examples/assets/indexone.sh \
     -m '/assets/manta/public/examples/assets/indexone.sh "$MANTA_INPUT_FILE"' \
     -s /manta/public/examples/assets/indexmerge.awk \
     -r 'awk -f /assets/manta/public/examples/assets/indexmerge.awk | sort'
