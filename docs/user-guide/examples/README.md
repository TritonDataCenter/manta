This directory holds Manta compute job examples for the Manta User Guide.
They all hold: some prose (index.md.in) and a "job.sh" to run the job.
The job is run and `mjob share` used to generate an HTML page that is
added to the docs.

E.g., *currently* ./word-index ultimately results in
<https://apidocs.joyent.com/manta/example-word-index.html>. See
[RFD 23](https://github.com/joyent/rfd/tree/master/rfd/0023) for the Manta docs
pipeline.

To regenerate all the examples:

    # in the manta.git top dir
    make docs-regenerate-examples

and then git commit any changes.


# Debugging

To regenerate a single example doc:

    cd docs/user-guide/examples
    TRACE=1 ./generate-example.sh EXAMPLE-DIR

