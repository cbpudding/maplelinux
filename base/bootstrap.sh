#!/bin/sh -e

# Define the build environment
export DIR_BASE=$(realpath $(dirname $0))
# NOTE: This is to make it easier to replicate the environment for
#       troubleshooting purposes. Under normal circumstances, this line is never
#       run, but I can ignore the pound sign when I copy the text so I can
#       simply paste it into the console. Might benefit others besides myself
#       too. :) ~ahill
#export DIR_BASE=$(pwd)
export DIR_BUILD=$DIR_BASE/build
export DIR_MAPLE=$DIR_BASE/maple
export DIR_PATCH=$DIR_BASE/patch
export DIR_SRC=$DIR_BASE/src
export DIR_TOOLS=$DIR_MAPLE/maple/tools

export CC=${CC:-cc}
export JOBS=${JOBS:-$(nproc)}
export LANG=C
export LC_ALL=C
export LEX=$(which flex)
export TARGET=${TARGET:-x86_64-maple-linux-musl}
export YACC=$(which byacc || which bison)

[ -z "$LEX" ] && (echo "flex is not installed. Please install flex or a compatible program and try again."; exit 1)
[ -z "$YACC" ] && (echo "byacc is not installed. Please install byacc or a compatible program and try again."; exit 1)

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
# NOTE: binutils requires texinfo to build documentation, with no way to disable
#       documentation from the configure script. As a workaround, MAKEINFO is
#       set to "true" so it runs the true command in its place, effectively
#       disabling documentation. At some point, this approach will be
#       re-considered, but it is not necessary for a successful bootstrap.
#       ~ahill
make -O -j $JOBS MAKEINFO=true
make -O -j $JOBS install MAKEINFO=true

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
    --disable-shared \
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
    --with-gmp=$DIR_SRC/gmp \
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

# Build a native copy of mapleconf for later use
# FIXME: How to prevent issues with runtime dependencies such as lua-cjson
#        during the bootstrap? ~ahill
$CC -o "$DIR_TOOLS/mapleconf" \
    -I $DIR_SRC/tomlc17/src \
    $DIR_SRC/mapleconf/mapleconf.c \
    $DIR_SRC/tomlc17/src/tomlc17.c \
    -llua

# Re-define the build environment to use the new tools
export AR="$TARGET-ar"
export AS="$TARGET-as"
export CC="$TARGET-gcc"
export CPP="$TARGET-cpp"
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
cp -r $DIR_SRC/toybox/. .
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
cp -r $DIR_SRC/hummingbird/. .
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
cp -r $DIR_SRC/skalibs/. .
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
cp -r $DIR_SRC/mdevd/. .
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
cp -a $DIR_SRC/ndhc/. .
CFLAGS="-static --sysroot=$DIR_MAPLE" make -j $JOBS
cp ndhc $DIR_MAPLE/bin/
mkdir -p $DIR_MAPLE/share/man/man8
cp ndhc.8 $DIR_MAPLE/share/man/man8/

# Build and install chrony
mkdir -p $DIR_BUILD/build-chrony
cd $DIR_BUILD/build-chrony
# NOTE: Out of tree builds for chrony are broken. ~ahill
cp -r $DIR_SRC/chrony/. .
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
$YACC -o expr.c $DIR_SRC/heirloom-toolchest/expr/expr.y
$CC -Ilibcommon -static expr.c libcommon/libcommon.a -o $DIR_MAPLE/bin/expr
cp $DIR_SRC/heirloom-toolchest/expr/expr.1 $DIR_MAPLE/share/man/man1/
$CC -Ilibcommon -static $DIR_SRC/heirloom-toolchest/sdiff/sdiff.c \
    libcommon/libcommon.a -o $DIR_MAPLE/bin/sdiff
cp $DIR_SRC/heirloom-toolchest/sdiff/sdiff.1 $DIR_MAPLE/share/man/man1/
$CC -Ilibcommon -static $DIR_SRC/heirloom-toolchest/tr/tr.c \
    libcommon/libcommon.a -o $DIR_MAPLE/bin/tr
cp $DIR_SRC/heirloom-toolchest/tr/tr.1 $DIR_MAPLE/share/man/man1/
# TODO: What exactly is man1b for? ~ahill

# Build and install xz
mkdir -p $DIR_BUILD/build-xz
cd $DIR_BUILD/build-xz
# NOTE: Curse you auto-generating build scripts! ~ahill
cp -r $DIR_SRC/xz/. .
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
cp -r $DIR_SRC/awk/. .
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
cp -r $DIR_SRC/m4/. .
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
cp -r $DIR_SRC/make/. .
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

# Build and install flex
mkdir $DIR_BUILD/build-flex
cd $DIR_BUILD/build-flex
# NOTE: Copying the source tree to the build folder since there's no configure
#       script available. ~ahill
cp -r $DIR_SRC/flex/. .
# NOTE: Flex 2.6.4 is almost a decade old, and 2.6.5 hasn't been released yet.
#       Since modern compilers don't like definitions without arguments, this
#       commit is being backported from upstream. ~ahill
patch -p1 < $DIR_PATCH/flex-malloc.patch
./autogen.sh
# TODO: Is libfl needed? ~ahill
./configure \
    --build=$(./build-aux/config.guess) \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --with-sysroot="$DIR_MAPLE"
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_MAPLE"

# Build and install Perl
mkdir -p $DIR_BUILD/build-perl
cd $DIR_BUILD/build-perl
# NOTE: Perl doesn't have the ability to properly cross-compile itself, so
#       perl-cross is used to make that possible. ~ahill
cp -r $DIR_SRC/perl/. .
# NOTE: Perl makes some crazy assumptions about the system. Who would ever want
#       to put header files under /usr/include? /s ~ahill
patch -p1 < $DIR_PATCH/perl-maple.patch
cp -r $DIR_SRC/perl-cross/. .
# TODO: Is it necessary to put the full Perl version in the archlib/privlib path
#       if the system is built as a single artifact? ~ahill
# NOTE: perl-cross tests for non-standard functions such as memrchr, which only
#       exists on musl if _GNU_SOURCE is defined. When perl-cross runs tests, it
#       always adds a "#define _GNU_SOURCE", but the Perl source code doesn't.
#       As a result, compilation fails due to undefined functions. Manually
#       passing -D_GNU_SOURCE fixes this. ~ahill
CFLAGS="$CFLAGS -D_GNU_SOURCE" ./configure \
    --build=$(./cnf/config.guess) \
    -Darchlib=/lib/perl5 \
    -Dbin=/bin \
    -Dprivlib=/share/perl5 \
    -Dscriptdir=/bin \
    -Dusrinc=/share/include \
    --html1dir=/share/doc/perl/html/man1 \
    --html3dir=/share/doc/perl/html/man3 \
    --man1dir=/share/man/man1 \
    --man3dir=/share/man/man3 \
    --prefix=/ \
    --sysroot="$DIR_MAPLE" \
    --target=$TARGET
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install autoconf
mkdir -p $DIR_BUILD/build-autoconf
cd $DIR_BUILD/build-autoconf
# NOTE: Since there is no configure script, the project needs to be
#       bootstrapped, which requires a mutable source tree to accomplish. ~ahill
cp -r $DIR_SRC/autoconf/. .
./bootstrap
# NOTE: PERL is manually set here so autoconf knows where to look on Maple Linux
#       and *not* the build system. ~ahill
PERL="/bin/perl" ./configure \
    --build=$(./config.guess) \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install automake
# FIXME: Point to /bin/perl for the interpreter instead of the host system's
#        path. ~ahill
mkdir -p $DIR_BUILD/build-automake
cd $DIR_BUILD/build-automake
# NOTE: Since there is no configure script, the project needs to be
#       bootstrapped, which requires a mutable source tree to accomplish. ~ahill
cp -r $DIR_SRC/automake/. .
./bootstrap
# NOTE: PERL is manually set here so automake knows where to look on Maple Linux
#       and *not* the build system. ~ahill
PERL="/bin/perl" ./configure \
    --build=$(./config.guess) \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install slibtool
mkdir -p $DIR_BUILD/build-slibtool
cd $DIR_BUILD/build-slibtool
# NOTE: This isn't using autoconf/automake, so I'm not sure what the default
#       values of the variables are. Might as well define everything to be sure.
#       ~ahill
$DIR_SRC/slibtool/configure \
    --all-static \
    --bindir=/bin \
    --build=$(cc -dumpmachine) \
    --docdir=/share/doc \
    --exec-prefix="" \
    --host=$TARGET \
    --includedir=/share/include \
    --libdir=/lib \
    --libexecdir=/lib \
    --localedir=/share/locale \
    --mandir=/share/man \
    --oldincludedir=/share/include \
    --prefix="" \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --sysconfdir=/etc \
    --sysroot="$DIR_MAPLE"
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE
ln -s slibtoolize $DIR_MAPLE/bin/libtoolize

# Build and install Sortix libz (Not zlib!)
mkdir -p $DIR_BUILD/build-libz
cd $DIR_BUILD/build-libz
$DIR_SRC/libz/configure \
    --eprefix="" \
    --includedir=/share/include \
    --libdir=/lib \
    --prefix="" \
    --sharedlibdir=/lib
make -O -j $JOBS
make -O -j $JOBS install DESTDIR=$DIR_MAPLE

# Build and install git
mkdir -p $DIR_BUILD/build-git
cd $DIR_BUILD/build-git
# NOTE: There's no way to configure git outside of the Makefile, so I'm copying
#       the source tree here. ~ahill
cp -r $DIR_SRC/git/. .
# NOTE: Tools like AR, CC, LD, OBJCOPY, and STRIP are manually passed to the
#       Makefile because they are assigned with "=" instead of "?=". ~ahill
make -O -j $JOBS install \
    gitexecdir=lib/git-core \
    prefix="" \
    AR="$AR" \
    CC="$CC" \
    DESTDIR="$DIR_MAPLE" \
    HOST_CPU=$(echo $TARGET | cut -d"-" -f1) \
    LD="$LD" \
    NO_CURL=YesPlease \
    NO_EXPAT=YesPlease \
    NO_GETTEXT=YesPlease \
    NO_GITWEB=YesPlease \
    NO_ICONV=YesPlease \
    NO_OPENSSL=YesPlease \
    NO_PERL=YesPlease \
    NO_PYTHON=YesPlease \
    NO_REGEX=NeedsStartEnd \
    NO_RUST=YesPlease \
    NO_TCLTK=YesPlease \
    OBJCOPY="$OBJCOPY" \
    STRIP="$STRIP"

# Build and install GMP
mkdir -p $DIR_BUILD/build-gmp
cd $DIR_BUILD/build-gmp
# NOTE: GMP needs to be bootstrapped, so the source tree is copied to the build
#       directory to keep the "immutable source tree" rule. ~ahill
cp -r $DIR_SRC/gmp/. .
./.bootstrap
# NOTE: GMP's tests are ancient and the assumptions it makes cause modern
#       compilers to choke. Passing -std=gnu99 tells it to use historical
#       behaviors for the C compiler rather than modern behaviors. ~ahill
CFLAGS="-std=gnu99" ./configure \
    --build=$(./config.guess) \
    --disable-static \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --with-sysroot="$DIR_MAPLE"
make -O -j $JOBS
# NOTE: Silly GMP, $exec_prefix/include is not valid here. Use the normal
#       include directory like a sane package. ~ahill
make -O -j $JOBS install DESTDIR="$DIR_MAPLE" includeexecdir=/share/include

# Build and install MPFR
mkdir -p $DIR_BUILD/build-mpfr
cd $DIR_BUILD/build-mpfr
# NOTE: Yet another repository that needs a configure script. ~ahill
cp -r $DIR_SRC/mpfr/. .
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
    --with-sysroot="$DIR_MAPLE"
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_MAPLE"

# Build and install MPC
mkdir -p $DIR_BUILD/build-mpc
cd $DIR_BUILD/build-mpc
# NOTE: This repository doesn't contain a configure OR an autogen.sh script, so
#       I'm doing this from scratch. ~ahill
cp -r $DIR_SRC/mpc/. .
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
    --with-sysroot="$DIR_MAPLE"
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_MAPLE"

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
make -O -j $(nproc) install DESTDIR="$DIR_MAPLE"

# Clean libtool files since they are harmful for cross-compilation
find $DIR_MAPLE/lib -type f -name "*.la" -delete

# Build and install binutils
# FIXME: How can I prevent binutils from making a /$TARGET folder? ~ahill
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
    --with-build-sysroot="$DIR_MAPLE" \
    --with-gcc-major-version-only
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_MAPLE"

# Build and install gcc
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
# NOTE: I *may* have discovered a gcc bug, where building with --libexecdir=/lib
#       causes make_relative_prefix to return NULL, crashing the program later,
#       while building with --libexecdir=/lib/ works. WHY?!? ~ahill
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
    --enable-shared \
    --enable-year2038 \
    --host=$TARGET \
    --includedir=/share/include \
    --libexecdir=/lib/ \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --target=$TARGET \
    --with-build-sysroot=$DIR_MAPLE \
    --with-gcc-major-version-only \
    --with-native-system-header-dir=/share/include \
    --with-sysroot=/
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_MAPLE"
ln -s gcc $DIR_MAPLE/bin/cc

# Build and install tomlc17
mkdir -p $DIR_BUILD/build-tomlc17
cd $DIR_BUILD/build-tomlc17
# NOTE: The source tree needs to be copied to preserve source immutability.
#       ~ahill
cp -r $DIR_SRC/tomlc17/. .
# NOTE: We don't need all of the library, and bootstrapping the other parts of
#       the library gets messy with the bootstrap toolchain. ~ahill
make -C src -O -j $JOBS
cp src/libtomlc17.a $DIR_MAPLE/lib/
cp src/tomlc17.h $DIR_MAPLE/share/include/
cp src/tomlcpp.hpp $DIR_MAPLE/share/include/

# Build and install Lua
mkdir -p $DIR_BUILD/build-lua
cd $DIR_BUILD/build-lua
# NOTE: Lua is an old-school Makefile that doesn't support out of tree builds,
#       so the source code is copied here to keep the source code immutable.
#       ~ahill
cp -r $DIR_SRC/lua/. .
# NOTE: LUA_ROOT defaults to /usr/local, which is not what I want. ~ahill
sed -i "/#define LUA_ROOT/s|/usr/local/|/|" luaconf.h
# NOTE: Lua ignores the CC environment variable, so it's declared here. ~ahill
# NOTE: Lua objects are built with -fPIC so it can be linked into a shared
#       library later on. ~ahill
# NOTE: LUA_USE_DLOPEN and LUA_USE_POSIX are defined individually instead of
#       using LUA_USE_LINUX, since that will also try to link with readline in
#       some cases. If readline becomes a requirement for something else, I may
#       change this to make Lua nicer to use overall. ~ahill
make -O -j $JOBS CC=$CC CFLAGS="-DLUA_USE_DLOPEN -DLUA_USE_POSIX -fPIC"
# NOTE: Here's an ugly hack to build a shared library. ~ahill
$CC -shared -fPIC -o $DIR_MAPLE/lib/liblua.so *.o -lm
# NOTE: Lua's Makefile does not have an install target. Is this correct? ~ahill
cp lauxlib.h $DIR_MAPLE/share/include/
cp lua.h $DIR_MAPLE/share/include/
cp luaconf.h $DIR_MAPLE/share/include/
cp lualib.h $DIR_MAPLE/share/include/
cp liblua.a $DIR_MAPLE/lib/
cp lua $DIR_MAPLE/bin/
# NOTE: For some reason, git doesn't have lua.hpp, so I made my own. ~ahill
cp $DIR_PATCH/lua.hpp $DIR_MAPLE/share/include/
# TODO: Is luac required? If so, how is it built? ~ahill

# Build and install LuaDate
mkdir -p $DIR_BUILD/build-luadate
cd $DIR_BUILD/build-luadate
# NOTE: There's no real install here. Just copy the file. ~ahill
mkdir -p $DIR_MAPLE/share/lua/5.5
cp $DIR_SRC/luadate/src/date.lua $DIR_MAPLE/share/lua/5.5/

# Build and install Lua CJSON
mkdir -p $DIR_BUILD/build-lua-cjson
cd $DIR_BUILD/build-lua-cjson
# NOTE: This uses a Makefile that manipulates the source tree. Copying the
#       source tree to preserve immutability of DIR_SRC. ~ahill
cp -r $DIR_SRC/lua-cjson/. .
make -O -j $JOBS
# NOTE: Just copying the library because it's easier than setting all of the
#       Makefile variables properly. ~ahill
mkdir -p $DIR_MAPLE/lib/lua/5.5
cp cjson.so $DIR_MAPLE/lib/lua/5.5/

# Build and install liquid.lua
mkdir -p $DIR_BUILD/build-liquid-lua
cd $DIR_BUILD/build-liquid-lua
# NOTE: There's no real install here. Just copy the file. ~ahill
mkdir -p $DIR_MAPLE/share/lua/5.5
cp $DIR_SRC/liquid-lua/lib/liquid.lua $DIR_MAPLE/share/lua/5.5/

# Build and install mapleconf
mkdir -p $DIR_BUILD/build-mapleconf
cd $DIR_BUILD/build-mapleconf
# TODO: Does this even need to have a build directory? ~ahill
$CC -o $DIR_MAPLE/bin/mapleconf \
    $DIR_SRC/mapleconf/mapleconf.c \
    -llua -ltomlc17
mkdir -p $DIR_MAPLE/share/mapleconf
cp $DIR_BASE/maple.toml $DIR_MAPLE/etc/

# Prepare the image
cd $DIR_MAPLE
#$DIR_TOOLS/mapleconf \
#    -c "$DIR_BASE/maple.toml" \
#    -r "$DIR_MAPLE" \
#    -t "$DIR_MAPLE/share/mapleconf"
#rm -rf $DIR_MAPLE/maple
#tar cJf ../base-$(date +%Y%m%d%H%M).txz *
