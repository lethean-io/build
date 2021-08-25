ARG IMG_PREFIX=lthn
FROM ${IMG_PREFIX}/build:wallet-android-base
ARG QT_VERSION=5.15.2
ARG THREADS=1
ENV SOURCE_DATE_EPOCH=1397818193


FROM base as zlib
ARG ZLIB_VERSION=1.2.11
ARG ZLIB_HASH=c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1
RUN wget -q https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz \
    && tar -xzf zlib-${ZLIB_VERSION}.tar.gz \
    && rm zlib-${ZLIB_VERSION}.tar.gz \
    && cd zlib-${ZLIB_VERSION} \
    && CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} ./configure --prefix=${PREFIX} --static \
    && make -j${THREADS} \
    && make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as qt
RUN git clone git://code.qt.io/qt/qt5.git -b ${QT_VERSION} --depth 1 \
    && cd qt5 \
    && perl init-repository --module-subset=default,-qtwebengine \
    && PATH=${HOST_PATH} ./configure -v -developer-build -release \
    -xplatform android-clang \
    -android-ndk-platform ${ANDROID_API} \
    -android-ndk ${ANDROID_NDK_ROOT} \
    -android-sdk ${ANDROID_SDK_ROOT} \
    -android-ndk-host linux-x86_64 \
    -no-dbus \
    -opengl es2 \
    -no-use-gold-linker \
    -no-sql-mysql \
    -opensource -confirm-license \
    -android-arch arm64-v8a \
    -prefix ${PREFIX} \
    -nomake tools -nomake tests -nomake examples \
    -skip qtwebengine \
    -skip qtserialport \
    -skip qtconnectivity \
    -skip qttranslations \
    -skip qtpurchasing \
    -skip qtgamepad -skip qtscript -skip qtdoc \
    -no-warnings-are-errors \
    && sed -i '213,215d' qtbase/src/3rdparty/pcre2/src/sljit/sljitConfigInternal.h \
    && PATH=${HOST_PATH} make -j${THREADS} \
    && PATH=${HOST_PATH} make -j${THREADS} install \
    && cd qttools/src/linguist/lrelease \
    && ../../../../qtbase/bin/qmake \
    && PATH=${HOST_PATH} make -j${THREADS} install \
    && cd ../../../.. \
    && rm -rf $(pwd)

FROM base as iconv
ARG ICONV_VERSION=1.16
ARG ICONV_HASH=e6a1b1b589654277ee790cce3734f07876ac4ccfaecbee8afa0b649cf529cc04
RUN wget -q http://ftp.gnu.org/pub/gnu/libiconv/libiconv-${ICONV_VERSION}.tar.gz \
    && echo "${ICONV_HASH}  libiconv-${ICONV_VERSION}.tar.gz" | sha256sum -c \
    && tar -xzf libiconv-${ICONV_VERSION}.tar.gz \
    && rm -f libiconv-${ICONV_VERSION}.tar.gz \
    && cd libiconv-${ICONV_VERSION} \
    && CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} ./configure --build=x86_64-linux-gnu --host=aarch64 --prefix=${PREFIX} --disable-rpath \
    && make -j${THREADS} \
    && make -j${THREADS} install

FROM base as boost
ARG BOOST_VERSION=1_74_0
ARG BOOST_VERSION_DOT=1.74.0
ARG BOOST_HASH=83bfc1507731a0906e387fc28b7ef5417d591429e51e788417fe9ff025e116b1
RUN wget -q https://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION_DOT}/boost_${BOOST_VERSION}.tar.bz2 \
    && echo "${BOOST_HASH}  boost_${BOOST_VERSION}.tar.bz2" | sha256sum -c \
    && tar -xf boost_${BOOST_VERSION}.tar.bz2 \
    && rm -f boost_${BOOST_VERSION}.tar.bz2 \
    && cd boost_${BOOST_VERSION} \
    && PATH=${HOST_PATH} ./bootstrap.sh --prefix=${PREFIX} \
    && PATH=${TOOLCHAIN_DIR}/bin:${HOST_PATH} ./b2 --build-type=minimal link=static runtime-link=static \
    --with-chrono --with-date_time --with-filesystem --with-program_options --with-regex --with-serialization \
    --with-system --with-thread --with-locale --build-dir=android --stagedir=android toolset=clang threading=multi \
    threadapi=pthread target-os=android -sICONV_PATH=${PREFIX} \
    cflags='--target=aarch64-linux-android' \
    cxxflags='--target=aarch64-linux-android' \
    linkflags='--target=aarch64-linux-android --sysroot=${ANDROID_NDK_ROOT}/platforms/${ANDROID_API}/arch-arm64 ${ANDROID_NDK_ROOT}/sources/cxx-stl/llvm-libc++/libs/arm64-v8a/libc++_shared.so -nostdlib++' \
    install -j${THREADS} \
    && rm -rf $(pwd)

FROM base as openssl
ARG OPENSSL_VERSION=1.1.1g
ARG OPENSSL_HASH=ddb04774f1e32f0c49751e21b67216ac87852ceb056b75209af2443400636d46
RUN wget -q https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar -xzf openssl-${OPENSSL_VERSION}.tar.gz \
    && rm openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ANDROID_NDK_HOME=${ANDROID_NDK_ROOT} ./Configure CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} \
    android-arm64 no-asm no-shared --static \
    --with-zlib-include=${PREFIX}/include --with-zlib-lib=${PREFIX}/lib \
    --prefix=${PREFIX} --openssldir=${PREFIX} \
    && sed -i 's/CNF_EX_LIBS=-ldl -pthread//g;s/BIN_CFLAGS=-pie $(CNF_CFLAGS) $(CFLAGS)//g' Makefile \
    && ANDROID_NDK_HOME=${ANDROID_NDK_ROOT} make -j${THREADS} \
    && make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as libzmq

ARG ZMQ_VERSION=v4.3.3
ARG ZMQ_HASH=04f5bbedee58c538934374dc45182d8fc5926fa3
RUN git clone https://github.com/zeromq/libzmq.git -b ${ZMQ_VERSION} --depth 1 \
    && cd libzmq \
    && git checkout ${ZMQ_HASH} \
    && ./autogen.sh \
    && CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} ./configure --prefix=${PREFIX} --host=aarch64-linux-android \
    --enable-static --disable-shared \
    && make -j${THREADS} \
    && make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as sodium
ARG SODIUM_VERSION=1.0.18
ARG SODIUM_HASH=4f5e89fa84ce1d178a6765b8b46f2b6f91216677
RUN set -ex \
    && git clone https://github.com/jedisct1/libsodium.git -b ${SODIUM_VERSION} --depth 1 \
    && cd libsodium \
    && test `git rev-parse HEAD` = ${SODIUM_HASH} || exit 1 \
    && ./autogen.sh \
    && CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} ./configure --prefix=${PREFIX} --host=aarch64-linux-android --enable-static --disable-shared \
    && make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as libgpg-error
RUN git clone -b libgpg-error-1.38 --depth 1 git://git.gnupg.org/libgpg-error.git \
    && cd libgpg-error \
    && git reset --hard 71d278824c5fe61865f7927a2ed1aa3115f9e439 \
    && ./autogen.sh \
    && CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} ./configure --host=aarch64-linux-android --prefix=${PREFIX} --disable-rpath --disable-shared --enable-static --disable-doc --disable-tests \
    && PATH=${TOOLCHAIN_DIR}/bin:${HOST_PATH} make -j${THREADS} \
    && make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as libgcrypt
COPY --from=libgpg-error ${PREFIX} ${PREFIX}
RUN git clone -b libgcrypt-1.8.5 --depth 1 git://git.gnupg.org/libgcrypt.git \
    && cd libgcrypt \
    && git reset --hard 56606331bc2a80536db9fc11ad53695126007298 \
    && ./autogen.sh \
    && CC=${ANDROID_CLANG} CXX=${ANDROID_CLANGPP} ./configure --host=aarch64-linux-android --prefix=${PREFIX} --with-gpg-error-prefix=${PREFIX} --disable-shared --enable-static --disable-doc --disable-tests \
    && PATH=${TOOLCHAIN_DIR}/bin:${HOST_PATH} make -j${THREADS} \
    && make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as tools
RUN cd tools \
    && wget -q http://dl-ssl.google.com/android/repository/tools_r25.2.5-linux.zip \
    && unzip -q tools_r25.2.5-linux.zip \
    && rm -f tools_r25.2.5-linux.zip \
    && echo y | ${ANDROID_SDK_ROOT}/tools/android update sdk --no-ui --all --filter build-tools-28.0.3

FROM base as cmake
COPY --from=openssl / /
RUN git clone -b v3.19.7 --depth 1 https://github.com/Kitware/CMake \
    && cd CMake \
    && git reset --hard 22612dd53a46c7f9b4c3f4b7dbe5c78f9afd9581 \
    && PATH=${HOST_PATH} ./bootstrap \
    && PATH=${HOST_PATH} make -j${THREADS} \
    && PATH=${HOST_PATH} make -j${THREADS} install \
    && rm -rf $(pwd)

FROM base as final

COPY --from=libzmq / /
COPY --from=sodium / /
COPY --from=boost / /
COPY --from=iconv / /
COPY --from=openssl / /
COPY --from=cmake / /
COPY --from=libgpg-error / /
COPY --from=libgcrypt / /
COPY --from=tools / /
COPY --from=qt / /
COPY --from=zlib / /

CMD set -ex \
    && cd /wallet-gui \
    && mkdir -p build/Android/release \
    && cd build/Android/release \
    && cmake \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_ROOT}/build/cmake/android.toolchain.cmake" \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH="${PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DARCH="armv8-a" \
    -DANDROID_NATIVE_API_LEVEL=${ANDROID_NATIVE_API_LEVEL} \
    -DANDROID_ABI="arm64-v8a" \
    -DANDROID_TOOLCHAIN=clang \
    -DBoost_USE_STATIC_RUNTIME=ON \
    -DLRELEASE_PATH="${PREFIX}/bin" \
    -DQT_ANDROID_APPLICATION_BINARY="lethean-wallet-gui" \
    -DWITH_SCANNER=ON \
    ../../.. \
    && PATH=${HOST_PATH} make generate_translations_header \
    && make -j${THREADS} -C src \
    && make -j${THREADS} apk
