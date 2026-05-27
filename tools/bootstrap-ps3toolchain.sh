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

	add_bin_path /opt/local/bin

	export PATH
	export PKG_CONFIG_PATH
}

have_toolchain()
{
	PATH=$tool_path command -v ppu-gcc >/dev/null 2>&1 &&
	PATH=$tool_path command -v spu-gcc >/dev/null 2>&1
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

echo "Building ps3toolchain with PS3DEV=$ps3dev"
echo "Using PSL1GHT=$psl1ght during toolchain bootstrap"
echo "This can take a long time and may require host packages listed by ps3toolchain."
(
	cd "$workdir"
	PS3DEV=$ps3dev PSL1GHT=$psl1ght PATH=$PATH PKG_CONFIG_PATH=$PKG_CONFIG_PATH ./toolchain.sh
)

echo "ps3toolchain bootstrap complete."
echo "Add these to your shell profile if they are not already present:"
echo "  export PS3DEV=$ps3dev"
echo "  export PATH=\$PATH:\$PS3DEV/bin:\$PS3DEV/ppu/bin:\$PS3DEV/spu/bin"
