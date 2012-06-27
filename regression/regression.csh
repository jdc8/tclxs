#!/bin/csh

if ($#argv == 0) then
    set TCLSH = `which tclsh`
else if ($#argv == 1) then
    set TCLSH = $1
else
    echo "Usage: regression.csh ?<tclsh_path>?"
    exit 1
endif

set V = $1
set failed = 0

git clone git://github.com/crossroads-io/libxs.git libxs
if ($status) then
    set failed = 1
    goto done
endif

cd libxs

./autogen.sh
if ($status) then
    set failed = 1
    goto cddone
endif

setenv CXXFLAGS -fPIC
setenv CFLAGS -fPIC

./configure --prefix=/tmp/libxs
if ($status) then
    set failed = 1
    goto cddone
endif

make
if ($status) then
    set failed = 1
    goto cddone
endif

make install
if ($status) then
    set failed = 1
    goto cddone
endif

cd ..

git clone git://github.com/jdc8/tclxs.git tclxs
if ($status) then
    set failed = 1
    goto done
endif

cd tclxs

$TCLSH build.tcl install lib -zmq /tmp/libxs -static
if ($status) then
    set failed = 1
    goto cddone
endif

cd test
$TCLSH all.tcl >& test.log
if ($status) then
    set failed = 1
    goto cdcddone
endif

cat test.log

$TCLSH ../regression/look_for_failed_tests.tcl test.log
if ($status) then
    set failed = 1
    goto cdcddone
endif

cdcddone:
cd ..

cddone:
cd ..

done:
rm -Rf libxs /tmp/libxs tclxs

exit $failed
