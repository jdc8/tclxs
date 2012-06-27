set TCLSH=c:\Tcl\bin\tclsh.exe

git clone https://github.com/crossroads-io/libxs.git
git clone https://github.com/jdc8/tclxs.git
cd tclxs
cd zmq_nMakefiles
nmake ZMQDIR=..\..\libzmq31 all64
cd ..
%TCLSH% build.tcl install -zmq zmq_nMakefiles -static
cd test
%TCLSH% all.tcl
cd ..
cd ..
rmdir /s /q libzmq31
rmdir /s /q tclzmq
