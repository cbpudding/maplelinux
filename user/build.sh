#!/bin/sh -e

# NOTE: Keep track of where we are for troubleshooting purposes ~ahill
STEP() {
    if [ -t 1 ]; then
        printf "\e[1;7m==> %s\n\e[0m" "$1"
    else
        echo "==> $1"
    fi
}

# NOTE: Keep track of licenses for legal purposes ~ahill
preserve_copyright() {
    [ -z "$1" ] && (echo "Name not provided to preserve_copyright"; exit 1)
    _softwaredir="$DIR_UNION/share/copyright/$1"
    mkdir -p "$_softwaredir"
    shift
    cp "$@" "$_softwaredir"
}

STEP "Prepare the build environment"
export DIR_BASE="$(realpath "$(dirname $0)")"
export DIR_BUILD="$DIR_BASE/build"
export DIR_PATCH="$DIR_BASE/patch"
export DIR_SRC="$DIR_BASE/src"
export DIR_UNION="$DIR_BASE/union"
export DIR_USER="$DIR_BASE/user"
export DIR_WORK="$DIR_BASE/work"

export JOBS=${JOBS:-$(nproc)}
export LANG=C
export LC_ALL=C
export PKG_CONFIG_LIBDIR="$DIR_UNION/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$DIR_UNION"


STEP "Clean the build environment"
if mountpoint -q "$DIR_UNION"; then
    echo "DIR_UNION was not cleanly unmounted. Unmounting now."
    doas umount "$DIR_UNION"
fi

[ -d "$DIR_BUILD" ] && rm -rf "$DIR_BUILD"
mkdir -p "$DIR_BUILD"

[ -d "$DIR_UNION" ] && rm -rf "$DIR_UNION"
mkdir -p "$DIR_UNION"

[ -d "$DIR_USER" ] && rm -rf "$DIR_USER"
mkdir -p "$DIR_USER"

[ -d "$DIR_WORK" ] && rm -rf "$DIR_WORK"
mkdir -p "$DIR_WORK"


STEP "Mounting overlay"
doas mount -t overlay overlay "$DIR_UNION" -o lowerdir=/,upperdir="$DIR_USER",workdir="$DIR_WORK"


STEP "Build and install libexpat"
mkdir -p "$DIR_BUILD/build-libexpat"
cd "$DIR_BUILD/build-libexpat"
# NOTE: Need to copy the source tree to keep the original source intact ~ahill
cp -r "$DIR_SRC/libexpat/." .
preserve_copyright libexpat COPYING
cd expat
# NOTE: For some reason, buildconf.sh is a "bash" script, despite being POSIX
#       compliant. Fixing the interpreter path so this actually runs. ~ahill
sed -i 's|^#!.*|#!/bin/sh|' buildconf.sh
./buildconf.sh
./configure \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --without-examples \
    --without-tests
make -O -j $JOBS
doas make -O -j $JOBS install DESTDIR="$DIR_UNION" pkgconfigdir=/share/pkgconfig


STEP "Build and install libffi"
mkdir -p "$DIR_BUILD/build-libffi"
cd "$DIR_BUILD/build-libffi"
# NOTE: Need to copy the source tree to keep the original source intact ~ahill
cp -r "$DIR_SRC/libffi/." .
preserve_copyright libffi LICENSE LICENSE-BUILDTOOLS
# NOTE: zsh chokes on "fi fi", which prevents the configure script from running
#       properly. Should this be reported upstream? ~ahill
sed -i "s/fi fi/fi; fi/" m4/ax_enable_builddir.m4
# NOTE: Make ignores the pkgconfigdir I pass it because the Makefile calls
#       itself recursively, dropping command line arguments in the process. This
#       will take care of the problem at its source. ~ahill
sed -i 's|$(libdir)/pkgconfig|/share/pkgconfig|' Makefile.am
./autogen.sh
./configure \
    --disable-builddir \
    --disable-docs \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc
make -O -j $JOBS
doas make -O -j $JOBS install DESTDIR="$DIR_UNION"


STEP "Build and install Wayland"
preserve_copyright wayland "$DIR_SRC/wayland/COPYING"
# TODO: wayland.ini was created to map embed.py to /bin/true, avoiding Python.
#       Technically, -Ddtd_validation=false should avoid Python by itself, but
#       embed.py is still run, despite nothing using the header. The only
#       consumer I can find is scanner.c, and that appears to be unused since
#       HAVE_LIBXML isn't set. I should probably submit a bug report for this,
#       since most of the developers probably have Python, making the bug
#       invisible. ~ahill
muon -C "$DIR_SRC/wayland" setup \
    -Ddefault_library=both \
    -Ddocumentation=false \
    -Ddtd_validation=false \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dtests=false \
    -p native:"$DIR_PATCH/wayland.ini" \
    "$DIR_BUILD/build-wayland"
# NOTE: Wayland's build runs wayland-scanner, which dynamically links with
#       libraries that aren't a part of the system yet. To prevent a linking
#       error, LD_LIBRARY_PATH points at the lib directory $DIR_UNION to get
#       libraries that are part of the base and user sets. ~ahill
LD_LIBRARY_PATH="$DIR_UNION/lib" muon -C "$DIR_BUILD/build-wayland" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-wayland" install
# FIXME: Is there a way to get muon to write to /share/pkgconfig instead of
#        /lib/pkgconfig? It looks like Meson is considering this, and muon will
#        likely follow whatever they do. ~ahill
# See also: https://github.com/mesonbuild/meson/pull/6343
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install Pixman"
preserve_copyright pixman "$DIR_SRC/pixman/COPYING"
# NOTE: -Dgnu-inline-asm=disabled is foreshadowing a non-GNU C compiler. I have
#       not added it yet since I can't build the entire system with it as-is and
#       I don't want to maintain two C compilers simultaneously. ~ahill
# FIXME: For some reason, pixman's static libraries are missing symbols, likely
#        due to the vector instruction set switching. I'll have to test with
#        Meson to see whether this is a muon bug or a pixman bug. Pixman is
#        built as a shared library as a workaround. ~ahill
muon -C "$DIR_SRC/pixman" setup \
    -Ddefault_library=shared \
    -Ddemos=disabled \
    -Dgnu-inline-asm=disabled \
    -Dgtk=disabled \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlibpng=disabled \
    -Dlocalstatedir=etc \
    -Dopenmp=disabled \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dtests=disabled \
    "$DIR_BUILD/build-pixman"
muon -C "$DIR_BUILD/build-pixman" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-pixman" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install libxkbcommon"
preserve_copyright libxkbcommon "$DIR_SRC/libxkbcommon/LICENSE"
muon -C "$DIR_SRC/libxkbcommon" setup \
    -Ddefault_library=both \
    -Denable-bash-completion=false \
    -Denable-x11=false \
    -Denable-xkbregistry=false \
    -Denable-wayland=false \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dx-locale-root=/share/compose \
    -Dxkb-config-root=/share/xkb \
    "$DIR_BUILD/build-libxkbcommon"
muon -C "$DIR_BUILD/build-libxkbcommon" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-libxkbcommon" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install libudev-zero"
preserve_copyright libudev-zero "$DIR_SRC/libudev-zero/LICENSE"
# TODO: Inform libudev-zero of where usb.ids is eventually placed. ~ahill
muon -C "$DIR_SRC/libudev-zero" setup \
    -Ddefault_library=both \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    "$DIR_BUILD/build-libudev-zero"
muon -C "$DIR_BUILD/build-libudev-zero" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-libudev-zero" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install Python"
# TODO: I never wanted to install Python, but I can't get a graphical
#       environment in a reasonable amount of time unless I add it. A lot of
#       scripts will likely need to be replaced, starting with libevdev's
#       make-event-name.py. ~ahill
# NOTE: This is pinned at Python 3.9.25 because future versions don't support
#       LibreSSL. ~ahill
# See also: https://peps.python.org/pep-0644/
mkdir -p "$DIR_BUILD/build-cpython"
cd "$DIR_BUILD/build-cpython"
"$DIR_SRC/cpython/configure" \
    --enable-optimizations \
    --includedir=/share/include \
    --libexecdir=/lib \
    --localstatedir=/etc \
    --oldincludedir=/share/include \
    --prefix="" \
    --runstatedir=/tmp \
    --sbindir=/bin \
    --sharedstatedir=/etc \
    --without-ensurepip
# NOTE: Python runs into the same "fi fi" bug libffi did. Refer to that for more
#       information. ~ahill
sed -i 's/fi \\/fi; \\/' Makefile
make -O -j $JOBS
make -O -j $JOBS install DESTDIR="$DIR_UNION"
# Bad Python! Bad! ~ahill
mkdir -p "$DIR_UNION/share/include/python3.9"
mv "$DIR_UNION/include/python3.9"/* "$DIR_UNION/share/include/python3.9/"
rm -rf "$DIR_UNION/include"


STEP "Build and install libevdev"
preserve_copyright libevdev "$DIR_SRC/libevdev/COPYING"
mkdir -p "$DIR_BUILD/build-libevdev"
cd "$DIR_BUILD/build-libevdev"
echo "[binaries]" > libevdev.ini
echo "libevdev/make-event-names.py = ['$DIR_UNION/bin/python3.9', '$DIR_SRC/libevdev/libevdev/make-event-names.py']" >> libevdev.ini
muon -C "$DIR_SRC/libevdev" setup \
    -Ddefault_library=both \
    -Ddocumentation=disabled \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dtests=disabled \
    -p cross:"$DIR_BUILD/build-libevdev/libevdev.ini" \
    "$DIR_BUILD/build-libevdev"
muon -C "$DIR_BUILD/build-libevdev" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-libevdev" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install libinput"
preserve_copyright libinput "$DIR_SRC/libinput/COPYING"
# NOTE: libinput's -pedantic build fails because musl's headers contains
#       warnings, which is fatal with -Werror. This is due to the
#       PKG_CONFIG_SYSROOT_DIR variable being set, causing GCC to treat musl's
#       headers as project headers instead of system headers. Setting --sysroot
#       fixes this behavior. ~ahill
CFLAGS="--sysroot=\"$DIR_UNION\"" muon -C "$DIR_SRC/libinput" setup \
    -Ddebug-gui=false \
    -Ddefault_library=both \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlibwacom=false \
    -Dlocalstatedir=etc \
    -Dmtdev=false \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dtests=false \
    "$DIR_BUILD/build-libinput"
muon -C "$DIR_BUILD/build-libinput" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-libinput" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install libdrm"
# TODO: I think this is the first case I've seen where a project doesn't keep a
#       central COPYING or LICENSE file. Not sure what to do here. ~ahill
# NOTE: PATH is temporarily set so libdrm can find Python. ~ahill
PATH="$DIR_UNION/bin:$PATH" muon -C "$DIR_SRC/libdrm" setup \
    -Damdgpu=disabled \
    -Dcairo-tests=disabled \
    -Ddefault_library=both \
    -Detnaviv=disabled \
    -Dexynos=disabled \
    -Dfreedreno=disabled \
    -Dincludedir=share/include \
    -Dintel=disabled \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dman-pages=disabled \
    -Dnouveau=disabled \
    -Domap=disabled \
    -Dprefix=/ \
    -Dradeon=disabled \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dtegra=disabled \
    -Dvalgrind=disabled \
    -Dvc4=disabled \
    -Dvmwgfx=disabled \
    "$DIR_BUILD/build-libdrm"
muon -C "$DIR_BUILD/build-libdrm" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-libdrm" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install libdisplay-info"
preserve_copyright libdisplay-info "$DIR_SRC/libdisplay-info/LICENSE"
mkdir -p "$DIR_BUILD/build-libdisplay-info"
cd "$DIR_BUILD/build-libdisplay-info"
echo "[binaries]" > libdisplay-info.ini
echo "tool/gen-search-table.py = ['$DIR_UNION/bin/python3.9', '$DIR_SRC/libdisplay-info/tool/gen-search-table.py']" >> libdisplay-info.ini
# NOTE: wrap_mode is set here because muon attempts to download v4l-utils, which
#       is not a required dependency. I wonder how many hidden dependencies like
#       this exist. ~ahill
muon -C "$DIR_SRC/libdisplay-info" setup \
    -Ddefault_library=both \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dprefix=/ \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dwrap_mode=nodownload \
    -p cross:"$DIR_BUILD/build-libdisplay-info/libdisplay-info.ini" \
    "$DIR_BUILD/build-libdisplay-info"
muon -C "$DIR_BUILD/build-libdisplay-info" samu
DESTDIR="$DIR_UNION" muon -C "$DIR_BUILD/build-libdisplay-info" install
# FIXME: Ditto from Wayland's install step. See that for details. ~ahill
mv "$DIR_UNION/lib/pkgconfig"/* "$DIR_UNION/share/pkgconfig/"
rm -rf "$DIR_UNION/lib/pkgconfig"


STEP "Build and install Weston"
preserve_copyright weston "$DIR_SRC/weston/COPYING"
# NOTE: Weston needs Python to build, so the PATH is temporarily set. ~ahill
PATH="$DIR_UNION/bin:$PATH" muon -C "$DIR_SRC/weston" setup \
    -Dbackend-headless=false \
    -Dbackend-pipewire=false \
    -Dbackend-rdp=false \
    -Dbackend-vnc=false \
    -Dbackend-x11=false \
    -Dcolor-management-lcms=false \
    -Ddemo-clients=false \
    -Dimage-jpeg=false \
    -Dimage-webp=false \
    -Dincludedir=share/include \
    -Dlibdir=lib \
    -Dlibexecdir=lib \
    -Dlocalstatedir=etc \
    -Dprefix=/ \
    -Drenderer-gl=false \
    -Drenderer-vulkan=false \
    -Dsbindir=bin \
    -Dsharedstatedir=etc \
    -Dsimple-clients= \
    -Dsystemd=false \
    -Dtest-junit-xml=false \
    -Dtests=false \
    -Dxwayland=false \
    "$DIR_BUILD/build-weston"


STEP "Cleaning up"
doas umount "$DIR_UNION"
