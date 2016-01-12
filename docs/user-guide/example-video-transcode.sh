mfind -t o -n '.*\.mov' /manta/public/examples/kart | mjob create -w \
    -m 'ffmpeg -nostdin -i $MANTA_INPUT_FILE -an out.webm && \
        mpipe -p -H "content-type: video/webm" -f out.webm \
	    "~~/public/manta-examples/kart/$(basename $MANTA_INPUT_OBJECT .mov).webm"'
