FROM ubuntu:20.04

RUN apt update && apt install --yes cmake ninja-build curl xz-utils gnupg
RUN curl 'https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz' | tar xJ --directory=/usr/local
RUN curl -fsS https://dlang.org/install.sh | bash -s -- install --path /dlang ldc
RUN chmod --recursive 777 /dlang

COPY ldc.conf /ldc.conf
RUN cat /ldc.conf >> /dlang/ldc-1.24.0/etc/ldc2.conf
COPY test.d /test.d


ENV PATH=/dlang/ldc-1.24.0/bin:/usr/local/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin:$PATH
ENV DMD=ldmd2
ENV DC=ldc2
ENV LIBRARY_PATH=/dlang/ldc-1.24.0/lib:$LIBRARY_PATH
ENV LD_LIBRARY_PATH=/dlang/ldc-1.24.0/lib:$LD_LIBRARY_PATH

RUN env CC=arm-linux-gnueabihf-gcc \
    ldc-build-runtime --ninja --dFlags="-mtriple=arm-linux-gnueabihf"

WORKDIR /ws
ENTRYPOINT ["dub", "--cache=local", "build", "--arch=armv6-linux-gnueabihf"]
