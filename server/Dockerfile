# Arena game server. Build from the repository root:
#   docker build -f server/Dockerfile -t arena-server .
ARG DART_VERSION=3.13.4

FROM dart:${DART_VERSION} AS build
WORKDIR /src
# Path dependencies first, then the server.
COPY packages/ludo_engine packages/ludo_engine
COPY packages/ludo_bots packages/ludo_bots
COPY packages/arena_protocol packages/arena_protocol
COPY server/auth server/auth
COPY server/wallet server/wallet
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get --enforce-lockfile
COPY server/bin server/bin
COPY server/lib server/lib
RUN mkdir -p /out && cd server && dart compile exe bin/server.dart -o /out/server

# Minimal image: the Dart runtime files plus the compiled server.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
ENV PORT=8080
EXPOSE 8080
USER 65534:65534
ENTRYPOINT ["/app/server"]
