echo ~~/reports/access-logs/latest | \
    mjob create -w \
        -m "json -ga -d'\t' \
            res.headers.date \
            res.headers'[\"x-server-name\"]' \
            res.headers'[\"x-request-id\"]' \
            res.statusCode \
            res.headers'[\"x-response-time\"]' \
            req.method \
            req'[\"request-uri\"]'" \
	-s /manta/public/examples/assets/mkrequestdb.awk \
	-r "awk -F '\t' -f /assets/manta/public/examples/assets/mkrequestdb.awk"
