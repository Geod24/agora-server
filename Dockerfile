# Build Agora from source
FROM alpine:edge AS builder
RUN apk --no-cache add build-base clang dtools dub git ldc libsodium-dev linux-headers llvm-libunwind-dev npm openssl-dev python3 sqlite-dev zlib-dev
ADD . /root/agora/
ARG AGORA_STANDALONE
WORKDIR /root/agora/talos/
RUN if [ -z ${AGORA_STANDALONE+x} ]; then npm ci && npm run build; else mkdir -p build; fi
WORKDIR /root/agora/
# Build Agora
ARG DUB_OPTIONS
ENV AGORA_VERSION="HEAD"
RUN dub build --skip-registry=all --compiler=ldc2 ${DUB_OPTIONS}
# Then build related utilities if not in standalone mode
# Otherwise, copy the placeholder script as Dockerfile don't support conditional copy
RUN if [ -z ${AGORA_STANDALONE+x} ]; then dub build --skip-registry=all --compiler=ldc2 -c client; \
    else cp -v scripts/cli_placeholder.sh build/agora-client; fi
RUN if [ -z ${AGORA_STANDALONE+x} ]; then dub build --skip-registry=all --compiler=ldc2 -c config-dumper; \
    else cp -v scripts/cli_placeholder.sh build/agora-config-dumper; fi

# Runner
# Uses edge as we need the same `ldc-runtime` as the LDC that compiled Agora,
# and `bosagora/agora-builder:latest` uses edge.
FROM alpine:edge
# The following makes debugging Agora much easier on server
# Since it's a tiny configuration file read by GDB at init, it won't affect release build
COPY devel/dotgdbinit /root/.gdbinit
RUN apk --no-cache add ldc-runtime llvm-libunwind libgcc libsodium libstdc++ sqlite-libs
COPY --from=builder /root/agora/talos/build/ /usr/share/agora/talos/
COPY --from=builder /root/agora/build/agora /usr/local/bin/agora
COPY --from=builder /root/agora/build/agora-client /usr/local/bin/agora-client
COPY --from=builder /root/agora/build/agora-config-dumper /usr/local/bin/agora-config-dumper
WORKDIR /agora/
ENTRYPOINT [ "/usr/local/bin/agora" ]
