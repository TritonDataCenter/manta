mfind -t o /manta/public/examples/node-v0.10.17 | grep '[^/]\.[^/]*$' |
    mjob create -o \
        -m 'echo "${MANTA_INPUT_OBJECT##*.}" "$(wc -l)"' \
	-r "awk '{ l[\$1] += \$2; f[\$1]++; } \
	 END { for (i in l) { printf(\"%10s %4d %8d\n\", i, f[i], l[i]); } }' | \
	    sort -rn -k3,3 | head -15"
