FROM ubuntu:20.04 AS builder

# !!! adjust also int the cat ldc.conf line !!!
ENV LDC_VERSION=1.28.0
# !!! adjust also int the cat ldc.conf line !!!
LABEL ldc-version=${LDC_VERSION}
RUN \
  apt update \
  && apt install --yes cmake ninja-build curl xz-utils gnupg \
  && apt clean \
  && rm -rf /var/lib/apt/lists/*

RUN curl 'https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz' | tar xJ --directory=/usr/local
RUN \
  curl -fsS https://dlang.org/install.sh | bash -s -- install --path /dlang ldc \
  && chmod --recursive 777 /dlang

ENV PATH=/dlang/ldc-$LDC_VERSION/bin:/usr/local/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin:$PATH
ENV DMD=ldmd2
ENV DC=ldc2
ENV LIBRARY_PATH=/dlang/ldc-${LDC_VERSION}/lib:$LIBRARY_PATH
ENV LD_LIBRARY_PATH=/dlang/ldc-${LDC_VERSION}/lib:$LD_LIBRARY_PATH

RUN \
  env CC=arm-linux-gnueabihf-gcc \
  ldc-build-runtime --ninja --dFlags="-mtriple=arm-linux-gnueabihf"

COPY ldc.conf /ldc.conf
RUN \
  cat /ldc.conf >> /dlang/ldc-1.28.0/etc/ldc2.conf

WORKDIR /ws
ENTRYPOINT ["dub", "build", "--arch=armv6-linux-gnueabihf", "--cache=local"]

FROM ubuntu:20.04

RUN \
  apt update \
  && apt install --yes curl gnupg xz-utils libxml2 gcc \
  && apt clean \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsS https://dlang.org/install.sh | bash -s -- install --path /dlang ldc \
  && chmod --recursive 777 /dlang \
  && apt remove gnupg xz-utils --yes \
  && apt autoremove --yes

ENV LDC_VERSION=1.28.0
ENV PATH=/dlang/ldc-${LDC_VERSION}/bin:/usr/local/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin:$PATH
ENV DMD=ldmd2
ENV DC=ldc2
ENV LIBRARY_PATH=/dlang/ldc-${LDC_VERSION}/lib:$LIBRARY_PATH
ENV LD_LIBRARY_PATH=/dlang/ldc-${LDC_VERSION}/lib:$LD_LIBRARY_PATH
ENV LDC_VERSION=${LDC_VERSION}

COPY --from=builder /usr/local/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf /usr/local/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf
COPY --from=builder /ldc-build-runtime.tmp/lib /ldc/lib


COPY ldc.conf /ldc.conf
RUN \
  cat /ldc.conf >> /dlang/ldc-1.28.0/etc/ldc2.conf

env HOME=/tmp
WORKDIR /ws
ENTRYPOINT ["dub", "build", "--arch=armv6-linux-gnueabihf"]
