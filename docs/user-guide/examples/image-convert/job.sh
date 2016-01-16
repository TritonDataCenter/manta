mfind -t o -n '.*\.png' /manta/public/examples/symbols | \
    mjob create -n "Image conversion" -w \
    -m 'convert "$MANTA_INPUT_FILE" out.gif && \
        mpipe -H "content-type: image/gif" -f out.gif \
	    "${MANTA_INPUT_OBJECT%.*}.gif"'
