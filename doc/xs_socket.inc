[section {Sockets}]

[subsection {Socket PACKAGE COMMANDS}]

[list_begin definitions]

[call [cmd {xs socket}] [opt [arg socketName]] [arg contextName] [arg socketType]]

This command creates a new Crossroads I/O socket object and associated Tcl
object command whose name is [arg socketName] if specified or auto generated if
not specified within the specified context and of the specified type. The object
command will be created under the current namespace if the [arg objectName] is
not fully qualified, and in the specified namespace otherwise. The object
command name is returned by this command. The object command methods are
explained in section [sectref {Socket OBJECT METHODS}].

Valid values for [arg socketType] are:

[list_begin options]
[opt_def PAIR]
[opt_def PUB]
[opt_def PULL]
[opt_def PUSH]
[opt_def REP]
[opt_def REQ]
[opt_def RESPONDENT]
[opt_def SUB]
[opt_def SURVEYOR]
[opt_def XPUB]
[opt_def XREP]
[opt_def XREQ]
[opt_def XRESPONDENT]
[opt_def XSUB]
[opt_def XSURVEYOR]
[list_end]

[list_end]

[subsection {Socket OBJECT METHODS}]

[list_begin definitions]

[call [arg socketName] [method bind] [arg endPoint]]

Accept connections on a socket for specified endpoint. Returns an endpoint
identifier needed to later call the [method shutdown] method.

[call [arg socketName] [method cget] [arg optionName]]

Get socket option. See [cmd configure] method for list of supported options.

[call [arg socketName] [method close]]

See [cmd destroy] method.

[call [arg socketName] [method configure] [opt [arg optionName]] [opt [arg "optionValue optionName optionValue ..."]]]

Query or modify socket options.  If no option is specified, returns a list
describing all of the available options. If option is specified with no value,
then the command returns the value for the specified option. If one or more
option-value pairs are specified, then the command modifies the given socket
option(s) to have the given value(s); in this case the command returns an empty
string. Supported options with associated data type are:

[list_begin options]
[opt_def AFFINITY] unsigned 64 bit integer
[opt_def BACKLOG] integer
[opt_def EVENTS] list of event flags, known events are [term POLLIN], [term POLLOUT] and [term POLLERR]
[opt_def FD] integer, read-only
[opt_def HWM] integer, write only, set both [term RCVHWM] and [term SNDHWM]
[opt_def IDENTITY] binary
[opt_def IPV4ONLY] integer
[opt_def KEEPALIVE] integer
[opt_def LINGER] integer
[opt_def MAXMSGSIZE] unsigned 64 bit integer
[opt_def MULTICAST_HOPS] integer
[opt_def RATE] integer
[opt_def RCVBUF] integer
[opt_def RCVHWM] integer
[opt_def RCVMORE] integer, read-only
[opt_def RCVTIMEO] integer
[opt_def RECONNECT_IVL] integer
[opt_def RECONNECT_IVL_MAX] integer
[opt_def RECOVERY_IVL] integer
[opt_def SNDBUF] integer
[opt_def SNDHWM] integer
[opt_def SNDTIMEO] integer
[opt_def SUBSCRIBE] binary, write-only
[opt_def SURVEY_TIMEOUT] integer
[opt_def TYPE] integer, read-only
[opt_def UNSUBSCRIBE] binary. write-only
[list_end]

[call [arg socketName] [method connect] [arg endPoint]]

Connect to a socket on the specified endpoint. Returns an endpoint identifier
needed to later call the [method shutdown] method.

[call [arg socketName] [method destroy]]

Close the Crossroads I/O socket and delete the associated Tcl object command.

[call [arg socketName] [method dump]]

Read message from the socket and return it in human readable debug format.

[call [arg socketName] [method get] [arg optionName]]

Get socket option. See [cmd configure] method for list of supported options.

[call [arg socketName] [method readable] [opt [arg command]]]

If specified set, or if not specified get, the socket readable callback command.

[call [arg socketName] [method recv] [opt [arg flagsList]]]

Read a message part from the socket and return it as a string. Only the
[term DONTWAIT] flag is supported.

[call [arg socketName] [method recvmsg] [arg message] [opt [arg flagsList]]]

Read a message part from the socket and place it in the specified message
object. Only the [term DONTWAIT] flag is supported.

[call [arg socketName] [method send] [arg data] [opt [arg flagsList]]]

Send the specified data to the socket as message part. Supported flags are
[term DONTWAIT] and [term SNDMORE].

[call [arg socketName] [method sendmsg] [arg message] [opt [arg flagsList]]]

Send the message part in the specified message object to the socket. Supported
flags are [term DONTWAIT] and [term SNDMORE].

[call [arg socketName] [method sendmore] [arg data] [opt [arg flagsList]]]

Send the specified data to the socket as message part and indicate there are more
message parts to come. Supported flags are [term DONTWAIT] and [term SNDMORE].

[call [arg socketName] [method set] [arg optionName] [arg optionValue] [opt [arg optionSize]]]

Set socket option. See [cmd configure] method for list of supported options.

[call [arg socketName] [method shutdown] [arg endPointId]]

Shut down part of a socket. The endpoint identifier is the identifier returned
by the [method bind] or [method connect] methods.

[call [arg socketName] [method writable] [opt [arg command]]]

If specified set, or if not specified get, the socket writable callback command.

[list_end]
