FROM linuxkit/alpine:4768505d40f23e198011b6f2c796f985fe50ec39 AS kernel-build
RUN apk add \
    argp-standalone \
    automake \
    bash \
    bc \
    binutils-dev \
    bison \
    build-base \
    curl \
    diffutils \
    flex \
    git \
    gmp-dev \
    gnupg \
    installkernel \
    kmod \
    libelf-dev \
    libressl \
    libressl-dev \
    linux-headers \
    mpc1-dev \
    mpfr-dev \
    ncurses-dev \
    patch \
    sed \
    squashfs-tools \
    tar \
    xz \
    xz-dev \
    zlib-dev

ENV KERNEL_SOURCE=https://github.com/raspberrypi/linux.git
ENV KERNEL_BRANCH=rpi-4.19.y

# Fetch source
RUN git clone --depth=1 -b ${KERNEL_BRANCH} ${KERNEL_SOURCE} /linux
WORKDIR /linux

# Save kernel source
RUN mkdir -p /out/src
RUN tar cJf /out/src/linux.tar.xz /linux

# Kernel config
RUN make bcmrpi3_defconfig

# Kernel
RUN make -j "$(getconf _NPROCESSORS_ONLN)" KCFLAGS="-fno-pie" && \
    cp arch/arm64/boot/Image.gz /out/kernel && \
    cp System.map /out

# Modules and Device Tree binaries
RUN make INSTALL_MOD_PATH=/tmp/kernel-modules modules_install && \
    ( DVER=$(basename $(find /tmp/kernel-modules/lib/modules/ -mindepth 1 -maxdepth 1)) && \
    cd /tmp/kernel-modules/lib/modules/$DVER && \
    rm build source && \
    ln -s /usr/src/linux-headers-$DVER build ) && \
    make INSTALL_DTBS_PATH=/tmp/kernel-modules/boot/dtb dtbs_install && \
    ( cd /tmp/kernel-modules && tar cf /out/kernel.tar . )

# Headers (userspace API)
RUN mkdir -p /tmp/kernel-headers/usr && \
    make INSTALL_HDR_PATH=/tmp/kernel-headers/usr headers_install && \
    ( cd /tmp/kernel-headers && tar cf /out/kernel-headers.tar usr )

# Headers (kernel development)
RUN DVER=$(basename $(find /tmp/kernel-modules/lib/modules/ -mindepth 1 -maxdepth 1)) && \
    dir=/tmp/usr/src/linux-headers-$DVER && \
    mkdir -p $dir && \
    cp /linux/.config $dir && \
    cp /linux/Module.symvers $dir && \
    find . -path './include/*' -prune -o \
           -path './arch/*/include' -prune -o \
           -path './scripts/*' -prune -o \
           -type f \( -name 'Makefile*' -o -name 'Kconfig*' -o -name 'Kbuild*' -o \
                      -name '*.lds' -o -name '*.pl' -o -name '*.sh' -o \
                      -name 'objtool' -o -name 'fixdep' -o -name 'randomize_layout_seed.h' \) | \
         tar cf - -T - | (cd $dir; tar xf -) && \
    ( cd /tmp && tar cf /out/kernel-dev.tar usr/src )

RUN printf "KERNEL_SOURCE=${KERNEL_SOURCE}\n" > /out/kernel-source-info

FROM scratch
ENTRYPOINT []
CMD []
WORKDIR /
COPY --from=kernel-build /out/* /
