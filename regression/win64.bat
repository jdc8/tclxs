set TCLSH=c:\Tcl\bin\tclsh.exe

git clone https://github.com/crossroads-io/libxs.git
git clone https://github.com/jdc8/tclxs.git

cd tclxs\regression
nmake XS=..\..\libxs all64

cd ..
%TCLSH% build.tcl install -xs regression -static
cd test
%TCLSH% all.tcl

cd ..\..
rmdir /s /q libxs
rmdir /s /q tclxs
