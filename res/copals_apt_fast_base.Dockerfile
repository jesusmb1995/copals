# TODO doc limitation copals, this all works assuming debian target... what if another base image?
# TODO copals-apt-fast-base move to docker registry... and maintain there.
ARG BASE
FROM ${BASE} AS copals-apt-fast-base

# Pin sources to the same snapshot as the aria2 debs.
# Regenerate with: copals/res/gen-aria2-docker-section.sh
RUN echo "deb http://snapshot.debian.org/archive/debian/20260704T120000Z testing main" > /etc/apt/sources.list

# ---BEGIN auto-generated aria2 deps for snapshot 20260704T120000Z---
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/a/aria2/aria2_1.37.0+debian-4+b1_amd64.deb /tmp/aria2_1.37.0+debian-4+b1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/a/aria2/libaria2-0_1.37.0+debian-4+b1_amd64.deb /tmp/libaria2-0_1.37.0+debian-4+b1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/c/c-ares/libcares2_1.34.6-1+b1_amd64.deb /tmp/libcares2_1.34.6-1+b1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/g/gnutls28/libgnutls30t64_3.8.13-1_amd64.deb /tmp/libgnutls30t64_3.8.13-1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/libs/libssh2/libssh2-1t64_1.11.1-4_amd64.deb /tmp/libssh2-1t64_1.11.1-4_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/s/sqlite3/libsqlite3-0_3.46.1-9+b1_amd64.deb /tmp/libsqlite3-0_3.46.1-9+b1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/libx/libxml2/libxml2-16_2.15.3+dfsg-1_amd64.deb /tmp/libxml2-16_2.15.3+dfsg-1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/libi/libidn2/libidn2-0_2.3.8-5_amd64.deb /tmp/libidn2-0_2.3.8-5_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/p/p11-kit/libp11-kit0_0.26.2-3_amd64.deb /tmp/libp11-kit0_0.26.2-3_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/libt/libtasn1-6/libtasn1-6_4.21.0-2+b1_amd64.deb /tmp/libtasn1-6_4.21.0-2+b1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/libu/libunistring/libunistring5_1.4.2-1_amd64.deb /tmp/libunistring5_1.4.2-1_amd64.deb
ADD http://snapshot.debian.org/archive/debian/20260704T120000Z/pool/main/libf/libffi/libffi8_3.5.2-4_amd64.deb /tmp/libffi8_3.5.2-4_amd64.deb
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    echo "fdb69eea9c5b7267e079419ace60dd1b2c66136253f279d7e18baceb6e626afd  /tmp/aria2_1.37.0+debian-4+b1_amd64.deb" | sha256sum --check \
     && echo "a7982e5e93dcbebfcd593474dc07fc2df815ed5d78ad3265e2f5a1304fad2841  /tmp/libaria2-0_1.37.0+debian-4+b1_amd64.deb" | sha256sum --check \
     && echo "2b7dd3c2b8f34ae1466de09f91722724d9515b495f27ae99d2369aad1da4885d  /tmp/libcares2_1.34.6-1+b1_amd64.deb" | sha256sum --check \
     && echo "81f7f28a3968228293cabf6a92f7d6b2a8807f64ccf57469f2ce9a06b7b226af  /tmp/libgnutls30t64_3.8.13-1_amd64.deb" | sha256sum --check \
     && echo "a6cbc3dfd229b492fa065aaa56492452dba27b084c35af8ce1f6287c77cbdb62  /tmp/libssh2-1t64_1.11.1-4_amd64.deb" | sha256sum --check \
     && echo "df8932f6c41e78bc33a4f61251c39777ed0681f73c9c91cd8520068a9c07a8b6  /tmp/libsqlite3-0_3.46.1-9+b1_amd64.deb" | sha256sum --check \
     && echo "b920f80146fb87f38402508ce1abda303bd3c8f4acb1f8c1b9b2f68a3c11e478  /tmp/libxml2-16_2.15.3+dfsg-1_amd64.deb" | sha256sum --check \
     && echo "25a38f7d9ba5bb3daf47a21ad5d348303e602f3c9037a48d621683fe87e7ce28  /tmp/libidn2-0_2.3.8-5_amd64.deb" | sha256sum --check \
     && echo "987bc1f26a1e3c3e214723b78aabd50a9b301f038100b88f4a0fd5fa2938feb8  /tmp/libp11-kit0_0.26.2-3_amd64.deb" | sha256sum --check \
     && echo "097059368c29f6bac5253cc9a4ee3b8c2f449326de016feddf5a00b896fabe49  /tmp/libtasn1-6_4.21.0-2+b1_amd64.deb" | sha256sum --check \
     && echo "509fb596f6b4de34f1d9cb5a0001abc3c6c51f4800e908ef888262ebdaaefa3b  /tmp/libunistring5_1.4.2-1_amd64.deb" | sha256sum --check \
     && echo "1883c3b720014b5fd7bed17f3a27afdc5af079517d762192f687b8dd407e5820  /tmp/libffi8_3.5.2-4_amd64.deb" | sha256sum --check \
     && dpkg -i /tmp/*.deb || apt-get install -f -y
# ---END auto-generated aria2 deps---

RUN rm -f /tmp/*.db

# ADD downloads apt-fast script (no external tools needed)
ADD https://raw.githubusercontent.com/ilikenwf/apt-fast/master/apt-fast /usr/local/sbin/apt-fast
ADD https://raw.githubusercontent.com/ilikenwf/apt-fast/master/apt-fast.conf /etc/apt-fast.conf
RUN echo "4df71b8bba3d2553e3450833f6626560d5c5022e5866a6816b53f131c99904b2  /usr/local/sbin/apt-fast" | sha256sum --check \
 && echo "e545093738b6023cc4c811a0d253a3ddc99b45025d7cf6426133fe3d3c151fdc  /etc/apt-fast.conf" | sha256sum --check \
 && chmod +x /usr/local/sbin/apt-fast \
 && sed -i 's|^#_APTMGR=apt-get|_APTMGR=/usr/bin/apt-get|' /etc/apt-fast.conf

# Keep using snapshot list, that pins versions to that date and keep container stable/reproducible
# TODO this might bite back if snapshot becomes too old...
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked  \
  apt-fast update
# update fetches faster than raw apt-get update
#RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
#  rm -f /etc/apt/sources.list.d/debian.sources \
#  && echo "deb http://deb.debian.org/debian testing main" > /etc/apt/sources.list  \
#  && apt-fast update \
#  && apt-fast upgrade -y

# eatmydata aims to speed disk giving up some safety/sync
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-fast install -y --no-install-recommends eatmydata
RUN ls /var/lib/apt/lists

# /usr/local/bin/apt-get wrapper: redirects to apt-fast, skips update if sources.list unchanged.
COPY gen-apt-wrapper.sh /tmp/gen-apt-wrapper.sh
RUN sh /tmp/gen-apt-wrapper.sh 337a9afe0c6514d5fd6e05c07704a193b1f90f578f4fe3731221d3d227ce4eaa && rm /tmp/gen-apt-wrapper.sh
