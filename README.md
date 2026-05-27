PSL1GHT
=======

PSL1GHT is a lightweight PlayStation 3 homebrew SDK that uses the open-source
PlayStation 3 toolchains to compile user applications that will run from the
XMB menu (GameOS homebrew).

Credits
-------

    AerialX     - Founder, Author
    Parlane     - Author
    phiren      - Author
    Tempus      - PSL1GHT Logo
    lousyphreak - libaudio
    Hermes      - sysmodule, libpngdec, libjpgdec
    BigBoss       - EyeToy support added to libcamera sample, libgem sample.
    ooPo        - ps3libraries
    ElSemi      - Vertex Program Compiler
    zerkman     - SPU sample code
    shagkur     - Author
    miigotu     - Author

Environment
-----------

A GCC toolchain that supports the PowerPC 64bit architecture is required to
build PSL1GHT and its samples. It also requires the toolchain to provide
a patched newlib environment; at the moment only one toolchain does so:

* [ps3toolchain](http://github.com/ps3dev/ps3toolchain)

The SDK also includes a few standalone tools to help compilation. A host gcc
and g++ are required to build the native helper tools. sprxlinker requires
libelf, ps3load requires zlib, and the signing tools require zlib, libgmp, and
OpenSSL libcrypto development files. Python 3 is preferred for fself.py,
sfo.py, and pkg.py.

Nvidia's [Cg Toolkit](http://developer.nvidia.com/object/cg_toolkit.html) is
only required for compiling Cg shader programs. Doxygen is only required when
regenerating the API documentation.

Most of the PSL1GHT samples included in the samples/ directory require various
libraries from [ps3libraries](http://github.com/ps3dev/ps3libraries) to be
installed.

Building
--------

PSL1GHT uses two different prefixes:

* `PS3DEV` is the ps3toolchain install prefix. If it is not set, PSL1GHT falls
  back to `DEVKITPS3`, then `/usr/local/ps3dev`.
* `PSL1GHT` is this SDK's install prefix. Headers, libraries, and the shared
  make rules are copied there for applications and samples to use.

Run the dependency check before building so missing tools are reported up
front:

    cd /path/to/psl1ght.git/
    export PS3DEV=/usr/local/ps3dev
    export PSL1GHT=/path/to/psl1ght.git/build
    make check-deps
    make install-ctrl
    make
    make install

`make doctor` is an alias for `make check-deps`. Ensure that `$PSL1GHT` is set
when you are building any of the examples or other apps that use PSL1GHT.

Known Gaps
----------

This repository still carries some older workflow debt that should be handled
in follow-up changes:

- PS3DEV fallback logic is duplicated across several rule and tool Makefiles.
- Some samples reference `$(PSL1GHT)/host/ppu.mk`, which is not installed by
  this tree.
- Generated Doxygen HTML is checked in under `docs/`; the project should decide
  whether generated documentation remains tracked.
- There is no CI or containerised build path yet.

Current Status
--------------

### Graphics

PSL1GHT supports hardware accelerated 3d graphics.
Vertex shaders are a work in progress and Fragment shaders don't exist yet.

### Input

PS3 controllers are fully supported, and pressing the PS button brings up the
in-game XMB menu, assuming the framebuffer is working.

Quitting from the XMB requires the application to register a callback to handle the event. An example using this is the camera example.

### Filesystem Access

Full filesystem support is available, with access to the internal PS3 hard
drive, game disc contents, and external devices like USB drives. Only directory
iteration is missing, though it can be done using the lv2 filesystem interface
directly (see include/psl1ght/lv2/filesystem.h)

### Networking

Berkeley sockets are available for use in PSL1GHT, though some
implementation remains incomplete at this time (hostname lookups, for example).

### STDOUT Debugging

By default, PSL1GHT applications redirect stdout and stderr to the lv2 TTY
interface. Kammy's ethdebug module can be used to retrieve this live debugging
information over UDP broadcast packets.
See [Kammy](http://github.com/AerialX/Kammy) for more information and a
precompiled ethdebug hook loader.

### SPUs

PSL1GHT provides access to running programs on the raw SPUs, and communication
with it from the PPU. See sputest in the samples directory for a simple
example.

### SPRX Linking

Any dynamic libraries available to normal PS3 applications can be used with
PSL1GHT, they just need to be made into a stub library and have the exports
filled out. See any of the examples in sprx/ for information on the
creation of SPRX stub libraries.

The following libraries are currently supported:

* libio
    * libpad
    * libmouse
* liblv2
* libsysutil
* libgcm_sys
* libsysmodule
* libpngdec
* libjpgdec
* libgem
