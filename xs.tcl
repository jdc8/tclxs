package require critcl 3

namespace eval ::xs {
}

critcl::license {Jos Decoster} {LGPLv3 / BSD}
critcl::summary {A Tcl wrapper for the Crossroads I/O library}
critcl::description {
    xs is a Tcl binding for the Crossroads I/O library (http://www.crossroads.io/).
}
critcl::subject {Crossroads I/O} {xs}
critcl::subject {messaging} {inter process communication} RPC
critcl::subject {message queue} {queue} broadcast communication
critcl::subject {producer - consumer} {publish - subscribe}

critcl::meta origin https://github.com/jdc8/tclxs

critcl::userconfig define mode {choose mode of Crossroads I/O to build and link against.} {static dynamic}

if {[string match "win32*" [::critcl::targetplatform]]} {
    critcl::clibraries -llibxs -luuid -lws2_32 -lcomctl32 -lrpcrt4
    switch -exact -- [critcl::userconfig query mode] {
	static {
	    critcl::cflags /DDLL_EXPORT
	}
	dynamic {
	}
    }
} else {
    switch -exact -- [critcl::userconfig query mode] {
	static {
	    critcl::clibraries -l:libxs.a -lstdc++
	}
	dynamic {
	    critcl::clibraries -lxs
	}
    }

    critcl::clibraries -lpthread -lm

    if {[string match "macosx*" [::critcl::targetplatform]]} {
	critcl::clibraries -lgcc_eh
    } else {
	critcl::clibraries -lrt
    }
}

critcl::cflags -ansi -pedantic -Wall


# Get local build configuration
set cfgfnm [file dirname [info script]]/xs_config.tcl
if {[file exists $cfgfnm]} {
    set fd [open $cfgfnm]
    eval [read $fd]
    close $fd
}

critcl::tcl 8.5
critcl::tsources xs_helper.tcl


critcl::ccode {

#include "errno.h"
#include "string.h"
#include "stdio.h"
#include "xs/xs.h"
#ifndef _WIN32
#include "pthread.h"
#endif

#ifdef _MSC_VER
    typedef __int64          int64_t;
    typedef unsigned __int64 uint64_t;
#else
#include <stdint.h>
#endif

#ifndef XS_HWM
#define XS_HWM 1
#endif

    typedef struct {
	Tcl_Interp* ip;
	Tcl_HashTable* readableCommands;
	Tcl_HashTable* writableCommands;
	int block_time;
	int id;
    } XsClientData;

    typedef struct {
	void* context;
	Tcl_Obj* tcl_cmd;
	XsClientData* xsClientData;
    } XsContextClientData;

    typedef struct {
	void* context;
	void* socket;
	Tcl_Obj* tcl_cmd;
	XsClientData* xsClientData;
    } XsSocketClientData;

    typedef struct {
	void* message;
	Tcl_Obj* tcl_cmd;
	XsClientData* xsClientData;
    } XsMessageClientData;

    typedef struct {
	Tcl_Event event; /* Must be first */
	Tcl_Interp* ip;
	Tcl_Obj* cmd;
    } XsEvent;

    static int last_xs_errno = 0;

    static void xs_free_client_data(void* p) { ckfree(p); }

    static void xs_ckfree(void* p, void* h) { ckfree(p); }

    static void* known_command(Tcl_Interp* ip, Tcl_Obj* obj, const char* what) {
	Tcl_CmdInfo ci;
	if (!Tcl_GetCommandInfo(ip, Tcl_GetStringFromObj(obj, 0), &ci)) {
	    Tcl_Obj* err;
	    err = Tcl_NewObj();
	    Tcl_AppendToObj(err, what, -1);
	    Tcl_AppendToObj(err, " \"", -1);
	    Tcl_AppendObjToObj(err, obj);
	    Tcl_AppendToObj(err, "\" does not exists", -1);
	    Tcl_SetObjResult(ip, err);
	    return 0;
	}
	return ci.objClientData;
    }

    static void* known_context(Tcl_Interp* ip, Tcl_Obj* obj)
    {
	void* p = known_command(ip, obj, "context");
	if (p)
	    return ((XsContextClientData*)p)->context;
	return 0;
    }

    static void* known_socket(Tcl_Interp* ip, Tcl_Obj* obj)
    {
	void* p = known_command(ip, obj, "socket");
	if (p)
	    return ((XsSocketClientData*)p)->socket;
	return 0;
    }

    static void* known_message(Tcl_Interp* ip, Tcl_Obj* obj)
    {
	void* p = known_command(ip, obj, "message");
	if (p)
	    return ((XsMessageClientData*)p)->message;
	return 0;
    }

    static const char* conames[]      = { "IO_THREADS", "MAX_SOCKETS", "PLUGIN", NULL };
    static const int   conames_cget[] = { 0,            0,             0 };

    static int get_context_option(Tcl_Interp* ip, Tcl_Obj* obj, int* name)
    {
	enum ExObjCOptionNames { CON_IO_THREADS, CON_MAX_SOCKETS, CON_PLUGIN };
	int index = -1;
	if (Tcl_GetIndexFromObj(ip, obj, conames, "name", 0, &index) != TCL_OK)
	    return TCL_ERROR;
	switch((enum ExObjCOptionNames)index) {
	case CON_IO_THREADS: *name = XS_IO_THREADS; break;
	case CON_MAX_SOCKETS: *name = XS_MAX_SOCKETS; break;
	case CON_PLUGIN: *name = XS_PLUGIN; break;
	}
	return TCL_OK;
    }

    static const char* monames[]      = { "MORE", NULL };
    static const int   monames_cget[] = { 1 };

    static int get_message_option(Tcl_Interp* ip, Tcl_Obj* obj, int* name)
    {
	enum ExObjMOptionNames { MSG_MORE };
	int index = -1;
	if (Tcl_GetIndexFromObj(ip, obj, monames, "name", 0, &index) != TCL_OK)
	    return TCL_ERROR;
	switch((enum ExObjMOptionNames)index) {
	case MSG_MORE: *name = XS_MORE; break;
	}
	return TCL_OK;
    }

    static const char* sonames[]      = { "HWM", "SNDHWM", "RCVHWM", "AFFINITY", "IDENTITY", "SUBSCRIBE", "UNSUBSCRIBE",
					  "RATE", "RECOVERY_IVL", "SNDBUF", "RCVBUF", "RCVMORE", "FD", "EVENTS",
					  "TYPE", "LINGER", "RECONNECT_IVL", "BACKLOG", "RECONNECT_IVL_MAX",
					  "MAXMSGSIZE", "MULTICAST_HOPS", "RCVTIMEO", "SNDTIMEO", "IPV4ONLY",
					  "KEEPALIVE", "PATTERN_VERSION", "SURVEY_TIMEOUT", "SERVICE_ID", NULL };
    static const int   sonames_cget[] = { 0, 1, 1, 1, 1, 0, 0,
					  1, 1, 1, 1, 1, 1, 1,
					  1, 1, 1, 1, 1,
					  1, 1, 1, 1, 1,
					  1, 0, 1, 0};

    static int get_socket_option(Tcl_Interp* ip, Tcl_Obj* obj, int* name)
    {
	enum ExObjOptionNames { ON_HWM, ON_SNDHWM, ON_RCVHWM, ON_AFFINITY, ON_IDENTITY, ON_SUBSCRIBE, ON_UNSUBSCRIBE,
				ON_RATE, ON_RECOVERY_IVL, ON_SNDBUF, ON_RCVBUF, ON_RCVMORE, ON_FD, ON_EVENTS,
				ON_TYPE, ON_LINGER, ON_RECONNECT_IVL, ON_BACKLOG, ON_RECONNECT_IVL_MAX,
				ON_MAXMSGSIZE, ON_MULTICAST_HOPS, ON_RCVTIMEO, ON_SNDTIMEO, ON_IPV4ONLY,
				ON_KEEPALIVE, ON_PATTERN_VERSION, ON_SURVEY_TIMEOUT, ON_SERVICE_ID };
	int index = -1;
	if (Tcl_GetIndexFromObj(ip, obj, sonames, "name", 0, &index) != TCL_OK)
	    return TCL_ERROR;
	switch((enum ExObjOptionNames)index) {
	case ON_HWM: *name = XS_HWM; break;
	case ON_AFFINITY: *name = XS_AFFINITY; break;
	case ON_IDENTITY: *name = XS_IDENTITY; break;
	case ON_SUBSCRIBE: *name = XS_SUBSCRIBE; break;
	case ON_UNSUBSCRIBE: *name = XS_UNSUBSCRIBE; break;
	case ON_RATE: *name = XS_RATE; break;
	case ON_RECOVERY_IVL: *name = XS_RECOVERY_IVL; break;
	case ON_SNDBUF: *name = XS_SNDBUF; break;
	case ON_RCVBUF: *name = XS_RCVBUF; break;
	case ON_RCVMORE: *name = XS_RCVMORE; break;
	case ON_FD: *name = XS_FD; break;
	case ON_EVENTS: *name = XS_EVENTS; break;
	case ON_TYPE: *name = XS_TYPE; break;
	case ON_LINGER: *name = XS_LINGER; break;
	case ON_RECONNECT_IVL: *name = XS_RECONNECT_IVL; break;
	case ON_BACKLOG: *name = XS_BACKLOG; break;
	case ON_RECONNECT_IVL_MAX: *name = XS_RECONNECT_IVL_MAX; break;
	case ON_MAXMSGSIZE: *name = XS_MAXMSGSIZE; break;
	case ON_SNDHWM: *name = XS_SNDHWM; break;
	case ON_RCVHWM: *name = XS_RCVHWM; break;
	case ON_MULTICAST_HOPS: *name = XS_MULTICAST_HOPS; break;
	case ON_RCVTIMEO: *name = XS_RCVTIMEO; break;
	case ON_SNDTIMEO: *name = XS_SNDTIMEO; break;
	case ON_IPV4ONLY: *name = XS_IPV4ONLY; break;
	case ON_KEEPALIVE: *name = XS_KEEPALIVE; break;
	case ON_PATTERN_VERSION: *name = XS_PATTERN_VERSION; break;
	case ON_SURVEY_TIMEOUT: *name = XS_SURVEY_TIMEOUT; break;
	case ON_SERVICE_ID: *name = XS_SERVICE_ID; break;
	}
	return TCL_OK;
    }

    static int get_poll_flags(Tcl_Interp* ip, Tcl_Obj* fl, int* events)
    {
	int objc = 0;
	Tcl_Obj** objv = 0;
	int i = 0;
	if (Tcl_ListObjGetElements(ip, fl, &objc, &objv) != TCL_OK) {
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("event flags not specified as list", -1));
	    return TCL_ERROR;
	}
	for(i = 0; i < objc; i++) {
	    static const char* eflags[] = {"POLLIN", "POLLOUT", "POLLERR", NULL};
	    enum ExObjEventFlags {ZEF_POLLIN, ZEF_POLLOUT, ZEF_POLLERR};
	    int efindex = -1;
	    if (Tcl_GetIndexFromObj(ip, objv[i], eflags, "event_flag", 0, &efindex) != TCL_OK)
		return TCL_ERROR;
	    switch((enum ExObjEventFlags)efindex) {
	    case ZEF_POLLIN: *events = *events | XS_POLLIN; break;
	    case ZEF_POLLOUT: *events = *events | XS_POLLOUT; break;
	    case ZEF_POLLERR: *events = *events | XS_POLLERR; break;
	    }
	}
	return TCL_OK;
    }

    static Tcl_Obj* set_poll_flags(Tcl_Interp* ip, int revents)
    {
	Tcl_Obj* fresult = Tcl_NewListObj(0, NULL);
	if (revents & XS_POLLIN) {
	    Tcl_ListObjAppendElement(ip, fresult, Tcl_NewStringObj("POLLIN", -1));
	}
	if (revents & XS_POLLOUT) {
	    Tcl_ListObjAppendElement(ip, fresult, Tcl_NewStringObj("POLLOUT", -1));
	}
	if (revents & XS_POLLERR) {
	    Tcl_ListObjAppendElement(ip, fresult, Tcl_NewStringObj("POLLERR", -1));
	}
	return fresult;
    }

    static int get_recv_send_flag(Tcl_Interp* ip, Tcl_Obj* fl, int* flags)
    {
	int objc = 0;
	Tcl_Obj** objv = 0;
	int i = 0;
	if (Tcl_ListObjGetElements(ip, fl, &objc, &objv) != TCL_OK) {
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("flags not specified as list", -1));
	    return TCL_ERROR;
	}
	for(i = 0; i < objc; i++) {
	    static const char* rsflags[] = {"DONTWAIT", "NOBLOCK", "SNDMORE", NULL};
	    enum ExObjRSFlags {RSF_DONTWAIT, RSF_NOBLOCK, RSF_SNDMORE};
	    int index = -1;
	    if (Tcl_GetIndexFromObj(ip, objv[i], rsflags, "flag", 0, &index) != TCL_OK)
                return TCL_ERROR;
	    switch((enum ExObjRSFlags)index) {
	    case RSF_DONTWAIT: *flags = *flags | XS_DONTWAIT; break;
	    case RSF_NOBLOCK: *flags = *flags | XS_DONTWAIT; break;
	    case RSF_SNDMORE: *flags = *flags | XS_SNDMORE; break;
	    }
        }
	return TCL_OK;
    }

    static Tcl_Obj* xs_s_dump(Tcl_Interp* ip, const char* data, int size)
    {
	int is_text = 1;
	int char_nbr;
	char buffer[TCL_INTEGER_SPACE+4];
	Tcl_Obj *result;
	for (char_nbr = 0; char_nbr < size && is_text; char_nbr++)
	    if ((unsigned char) data [char_nbr] < 32
		|| (unsigned char) data [char_nbr] > 127)
		is_text = 0;

	sprintf(buffer, "[%03d] ", size);
	result = Tcl_NewStringObj(buffer, -1);
	if (is_text) {
	    Tcl_AppendToObj(result, data, size);
	} else {
	    for (char_nbr = 0; char_nbr < size; char_nbr++) {
		sprintf(buffer, "%02X", data[char_nbr]);
		Tcl_AppendToObj(result, buffer, 2);
	    }
	}
	return result;
    }

    static int cget_context_option_as_tcl_obj(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj, Tcl_Obj** result)
    {
	int name = 0;
	void* xsp = ((XsContextClientData*)cd)->context;
	XsClientData* xsClientData = ((XsContextClientData*)cd)->xsClientData;
	*result = 0;
	if (get_context_option(ip, optObj, &name) != TCL_OK)
	    return TCL_ERROR;
	/*
	int val = xs_getctxopt(xsp, name);
	last_xs_errno = xs_errno();
	if (val < 0) {
	    *result = Tcl_NewStringObj(xs_strerror(last_xs_errno), -1);
	    return TCL_ERROR;
	}
	*result = Tcl_NewIntObj(val);
	return TCL_OK;
	*/
	*result = Tcl_NewStringObj("Can not get context options", -1);
	return TCL_ERROR;
    }

    static int cget_context_option(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj)
    {
	Tcl_Obj* result = 0;
	int rt = cget_context_option_as_tcl_obj(cd, ip, optObj, &result);
	if (result)
	    Tcl_SetObjResult(ip, result);
	return rt;
    }

    static int cset_context_option_as_tcl_obj(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj, Tcl_Obj* valObj)
    {
	int name = 0;
	void* xsp = ((XsContextClientData*)cd)->context;
	XsClientData* xsClientData = ((XsContextClientData*)cd)->xsClientData;
	int rt = 0;
	int val = -1;
	if (get_context_option(ip, optObj, &name) != TCL_OK)
	    return TCL_ERROR;
	if (Tcl_GetIntFromObj(ip, valObj, &val) != TCL_OK) {
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong option value, expected integer", -1));
	    return TCL_ERROR;
	}
	rt = xs_setctxopt(xsp, name, &val, sizeof val);
	last_xs_errno = xs_errno();
	if (rt != 0) {
	    Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
	    return TCL_ERROR;
	}
	return TCL_OK;
    }

    int xs_context_objcmd(ClientData cd, Tcl_Interp* ip, int objc, Tcl_Obj* const objv[]) {
	static const char* methods[] = {"cget", "configure", "destroy", "get",
					"set", "term", NULL};
	enum ExObjContextMethods {EXCTXOBJ_CGET, EXCTXOBJ_CONFIGURE, EXCTXOBJ_DESTROY, EXCTXOBJ_GET,
				  EXCTXOBJ_SET, EXCTXOBJ_TERM};
	int index = -1;
	void* xsp = ((XsContextClientData*)cd)->context;
	int rt = 0;
	if (objc < 2) {
	    Tcl_WrongNumArgs(ip, 1, objv, "method ?argument ...?");
	    return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(ip, objv[1], methods, "method", 0, &index) != TCL_OK)
            return TCL_ERROR;
	switch((enum ExObjContextMethods)index) {
	case EXCTXOBJ_CONFIGURE:
	{
	    if (objc == 2) {
		/* Return all options */
		int cnp = 0;
		Tcl_Obj* cresult = Tcl_NewListObj(0, NULL);
		while(conames[cnp]) {
		    if (conames_cget[cnp]) {
			Tcl_Obj* result = 0;
			Tcl_Obj* cname = Tcl_NewStringObj(conames[cnp], -1);
			Tcl_Obj* oresult = 0;
			int rt = cget_context_option_as_tcl_obj(cd, ip, cname, &result);
			if (rt != TCL_OK) {
			    if (result)
				Tcl_SetObjResult(ip, result);
			    return rt;
			}
			oresult = Tcl_NewListObj(0, NULL);
			Tcl_ListObjAppendElement(ip, oresult, cname);
			Tcl_ListObjAppendElement(ip, oresult, result);
			Tcl_ListObjAppendElement(ip, cresult, oresult);
		    }
		    cnp++;
		}
		Tcl_SetObjResult(ip, cresult);
	    }
	    else if (objc == 3) {
		/* Get specified option */
		Tcl_Obj* result = 0;
		Tcl_Obj* oresult = 0;
		int rt = cget_context_option_as_tcl_obj(cd, ip, objv[2], &result);
		if (rt != TCL_OK) {
		    if (result)
			Tcl_SetObjResult(ip, result);
		    return rt;
		}
		oresult = Tcl_NewListObj(0, NULL);
		Tcl_ListObjAppendElement(ip, oresult, objv[2]);
		Tcl_ListObjAppendElement(ip, oresult, result);
		Tcl_SetObjResult(ip, oresult);
	    }
	    else if ((objc % 2) == 0) {
		/* Set specified options */
		int i;
		for(i = 2; i < objc; i += 2)
		    if (cset_context_option_as_tcl_obj(cd, ip, objv[i], objv[i+1]) != TCL_OK)
			return TCL_ERROR;
	    }
	    else {
		Tcl_WrongNumArgs(ip, 2, objv, "?name? ?value option value ...?");
		return TCL_ERROR;
	    }
	    break;
	}
	case EXCTXOBJ_DESTROY:
	case EXCTXOBJ_TERM:
	{
	    Tcl_HashEntry* hashEntry = 0;
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    rt = xs_term(xsp);
	    last_xs_errno = xs_errno();
	    if (rt == 0) {
		Tcl_DecrRefCount(((XsContextClientData*)cd)->tcl_cmd);
		Tcl_DeleteCommand(ip, Tcl_GetStringFromObj(objv[0], 0));
	    }
	    else {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	case EXCTXOBJ_CGET:
	case EXCTXOBJ_GET:
	{
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "name");
		return TCL_ERROR;
	    }
	    return cget_context_option(cd, ip, objv[2]);
	}
	case EXCTXOBJ_SET:
	{
	    if (objc != 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "name value");
		return TCL_ERROR;
	    }
	    return cset_context_option_as_tcl_obj(cd, ip, objv[2], objv[3]);
	}
        }
 	return TCL_OK;
    }

    static int cget_socket_option_as_tcl_obj(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj, Tcl_Obj** result)
    {
	int name = 0;
	void* sockp = ((XsSocketClientData*)cd)->socket;
	*result = 0;
	if (get_socket_option(ip, optObj, &name) != TCL_OK)
	    return TCL_ERROR;
	switch(name) {
	    /* int options */
	case XS_TYPE:
	case XS_RCVMORE:
	case XS_SNDHWM:
	case XS_RCVHWM:
	case XS_RATE:
	case XS_RECONNECT_IVL:
	case XS_SNDBUF:
	case XS_RCVBUF:
	case XS_LINGER:
	case XS_RECOVERY_IVL:
	case XS_RECONNECT_IVL_MAX:
	case XS_BACKLOG:
	case XS_MULTICAST_HOPS:
	case XS_SNDTIMEO:
	case XS_RCVTIMEO:
	case XS_IPV4ONLY:
	case XS_FD:
	case XS_KEEPALIVE:
	case XS_SURVEY_TIMEOUT:
	{
	    int val = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getsockopt(sockp, name, &val, &len);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    *result = Tcl_NewIntObj(val);
	    break;
	}
	case XS_EVENTS:
	{
	    int val = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getsockopt(sockp, name, &val, &len);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    *result = set_poll_flags(ip, val);
	    break;
	}
	/* uint64_t options */
	case XS_AFFINITY:
	case XS_MAXMSGSIZE:
	{
	    uint64_t val = 0;
	    size_t len = sizeof(uint64_t);
	    int rt = xs_getsockopt(sockp, name, &val, &len);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    *result = Tcl_NewWideIntObj(val);
	    break;
	}
	/* binary options */
	case XS_IDENTITY:
	{
	    const char val[256];
	    size_t len = 256;
	    int rt = xs_getsockopt(sockp, name, (void*)val, &len);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    *result = Tcl_NewStringObj(val, len);
	    break;
	}
	default:
	{
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("unsupported option", -1));
	    return TCL_ERROR;
	}
	}
	return TCL_OK;
    }

    static int cget_socket_option(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj)
    {
	Tcl_Obj* result = 0;
	int rt = cget_socket_option_as_tcl_obj(cd, ip, optObj, &result);
	if (result)
	    Tcl_SetObjResult(ip, result);
	return rt;
    }

    static int cset_socket_option_as_tcl_obj(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj, Tcl_Obj* valObj, Tcl_Obj* sizeObj)
    {
	void* sockp = ((XsSocketClientData*)cd)->socket;
	int name = -1;
	if (get_socket_option(ip, optObj, &name) != TCL_OK)
	    return TCL_ERROR;
	switch(name) {
	/* int options */
	case XS_HWM:
	{
	    int val = 0;
	    int rt = 0;
	    if (Tcl_GetIntFromObj(ip, valObj, &val) != TCL_OK) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong HWM argument, expected integer", -1));
		return TCL_ERROR;
	    }
	    rt = xs_setsockopt(sockp, XS_SNDHWM, &val, sizeof val);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    rt = xs_setsockopt(sockp, XS_RCVHWM, &val, sizeof val);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	case XS_SNDHWM:
	case XS_RCVHWM:
	case XS_RATE:
	case XS_RECOVERY_IVL:
	case XS_SNDBUF:
	case XS_RCVBUF:
	case XS_LINGER:
	case XS_RECONNECT_IVL:
	case XS_RECONNECT_IVL_MAX:
	case XS_BACKLOG:
	case XS_MULTICAST_HOPS:
	case XS_RCVTIMEO:
	case XS_SNDTIMEO:
	case XS_IPV4ONLY:
	case XS_KEEPALIVE:
	case XS_SURVEY_TIMEOUT:
	{
	    int val = 0;
	    int rt = 0;
	    if (Tcl_GetIntFromObj(ip, valObj, &val) != TCL_OK) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong HWM argument, expected integer", -1));
		return TCL_ERROR;
	    }
	    rt = xs_setsockopt(sockp, name, &val, sizeof val);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	/* uint64_t options */
	case XS_AFFINITY:
	case XS_MAXMSGSIZE:
	{
	    int64_t val = 0;
	    uint64_t uval = 0;
	    int rt = 0;
	    if (Tcl_GetWideIntFromObj(ip, valObj, &val) != TCL_OK) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong HWM argument, expected integer", -1));
		return TCL_ERROR;
	    }
	    uval = val;
	    rt = xs_setsockopt(sockp, name, &uval, sizeof uval);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	/* binary options */
	case XS_IDENTITY:
	case XS_SUBSCRIBE:
	case XS_UNSUBSCRIBE:
	{
	    int len = 0;
	    const char* val = 0;
	    int rt = 0;
	    int size = -1;
	    val = Tcl_GetStringFromObj(valObj, &len);
	    if (sizeObj) {
		if (Tcl_GetIntFromObj(ip, sizeObj, &size) != TCL_OK) {
		    Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong size argument, expected integer", -1));
		    return TCL_ERROR;
		}
	    }
	    else
		size = len;
	    rt = xs_setsockopt(sockp, name, val, size);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	default:
	{
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("unsupported option", -1));
	    return TCL_ERROR;
	}
	}
	return TCL_OK;
    }

    int xs_socket_objcmd(ClientData cd, Tcl_Interp* ip, int objc, Tcl_Obj* const objv[]) {
	static const char* methods[] = {"bind", "cget", "close", "configure", "connect",
					"destroy", "get", "getsockopt",
					"readable", "recvmsg", "recv_msg", "sendmsg", "send_msg",
					"dump", "recv", "send", "sendmore", "set",
					"setsockopt", "writable", "shutdown", NULL};
	enum ExObjSocketMethods {EXSOCKOBJ_BIND, EXSOCKOBJ_CGET, EXSOCKOBJ_CLOSE, EXSOCKOBJ_CONFIGURE, EXSOCKOBJ_CONNECT,
				 EXSOCKOBJ_DESTROY, EXSOCKOBJ_GET, EXSOCKOBJ_GETSOCKETOPT,
				 EXSOCKOBJ_READABLE, EXSOCKOBJ_RECVMSG, EXSOCKOBJ_RECV_MSG, EXSOCKOBJ_SENDMSG, EXSOCKOBJ_SEND_MSG,
				 EXSOCKOBJ_DUMP, EXSOCKOBJ_RECV, EXSOCKOBJ_SEND, EXSOCKOBJ_SENDMORE, EXSOCKOBJ_SET,
				 EXSOCKOBJ_SETSOCKETOPT, EXSOCKOBJ_WRITABLE, EXSOCKOBJ_SHUTDOWN};
	int index = -1;
	void* sockp = ((XsSocketClientData*)cd)->socket;
	XsClientData* xsClientData = (((XsSocketClientData*)cd)->xsClientData);
	if (objc < 2) {
	    Tcl_WrongNumArgs(ip, 1, objv, "method ?argument ...?");
	    return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(ip, objv[1], methods, "method", 0, &index) != TCL_OK)
            return TCL_ERROR;
	switch((enum ExObjSocketMethods)index) {
        case EXSOCKOBJ_BIND:
        {
	    int rt = 0;
	    const char* endpoint = 0;
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "endpoint");
		return TCL_ERROR;
	    }
	    endpoint = Tcl_GetStringFromObj(objv[2], 0);
	    rt = xs_bind(sockp, endpoint);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXSOCKOBJ_CLOSE:
	case EXSOCKOBJ_DESTROY:
	{
	    Tcl_HashEntry* hashEntry = 0;
	    int rt = 0;
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    rt = xs_close(sockp);
	    last_xs_errno = xs_errno();
	    if (rt == 0) {
		Tcl_DecrRefCount(((XsSocketClientData*)cd)->tcl_cmd);
		Tcl_DeleteCommand(ip, Tcl_GetStringFromObj(objv[0], 0));
	    }
	    else {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    hashEntry = Tcl_FindHashEntry(xsClientData->readableCommands, sockp);
	    if (hashEntry)
		Tcl_DeleteHashEntry(hashEntry);
	    hashEntry = Tcl_FindHashEntry(xsClientData->writableCommands, sockp);
	    if (hashEntry)
		Tcl_DeleteHashEntry(hashEntry);
	    break;
	}
	case EXSOCKOBJ_CONFIGURE:
	{
	    if (objc == 2) {
		/* Return all options */
		int cnp = 0;
		Tcl_Obj* cresult = Tcl_NewListObj(0, NULL);
		while(sonames[cnp]) {
		    if (sonames_cget[cnp]) {
			Tcl_Obj* result = 0;
			Tcl_Obj* oresult = 0;
			Tcl_Obj* cname = Tcl_NewStringObj(sonames[cnp], -1);
			int rt = cget_socket_option_as_tcl_obj(cd, ip, cname, &result);
			if (rt != TCL_OK) {
			    if (result)
				Tcl_SetObjResult(ip, result);
			    return rt;
			}
			oresult = Tcl_NewListObj(0, NULL);
			Tcl_ListObjAppendElement(ip, oresult, cname);
			Tcl_ListObjAppendElement(ip, oresult, result);
			Tcl_ListObjAppendElement(ip, cresult, oresult);
		    }
		    cnp++;
		}
		Tcl_SetObjResult(ip, cresult);
	    }
	    else if (objc == 3) {
		/* Get specified option */
		Tcl_Obj* result = 0;
		Tcl_Obj* oresult = 0;
		int rt = cget_socket_option_as_tcl_obj(cd, ip, objv[2], &result);
		if (rt != TCL_OK) {
		    if (result)
			Tcl_SetObjResult(ip, result);
		    return rt;
		}
		oresult = Tcl_NewListObj(0, NULL);
		Tcl_ListObjAppendElement(ip, oresult, objv[2]);
		Tcl_ListObjAppendElement(ip, oresult, result);
		Tcl_SetObjResult(ip, oresult);
	    }
	    else if ((objc % 2) == 0) {
		/* Set specified options */
		int i;
		for(i = 2; i < objc; i += 2)
		    if (cset_socket_option_as_tcl_obj(cd, ip, objv[i], objv[i+1], 0) != TCL_OK)
			return TCL_ERROR;
	    }
	    else {
		Tcl_WrongNumArgs(ip, 2, objv, "?name? ?value option value ...?");
		return TCL_ERROR;
	    }
	    break;
	}
        case EXSOCKOBJ_CONNECT:
        {
	    int rt = 0;
	    const char* endpoint = 0;
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "endpoint");
		return TCL_ERROR;
	    }
	    endpoint = Tcl_GetStringFromObj(objv[2], 0);
	    rt = xs_connect(sockp, endpoint);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXSOCKOBJ_CGET:
	case EXSOCKOBJ_GET:
	case EXSOCKOBJ_GETSOCKETOPT:
	{
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "name");
		return TCL_ERROR;
	    }
	    return cget_socket_option(cd, ip, objv[2]);
	}
	case EXSOCKOBJ_READABLE:
	{
	    int len = 0;
	    XsClientData* xsClientData = (((XsSocketClientData*)cd)->xsClientData);
	    Tcl_HashEntry* currCommand = 0;
	    Tcl_Time waitTime = { 0, 0 };
	    if (objc < 2 || objc > 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "?command?");
		return TCL_ERROR;
	    }
	    if (objc == 2) {
		currCommand = Tcl_FindHashEntry(xsClientData->readableCommands, sockp);
		if (currCommand) {
		    Tcl_Obj* old_command = (Tcl_Obj*)Tcl_GetHashValue(currCommand);
		    Tcl_SetObjResult(ip, old_command);
		}
	    }
	    else {
		/* If [llength $command] == 0 => delete readable event if present */
		if (Tcl_ListObjLength(ip, objv[2], &len) != TCL_OK) {
		    Tcl_SetObjResult(ip, Tcl_NewStringObj("command not passed as a list", -1));
		    return TCL_ERROR;
		}
		/* If socket already present, replace the command */
		currCommand = Tcl_FindHashEntry(xsClientData->readableCommands, sockp);
		if (currCommand) {
		    Tcl_Obj* old_command = (Tcl_Obj*)Tcl_GetHashValue(currCommand);
		    Tcl_DecrRefCount(old_command);
		    if (len) {
			/* Replace */
			Tcl_IncrRefCount(objv[2]);
			Tcl_SetHashValue(currCommand, objv[2]);
		    }
		    else {
			/* Remove */
			Tcl_DeleteHashEntry(currCommand);
		    }
		}
		else {
		    if (len) {
			/* Add */
			int newPtr = 0;
			Tcl_IncrRefCount(objv[2]);
			currCommand = Tcl_CreateHashEntry(xsClientData->readableCommands, sockp, &newPtr);
			Tcl_SetHashValue(currCommand, objv[2]);
		    }
		}
		Tcl_WaitForEvent(&waitTime);
	    }
	    break;
	}
	case EXSOCKOBJ_RECVMSG:
	case EXSOCKOBJ_RECV_MSG:
	{
	    void* msgp = 0;
	    int flags = 0;
	    int rt = 0;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "message ?flags?");
		return TCL_ERROR;
	    }
	    msgp = known_message(ip, objv[2]);
	    if (msgp == NULL) {
		return TCL_ERROR;
	    }
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    rt = xs_recvmsg(sockp, msgp, flags);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXSOCKOBJ_SENDMSG:
	case EXSOCKOBJ_SEND_MSG:
	{
	    void* msgp = 0;
	    int flags = 0;
	    int rt = 0;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "message ?flags?");
		return TCL_ERROR;
	    }
	    msgp = known_message(ip, objv[2]);
	    if (msgp == NULL) {
		return TCL_ERROR;
	    }
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    rt = xs_sendmsg(sockp, msgp, flags);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXSOCKOBJ_DUMP:
	{
	    Tcl_Obj* result = 0;
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    result = Tcl_NewListObj(0, NULL);
	    while (1) {
		int more; /* Multipart detection */
		size_t more_size = sizeof (more);
		xs_msg_t message;

		/* Process all parts of the message */
		xs_msg_init (&message);
		xs_recvmsg(sockp, &message, 0);

		/* Dump the message as text or binary */
		Tcl_ListObjAppendElement(ip, result, xs_s_dump(ip, xs_msg_data(&message), xs_msg_size(&message)));

		xs_getsockopt (sockp, XS_RCVMORE, &more, &more_size);
		xs_msg_close (&message);
		if (!more)
		    break; /* Last message part */
	    }
	    Tcl_SetObjResult(ip, result);
	    break;
	}
	case EXSOCKOBJ_RECV:
	{
	    xs_msg_t msg;
	    int rt = 0;
	    int flags = 0;
	    if (objc < 2 || objc > 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "?flags?");
		return TCL_ERROR;
	    }
	    if (objc > 2 && get_recv_send_flag(ip, objv[2], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    rt = xs_msg_init(&msg);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    rt = xs_recvmsg(sockp, &msg, flags);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		xs_msg_close(&msg);
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_msg_data(&msg), xs_msg_size(&msg)));
	    xs_msg_close(&msg);
	    break;
	}
	case EXSOCKOBJ_SEND:
	{
	    int size = 0;
	    int rt = 0;
	    char* data = 0;
	    void* buffer = 0;
	    xs_msg_t msg;
	    int flags = 0;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "data ?flags?");
		return TCL_ERROR;
	    }
	    data = Tcl_GetStringFromObj(objv[2], &size);
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    buffer = ckalloc(size);
	    memcpy(buffer, data, size);
	    rt = xs_msg_init_data(&msg, buffer, size, xs_ckfree, NULL);
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    rt = xs_sendmsg(sockp, &msg, flags);
	    last_xs_errno = xs_errno();
	    xs_msg_close(&msg);
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	case EXSOCKOBJ_SENDMORE:
	{
	    int size = 0;
	    int rt = 0;
	    char* data = 0;
	    void* buffer = 0;
	    xs_msg_t msg;
	    int flags = XS_SNDMORE;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "data ?flags?");
		return TCL_ERROR;
	    }
	    data = Tcl_GetStringFromObj(objv[2], &size);
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    buffer = ckalloc(size);
	    memcpy(buffer, data, size);
	    rt = xs_msg_init_data(&msg, buffer, size, xs_ckfree, NULL);
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    rt = xs_sendmsg(sockp, &msg, XS_SNDMORE);
	    last_xs_errno = xs_errno();
	    xs_msg_close(&msg);
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	case EXSOCKOBJ_SET:
	case EXSOCKOBJ_SETSOCKETOPT:
	{
	    if (objc < 4 || objc > 5) {
		Tcl_WrongNumArgs(ip, 2, objv, "name value ?size?");
		return TCL_ERROR;
	    }
	    return cset_socket_option_as_tcl_obj(cd, ip, objv[2], objv[3], objc==5?objv[4]:0);
	    break;
	}
	case EXSOCKOBJ_WRITABLE:
	{
	    int len = 0;
	    XsClientData* xsClientData = (((XsSocketClientData*)cd)->xsClientData);
	    Tcl_HashEntry* currCommand = 0;
	    Tcl_Time waitTime = { 0, 0 };
	    if (objc < 2 || objc > 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "?command?");
		return TCL_ERROR;
	    }
	    if (objc == 2) {
		currCommand = Tcl_FindHashEntry(xsClientData->writableCommands, sockp);
		if (currCommand) {
		    Tcl_Obj* old_command = (Tcl_Obj*)Tcl_GetHashValue(currCommand);
		    Tcl_SetObjResult(ip, old_command);
		}
	    }
	    else {
		/* If [llength $command] == 0 => delete writable event if present */
		if (Tcl_ListObjLength(ip, objv[2], &len) != TCL_OK) {
		    Tcl_SetObjResult(ip, Tcl_NewStringObj("command not passed as a list", -1));
		    return TCL_ERROR;
		}
		/* If socket already present, replace the command */
		currCommand = Tcl_FindHashEntry(xsClientData->writableCommands, sockp);
		if (currCommand) {
		    Tcl_Obj* old_command = (Tcl_Obj*)Tcl_GetHashValue(currCommand);
		    Tcl_DecrRefCount(old_command);
		    if (len) {
			/* Replace */
			Tcl_IncrRefCount(objv[2]);
			Tcl_SetHashValue(currCommand, objv[2]);
		    }
		    else {
			/* Remove */
			Tcl_DeleteHashEntry(currCommand);
		    }
		}
		else {
		    if (len) {
			/* Add */
			int newPtr = 0;
			Tcl_IncrRefCount(objv[2]);
			currCommand = Tcl_CreateHashEntry(xsClientData->writableCommands, sockp, &newPtr);
			Tcl_SetHashValue(currCommand, objv[2]);
		    }
		}
		Tcl_WaitForEvent(&waitTime);
	    }
	    break;
	}
	case EXSOCKOBJ_SHUTDOWN:
	{
	    int rt = 0;
	    int endpoint = -1;
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "endpoint_id");
		return TCL_ERROR;
	    }
	    if (Tcl_GetIntFromObj(ip, objv[2], &endpoint) != TCL_OK) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong endpoint_id value, expected integer", -1));
		return TCL_ERROR;
	    }
	    rt = xs_shutdown(sockp, endpoint);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
        }
 	return TCL_OK;
    }

    static int cget_message_option_as_tcl_obj(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj, Tcl_Obj** result)
    {
	void* msgp = ((XsMessageClientData*)cd)->message;
	int name = 0;
	*result = 0;
	if (get_message_option(ip, optObj, &name) != TCL_OK)
		return TCL_ERROR;
	switch(name) {
	case XS_MORE:
	{
	    int val = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getmsgopt(msgp, name, &val, &len);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		*result = Tcl_NewStringObj(xs_strerror(last_xs_errno), -1);
		return TCL_ERROR;
	    }
	    *result = Tcl_NewIntObj(val);
	    break;
	}
	default:
	{
	    *result = Tcl_NewStringObj("unsupported option", -1);
	    return TCL_ERROR;
	}
	}
	return TCL_OK;
    }

    static int cget_message_option(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj)
    {
	Tcl_Obj* result = 0;
	int rt = cget_message_option_as_tcl_obj(cd, ip, optObj, &result);
	if (result)
	    Tcl_SetObjResult(ip, result);
	return rt;
    }

    static int cset_message_option_as_tcl_obj(ClientData cd, Tcl_Interp* ip, Tcl_Obj* optObj, Tcl_Obj* valObj)
    {
	int name = 0;
	int val = 0;
	void* msgp = ((XsMessageClientData*)cd)->message;
	if (get_message_option(ip, optObj, &name) != TCL_OK)
	    return TCL_ERROR;
	switch(name) {
	default:
	{
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("unsupported option", -1));
	    return TCL_ERROR;
	}
	}
	return TCL_OK;
    }

    int xs_message_objcmd(ClientData cd, Tcl_Interp* ip, int objc, Tcl_Obj* const objv[]) {
	static const char* methods[] = {"cget", "close", "configure", "copy", "data",
					"destroy", "move", "size", "dump", "get",
					"getmsgopt", "set", "setmsgopt", "send", "sendmore", "recv", NULL};
	enum ExObjMessageMethods {EXMSGOBJ_CGET, EXMSGOBJ_CLOSE, EXMSGOBJ_CONFIGURE, EXMSGOBJ_COPY, EXMSGOBJ_DATA,
				  EXMSGOBJ_DESTROY, EXMSGOBJ_MOVE, EXMSGOBJ_SIZE, EXMSGOBJ_SDUMP, EXMSGOBJ_GET,
				  EXMSGOBJ_GETMSGOPT, EXMSGOBJ_SET, EXMSGOBJ_SETMSGOPT, EXMSGOBJ_SEND, EXMSGOBJ_SENDMORE,
				  EXMSGOBJ_RECV};
	int index = -1;
	void* msgp = 0;
	if (objc < 2) {
	    Tcl_WrongNumArgs(ip, 1, objv, "method ?argument ...?");
	    return TCL_ERROR;
	}
	if (Tcl_GetIndexFromObj(ip, objv[1], methods, "method", 0, &index) != TCL_OK)
            return TCL_ERROR;
	msgp = ((XsMessageClientData*)cd)->message;
	switch((enum ExObjMessageMethods)index) {
	case EXMSGOBJ_CLOSE:
	case EXMSGOBJ_DESTROY:
	{
	    int rt = 0;
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    rt = xs_msg_close(msgp);
	    last_xs_errno = xs_errno();
	    if (rt == 0) {
		Tcl_DecrRefCount(((XsMessageClientData*)cd)->tcl_cmd);
		Tcl_DeleteCommand(ip, Tcl_GetStringFromObj(objv[0], 0));
	    }
	    else {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    break;
	}
	case EXMSGOBJ_CONFIGURE:
	{
	    if (objc == 2) {
		/* Return all options */
		int cnp = 0;
		Tcl_Obj* cresult = Tcl_NewListObj(0, NULL);
		while(monames[cnp]) {
		    if (monames_cget[cnp]) {
			Tcl_Obj* result = 0;
			Tcl_Obj* oresult = 0;
			Tcl_Obj* cname = Tcl_NewStringObj(monames[cnp], -1);
			int rt = cget_message_option_as_tcl_obj(cd, ip, cname, &result);
			if (rt != TCL_OK) {
			    if (result)
				Tcl_SetObjResult(ip, result);
			    return rt;
			}
			oresult = Tcl_NewListObj(0, NULL);
			Tcl_ListObjAppendElement(ip, oresult, cname);
			Tcl_ListObjAppendElement(ip, oresult, result);
			Tcl_ListObjAppendElement(ip, cresult, oresult);
		    }
		    cnp++;
		}
		Tcl_SetObjResult(ip, cresult);
	    }
	    else if (objc == 3) {
		/* Get specified option */
		Tcl_Obj* result = 0;
		Tcl_Obj* oresult = 0;
		int rt = cget_message_option_as_tcl_obj(cd, ip, objv[2], &result);
		if (rt != TCL_OK) {
		    if (result)
			Tcl_SetObjResult(ip, result);
		    return rt;
		}
		oresult = Tcl_NewListObj(0, NULL);
		Tcl_ListObjAppendElement(ip, oresult, objv[2]);
		Tcl_ListObjAppendElement(ip, oresult, result);
		Tcl_SetObjResult(ip, oresult);
	    }
	    else if ((objc % 2) == 0) {
		/* Set specified options */
		int i;
		for(i = 2; i < objc; i += 2)
		    if (cset_message_option_as_tcl_obj(cd, ip, objv[i], objv[i+1]) != TCL_OK)
			return TCL_ERROR;
	    }
	    else {
		Tcl_WrongNumArgs(ip, 2, objv, "?name? ?value option value ...?");
		return TCL_ERROR;
	    }
	    break;
	}
        case EXMSGOBJ_COPY:
        {
	    void* dmsgp = 0;
	    int rt = 0;
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "dest_message");
		return TCL_ERROR;
	    }
	    dmsgp = known_message(ip, objv[2]);
	    if (!dmsgp) {
	        return TCL_ERROR;
	    }
	    rt = xs_msg_copy(dmsgp, msgp);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
   	    break;
	}
        case EXMSGOBJ_DATA:
        {
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_msg_data(msgp), xs_msg_size(msgp)));
   	    break;
	}
	case EXMSGOBJ_CGET:
	case EXMSGOBJ_GET:
	case EXMSGOBJ_GETMSGOPT:
	{
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "name");
		return TCL_ERROR;
	    }
	    return cget_message_option(cd, ip, objv[2]);
	}
        case EXMSGOBJ_MOVE:
        {
	    void* dmsgp = 0;
	    int rt = 0;
	    if (objc != 3) {
		Tcl_WrongNumArgs(ip, 2, objv, "dest_message");
		return TCL_ERROR;
	    }
	    dmsgp = known_message(ip, objv[2]);
	    if (!dmsgp) {
	        return TCL_ERROR;
	    }
	    rt = xs_msg_move(dmsgp, msgp);
	    last_xs_errno = xs_errno();
	    if (rt != 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
   	    break;
	}
	case EXMSGOBJ_RECV:
	{
	    void* sockp = 0;
	    int flags = 0;
	    int rt = 0;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "socket ?flags?");
		return TCL_ERROR;
	    }
	    sockp = known_socket(ip, objv[2]);
	    if (sockp == NULL) {
		return TCL_ERROR;
	    }
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    rt = xs_recvmsg(sockp, msgp, flags);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXMSGOBJ_SEND:
	{
	    void* sockp = 0;
	    int flags = 0;
	    int rt = 0;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "socket ?flags?");
		return TCL_ERROR;
	    }
	    sockp = known_socket(ip, objv[2]);
	    if (sockp == NULL) {
		return TCL_ERROR;
	    }
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    rt = xs_sendmsg(sockp, msgp, flags);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXMSGOBJ_SENDMORE:
	{
	    void* sockp = 0;
	    int flags = XS_SNDMORE;
	    int rt = 0;
	    if (objc < 3 || objc > 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "socket ?flags?");
		return TCL_ERROR;
	    }
	    sockp = known_socket(ip, objv[2]);
	    if (sockp == NULL) {
		return TCL_ERROR;
	    }
	    if (objc > 3 && get_recv_send_flag(ip, objv[3], &flags) != TCL_OK) {
	        return TCL_ERROR;
	    }
	    rt = xs_sendmsg(sockp, msgp, flags);
	    last_xs_errno = xs_errno();
	    if (rt < 0) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(rt));
	    break;
	}
	case EXMSGOBJ_SET:
	case EXMSGOBJ_SETMSGOPT:
	{
	    if (objc != 4) {
		Tcl_WrongNumArgs(ip, 2, objv, "name value");
		return TCL_ERROR;
	    }
	    return cset_message_option_as_tcl_obj(cd, ip, objv[2], objv[3]);
	    break;
	}
        case EXMSGOBJ_SIZE:
        {
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, Tcl_NewIntObj(xs_msg_size(msgp)));
   	    break;
	}
	case EXMSGOBJ_SDUMP:
	{
	    if (objc != 2) {
		Tcl_WrongNumArgs(ip, 2, objv, "");
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(ip, xs_s_dump(ip, xs_msg_data(msgp), xs_msg_size(msgp)));
	    break;
	}
	}
 	return TCL_OK;
    }

    static Tcl_Obj* unique_namespace_name(Tcl_Interp* ip, Tcl_Obj* obj, XsClientData* cd) {
	Tcl_Obj* fqn = 0;
	if (obj) {
	    const char* name = Tcl_GetStringFromObj(obj, 0);
	    Tcl_CmdInfo ci;
	    if (!Tcl_StringMatch(name, "::*")) {
		Tcl_Eval(ip, "namespace current");
		fqn = Tcl_GetObjResult(ip);
		fqn = Tcl_DuplicateObj(fqn);
		Tcl_IncrRefCount(fqn);
		if (!Tcl_StringMatch(Tcl_GetStringFromObj(fqn, 0), "::")) {
		    Tcl_AppendToObj(fqn, "::", -1);
		}
		Tcl_AppendToObj(fqn, name, -1);
	    } else {
		fqn = Tcl_NewStringObj(name, -1);
		Tcl_IncrRefCount(fqn);
	    }
	    if (Tcl_GetCommandInfo(ip, Tcl_GetStringFromObj(fqn, 0), &ci)) {
		Tcl_Obj* err;
		err = Tcl_NewObj();
		Tcl_AppendToObj(err, "command \"", -1);
		Tcl_AppendObjToObj(err, fqn);
		Tcl_AppendToObj(err, "\" already exists, unable to create object", -1);
		Tcl_DecrRefCount(fqn);
		Tcl_SetObjResult(ip, err);
		return 0;
	    }
	}
	else {
	    Tcl_Eval(ip, "namespace current");
	    fqn = Tcl_GetObjResult(ip);
	    fqn = Tcl_DuplicateObj(fqn);
	    Tcl_IncrRefCount(fqn);
	    if (!Tcl_StringMatch(Tcl_GetStringFromObj(fqn, 0), "::")) {
		Tcl_AppendToObj(fqn, "::", -1);
	    }
	    Tcl_AppendToObj(fqn, "xs", -1);
	    Tcl_AppendPrintfToObj(fqn, "%d", cd->id);
	    cd->id = cd->id + 1;
	}
	return fqn;
    }

    static void xsEventSetup(ClientData cd, int flags)
    {
	XsClientData* xsClientData = (XsClientData*)cd;
	Tcl_Time blockTime = { 0, 0};
	Tcl_HashSearch hsr;
	Tcl_HashEntry* her = Tcl_FirstHashEntry(xsClientData->readableCommands, &hsr);
	Tcl_HashSearch hsw;
	Tcl_HashEntry* hew = 0;
	int pme = 0;
	while(her) {
	    int events = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getsockopt(Tcl_GetHashKey(xsClientData->readableCommands, her), XS_EVENTS, &events, &len);
	    if (!rt && events & XS_POLLIN) {
		Tcl_SetMaxBlockTime(&blockTime);
		return;
	    }
	    her = Tcl_NextHashEntry(&hsr);
	}
	hew = Tcl_FirstHashEntry(xsClientData->writableCommands, &hsw);
	while(hew) {
	    int events = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getsockopt(Tcl_GetHashKey(xsClientData->writableCommands, hew), XS_EVENTS, &events, &len);
	    if (!rt && events & XS_POLLOUT) {
		Tcl_SetMaxBlockTime(&blockTime);
		return;
	    }
	    hew = Tcl_NextHashEntry(&hsw);
	}
	blockTime.usec = xsClientData->block_time;
	Tcl_SetMaxBlockTime(&blockTime);
    }

    static int xsEventProc(Tcl_Event* evp, int flags)
    {
	XsEvent* ztep = (XsEvent*)evp;
	int rt = Tcl_GlobalEvalObj(ztep->ip, ztep->cmd);
	Tcl_DecrRefCount(ztep->cmd);
	if (rt != TCL_OK)
	    Tcl_BackgroundError(ztep->ip);
	Tcl_Release(ztep->ip);
	return 1;
    }

    static void xsEventCheck(ClientData cd, int flags)
    {
	XsClientData* xsClientData = (XsClientData*)cd;
	Tcl_HashSearch hsr;
	Tcl_HashEntry* her = Tcl_FirstHashEntry(xsClientData->readableCommands, &hsr);
	Tcl_HashSearch hsw;
	Tcl_HashEntry* hew = 0;
	Tcl_HashSearch hsm;
	Tcl_HashEntry* hem = 0;
	while(her) {
	    int events = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getsockopt(Tcl_GetHashKey(xsClientData->readableCommands, her), XS_EVENTS, &events, &len);
	    if (!rt && events & XS_POLLIN) {
		XsEvent* ztep = (XsEvent*)ckalloc(sizeof(XsEvent));
		ztep->event.proc = xsEventProc;
		ztep->ip = xsClientData->ip;
		Tcl_Preserve(ztep->ip);
		ztep->cmd = (Tcl_Obj*)Tcl_GetHashValue(her);
		Tcl_IncrRefCount(ztep->cmd);
		Tcl_QueueEvent((Tcl_Event*)ztep, TCL_QUEUE_TAIL);
	    }
	    her = Tcl_NextHashEntry(&hsr);
	}
	hew = Tcl_FirstHashEntry(xsClientData->writableCommands, &hsw);
	while(hew) {
	    int events = 0;
	    size_t len = sizeof(int);
	    int rt = xs_getsockopt(Tcl_GetHashKey(xsClientData->writableCommands, hew), XS_EVENTS, &events, &len);
	    if (!rt && events & XS_POLLOUT) {
		XsEvent* ztep = (XsEvent*)ckalloc(sizeof(XsEvent));
		ztep->event.proc = xsEventProc;
		ztep->ip = xsClientData->ip;
		Tcl_Preserve(ztep->ip);
		ztep->cmd = (Tcl_Obj*)Tcl_GetHashValue(hew);
		Tcl_IncrRefCount(ztep->cmd);
		Tcl_QueueEvent((Tcl_Event*)ztep, TCL_QUEUE_TAIL);
	    }
	    hew = Tcl_NextHashEntry(&hsw);
	}
    }
}

critcl::ccommand ::xs::version {cd ip objc objv} -clientdata xsClientDataInitVar {
    int major=0, minor=0, patch=0;
    char version[128];
    xs_version(&major, &minor, &patch);
    sprintf(version, "%d.%d.%d", major, minor, patch);
    Tcl_SetObjResult(ip, Tcl_NewStringObj(version, -1));
    return TCL_OK;
}

critcl::cproc ::xs::errno {} int {
    return last_xs_errno;
}

critcl::ccommand ::xs::strerror {cd ip objc objv} -clientdata xsClientDataInitVar {
    int errnum = 0;
    if (objc != 2) {
	Tcl_WrongNumArgs(ip, 1, objv, "errnum");
	return TCL_ERROR;
    }
    if (Tcl_GetIntFromObj(ip, objv[1], &errnum) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong errnum argument, expected integer", -1));
	return TCL_ERROR;
    }
    Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(errnum), -1));
    return TCL_OK;
}

critcl::ccommand ::xs::max_block_time {cd ip objc objv} -clientdata xsClientDataInitVar {
    int block_time = 0;
    XsClientData* xsClientData = (XsClientData*)cd;
    if (objc != 2) {
	Tcl_WrongNumArgs(ip, 1, objv, "block_time");
	return TCL_ERROR;
    }
    if (Tcl_GetIntFromObj(ip, objv[1], &block_time) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong block_time argument, expected integer", -1));
	return TCL_ERROR;
    }
    xsClientData->block_time = block_time;
    return TCL_OK;
}

critcl::ccommand ::xs::context {cd ip objc objv} -clientdata xsClientDataInitVar {
    Tcl_Obj* fqn = 0;
    void* xsp = 0;
    XsContextClientData* ccd = 0;
    int i = 0;
    int newPtr = 0;
    Tcl_HashEntry* hashEntry = 0;
    if (objc == 1) {
	/* No name specified */
	fqn = unique_namespace_name(ip, 0, (XsClientData*)cd);
	if (!fqn)
	    return TCL_ERROR;
	i = 1;
    }
    else if (objc == 2) {
	/* Name specified */
	fqn = unique_namespace_name(ip, objv[1], (XsClientData*)cd);
	if (!fqn)
	    return TCL_ERROR;
	i = 2;
    }
    else {
	Tcl_WrongNumArgs(ip, 1, objv, "?name?");
	return TCL_ERROR;
    }
    xsp = xs_init();
    last_xs_errno = xs_errno();
    if (xsp == NULL) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
	Tcl_DecrRefCount(fqn);
	return TCL_ERROR;
    }
    ccd = (XsContextClientData*)ckalloc(sizeof(XsContextClientData));
    ccd->context = xsp;
    ccd->tcl_cmd = fqn;
    ccd->xsClientData = cd;
    Tcl_CreateObjCommand(ip, Tcl_GetStringFromObj(fqn, 0), xs_context_objcmd, (ClientData)ccd, xs_free_client_data);
    Tcl_SetObjResult(ip, fqn);
    Tcl_CreateEventSource(xsEventSetup, xsEventCheck, cd);
    return TCL_OK;
}

critcl::ccommand ::xs::socket {cd ip objc objv} -clientdata xsClientDataInitVar {
    Tcl_Obj* fqn = 0;
    void* ctxp = 0;
    int stype = 0;
    int stindex = -1;
    void* sockp = 0;
    XsSocketClientData* scd = 0;
    int ctxidx = 2;
    int typeidx = 3;
    Tcl_HashEntry* hashEntry = 0;
    int newPtr = 0;
    static const char* stypes[] = {"PAIR", "PUB", "SUB", "REQ", "REP", "XREQ", "XREP", "PULL", "PUSH",
				   "XPUB", "XSUB", "SURVEYOR", "RESPONDENT", "XSURVEYOR", "XRESPONDENT", NULL};
    enum ExObjSocketMethods {XST_PAIR, XST_PUB, XST_SUB, XST_REQ, XST_REP, XST_XREQ, XST_XREP, XST_PULL, XST_PUSH,
			     XST_XPUB, XST_XSUB, XST_SURVEYOR, XST_RESPONDENT, XST_XSURVEYOR, XST_XRESPONDENT};
    if (objc == 3) {
	fqn = unique_namespace_name(ip, NULL, (XsClientData*)cd);
	ctxidx = 1;
	typeidx = 2;
    }
    else if (objc == 4) {
	fqn = unique_namespace_name(ip, objv[1], (XsClientData*)cd);
	if (!fqn)
	    return TCL_ERROR;
	ctxidx = 2;
	typeidx = 3;
    }
    else {
	Tcl_WrongNumArgs(ip, 1, objv, "?name? context type");
	return TCL_ERROR;
    }
    ctxp = known_context(ip, objv[ctxidx]);
    if (!ctxp) {
	Tcl_DecrRefCount(fqn);
	return TCL_ERROR;
    }
    if (Tcl_GetIndexFromObj(ip, objv[typeidx], stypes, "type", 0, &stindex) != TCL_OK)
	return TCL_ERROR;
    switch((enum ExObjSocketMethods)stindex) {
    case XST_PAIR: stype = XS_PAIR; break;
    case XST_PUB: stype = XS_PUB; break;
    case XST_SUB: stype = XS_SUB; break;
    case XST_REQ: stype = XS_REQ; break;
    case XST_REP: stype = XS_REP; break;
    case XST_XREQ: stype = XS_XREQ; break;
    case XST_XREP: stype = XS_XREP; break;
    case XST_PULL: stype = XS_PULL; break;
    case XST_PUSH: stype = XS_PUSH; break;
    case XST_XPUB: stype = XS_XPUB; break;
    case XST_XSUB: stype = XS_XSUB; break;
    case XST_SURVEYOR: stype = XS_SURVEYOR; break;
    case XST_RESPONDENT: stype = XS_RESPONDENT; break;
    case XST_XSURVEYOR: stype = XS_XSURVEYOR; break;
    case XST_XRESPONDENT: stype = XS_XRESPONDENT; break;
    }
    sockp = xs_socket(ctxp, stype);
    last_xs_errno = xs_errno();
    if (sockp == NULL) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
	Tcl_DecrRefCount(fqn);
	return TCL_ERROR;
    }
    scd = (XsSocketClientData*)ckalloc(sizeof(XsSocketClientData));
    scd->context = ctxp;
    scd->socket = sockp;
    scd->tcl_cmd = fqn;
    scd->xsClientData = cd;
    Tcl_CreateObjCommand(ip, Tcl_GetStringFromObj(fqn, 0), xs_socket_objcmd, (ClientData)scd, xs_free_client_data);
    Tcl_SetObjResult(ip, fqn);
    return TCL_OK;
}

critcl::ccommand ::xs::message {cd ip objc objv} -clientdata xsClientDataInitVar {
    char* data = 0;
    int size = -1;
    Tcl_Obj* fqn = 0;
    int i;
    void* msgp = 0;
    int rt = 0;
    XsMessageClientData* mcd = 0;
    if (objc < 1) {
	Tcl_WrongNumArgs(ip, 1, objv, "?name? ?-size <size>? ?-data <data>?");
	return TCL_ERROR;
    }
    if ((objc-2) % 2) {
	/* No name specified */
	fqn = unique_namespace_name(ip, 0, (XsClientData*)cd);
	if (!fqn)
	    return TCL_ERROR;
	i = 1;
    }
    else {
	/* Name specified */
	fqn = unique_namespace_name(ip, objv[1], (XsClientData*)cd);
	if (!fqn)
	    return TCL_ERROR;
	i = 2;
    }
    for(; i < objc; i+=2) {
	Tcl_Obj* k = objv[i];
	Tcl_Obj* v = objv[i+1];
	static const char* params[] = {"-data", "-size", NULL};
	enum ExObjParams {EXMSGPARAM_DATA, EXMSGPARAM_SIZE};
	int index = -1;
	if (Tcl_GetIndexFromObj(ip, k, params, "parameter", 0, &index) != TCL_OK) {
	    Tcl_DecrRefCount(fqn);
	    return TCL_ERROR;
	}
	switch((enum ExObjParams)index) {
	case EXMSGPARAM_DATA:
	{
	    data = Tcl_GetStringFromObj(v, &size);
	    break;
	}
	case EXMSGPARAM_SIZE:
	{
	    if (Tcl_GetIntFromObj(ip, v, &size) != TCL_OK) {
		Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong size argument, expected integer", -1));
		Tcl_DecrRefCount(fqn);
		return TCL_ERROR;
	    }
	    break;
	}
	}
    }
    msgp = ckalloc(32);
    if (data) {
	void* buffer = 0;
	if (size < 0)
	    size = strlen(data);
	buffer = ckalloc(size);
	memcpy(buffer, data, size);
	rt = xs_msg_init_data(msgp, buffer, size, xs_ckfree, NULL);
    }
    else if (size >= 0) {
	rt = xs_msg_init_size(msgp, size);
    }
    else {
	rt = xs_msg_init(msgp);
    }
    last_xs_errno = xs_errno();
    if (rt != 0) {
	ckfree(msgp);
	Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
	Tcl_DecrRefCount(fqn);
	return TCL_ERROR;
    }
    mcd = (XsMessageClientData*)ckalloc(sizeof(XsMessageClientData));
    mcd->message = msgp;
    mcd->tcl_cmd = fqn;
    mcd->xsClientData = cd;
    Tcl_CreateObjCommand(ip, Tcl_GetStringFromObj(fqn, 0), xs_message_objcmd, (ClientData)mcd, xs_free_client_data);
    Tcl_SetObjResult(ip, fqn);
    return TCL_OK;
}

critcl::ccommand ::xs::poll {cd ip objc objv} -clientdata xsClientDataInitVar {
    int slobjc = 0;
    Tcl_Obj** slobjv = 0;
    int i = 0;
    int timeout = 1; /* default in milliseconds */
    xs_pollitem_t* sockl = 0;
    int rt = 0;
    Tcl_Obj* result = 0;
    static const char* tounit[] = {"s", "ms", NULL};
    enum ExObjTimeoutUnit {EXTO_S, EXTO_MS};
    int toindex = -1;
    if (objc < 3 || objc > 4) {
	Tcl_WrongNumArgs(ip, 1, objv, "socket_list timeout ?timeout_unit?");
	return TCL_ERROR;
    }
    if (objc == 4 && Tcl_GetIndexFromObj(ip, objv[3], tounit, "timeout_unit", 0, &toindex) != TCL_OK)
	return TCL_ERROR;
    if (Tcl_ListObjGetElements(ip, objv[1], &slobjc, &slobjv) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("sockets_list not specified as list", -1));
	return TCL_ERROR;
    }
    for(i = 0; i < slobjc; i++) {
	int flobjc = 0;
	Tcl_Obj** flobjv = 0;
	int events = 0;
	if (Tcl_ListObjGetElements(ip, slobjv[i], &flobjc, &flobjv) != TCL_OK) {
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("socket not specified as list", -1));
	    return TCL_ERROR;
	}
	if (flobjc != 2) {
	    Tcl_SetObjResult(ip, Tcl_NewStringObj("socket not specified as list of <socket_handle list_of_event_flags>", -1));
	    return TCL_ERROR;
	}
	if (!known_socket(ip, flobjv[0]))
	    return TCL_ERROR;
	if (get_poll_flags(ip, flobjv[1], &events) != TCL_OK)
	    return TCL_ERROR;
    }
    if (Tcl_GetIntFromObj(ip, objv[2], &timeout) != TCL_OK) {
	Tcl_SetObjResult(ip, Tcl_NewStringObj("Wrong timeout argument, expected integer", -1));
	return TCL_ERROR;
    }
    switch((enum ExObjTimeoutUnit)toindex) {
    case EXTO_S: timeout *= 1000; break;
    case EXTO_MS: break;
    }
    sockl = (xs_pollitem_t*)ckalloc(sizeof(xs_pollitem_t) * slobjc);
    for(i = 0; i < slobjc; i++) {
	int flobjc = 0;
	Tcl_Obj** flobjv = 0;
	int elobjc = 0;
	Tcl_Obj** elobjv = 0;
	int events = 0;
	Tcl_ListObjGetElements(ip, slobjv[i], &flobjc, &flobjv);
	Tcl_ListObjGetElements(ip, flobjv[1], &elobjc, &elobjv);
	if (get_poll_flags(ip, flobjv[1], &events) != TCL_OK)
	    return TCL_ERROR;
	sockl[i].socket = known_socket(ip, flobjv[0]);
	sockl[i].fd = 0;
	sockl[i].events = events;
	sockl[i].revents = 0;
    }
    rt = xs_poll(sockl, slobjc, timeout);
    last_xs_errno = xs_errno();
    if (rt < 0) {
	ckfree((void*)sockl);
	Tcl_SetObjResult(ip, Tcl_NewStringObj(xs_strerror(last_xs_errno), -1));
	return TCL_ERROR;
    }
    result = Tcl_NewListObj(0, NULL);
    for(i = 0; i < slobjc; i++) {
	if (sockl[i].revents) {
	    int flobjc = 0;
	    Tcl_Obj** flobjv = 0;
	    Tcl_Obj* sresult = 0;
	    Tcl_ListObjGetElements(ip, slobjv[i], &flobjc, &flobjv);
	    sresult = Tcl_NewListObj(0, NULL);
	    Tcl_ListObjAppendElement(ip, sresult, flobjv[0]);
	    Tcl_ListObjAppendElement(ip, sresult, set_poll_flags(ip, sockl[i].revents));
	    Tcl_ListObjAppendElement(ip, result, sresult);
	}
    }
    Tcl_SetObjResult(ip, result);
    ckfree((void*)sockl);
    return TCL_OK;
}

critcl::ccommand ::xs::zframe_strhex {cd ip objc objv} {
    char* data = 0;
    int size = -1;
    static char hex_char [] = "0123456789ABCDEF";
    char *hex_str = 0;
    int byte_nbr;
    if (objc != 2) {
	Tcl_WrongNumArgs(ip, 1, objv, "string");
	return TCL_ERROR;
    }
    data = Tcl_GetStringFromObj(objv[1], &size);
    hex_str = (char*)ckalloc(size*2+1);
    for (byte_nbr = 0; byte_nbr < size; byte_nbr++) {
	hex_str [byte_nbr * 2 + 0] = hex_char [(data [byte_nbr] >> 4) & 15];
	hex_str [byte_nbr * 2 + 1] = hex_char [data [byte_nbr] & 15];
    }
    hex_str [size * 2] = 0;
    Tcl_SetObjResult(ip, Tcl_NewStringObj(hex_str, -1));
    ckfree(hex_str);
    return TCL_OK;
}

critcl::cinit {
    xsClientDataInitVar = (XsClientData*)ckalloc(sizeof(XsClientData));
    xsClientDataInitVar->ip = ip;
    xsClientDataInitVar->readableCommands = (struct Tcl_HashTable*)ckalloc(sizeof(struct Tcl_HashTable));
    Tcl_InitHashTable(xsClientDataInitVar->readableCommands, TCL_ONE_WORD_KEYS);
    xsClientDataInitVar->writableCommands = (struct Tcl_HashTable*)ckalloc(sizeof(struct Tcl_HashTable));
    Tcl_InitHashTable(xsClientDataInitVar->writableCommands, TCL_ONE_WORD_KEYS);
    xsClientDataInitVar->block_time = 1000;
    xsClientDataInitVar->id = 0;
} {
    static XsClientData* xsClientDataInitVar = 0;
}



package provide xs 1.2.0
