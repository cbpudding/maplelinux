#!/bin/sh -e

# Define the build environment
export DIR_BASE=$(pwd)
export DIR_BUILD=$DIR_BASE/build
export DIR_MAPLE=$DIR_BASE/maple
export DIR_PATCH=$DIR_BASE/patch
export DIR_SRC=$DIR_BASE/src
export DIR_TOOLS=$DIR_MAPLE/maple/tools
export JOBS=${JOBS:-$(nproc)}
export LEX=$(which lex || which flex)
export TARGET=${TARGET:-x86_64-maple-linux-musl}
export YACC=$(which byacc || which bison || which yacc)

[ -z "$LEX" ] && (echo "lex is not installed. Please install lex or a compatible program and try again."; exit 1)
[ -z "$YACC" ] && (echo "yacc is not installed. Please install yacc or a compatible program and try again."; exit 1)

# Prepare a clean build environment
[ -d $DIR_BUILD ] && rm -rf $DIR_BUILD
mkdir -p $DIR_BUILD

[ -d $DIR_MAPLE ] && rm -rf $DIR_MAPLE
mkdir -p $DIR_MAPLE

[ -d $DIR_TOOLS ] && rm -rf $DIR_TOOLS
mkdir -p $DIR_TOOLS

# Create the root hierarchy
mkdir -p $DIR_MAPLE/bin           # Executables (User-Executable Code)
mkdir -p $DIR_MAPLE/boot          # Boot Partition
mkdir -p $DIR_MAPLE/cache         # Retained Data
mkdir -p $DIR_MAPLE/dev           # Linux Device Nodes
mkdir -p $DIR_MAPLE/etc           # Persistent Data
mkdir -p $DIR_MAPLE/home          # User Data
mkdir -p $DIR_MAPLE/lib           # Libraries (Machine-Executable Code)
mkdir -p $DIR_MAPLE/proc          # Linux Process Objects
mkdir -p $DIR_MAPLE/share         # Immutable Data
mkdir -p $DIR_MAPLE/share/include # C Header Files
mkdir -p $DIR_MAPLE/sys           # Linux Kernel Objects
mkdir -p $DIR_MAPLE/tmp           # Temporary Data

# Build the cross-linker/assembler
mkdir -p $DIR_BUILD/cross-binutils
cd $DIR_BUILD/cross-binutils
$DIR_SRC/binutils-gdb/configure \
    --build=$($DIR_SRC/binutils-gdb/config.guess) \
    --disable-gdb \
    --disable-gprofng \
    --disable-nls \
    --disable-static \
    --disable-werror \
    --enable-year2038 \
    --host=$($DIR_SRC/binutils-gdb/config.guess) \
    --includedir=$DIR_TOOLS/share/include \
    --libexecdir=$DIR_TOOLS/lib \
    --localstatedir=$DIR_TOOLS/etc \
    --oldincludedir=$DIR_TOOLS/share/include \
    --prefix=$DIR_TOOLS \
    --sbindir=$DIR_TOOLS/bin \
    --sharedstatedir=$DIR_TOOLS/etc \
    --target=$TARGET \
    --with-build-sysroot=$DIR_MAPLE
make -O -j $JOBS
make -O -j $JOBS install

# Build the cross-compiler
mkdir -p $DIR_BUILD/cross-gcc
cd $DIR_BUILD/cross-gcc
# NOTE: Technically, gcc supports an out-of-tree build, but GCC doesn't conform
#       to Maple Linux's filesystem hierarchy and installs libraries like
#       libstdc++ under /lib64 instead of /lib. To fix this, the cross-compiler
#       itself needs to be patched since autoconf follows gcc's lead. ~ahill
cp -r $DIR_SRC/gcc/. .
# NOTE: Credit to Linux From Scratch for this patch. It would have taken me a
#       long time to figure this one out otherwise. ~ahill
# TODO: Will similar patches be required for other architectures? ~ahill
sed -i "/m64=/s/lib64/lib/" gcc/config/i386/t-linux64
# NOTE: gcc makes some assumptions about the directory structure due to the way
#       relative paths are coded. A successful build requires a subdirectory so
#       the parts of the build script that use "../.." can get back to the root
#       of the source code. ~ahill
mkdir build-within-a-build
cd build-within-a-build
../configure \
    --build=$(../config.guess) \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --disable-multilib \
    --disable-nls \
    --disable-threads \
    --enable-default-pie \
    --enable-default-ssp \
    --enable-languages=c,c++ \
    --enable-year2038 \
    --host=$(../config.guess) \
    --includedir=$DIR_TOOLS/share/include \
    --libexecdir=$DIR_TOOLS/lib \
    --localstatedir=$DIR_TOOLS/etc \
    --oldincludedir=$DIR_TOOLS/share/include \
    --prefix=$DIR_TOOLS \
    --sbindir=$DIR_TOOLS/bin \
    --sharedstatedir=$DIR_TOOLS/etc \
    --target=$TARGET \
    --with-gcc-major-version-only \
    --with-gmp=$DIR_SRC/mpir \
    --with-mpc=$DIR_SRC/mpc \
    --with-mpfr=$DIR_SRC/mpfr \
    --with-native-system-header-dir=/share/include \
    --with-newlib \
    --with-sysroot=$DIR_MAPLE \
    --without-headers \
    --without-isl
make -O -j $JOBS
make -O -j $JOBS install
# NOTE: Even gcc uses cc instead of gcc in some places, so a symlink is required
#       for future builds to succeed. ~ahill
ln -s $TARGET-gcc $DIR_TOOLS/bin/$TARGET-cc

# Re-define the build environment to use the new tools
export AR="$TARGET-ar"
export AS="$TARGET-as"
export CC="$TARGET-gcc"
export CXX="$TARGET-g++"
export LD="$TARGET-ld"
export NM="$TARGET-nm"
export OBJCOPY="$TARGET-objcopy"
export OBJDUMP="$TARGET-objdump"
export PATH="$DIR_TOOLS/bin:$PATH"
export RANLIB="$TARGET-ranlib"
export STRIP="$TARGET-strip"

# Install Linux headers
mkdir -p $DIR_BUILD/build-linux
cd $DIR_BUILD/build-linux
make -C $DIR_SRC/linux -j $JOBS headers O=$(pwd)
find usr/include -type f ! -name "*.h" -delete
cp -r usr/include $DIR_MAPLE/share/

# Build and install musl
mkdir -p $DIR_BUILD/build-musl
cd $DIR_BUILD/build-musl
$DIR_SRC/musl/configure \
    --bindir=/bin \
    --includedir=/share/include \
    --libdir=/lib \
    --prefix=/ \
    --target=$TARGET
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE
# NOTE: This is absolute witchcraft and I need to learn how this actually works.
#       ~ahill
ln -s /lib/libc.so $DIR_MAPLE/bin/ldd

# Build and install toybox
mkdir -p $DIR_BUILD/build-toybox
cd $DIR_BUILD/build-toybox
# NOTE: I cannot figure out how the heck to build toybox outside of the source
#       tree, so this will have to do for now. ~ahill
cp -r $DIR_SRC/toybox/* .
# NOTE: Toybox sees $TARGET and decides to append a suffix to the main program,
#       which is not what I'm looking for. Yes, it's being cross-compiled, but
#       the system that's running it doesn't need to be reminded of its own
#       target triple. ~ahill
# NOTE: I haven't looked into why yet, but genconfig.sh seems to generate more
#       than just the .config file. Attempting to build Toybox without running
#       this first causes an error. ~ahill
TARGET="" ./scripts/genconfig.sh -d
cp $DIR_PATCH/toybox.config .config
LDFLAGS="-static" TARGET="" ./scripts/make.sh
PREFIX=$DIR_MAPLE/bin TARGET="" ./scripts/install.sh --symlink

# Build and install oksh
mkdir -p $DIR_BUILD/build-oksh
cd $DIR_BUILD/build-oksh
$DIR_SRC/oksh/configure \
    --bindir=/bin \
    --cc=$CC \
    --cflags=$CFLAGS \
    --enable-ksh \
    --enable-small \
    --enable-static \
    --prefix=/ \
    --mandir=/share/man
make -O -j $JOBS
# FIXME: For some reason, out-of-tree builds don't install the documentation
#        correctly. This is a temporary workaround, but this should be patched
#        upstream. ~ahill
cp $DIR_SRC/oksh/ksh.1 .
# NOTE: Rather than having two copies of ksh that are identical, make a symlink
#       to /bin/ksh so users can clearly see that it's a copy. Has the added
#       bonus of not wasting space on the disk. ~ahill
ln -s ksh $DIR_MAPLE/bin/sh
make install DESTDIR="$DIR_MAPLE"

# Build and install Hummingbird
mkdir -p $DIR_BUILD/build-hummingbird
cd $DIR_BUILD/build-hummingbird
# NOTE: Yes, an out of tree build is incredibly easy to do in this case, but the
#       source code needs to be patched to adapt to Maple Linux's unique
#       filesystem hierarchy, and everything under $DIR_SRC should be immutable.
#       ~ahill
cp -r $DIR_SRC/hummingbird/* .
# NOTE: Hummingbird is an incredibly simple project, and as such, it makes a lot
#       of assumptions about the environment it's going to run in. Thankfully,
#       since Hummingbird is so simple, it's easy to make a patch that adapts it
#       to Maple Linux. ~ahill
patch -p1 < $DIR_PATCH/hummingbird-maple.patch
$CC $CFLAGS -static \
    src/hummingbird.c \
    src/init.c \
    src/signal.c \
    src/shutdown.c \
    -o hummingbird
cp hummingbird $DIR_MAPLE/bin/
ln -s hummingbird $DIR_MAPLE/bin/init
cp bin/reboot $DIR_MAPLE/bin/
cp bin/shutdown $DIR_MAPLE/bin/
mkdir -p $DIR_MAPLE/lib/hummingbird
cp $DIR_SRC/hummingbird/usr/lib/hummingbird/* $DIR_MAPLE/lib/hummingbird/
dd bs=512 count=1 if=/dev/urandom of=$DIR_MAPLE/etc/random.seed status=none

# Build and install skalibs
mkdir -p $DIR_BUILD/build-skalibs
cd $DIR_BUILD/build-skalibs
# NOTE: Skalibs does not support out of tree builds, so we copy the tree here to
#       keep $DIR_SRC immutable. ~ahill
cp -r $DIR_SRC/skalibs/* .
# TODO: Does Maple Linux need --enable-pkgconfig? ~ahill
./configure \
    --disable-shared \
    --includedir=/share/include \
    --pkgconfdir=/share/pkgconfig \
    --prefix=/ \
    --sysdepdir=/share/skalibs/sysdeps \
    --target=$TARGET \
    --with-sysdep-devurandom=yes \
    --with-sysdep-posixspawnearlyreturn=no \
    --with-sysdep-procselfexe=yes
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install mdevd
mkdir -p $DIR_BUILD/build-mdevd
cd $DIR_BUILD/build-mdevd
# NOTE: mdevd does not support out of tree builds, so we copy the tree here to
#       keep $DIR_SRC immutable. ~ahill
cp -r $DIR_SRC/mdevd/* .
# TODO: Does Maple Linux need --enable-pkgconfig? ~ahill
./configure \
    --enable-static-libc \
    --includedir=/share/include \
    --libexecdir=/lib \
    --pkgconfdir=/share/pkgconfig \
    --prefix=/ \
    --target=$TARGET \
    --with-lib=$DIR_MAPLE/lib \
    --with-sysdeps=$DIR_MAPLE/share/skalibs/sysdeps
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install Linux
mkdir -p $DIR_BUILD/build-linux
cd $DIR_BUILD/build-linux
# TODO: Create a sane config for Maple Linux ~ahill
make -C $DIR_SRC/linux -j $JOBS defconfig O=$(pwd)
make -C $DIR_SRC/linux -j $JOBS O=$(pwd)
make -C $DIR_SRC/linux -j $JOBS modules_install INSTALL_MOD_PATH=$DIR_MAPLE O=$(pwd)
cp $(make image_name) $DIR_MAPLE/boot/vmlinuz-$(make kernelrelease)
cp System.map $DIR_MAPLE/boot/System.map-$(make kernelrelease)
# NOTE: I have yet to test the following since I have only been testing on x86
#       so far. ~ahill
if make -C $DIR_SRC/linux -q dtbs > /dev/null 2>&1; then
    make -C $DIR_SRC/linux -j $JOBS dtbs O=$(pwd)
    make -C $DIR_SRC/linux -j $JOBS dtbs_install INSTALL_DTBS_PATH=$DIR_MAPLE O=$(pwd)
fi

# Build and install ndhc
mkdir -p $DIR_BUILD/build-ndhc
cd $DIR_BUILD/build-ndhc
# NOTE: ndhc does not support out-of-tree builds, so we copy the source here.
#       ~ahill
# NOTE: Ragel will *sometimes* get invoked because the timestamp of the parser
#       is newer than the C code it generated. Telling cp to preserve timestamps
#       fixes this behavior. ~ahill
cp -a $DIR_SRC/ndhc/* .
CFLAGS="-static --sysroot=$DIR_MAPLE" make -j $JOBS
cp ndhc $DIR_MAPLE/bin/
mkdir -p $DIR_MAPLE/share/man/man8
cp ndhc.8 $DIR_MAPLE/share/man/man8/

# Build and install chrony
mkdir -p $DIR_BUILD/build-chrony
cd $DIR_BUILD/build-chrony
# NOTE: Out of tree builds for chrony are broken. ~ahill
cp -r $DIR_SRC/chrony/* .
# TODO: Create an actual user for chrony{c,d} and specify --with{,-chronyc}-user
#       ~ahill
# NOTE: There does not appear to be an option to specify a sysroot or static
#       build, so I'm forced to pass custom CFLAGS instead. ~ahill
CFLAGS="-static --sysroot=$DIR_MAPLE" ./configure \
    --chronyrundir=/tmp \
    --chronyvardir=/etc/chrony \
    --disable-readline \
    --host-machine=$(echo $TARGET | cut -d"-" -f1) \
    --host-system=Linux \
    --localstatedir=/etc \
    --prefix=/ \
    --sbindir=/bin \
    --with-pidfile=/tmp/chronyd.pid
CFLAGS="-static --sysroot=$DIR_MAPLE" make -j $JOBS
make -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install Heirloom Toolchest
mkdir -p $DIR_BUILD/build-heirloom-toolchest
cd $DIR_BUILD/build-heirloom-toolchest
# NOTE: Out of tree builds aren't possible with Makefiles this old. ~ahill
cp -r $DIR_SRC/heirloom-toolchest/libcommon .
# NOTE: libcommon builds itself in different ways depending on which libc it
#       detects. Unfortunately, musl is way too new for the older source code to
#       know about, so I'm defining __dietlibc__ since that's the closest to
#       what musl actually is. ~ahill
# NOTE: No, that's not a typo. This Makefile uses CFLAGSS, not CFLAGS. ~ahill
CFLAGSS="-D__dietlibc__" make -C libcommon -f Makefile.mk -O -j $JOBS
# NOTE: The Makefile seems like a waste here, but it was likely added for SCCS
#       compliance. Bypassing it since it's only a single file to build. ~ahill
$CC -Ilibcommon -static $DIR_SRC/heirloom-toolchest/cmp/cmp.c \
    libcommon/libcommon.a -o $DIR_MAPLE/bin/cmp
cp $DIR_SRC/heirloom-toolchest/cmp/cmp.1 $DIR_MAPLE/share/man/man1/
cp -r $DIR_SRC/heirloom-toolchest/diff .
# NOTE: For some reason, symbols are defined in a header file without an
#       "extern" modifier, so this patch fixes the duplicate symbols that occur
#       as a result of using modern compilers and linkers. ~ahill
patch -p1 < $DIR_PATCH/diff-extern.patch
# NOTE: These Makefiles are strange. Now it's CFLAGS2 for CFLAGS, and ICOMMON
#       and LCOMMON must be defined to point to where the library lives. On top
#       of that, LD is replaced with CC because it refuses to link the C runtime
#       otherwise. ~ahill
CFLAGS2="-static" ICOMMON="-I../libcommon" LCOMMON="../libcommon/libcommon.a" \
    LD="$CC" make -C diff -f Makefile.mk -O -j $JOBS
cp diff/diff $DIR_MAPLE/bin/
cp diff/diff.1 $DIR_MAPLE/share/man/man1/
$CC -Ilibcommon -static $DIR_SRC/heirloom-toolchest/diff3/diff3prog.c \
    libcommon/libcommon.a -o $DIR_MAPLE/lib/diff3prog
cp $DIR_SRC/heirloom-toolchest/diff3/diff3.1 $DIR_MAPLE/share/man/man1/
# TODO: What the heck is @SV3BIN@ supposed to be? ~ahill
echo "#!/bin/sh" | cat - $DIR_SRC/heirloom-toolchest/diff3/diff3.sh \
    | sed "s|@DEFBIN@|/bin|;s|@DEFLIB@|/lib|;s|@SV3BIN@:||" \
    > $DIR_MAPLE/bin/diff3
chmod +x $DIR_MAPLE/bin/diff3
$CC -Ilibcommon -static $DIR_SRC/heirloom-toolchest/sdiff/sdiff.c \
    libcommon/libcommon.a -o $DIR_MAPLE/bin/sdiff
cp $DIR_SRC/heirloom-toolchest/sdiff/sdiff.1 $DIR_MAPLE/share/man/man1/

# Build and install xz
mkdir -p $DIR_BUILD/build-xz
cd $DIR_BUILD/build-xz
# NOTE: Curse you auto-generating build scripts! ~ahill
cp -r $DIR_SRC/xz/* .
./autogen.sh --no-po4a
# TODO: Is sysroot even required if the compiler is told to use the sysroot
#       anyways? ~ahill
CFLAGS="--sysroot=$DIR_MAPLE" ./configure \
    --enable-year2038 \
    --build=$(build-aux/config.guess) \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
CFLAGS="--sysroot=$DIR_MAPLE" make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install awk
mkdir -p $DIR_BUILD/build-awk
cd $DIR_BUILD/build-awk
# NOTE: I'm sensing a pattern here, but there's no out of tree build. ~ahill
cp -r $DIR_SRC/awk/* .
# NOTE: Awk's Makefile makes a few assumptions about the build environment, so I
#       told it to use the actual cross-compiler and byacc in place of bison.
#       Outside of the selection of tools, CFLAGS is shared between CC and
#       HOSTCC, which seems like a bad idea since I need to pass --sysroot.
#       ~ahill
make -O -j $JOBS CC="$CC -static --sysroot=$DIR_MAPLE" YACC="byacc -d -b awkgram"
# NOTE: There's no make install target in this case, so I hope I'm doing this
#       correctly. ~ahill
cp a.out $DIR_MAPLE/bin/awk
mkdir -p $DIR_MAPLE/share/man/man1
cp awk.1 $DIR_MAPLE/share/man/man1/

# Build and install byacc
mkdir -p $DIR_BUILD/build-byacc
cd $DIR_BUILD/build-byacc
# NOTE: Despite being based on autotools, this script gave no static or sysroot
#       options, so I have to pass stuff via CFLAGS. ~ahill
CFLAGS="-static --sysroot=$DIR_MAPLE" $DIR_SRC/byacc/configure \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
CFLAGS="-static --sysroot=$DIR_MAPLE" make -O -j $JOBS
# NOTE: I don't like software pretending to be something else unless it's for
#       compatibility, so byacc will actually be called byacc and yacc should be
#       a symlink. ~ahill
cp yacc $DIR_MAPLE/bin/byacc
ln -s byacc $DIR_MAPLE/bin/yacc

# Build and install m4
mkdir -p $DIR_BUILD/build-m4
cd $DIR_BUILD/build-m4
# NOTE: Technically, m4 supports building outside of the source tree, but the
#       configure script was never committed. Therefore, the configure script
#       must be created to build the software. The source tree is copied here to
#       keep DIR_SRC immutable. ~ahill
cp -r $DIR_SRC/m4/* .
# NOTE: The bootstrap script will attempt to pull the sources from the network,
#       which is something I want to avoid. A pure bootstrap doesn't need to
#       reach out to *any* server for *anything*. ~ahill
./bootstrap --gnulib-srcdir=$DIR_SRC/gnulib --skip-git --skip-po
# NOTE: Once again, static and sysroot are not options here. ~ahill
CFLAGS="-static --sysroot=$DIR_MAPLE" ./configure \
    --enable-year2038 \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
CFLAGS="-static --sysroot=$DIR_MAPLE" make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install make
mkdir -p $DIR_BUILD/build-make
cd $DIR_BUILD/build-make
# NOTE: Like a lot of GNU software, the configure script needs to be
#       bootstrapped. ~ahill
cp -r $DIR_SRC/make/* .
./bootstrap --gen --gnulib-srcdir=$DIR_SRC/gnulib --no-git --skip-po
patch -p1 < $DIR_PATCH/make-maple.patch
# NOTE: Configure doesn't give static and sysroot as options! ~ahill
CFLAGS="-static --sysroot=$DIR_MAPLE" ./configure \
    --build=$(build-aux/config.guess) \
    --enable-year2038 \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
CFLAGS="-static --sysroot=$DIR_MAPLE" make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install bc
mkdir -p $DIR_BUILD/build-bc
cd $DIR_BUILD/build-bc
# NOTE: bc does not respect the prefix when installing locales, so locales are
#       disabled to prevent bc from violating the filesystem heirarchy. ~ahill
CFLAGS="-static" $DIR_SRC/bc/configure \
    --disable-nls \
    --enable-internal-history \
    --includedir /share/include \
    --prefix /
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install lex
mkdir -p $DIR_BUILD/build-lex
cd $DIR_BUILD/build-lex
# NOTE: This is old enough that I'll be impressed if it works. Who cares if it
#       doesn't support out of tree builds, it builds! ~ahill
cp -r $DIR_SRC/heirloom-devtools/lex/* .
# NOTE: For some reason, the Makefile doesn't do this part. ~ahill
$YACC parser.y -o parser.c
# NOTE: LIBDIR *must* be defined here because it's compiling the path into the
#       executable. ~ahill
CFLAGS="-static --sysroot=$DIR_MAPLE" \
    make -f Makefile.mk -O -j $JOBS LIBDIR=/share
# NOTE: make install wants to do some strange things so I'm installing this
#       manually. ~ahill
cp lex $DIR_MAPLE/bin/
mkdir -p $DIR_MAPLE/share/lex
cp nceucform $DIR_MAPLE/share/lex/
cp ncform $DIR_MAPLE/share/lex/
cp nrform $DIR_MAPLE/share/lex/
mkdir -p $DIR_MAPLE/share/man/man1
cp lex.1 $DIR_MAPLE/share/man/man1/
# FIXME: Is there a way to make this a shared library so the CDDL license does
#        not accidentally conflict other licenses such as GPL? ~ahill
#cp libl.a $DIR_MAPLE/lib/

# TODO: Build and install autoconf

# TODO: Build and install automake

# TODO: Build and install libtool
# TODO: Would slibtool be a better fit? ~ahill

# TODO: Build and install Perl

# TODO: Build and install git

# Build and install MPIR
mkdir -p $DIR_BUILD/build-mpir
cd $DIR_BUILD/build-mpir
# NOTE: Yet another repository that needs a configure script. ~ahill
cp -r $DIR_SRC/mpir/* .
./autogen.sh
# NOTE: Some of the tests fail because they assume that a function without a
#       return type returns an int, which causes an error. Something is probably
#       passing -Werror, converting it from a warning into an error. Passing
#       -Wno-implicit-int to remedy this. ~ahill
# NOTE: Some tests include implicit functions, which cause errors. Passing
#       -Wno-implicit-function-declaration to fix that as well. ~ahill
# TODO: Is there a way to build MPIR without YASM? ~ahill
CFLAGS="-Wno-implicit-function-declaration -Wno-implicit-int" ./configure \
    --build=$(./config.guess) \
    --disable-static \
    --enable-gmpcompat \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --with-sysroot=$DIR_MAPLE
make -O -j $JOBS
# NOTE: For some reason, the Makefile completely ignores includedir and decides
#       to do its own thing instead. To prevent it from installing to /include,
#       includeexecdir is passed to force the headers to be installed in the
#       correct location. ~ahill
make -O -j $JOBS install DESTDIR=$DIR_MAPLE includeexecdir="/share/include"

# Build and install MPFR
mkdir -p $DIR_BUILD/build-mpfr
cd $DIR_BUILD/build-mpfr
# NOTE: Yet another repository that needs a configure script. ~ahill
cp -r $DIR_SRC/mpfr/* .
./autogen.sh
# FIXME: For some reason, libgcc doesn't have the necessary decimal float
#        functions MPFR requires. Passing --disable-decimal-float for now, but
#        this should be investigated. ~ahill
./configure \
    --build=$(./config.guess) \
    --disable-decimal-float \
    --disable-static \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --with-sysroot=$DIR_MAPLE
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install MPC
mkdir -p $DIR_BUILD/build-mpc
cd $DIR_BUILD/build-mpc
# NOTE: This repository doesn't contain a configure OR an autogen.sh script, so
#       I'm doing this from scratch. ~ahill
cp -r $DIR_SRC/mpc/* .
autoreconf -i
./configure \
    --build=$(./config.guess) \
    --disable-static \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --with-sysroot=$DIR_MAPLE
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install libstdc++
mkdir -p $DIR_BUILD/build-libstdc++
cd $DIR_BUILD/build-libstdc++
# NOTE: Even though this is GPL-licensed, I'm building the static version of
#       libstdc++ because it seems to fall under either LGPL or the GCC RUNTIME
#       LIBRARY EXCEPTION, found under COPYING.LIB and COPYING.RUNTIME
#       respectively. In theory, this means there is no licensing violation from
#       accidentally linking this statically. ~ahill
$DIR_SRC/gcc/libstdc++-v3/configure \
    --build=$($DIR_SRC/gcc/config.guess) \
    --disable-libstdcxx-pch \
    --disable-multilib \
    --disable-nls \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --with-gcc-major-version-only \
    --with-gxx-include-dir=/maple/tools/$TARGET/include/c++/16
make -O -j $(nproc)
make -O -j $(nproc) install DESTDIR=$DIR_MAPLE

# Clean libtool files since they are harmful for cross-compilation
find $DIR_MAPLE/lib -type f -name "*.la" -delete

# Build and install binutils
mkdir -p $DIR_BUILD/build-binutils
cd $DIR_BUILD/build-binutils
# NOTE: binutils can handle out of tree builds, but there's apparently a
#       *slight* API incompatibility with struct termios that prevents
#       gdb/ser-unix.c from building properly under musl. ~ahill
cp -r $DIR_SRC/binutils-gdb/. .
#patch -p1 < $DIR_PATCH/gdb-musl-compat.patch
# FIXME: gdb requires readline to function, which is not installed right now.
#        I'll have to revisit this later. ~ahill
./configure \
    --build=$(./config.guess) \
    --disable-gdb \
    --disable-gdbserver \
    --disable-static \
    --enable-year2038 \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --target=$TARGET \
    --with-build-sysroot=$DIR_MAPLE \
    --with-gcc-major-version-only
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# TODO: Build and install (nasm? yasm?)

# Build and install gcc
# FIXME: Why does this segfault? ~ahill
mkdir -p $DIR_BUILD/build-gcc
cd $DIR_BUILD/build-gcc
# NOTE: Technically, gcc supports an out-of-tree build, but GCC doesn't conform
#       to Maple Linux's filesystem hierarchy and installs libraries like
#       libstdc++ under /lib64 instead of /lib. To fix this, the cross-compiler
#       itself needs to be patched since autoconf follows gcc's lead. ~ahill
cp -r $DIR_SRC/gcc/. .
# NOTE: Credit to Linux From Scratch for this patch. It would have taken me a
#       long time to figure this one out otherwise. ~ahill
# TODO: Will similar patches be required for other architectures? ~ahill
sed -i "/m64=/s/lib64/lib/" gcc/config/i386/t-linux64
# NOTE: gcc makes some assumptions about the directory structure due to the way
#       relative paths are coded. A successful build requires a subdirectory so
#       the parts of the build script that use "../.." can get back to the root
#       of the source code. ~ahill
mkdir build-within-a-build
cd build-within-a-build
# NOTE: LDFLAGS_FOR_TARGET is specified here since the libgcc in $DIR_MAPLE is
#       insufficient for C++ to function properly. This forces it to link with
#       the new libgcc it just built. ~ahill
LDFLAGS_FOR_TARGET="-L$(pwd)/$TARGET/libgcc" ../configure \
    --build=$(../config.guess) \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libvtv \
    --disable-multilib \
    --disable-nls \
    --enable-default-pie \
    --enable-default-ssp \
    --enable-languages=c,c++ \
    --enable-year2038 \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix=/ \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --target=$TARGET \
    --with-build-sysroot=$DIR_MAPLE \
    --with-gcc-major-version-only \
    --with-native-system-header-dir=/share/include
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_MAPLE"
ln -s gcc $DIR_MAPLE/bin/cc

# TODO: Prepare the image
