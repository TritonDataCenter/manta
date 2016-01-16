#!/bin/bash

#
# indexone.sh: simple indexer for plaintext files
#
sed -E -e "s/[^A-Za-z']/ /g;" -e "s#([[:space:]])'+#\1#g" -e "s#^'+##g" "$1" | \
    tr '[:upper:]' '[:lower:]' | \
    awk -v OBJLABEL="$(basename ${1-stdin})" '{ \
             for (i = 1; i <= NF; i++) { \
                 if (length($i) < 4) \
                     continue; \
                 if ($i in indx) { \
                     indx[$i] = indx[$i] "," NR \
                 } else { \
                     indx[$i] = OBJLABEL ":" NR \
                 } \
             } \
         } \
         END { \
             for (word in indx) { \
                 print word, indx[word] \
             } \
         }'
