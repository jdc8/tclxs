[section {Miscellaneous}]

[list_begin definitions]

[call [cmd {xs version}]]

Return the Crossroads I/O version used by the Tcl wrapper.

[call [cmd {xs errno}]]

Return the last returned Crossroads I/O error code.

[call [cmd {xs strerror}] [arg errorNumber]]

Return the human readable string for a Crossroads I/O error code.

[call [cmd {xs max_block_time}] [arg blockTime]]

Set maximum blocking time for the Tcl event loop waiting for Crossroads I/O
events in micro seconds. Default is 1000 micro seconds.

[list_end]
