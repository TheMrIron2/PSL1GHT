#!/bin/sh

errors=0
warnings=0

say()
{
	printf '%s\n' "$*"
}

fail()
{
	errors=$((errors + 1))
	say "error: $*"
}

warn()
{
	warnings=$((warnings + 1))
	say "warning: $*"
}

find_tool()
{
	tool=$1
	old_ifs=$IFS
	IFS=:
	for dir in $CHECK_PATH; do
		[ -n "$dir" ] || dir=.
		if [ -x "$dir/$tool" ]; then
			IFS=$old_ifs
			return 0
		fi
	done
	IFS=$old_ifs
	return 1
}

require_tool()
{
	tool=$1
	reason=$2
	fix=$3

	if ! find_tool "$tool"; then
		fail "missing $tool - $reason. Searched the PS3DEV tool directories and PATH shown above. $fix"
	fi
}

warn_tool()
{
	tool=$1
	reason=$2
	fix=$3

	if ! find_tool "$tool"; then
		warn "missing optional $tool - $reason. $fix"
	fi
}

nearest_existing_parent()
{
	path=$1
	parent=$(dirname "$path")

	while [ ! -d "$parent" ] && [ "$parent" != "/" ] && [ "$parent" != "." ]; do
		parent=$(dirname "$parent")
	done

	printf '%s\n' "$parent"
}

check_psl1ght()
{
	if [ -z "$PSL1GHT" ]; then
		fail "PSL1GHT is not set - it is the install prefix where PSL1GHT headers, libraries, and make rules are copied. Set it with: export PSL1GHT=/path/to/psl1ght/build"
		return
	fi

	if [ -e "$PSL1GHT" ] && [ ! -d "$PSL1GHT" ]; then
		fail "PSL1GHT points to '$PSL1GHT', but that path exists and is not a directory. Choose a directory install prefix."
		return
	fi

	if [ -d "$PSL1GHT" ]; then
		if [ ! -w "$PSL1GHT" ]; then
			fail "PSL1GHT points to '$PSL1GHT', but it is not writable. Choose a writable install prefix or adjust permissions."
		fi
		return
	fi

	parent=$(nearest_existing_parent "$PSL1GHT")
	if [ ! -d "$parent" ] || [ ! -w "$parent" ]; then
		fail "PSL1GHT points to '$PSL1GHT', but its nearest existing parent '$parent' is not writable. Create the directory or choose a writable install prefix."
	fi
}

probe_c_program()
{
	name=$1
	source=$2
	shift 2

	if ! find_tool gcc; then
		return 1
	fi

	tmpdir=${TMPDIR:-/tmp}/psl1ght-check-$$
	rm -rf "$tmpdir"
	if ! mkdir "$tmpdir" 2>/dev/null; then
		warn "could not create temporary probe directory '$tmpdir'; skipping $name compile probe"
		return 1
	fi

	src=$tmpdir/probe.c
	bin=$tmpdir/probe
	printf '%s\n' "$source" > "$src"

	if gcc "$src" "$@" -o "$bin" >/dev/null 2>&1; then
		rm -rf "$tmpdir"
		return 0
	fi

	rm -rf "$tmpdir"
	return 1
}

check_host_libraries()
{
	if find_tool gcc; then
		if ! probe_c_program "zlib" '#include <zlib.h>
int main(void) { return (int)zlibVersion()[0]; }' -lz; then
			fail "missing zlib development files - ps3load and signing tools link with zlib. Install zlib headers and libraries for your host system."
		fi

		if ! probe_c_program "libelf" '#include <libelf.h>
int main(void) { return elf_version(EV_CURRENT) == EV_NONE; }' -lelf; then
			fail "missing libelf development files - sprxlinker links with libelf. Install libelf headers and libraries for your host system."
		fi

		if ! probe_c_program "libgmp" '#include <gmp.h>
int main(void) { mpz_t n; mpz_init(n); mpz_clear(n); return 0; }' -lgmp; then
			fail "missing GMP development files - make_self/package_finalize link with GMP. Install libgmp headers and libraries for your host system."
		fi

		if ! probe_c_program "OpenSSL libcrypto" '#include <openssl/aes.h>
int main(void) { AES_KEY key; (void)key; return 0; }' -lcrypto; then
			fail "missing OpenSSL libcrypto development files - make_self/package_finalize link with libcrypto. Install OpenSSL headers and libraries for your host system."
		fi
	else
		fail "missing gcc - host tools cannot be compiled, and library probes for zlib/libelf/GMP/OpenSSL could not run. Install a host C compiler."
	fi
}

if [ -n "$PS3DEV" ]; then
	resolved_ps3dev=$PS3DEV
	ps3dev_source=PS3DEV
elif [ -n "$DEVKITPS3" ]; then
	resolved_ps3dev=$DEVKITPS3
	ps3dev_source=DEVKITPS3
elif [ "$(uname -s 2>/dev/null)" = Darwin ]; then
	resolved_ps3dev=${HOME:-/tmp}/ps3dev
	ps3dev_source="macOS default"
else
	resolved_ps3dev=/usr/local/ps3dev
	ps3dev_source=default
fi

CHECK_PATH=$resolved_ps3dev/bin:$resolved_ps3dev/ppu/bin:$resolved_ps3dev/spu/bin:$PATH

say "Checking PSL1GHT build dependencies..."
say "PS3DEV resolved from $ps3dev_source: $resolved_ps3dev"
say "Tool search path: $CHECK_PATH"

check_psl1ght

if [ ! -d "$resolved_ps3dev" ]; then
	fail "PS3DEV directory '$resolved_ps3dev' does not exist - PSL1GHT expects ps3toolchain to be installed there. Build/install ps3toolchain or set PS3DEV to the correct prefix."
fi

require_tool make "recursive builds use make throughout the SDK" "Install GNU make or ensure make is on PATH."
require_tool gcc "host tools such as raw2h, ps3load, fself, and sprxlinker are built locally" "Install a host C compiler."
require_tool g++ "host tools such as cgcomp are built locally" "Install a host C++ compiler."
require_tool python3 "tools/ps3py prefers Python 3 for pkg.py, sfo.py, and fself.py" "Install Python 3 or ensure python3 is on PATH."

require_tool ppu-gcc "PPU libraries and applications are compiled with the ps3toolchain PPU compiler" "Build/install ps3toolchain and ensure '$resolved_ps3dev/ppu/bin' is populated."
require_tool ppu-g++ "PPU C++ samples and libraries need the ps3toolchain PPU C++ compiler" "Build/install ps3toolchain and ensure '$resolved_ps3dev/ppu/bin' is populated."
require_tool ppu-ar "PPU static libraries are archived with the ps3toolchain PPU archiver" "Build/install ps3toolchain and ensure '$resolved_ps3dev/ppu/bin' is populated."
require_tool ppu-strip "SELF/package build rules strip PPU ELF files with the ps3toolchain strip tool" "Build/install ps3toolchain and ensure '$resolved_ps3dev/ppu/bin' is populated."
require_tool spu-gcc "SPU libraries and programs are compiled with the ps3toolchain SPU compiler" "Build/install ps3toolchain and ensure '$resolved_ps3dev/spu/bin' is populated."
require_tool spu-ar "SPU static libraries are archived with the ps3toolchain SPU archiver" "Build/install ps3toolchain and ensure '$resolved_ps3dev/spu/bin' is populated."

check_host_libraries

warn_tool doxygen "only needed for 'make doc'" "Install doxygen if you want to regenerate API documentation."
warn_tool cgc "only needed by NVIDIA Cg shader workflows used by some graphics samples" "Install NVIDIA Cg Toolkit if you need to compile Cg shaders."

if [ "$errors" -ne 0 ]; then
	say ""
	say "Dependency check failed with $errors error(s) and $warnings warning(s)."
	say "Most missing PPU/SPU tools are fixed by building ps3toolchain, then exporting PS3DEV to that install prefix."
	say "You can opt in to that bootstrap with: make bootstrap-toolchain"
	exit 1
fi

say "Dependency check passed with $warnings warning(s)."
exit 0
