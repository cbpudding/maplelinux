#!/bin/sh -e

# Define the build environment
export DIR_BASE=$(pwd)
export DIR_BUILD=$DIR_BASE/build
export DIR_MAPLE=$DIR_BASE/maple
export DIR_PATCH=$DIR_BASE/patch
export DIR_SRC=$DIR_BASE/src
export DIR_TOOLS=$DIR_MAPLE/maple/tools
export TARGET=${TARGET:-x86_64-maple-linux-musl}

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
    --disable-gdb \
    --disable-gprofng \
    --disable-nls \
    --disable-werror \
    --enable-year2038 \
    --includedir=$DIR_TOOLS/share/include \
    --libexecdir=$DIR_TOOLS/lib \
    --localstatedir=$DIR_TOOLS/etc \
    --oldincludedir=$DIR_TOOLS/share/include \
    --prefix=$DIR_TOOLS \
    --sbindir=$DIR_TOOLS/bin \
    --sharedstatedir=$DIR_TOOLS/etc \
    --target=$TARGET \
    --with-sysroot=$DIR_MAPLE
make -O -j $(nproc)
make -O -j $(nproc) install

# Build the cross-compiler
mkdir -p $DIR_BUILD/cross-gcc
cd $DIR_BUILD/cross-gcc
# FIXME: For some reason, GCC fails to compile with --enable-year2038! ~ahill
$DIR_SRC/gcc/configure \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --enable-default-pie \
    --enable-default-ssp \
    --enable-languages=c,c++ \
    --includedir=$DIR_TOOLS/share/include \
    --libexecdir=$DIR_TOOLS/lib \
    --localstatedir=$DIR_TOOLS/etc \
    --oldincludedir=$DIR_TOOLS/share/include \
    --prefix=$DIR_TOOLS \
    --sbindir=$DIR_TOOLS/bin \
    --sharedstatedir=$DIR_TOOLS/etc \
    --target=$TARGET \
    --with-gcc-major-version-only \
    --with-native-system-header-dir=/share/include \
    --with-newlib \
    --with-sysroot=$DIR_MAPLE \
    --without-headers
make -O -j $(nproc)
make -O -j $(nproc) install

# Re-define the build environment to use the new tools
export AR="$DIR_TOOLS/bin/$TARGET-ar"
export AS="$DIR_TOOLS/bin/$TARGET-as"
export CC="$DIR_TOOLS/bin/$TARGET-gcc"
export CXX="$DIR_TOOLS/bin/$TARGET-g++"
export LD="$DIR_TOOLS/bin/$TARGET-ld"
export NM="$DIR_TOOLS/bin/$TARGET-nm"
export OBJCOPY="$DIR_TOOLS/bin/$TARGET-objcopy"
export OBJDUMP="$DIR_TOOLS/bin/$TARGET-objdump"
export RANLIB="$DIR_TOOLS/bin/$TARGET-ranlib"
export STRIP="$DIR_TOOLS/bin/$TARGET-strip"

# Install Linux headers
mkdir -p $DIR_BUILD/build-linux
cd $DIR_BUILD/build-linux
make -C $DIR_SRC/linux -j $(nproc) headers O=$(pwd)
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
make -O -j $(nproc)
make -O -j $(nproc) install DESTDIR=$DIR_MAPLE
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
make -O -j $(nproc)
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
make -O -j $(nproc)
make -O -j $(nproc) install DESTDIR=$DIR_MAPLE

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
make -O -j $(nproc)
make -O -j $(nproc) install DESTDIR=$DIR_MAPLE

# Build and install Linux
mkdir -p $DIR_BUILD/build-linux
cd $DIR_BUILD/build-linux
# TODO: Create a sane config for Maple Linux ~ahill
make -C $DIR_SRC/linux -j $(nproc) defconfig O=$(pwd)
make -C $DIR_SRC/linux -j $(nproc) O=$(pwd)
make -C $DIR_SRC/linux -j $(nproc) modules_install INSTALL_MOD_PATH=$DIR_MAPLE O=$(pwd)
cp $(make image_name) $DIR_MAPLE/boot/vmlinuz-$(make kernelrelease)
cp System.map $DIR_MAPLE/boot/System.map-$(make kernelrelease)
# NOTE: I have yet to test the following since I have only been testing on x86
#       so far. ~ahill
if make -C $DIR_SRC/linux -q dtbs > /dev/null 2>&1; then
    make -C $DIR_SRC/linux -j $(nproc) dtbs O=$(pwd)
    make -C $DIR_SRC/linux -j $(nproc) dtbs_install INSTALL_DTBS_PATH=$DIR_MAPLE O=$(pwd)
fi

# Build and install ndhc
mkdir -p $DIR_BUILD/build-ndhc
cd $DIR_BUILD/build-ndhc
# NOTE: ndhc does not support out-of-tree builds, so we copy the source here.
#       ~ahill
cp -r $DIR_SRC/ndhc/* .
CFLAGS="-static --sysroot=$DIR_MAPLE" make -j $(nproc)
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
CFLAGS="-static --sysroot=$DIR_MAPLE" make -j $(nproc)
make -j $(nproc) install DESTDIR=$DIR_MAPLE

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
make -O -j $(nproc) CC="$CC -static --sysroot=$DIR_MAPLE" YACC="byacc -d -b awkgram"
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
CFLAGS="-static --sysroot=$DIR_MAPLE" make -O -j $(nproc)
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
CFLAGS="-static --sysroot=$DIR_MAPLE" make -O -j $(nproc)
make -O -j $(nproc) install DESTDIR=$DIR_MAPLE

# TODO: Build and install autoconf

# TODO: Build and install automake

# TODO: Build and install diffutils

# TODO: Build and install flex

# TODO: Build and install libtool

# TODO: Build and install make

# TODO: Build and install muon

# TODO: Build and install Perl

# TODO: Build and install xz

# TODO: Build and install binutils

# TODO: Build and install gcc

# TODO: Decide on a gzip implementation
