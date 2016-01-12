BEGIN {
	#
	# Start a transaction to disable auto-commit.  This improves
	# performance significantly.
	#
	print "BEGIN;"
	print
	print "CREATE TABLE AllRequests ("
	print "    Date          TIMESTAMP,"
	print "    ServerName    VARCHAR(37),"
	print "    RequestId     VARCHAR(37),"
	print "    StatusCode    INTEGER,"
	print "    ResponseTime  INTEGER,"
	print "    Method        VARCHAR(7),"
	print "    URI           VARCHAR(1023)"
	print ");\n";
}

{
	#
	# In general, you should consider whether these values need to be
	# treated specially on the way in or escaped on the way out.  In our
	# case, the caller uses tabs to separate values, which cannot appear in
	# any of these fields.  We escape backslashes and single quotes in the
	# URI, which would be interpreted by postgres.
	# 
	gsub(/\\/, "\\\\", $7);
	gsub(/'/, "\\'", $7);
	printf("INSERT INTO AllRequests VALUES " \
	    "('%s', '%s', '%s', %d, %d, '%s', E'%s');\n",
	    $1, $2, $3, $4, $5, $6, $7);
}

END {
	print "\nCOMMIT;"
}
