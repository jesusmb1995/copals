ARG BASE
FROM ${BASE} AS tools
ARG USERNAME=user
USER root

# Snapshot existing files before install
RUN find /etc /opt /usr /var \( -type f -o -type l \) | sort > /tmp/before.txt

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
 apt-get install -y --no-install-recommends \
    xvfb \
    xdotool \
    imagemagick \
    jq \
 && rm -rf /var/lib/apt/lists/*

# Extract only newly installed files (tools + libs)
RUN find /etc /opt /usr /var \( -type f -o -type l \) | sort > /tmp/after.txt \
 && mkdir -p /out \
 && comm -13 /tmp/before.txt /tmp/after.txt | while IFS= read -r f; do \
      cp -a --parents "$f" /out/; \
    done \
 && rm -rf /out/var/lib/apt

# Stage 2: scratch image with only the test tools and their libraries
FROM scratch AS copals-test-base
COPY --from=tools /out/ /

