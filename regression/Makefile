#
# Build Crossroads I/O for static linking with the Tcl wrapper, 32 or 64 bit.
#
# Specify the XSDIR=<path_to_libxs> and INSTALLDIR=<path> on the nmake command
# line
#
# Use the following commands to build and install the xs library for 32 or 64 bit:
#
# % nmake XSDIR=../../libxs INSTALLDIR=. all32
#
# % nmake XSDIR=../../libxs INSTALLDIR=. all64
#

XSDIR = ..\..\libxs
INSTALLDIR = .

include_HEADERS = $(XSDIR)\include\xs\xs.h

CFLAGS =    /c /Zi /nologo /W3 /WX- /MP /O2 /GL /I. /I$(XSDIR)\include /I$(XSDIR)\src /I$(XSDIR)\builds\msvc /D NDEBUG /D _WIN64 /D _CRT_SECURE_NO_WARNINGS /D DLL_EXPORT /D FD_SETSIZE=1024 /D _WINDOWS /D _USRDLL /D _BIND_TO_CURRENT_VCLIBS_VERSION=1 /D _MBCS /Gm- /EHsc /MD /GS /Gy /fp:precise /Zc:wchar_t /Gd /TP /wd4355 /FIprecompiled.hpp /Zc:forScope /Fo"work/"

CLCFLAGS = $(CFLAGS) /Yu"precompiled.hpp"
PCCFLAGS = $(CFLAGS) /Yc"precompiled.hpp"

SOURCES = \
    $(XSDIR)\src\address.cpp \
    $(XSDIR)\src\clock.cpp \
    $(XSDIR)\src\core.cpp \
    $(XSDIR)\src\ctx.cpp \
    $(XSDIR)\src\decoder.cpp \
    $(XSDIR)\src\devpoll.cpp \
    $(XSDIR)\src\dist.cpp \
    $(XSDIR)\src\encoder.cpp \
    $(XSDIR)\src\epoll.cpp \
    $(XSDIR)\src\err.cpp \
    $(XSDIR)\src\fq.cpp \
    $(XSDIR)\src\io_object.cpp \
    $(XSDIR)\src\io_thread.cpp \
    $(XSDIR)\src\ip.cpp \
    $(XSDIR)\src\ipc_connecter.cpp \
    $(XSDIR)\src\ipc_listener.cpp \
    $(XSDIR)\src\kqueue.cpp \
    $(XSDIR)\src\lb.cpp \
    $(XSDIR)\src\mailbox.cpp \
    $(XSDIR)\src\msg.cpp \
    $(XSDIR)\src\object.cpp \
    $(XSDIR)\src\options.cpp \
    $(XSDIR)\src\own.cpp \
    $(XSDIR)\src\pair.cpp \
    $(XSDIR)\src\pgm_receiver.cpp \
    $(XSDIR)\src\pgm_sender.cpp \
    $(XSDIR)\src\pgm_socket.cpp \
    $(XSDIR)\src\pipe.cpp \
    $(XSDIR)\src\poll.cpp \
    $(XSDIR)\src\prefix_filter.cpp \
    $(XSDIR)\src\pull.cpp \
    $(XSDIR)\src\push.cpp \
    $(XSDIR)\src\reaper.cpp \
    $(XSDIR)\src\pub.cpp \
    $(XSDIR)\src\random.cpp \
    $(XSDIR)\src\rep.cpp \
    $(XSDIR)\src\req.cpp \
    $(XSDIR)\src\respondent.cpp \
    $(XSDIR)\src\select.cpp \
    $(XSDIR)\src\session_base.cpp \
    $(XSDIR)\src\signaler.cpp \
    $(XSDIR)\src\socket_base.cpp \
    $(XSDIR)\src\stream_engine.cpp \
    $(XSDIR)\src\sub.cpp \
    $(XSDIR)\src\surveyor.cpp \
    $(XSDIR)\src\tcp_connecter.cpp \
    $(XSDIR)\src\tcp_listener.cpp \
    $(XSDIR)\src\thread.cpp \
    $(XSDIR)\src\topic_filter.cpp \
    $(XSDIR)\src\upoll.cpp \
    $(XSDIR)\src\xpub.cpp \
    $(XSDIR)\src\xrep.cpp \
    $(XSDIR)\src\xreq.cpp \
    $(XSDIR)\src\xrespondent.cpp \
    $(XSDIR)\src\xsub.cpp \
    $(XSDIR)\src\xsurveyor.cpp \
    $(XSDIR)\src\xs.cpp

all64: lib64 install headers

all32: lib32 install headers

install:
	-mkdir $(INSTALLDIR)
	-mkdir $(INSTALLDIR)\lib
	copy work\libxs.lib $(INSTALLDIR)\lib\libxs.lib

headers: $(include_HEADERS)
	- mkdir $(INSTALLDIR)
	- mkdir $(INSTALLDIR)\include
	- mkdir $(INSTALLDIR)\include\xs
	copy /Y $(XSDIR)\include\xs\* $(INSTALLDIR)\include\xs

lib64: objs64
	lib work\*.obj /out:work\libxs.lib /LTCG

lib32: objs32
	lib work\*.obj /out:work\libxs.lib /LTCG

objs64: $(SOURCES)
	- mkdir work
	cl $(XSDIR)\src\precompiled.cpp $(PCCFLAGS) /D _WIN64
	cl $(SOURCES) $(CLCFLAGS) /D _WIN64

objs32: $(SOURCES)
	- mkdir work
	cl $(XSDIR)\src\precompiled.cpp $(PCCFLAGS)
	cl $(SOURCES) $(CLCFLAGS)

clean:
	rmdir /S /Q work
