# rnbo-build

Build a native version of Cycling '74 RNBO runner packages from scratch.

## Notes

- Fetching might occasionally fail when downloading Boost since the main JFrog mirror is down. It should eventually fetch from an alternative mirror, but if it doesn't, just retry.  
- Building `libossia` requires a lot of RAM (8–10 GiB). If Docker doesn't have enough memory, the OOM Killer might terminate the process.  
- You probably want to run `docker system prune` occasionally to clean up caches and free some disk space.  

## Run

```sh
docker build . --output .
```

Then grab the `*.deb` files from the current directory.  

## Target

The default target is **ARMv8 (aarch64) with Cortex-A76**. You can adjust the target architecture using:  

```Dockerfile
# CPU for CMake and arch for Conan
ARG CPU=armv8
# CPU flags for the compiler
ARG MCPU=-mcpu=cortex-a76
# Debian package architecture
ARG ARCH=arm64
# Toolchain prefix
ARG CHOST=aarch64-linux-gnu
```

## Package Versions

You can customize the versions being built with:  

```Dockerfile
# rnbo-runner-panel git tag to build
ARG RNBO_RUNNER_PANEL_TAG=v2.1.0
# RNBO source version
ARG RNBO_SOURCE_VER=1.3.4
# rnbo.oscquery.runner git tag to build
ARG RNBO_RUNNER_TAG=rnbo_v${RNBO_SOURCE_VER}
```

## Examples

### RPi4 (ARMv8 64-bit) using RNBO beta 1.4.0  

```sh
docker build \
    --build-arg MCPU="-mcpu=cortex-a72" \
    --build-arg RNBO_RUNNER_PANEL_TAG=develop \
    --build-arg RNBO_SOURCE_VER=1.4.0-dev.117 \
    --build-arg RNBO_RUNNER_TAG=develop \
    . --output .
```

### RPi3 (ARMv7 32-bit)  

```sh
docker build \
    --build-arg CPU=armv7 \
    --build-arg MCPU="-march=armv7-a+neon-vfpv4 -mtune=cortex-a53" \
    --build-arg ARCH=armhf \
    --build-arg CHOST=arm-linux-gnueabihf \
    . --output .
```
