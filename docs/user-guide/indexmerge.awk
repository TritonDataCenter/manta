{
    for (i = 2; i <= NF; i++) {
        indx[$1] = indx[$1] " " $i
    }
}
END {
    for (word in indx) {
        print word, indx[word]
    }
}
