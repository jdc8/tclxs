[section {Multi-part message helper functions}]

Crossroads I/O sends multi-part messages (e.g. when using envelopes). These
helper functions can be used to make it easier to handle those. Data is
specified as a (binary) string. A multi-part message is specified a a list of
(binary) strings.

[list_begin definitions]

[call [cmd {xsmsg add}] [arg messageList] [arg data]]

Add a message part to a multi-part message. The updated multi-part message is
returned.

[call [cmd {xsmsg dump}] [arg messageList]]

Return the multi-part message in a human readable form.

[call [cmd {xsmsg pop}] [arg messageListName]]

Pop a message part from the beginning of the specified multi-part message. The
popped message part is returned and the specified multi-part message is modified.

[call [cmd {xsmsg push}] [arg messageList] [arg data]]

Push a message part to the beginning of a multi-part message. The modified
multi-part message is returned.

[call [cmd {xsmsg recv}] [arg socketName]]

Receive a multi-part message on the specified socket. The received message is
returned.

[call [cmd {xsmsg send}] [arg socketName] [arg messageList]]

Send a multi-part message to the specified socket.

[call [cmd {xsmsg unwrap}] [arg messageListName]]

Unwrap multi-part message. The unwrapped message part is returned. An empty
message-part following the unwrapped message part (e.g as part of an envelope)
is also removed.

[call [cmd {xsmsg wrap}] [arg messageList] [arg data]]

Wrap the multi-part message with the specified data. An empty message part is
inserted between the specified data and the spoecified multi-part message.

[list_end]
