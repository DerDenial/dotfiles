# Optional compact logout screen

This is a locally customized copy of [Hyprshutdown v0.1.1](https://github.com/hyprwm/hyprshutdown/tree/db1f38b03b173984ae9ed3abeb9750583c9bbd91), based on commit `db1f38b03b173984ae9ed3abeb9750583c9bbd91`.
The compact card, app rows and German labels are local changes. Upstream's BSD 3-Clause license is retained in `LICENSE`. This directory contains source only.

## Build requirements

The supplied `CMakeLists.txt` requires CMake 3.19 or newer, a C++23 compiler, a build backend and pkg-config. Required libraries are `hyprtoolkit`, `hyprutils >= 0.11.0`, `pixman-1` and `libdrm`, including development headers. An installed CMake package for `glaze` is used when available; otherwise CMake fetches `glaze` v6.1.0 from GitHub, which needs Git and network access.

From this directory, build with:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build build
```

Hyprland toolkit APIs change frequently. Use dependencies compatible with this source; a successful configure does not guarantee compatibility with every newer toolkit.

## Optional local installation

The exported Quickshell launcher looks for an executable at `~/.config/quickshell/Logout/native/hyprshutdown`. Copy the newly built `build/hyprshutdown` there only after building against your installed system libraries.

Its neighboring `build.json` must contain a `packages` object whose package names and exact versions match `package_versions()` in `~/.config/quickshell/Logout/launch.py`. The current launcher queries Arch's `pacman -Q` for:

- `hyprshutdown`
- `hyprtoolkit`
- `hyprutils-git`
- `hyprlang-git`
- `hyprgraphics-git`
- `aquamarine-git`
- `hyprland`

Record those versions immediately after building, on the machine where the binary will run. Do not reuse another machine's manifest or mark an old binary compatible after a package update: rebuild it first. Missing packages, metadata or mismatched versions make the launcher use `/usr/bin/hyprshutdown` instead. Other distribution/package naming schemes require adapting the version check.

No binary, dependency checkout, build directory or machine-specific manifest is included in this export.
