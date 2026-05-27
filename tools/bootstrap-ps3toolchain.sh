#!/bin/sh

set -e

repo=${PS3TOOLCHAIN_REPO:-https://github.com/ps3dev/ps3toolchain.git}
workdir=${PS3TOOLCHAIN_DIR:-${HOME:-/tmp}/.cache/ps3toolchain}
host_os=$(uname -s 2>/dev/null || echo unknown)

if [ -n "$PS3DEV" ]; then
	ps3dev=$PS3DEV
elif [ -n "$DEVKITPS3" ]; then
	ps3dev=$DEVKITPS3
elif [ "$host_os" = Darwin ]; then
	ps3dev=${HOME:-/tmp}/ps3dev
else
	ps3dev=/usr/local/ps3dev
fi

if [ -n "$PSL1GHT" ]; then
	psl1ght=$PSL1GHT
else
	psl1ght=$ps3dev
fi

tool_path=$ps3dev/bin:$ps3dev/ppu/bin:$ps3dev/spu/bin:$PATH
PATH=$tool_path
export PATH PSL1GHT
PSL1GHT=$psl1ght
missing_deps=
shimdir=${TMPDIR:-/tmp}/psl1ght-ps3toolchain-shims-$$

add_pkg_config_path()
{
	dir=$1
	if [ -d "$dir" ]; then
		if [ -n "$PKG_CONFIG_PATH" ]; then
			PKG_CONFIG_PATH=$dir:$PKG_CONFIG_PATH
		else
			PKG_CONFIG_PATH=$dir
		fi
	fi
}

add_bin_path()
{
	dir=$1
	if [ -d "$dir" ]; then
		PATH=$dir:$PATH
	fi
}

add_homebrew_paths()
{
	for prefix in /opt/homebrew /usr/local; do
		[ -d "$prefix" ] || continue
		for package in autoconf automake bison flex gcc libtool pkg-config texinfo wget libelf zlib openssl@3 openssl ncurses gmp; do
			add_bin_path "$prefix/opt/$package/bin"
			add_pkg_config_path "$prefix/opt/$package/lib/pkgconfig"
		done
	done

	for dir in /opt/local/lib/pkgconfig /opt/local/libexec/openssl3/lib/pkgconfig; do
		add_pkg_config_path "$dir"
	done

	if ! command -v brew >/dev/null 2>&1; then
		add_bin_path /opt/local/bin
	fi

	export PATH
	export PKG_CONFIG_PATH
}

have_toolchain()
{
	PATH=$tool_path command -v ppu-gcc >/dev/null 2>&1 &&
	PATH=$tool_path command -v spu-gcc >/dev/null 2>&1 &&
	[ -f "$psl1ght/ppu_rules" ] &&
	[ -x "$psl1ght/bin/ps3load" ] &&
	[ -f "$psl1ght/bin/pkgcrypt.so" ]
}

usage()
{
	cat <<EOF
Usage: make bootstrap-toolchain

Environment overrides:
  PS3DEV              Install prefix used by ps3toolchain
                      default: ~/ps3dev on macOS, /usr/local/ps3dev elsewhere
  PSL1GHT             PSL1GHT prefix used while bootstrapping
                      default: same as PS3DEV
  PS3TOOLCHAIN_REPO   Git repository to clone (default: $repo)
  PS3TOOLCHAIN_DIR    Clone/build directory (default: $workdir)

This target is intentionally opt-in. It clones ps3toolchain when needed and
runs its upstream ./toolchain.sh script. It does not run sudo; choose a writable
PS3DEV or run ps3toolchain's sudo flow manually if your system requires it.
EOF
}

need_command()
{
	cmd=$1
	package=$2

	if ! command -v "$cmd" >/dev/null 2>&1; then
		missing_deps="$missing_deps $package"
	fi
}

need_runnable_command()
{
	cmd=$1
	package=$2
	probe=$3

	if ! command -v "$cmd" >/dev/null 2>&1 || ! sh -c "$probe" >/dev/null 2>&1; then
		missing_deps="$missing_deps $package"
	fi
}

need_pkg_config()
{
	module=$1
	package=$2

	if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists "$module"; then
		missing_deps="$missing_deps $package"
	fi
}

check_host_dependencies()
{
	need_command autoconf autoconf
	need_command automake automake
	need_command bison bison
	need_command flex flex
	need_command gcc gcc
	need_command g++ g++
	need_command make make
	need_runnable_command makeinfo texinfo "makeinfo --version"
	need_command patch patch
	need_command pkg-config pkg-config
	need_command python python
	if ! command -v python-config >/dev/null 2>&1 && ! command -v python3-config >/dev/null 2>&1; then
		missing_deps="$missing_deps python-dev"
	fi
	need_command wget wget

	need_pkg_config libelf libelf
	need_pkg_config zlib zlib
	need_pkg_config gmp gmp
	need_pkg_config ncurses ncurses

	if [ -n "$missing_deps" ]; then
		echo "error: missing host dependencies for ps3toolchain:$missing_deps" >&2
		case "$host_os" in
			Darwin)
				if command -v brew >/dev/null 2>&1; then
					echo "Install them with Homebrew:" >&2
					echo "  brew install autoconf automake bison flex gcc gmp libelf libtool ncurses openssl pkg-config texinfo wget zlib" >&2
					echo "If texinfo is already installed but makeinfo is broken, run:" >&2
					echo "  brew reinstall texinfo" >&2
				else
					echo "Install Homebrew or provide these dependencies with MacPorts/manual paths." >&2
				fi
				;;
			*)
				echo "Install the ps3toolchain host packages for your platform, then rerun make bootstrap-toolchain." >&2
				;;
		esac
		exit 1
	fi
}

setup_python_shims()
{
	need_shims=

	if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
		need_shims=yes
	fi

	if ! command -v python-config >/dev/null 2>&1 && command -v python3-config >/dev/null 2>&1; then
		need_shims=yes
	fi

	[ -n "$need_shims" ] || return

	rm -rf "$shimdir"
	mkdir -p "$shimdir"

	if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
		python3_path=$(command -v python3)
		printf '#!/bin/sh\nexec "%s" "$@"\n' "$python3_path" > "$shimdir/python"
		chmod +x "$shimdir/python"
	fi

	if ! command -v python-config >/dev/null 2>&1 && command -v python3-config >/dev/null 2>&1; then
		python3_config_path=$(command -v python3-config)
		printf '#!/bin/sh\nexec "%s" "$@"\n' "$python3_config_path" > "$shimdir/python-config"
		chmod +x "$shimdir/python-config"
	fi

	PATH=$shimdir:$PATH
	export PATH
}

setup_host_compilers()
{
	[ "$host_os" = Darwin ] || return
	[ "$PS3TOOLCHAIN_USE_HOMEBREW_GCC" = 1 ] || return 0

	if [ -z "$CC" ]; then
		for candidate in gcc-15 gcc-14 gcc-13 gcc-12 gcc-11 gcc-10; do
			if command -v "$candidate" >/dev/null 2>&1; then
				CC=$candidate
				CC_FOR_BUILD=$candidate
				break
			fi
		done
	fi

	if [ -z "$CXX" ]; then
		for candidate in g++-15 g++-14 g++-13 g++-12 g++-11 g++-10; do
			if command -v "$candidate" >/dev/null 2>&1; then
				CXX=$candidate
				CXX_FOR_BUILD=$candidate
				break
			fi
		done
	fi

	if [ -n "$CC" ]; then
		CC_FOR_BUILD=${CC_FOR_BUILD:-$CC}
		export CC CC_FOR_BUILD
	fi

	if [ -n "$CXX" ]; then
		CXX_FOR_BUILD=${CXX_FOR_BUILD:-$CXX}
		export CXX CXX_FOR_BUILD
	fi
}

patch_zlib_file()
{
	file=$1
	label=$2
	[ -f "$file" ] || return 0
	if grep -F 'defined(TARGET_OS_MAC) && !defined(__APPLE__)' "$file" >/dev/null 2>&1; then
		return 0
	fi
	if ! grep -F '#if defined(MACOS) || defined(TARGET_OS_MAC)' "$file" >/dev/null 2>&1; then
		return 0
	fi

	tmp=${file}.psl1ght-tmp
	sed 's/^#if defined(MACOS) || defined(TARGET_OS_MAC)$/#if defined(MACOS) || (defined(TARGET_OS_MAC) \&\& !defined(__APPLE__))/' "$file" > "$tmp"
	mv "$tmp" "$file"
	echo "Patched $label zlib Darwin fdopen probe in $file"
}

patch_gdb_readline_file()
{
	file=$1
	[ -f "$file" ] || return 0
	if grep -F '#  include <sys/ioctl.h>' "$file" >/dev/null 2>&1; then
		return 0
	fi
	if ! grep -F '#include <sys/types.h>' "$file" >/dev/null 2>&1; then
		return 0
	fi

	tmp=${file}.psl1ght-tmp
	awk '
		{
			print
			if ($0 == "#include <sys/types.h>") {
				print "#if defined (__APPLE__)"
				print "#  include <sys/ioctl.h>"
				print "#endif"
			}
		}
	' "$file" > "$tmp"
	mv "$tmp" "$file"
	echo "Patched GDB readline Darwin ioctl declaration in $file"
}

patch_gdb_enum_flags_file()
{
	file=$1
	[ -f "$file" ] || return 0
	if grep -F 'Wenum-constexpr-conversion' "$file" >/dev/null 2>&1; then
		return 0
	fi
	if ! grep -F 'struct enum_underlying_type' "$file" >/dev/null 2>&1; then
		return 0
	fi

	tmp=${file}.psl1ght-tmp
	awk '
		{
			if ($0 == "template<typename T>") {
				print "#if defined (__clang__)"
				print "#  pragma clang diagnostic push"
				print "#  pragma clang diagnostic ignored \"-Wenum-constexpr-conversion\""
				print "#endif"
				in_enum_underlying = 1
			}

			print

			if (in_enum_underlying && $0 == "};") {
				print "#if defined (__clang__)"
				print "#  pragma clang diagnostic pop"
				print "#endif"
				in_enum_underlying = 0
			}
		}
	' "$file" > "$tmp"
	mv "$tmp" "$file"
	echo "Patched GDB enum flags for modern Clang diagnostics in $file"
}

patch_ps3toolchain_sources()
{
	[ "$host_os" = Darwin ] || return 0

	patch_file=$workdir/patches/gdb-8.3.1-PS3.patch
	if [ -f "$patch_file" ] && ! grep -F 'defined(TARGET_OS_MAC) && !defined(__APPLE__)' "$patch_file" >/dev/null 2>&1; then
		cat >> "$patch_file" <<'EOF'
--- a/zlib/zutil.h
+++ b/zlib/zutil.h
@@ -130,7 +130,7 @@
 #  endif
 #endif
 
-#if defined(MACOS) || defined(TARGET_OS_MAC)
+#if defined(MACOS) || (defined(TARGET_OS_MAC) && !defined(__APPLE__))
 #  define OS_CODE  7
 #  ifndef Z_SOLO
 #    if defined(__MWERKS__) && __dest_os != __be_os && __dest_os != __win32_os
EOF
		echo "Patched ps3toolchain GDB patch for Darwin zlib fdopen compatibility."
	fi
	if [ -f "$patch_file" ] && ! grep -F -- '--- a/readline/rltty.c' "$patch_file" >/dev/null 2>&1; then
		cat >> "$patch_file" <<'EOF'
--- a/readline/rltty.c
+++ b/readline/rltty.c
@@ -22,6 +22,9 @@
 #endif
 
 #include <sys/types.h>
+#if defined (__APPLE__)
+#  include <sys/ioctl.h>
+#endif
 #include <signal.h>
 #include <errno.h>
 #include <stdio.h>
EOF
		echo "Patched ps3toolchain GDB patch for Darwin readline ioctl compatibility."
	fi
	if [ -f "$patch_file" ] && ! grep -F -- '--- a/readline/terminal.c' "$patch_file" >/dev/null 2>&1; then
		cat >> "$patch_file" <<'EOF'
--- a/readline/terminal.c
+++ b/readline/terminal.c
@@ -22,6 +22,9 @@
 #endif
 
 #include <sys/types.h>
+#if defined (__APPLE__)
+#  include <sys/ioctl.h>
+#endif
 #include "posixstat.h"
 #include <fcntl.h>
 #if defined (HAVE_SYS_FILE_H)
--- a/readline/input.c
+++ b/readline/input.c
@@ -27,6 +27,9 @@
 #endif
 
 #include <sys/types.h>
+#if defined (__APPLE__)
+#  include <sys/ioctl.h>
+#endif
 #include <fcntl.h>
 #if defined (HAVE_SYS_FILE_H)
 #  include <sys/file.h>
--- a/readline/util.c
+++ b/readline/util.c
@@ -22,6 +22,9 @@
 #endif
 
 #include <sys/types.h>
+#if defined (__APPLE__)
+#  include <sys/ioctl.h>
+#endif
 #include <fcntl.h>
 #include "posixjmp.h"
 
EOF
		echo "Patched ps3toolchain GDB patch for additional Darwin readline ioctl declarations."
	fi
	if [ -f "$patch_file" ] && ! grep -F 'Wenum-constexpr-conversion' "$patch_file" >/dev/null 2>&1; then
		cat >> "$patch_file" <<'EOF'
--- a/gdb/common/enum-flags.h
+++ b/gdb/common/enum-flags.h
@@ -80,6 +80,10 @@ template<> struct integer_for_size<2, 1> { typedef int16_t type; };
 template<> struct integer_for_size<4, 1> { typedef int32_t type; };
 template<> struct integer_for_size<8, 1> { typedef int64_t type; };
 
+#if defined (__clang__)
+#  pragma clang diagnostic push
+#  pragma clang diagnostic ignored "-Wenum-constexpr-conversion"
+#endif
 template<typename T>
 struct enum_underlying_type
 {
@@ -88,6 +92,9 @@ struct enum_underlying_type
     type;
 };
 
+#if defined (__clang__)
+#  pragma clang diagnostic pop
+#endif
 template <typename E>
 class enum_flags
 {
EOF
		echo "Patched ps3toolchain GDB patch for modern Clang enum diagnostics."
	fi

	patch_zlib_file "$workdir/build/gdb-8.3.1/zlib/zutil.h" GDB
	patch_zlib_file "$workdir/build/gcc-7.2.0/zlib/zutil.h" GCC
	patch_gdb_readline_file "$workdir/build/gdb-8.3.1/readline/rltty.c"
	patch_gdb_readline_file "$workdir/build/gdb-8.3.1/readline/terminal.c"
	patch_gdb_readline_file "$workdir/build/gdb-8.3.1/readline/input.c"
	patch_gdb_readline_file "$workdir/build/gdb-8.3.1/readline/util.c"
	patch_gdb_enum_flags_file "$workdir/build/gdb-8.3.1/gdb/common/enum-flags.h"
}

case "$1" in
	-h|--help)
		usage
		exit 0
		;;
esac

if have_toolchain; then
	echo "ps3toolchain already appears to be installed under: $ps3dev"
	exit 0
fi

if ! command -v git >/dev/null 2>&1; then
	echo "error: git is required to clone ps3toolchain." >&2
	exit 1
fi

add_homebrew_paths
setup_python_shims
setup_host_compilers
if [ "$host_os" = Darwin ] && [ -z "$CFLAGS_FOR_BUILD" ]; then
	CFLAGS_FOR_BUILD="-Wno-error=int-conversion -Wno-int-conversion"
	export CFLAGS_FOR_BUILD
fi
check_host_dependencies

parent=$(dirname "$ps3dev")
if [ ! -d "$ps3dev" ] && [ ! -w "$parent" ]; then
	echo "error: PS3DEV '$ps3dev' does not exist and parent '$parent' is not writable." >&2
	echo "Set PS3DEV to a writable prefix, create it with suitable permissions, or run ps3toolchain's sudo flow manually." >&2
	exit 1
fi

mkdir -p "$ps3dev"

if [ -d "$workdir/.git" ]; then
	echo "Updating ps3toolchain in $workdir"
	git -C "$workdir" pull --ff-only
else
	echo "Cloning ps3toolchain into $workdir"
	mkdir -p "$(dirname "$workdir")"
	git clone "$repo" "$workdir"
fi
patch_ps3toolchain_sources

echo "Building ps3toolchain with PS3DEV=$ps3dev"
echo "Using PSL1GHT=$psl1ght during toolchain bootstrap"
if [ -n "$CC" ]; then echo "Using host C compiler: $CC"; fi
if [ -n "$CXX" ]; then echo "Using host C++ compiler: $CXX"; fi
if [ -n "$CFLAGS_FOR_BUILD" ]; then echo "Using build C flags: $CFLAGS_FOR_BUILD"; fi
echo "This can take a long time and may require host packages listed by ps3toolchain."
(
	cd "$workdir"
	PS3DEV=$ps3dev
	PSL1GHT=$psl1ght
	export PS3DEV PSL1GHT PATH PKG_CONFIG_PATH
	if [ -n "$CC" ]; then export CC; else unset CC; fi
	if [ -n "$CXX" ]; then export CXX; else unset CXX; fi
	if [ -n "$CC_FOR_BUILD" ]; then export CC_FOR_BUILD; else unset CC_FOR_BUILD; fi
	if [ -n "$CXX_FOR_BUILD" ]; then export CXX_FOR_BUILD; else unset CXX_FOR_BUILD; fi
	if [ -n "$CFLAGS_FOR_BUILD" ]; then export CFLAGS_FOR_BUILD; else unset CFLAGS_FOR_BUILD; fi
	./toolchain.sh
)

echo "ps3toolchain bootstrap complete."
echo "Add these to your shell profile if they are not already present:"
echo "  export PS3DEV=$ps3dev"
echo "  export PATH=\$PATH:\$PS3DEV/bin:\$PS3DEV/ppu/bin:\$PS3DEV/spu/bin"
