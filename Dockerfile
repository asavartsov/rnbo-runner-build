#
# Base Debian 12 + Node.js 20 image
#
FROM node:20-bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV FAKECHROOT=true
VOLUME /var/cache/apt/packages

# Cross-compilation options
# CPU for CMake and arch for Conan
ARG CPU=armv8
# CPU flags for compiler
ARG MCPU=-mcpu=cortex-a76
# Debian package architecture
ARG ARCH=arm64
# Toolchain prefix
ARG CHOST=aarch64-linux-gnu

# Toolchain
ENV AR=${CHOST}-ar
ENV AS=${CHOST}-as
ENV RANLIB=${CHOST}-ranlib
ENV CC=${CHOST}-gcc
ENV CXX=${CHOST}-g++
ENV STRIP=${CHOST}-strip
ENV RC=${CHOST}-windres
ENV CFLAGS="${MCPU} -O3"
ENV CXXFLAGS=${CFLAGS}
ENV ASFLAGS=${CFLAGS}

# Packages
RUN <<EOF
  # Add target architecture for library dependencies
  dpkg --add-architecture ${ARCH} && apt-get update

  # Install build tools and libraries
  apt-get -y --no-install-recommends install \
      ca-certificates make git \
      gcc g++ cmake gettext-base python3-pip \
      crossbuild-essential-${ARCH} \
      libavahi-compat-libdnssd-dev:${ARCH} \
      libssl-dev:${ARCH} libjack-jackd2-dev:${ARCH} \
      libxml2-dev:${ARCH} libsndfile1-dev:${ARCH}

  # Runner requires Conan 1.61
  pip3 install conan --break-system-packages conan==1.61.0
EOF

#
# RNBO Runner Panel
#
FROM base AS rnbo-runner-panel

WORKDIR /build

# rnbo-runner-panel git tag to build
ENV RNBO_RUNNER_PANEL_TAG=v2.1.0

# Fetch the source
RUN git clone --depth 1 --branch ${RNBO_RUNNER_PANEL_TAG} \
    https://github.com/Cycling74/rnbo-runner-panel.git .

# Install dependencies and build deb package
RUN npm ci && npm run package-debian

#
# RNBO OSCQuery Runner
#
FROM base AS rnbo-runner
WORKDIR /build
VOLUME /root/.conan/data  

# RNBO source version
ARG RNBO_SOURCE_VER=1.3.4

# rnbo.oscquery.runner git tag to build
ARG RNBO_RUNNER_TAG=rnbo_v${RNBO_SOURCE_VER}

# Fetch sources
RUN git clone --depth 1 --branch ${RNBO_RUNNER_TAG} \
    https://github.com/Cycling74/rnbo.oscquery.runner.git .

# Add Cycling '74's repository to fetch RNBO sources
RUN <<EOF
  cp config/cycling74.list /etc/apt/sources.list.d/
  cp config/apt-cycling74-pubkey.asc /usr/share/keyrings/
EOF

# Add beta channel to allow building against beta versions of RNBO
#
# See `dpkg --add-architecture armhf && apt-get update && apt-cache madison rnbooscquery` for full list
#
# Package version will be set to RNBO version, and it needs to be compatible with the runner panel package.
#
# Example: RNBO_RUNNER_PANEL_TAG=v2.1.1-beta.4 RNBO_RUNNER_TAG=develop RNBO_SOURCE_VER=1.4.0-dev.117
#
# Looks like Cycling '74 publishes all this stuff under MIT <3 but it is always good to check LICENSE/copyright/terms
# to confirm if it's allowed to use a specific version. You can always get RNBO sources from Max and ADD 
# them to /opt/usr/src/rnbo instead of the steps below.
RUN sed -E 's/^\s*(deb.*bookworm).*/\1 beta/g' config/cycling74.list > /etc/apt/sources.list.d/cycling74-beta.list

# Fetch pre-built rnbooscquery of the target version and extract to /opt
# RNBO source files will be available at /opt/usr/src/rnbo
RUN <<EOF
  dpkg --add-architecture armhf && apt-get update
  apt-get download rnbooscquery=${RNBO_SOURCE_VER}
  dpkg-deb -X *.deb /opt && rm -f *.deb
EOF

# Create Conan profile from the template
#
# To avoid dealing with toolchains, let's just set compiler and tool values to the environment 
# variables and put the exact same values in the Conan profile.
#
# Target architecture libraries are installed from the regular Debian repository at the 
# usual location by adding the architecture to dpkg during the previous stage.
RUN mkdir -p /root/.conan/profiles
RUN CHOST=$CHOST CC=$CC CXX=$CXX CPU=$CPU envsubst <<EOF > /root/.conan/profiles/default
  [buildenv]
  CHOST=$CHOST
  CC=$CC
  CXX=$CXX

  [settings]
  os=Linux
  arch=$CPU
  build_type=Release
  compiler=gcc
  compiler.version=12
  compiler.libcxx=libstdc++11
EOF

# Prepare CMake, which will fetch and build Conan dependencies too
# This step will take a while
RUN cmake \
      -DCMAKE_SYSTEM_PROCESSOR=${CPU} -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE=${ARCH} \
      -DCMAKE_BUILD_TYPE=Release -DWITH_DBUS=Off -DRNBO_DIR=/opt/usr/src/rnbo .

# Build and create deb package
RUN cmake --build . && cpack

#
# JACK Transport Link
#
FROM base AS jack-transport-link
WORKDIR /build

RUN <<EOF
  git clone --depth=1 --branch main https://github.com/x37v/jack_transport_link.git .
  git submodule update --init --recursive
EOF

RUN cmake \
      -DCMAKE_SYSTEM_PROCESSOR=${CPU} -DCPACK_DEBIAN_PACKAGE_ARCHITECTURE=${ARCH} \
      -DCMAKE_BUILD_TYPE=Release .

RUN cmake --build . && cpack

# Final stage
FROM scratch

COPY --from=rnbo-runner /build/*.deb /
COPY --from=rnbo-runner-panel /build/*.deb /
COPY --from=jack-transport-link /build/*.deb /
