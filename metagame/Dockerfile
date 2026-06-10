# Image for the metagame BYOSnap (byosnap-metagame).
# Build context MUST be the repo root so both metagame/ and the vendored
# snapser-pb/ module (consumed via a local `replace` directive) are visible:
#   docker build -f metagame/Dockerfile --platform linux/arm64 .
# The root .dockerignore allowlists only these two directories.
FROM --platform=$BUILDPLATFORM golang:1.26 AS build

WORKDIR /src

# Module manifests first so dependency downloads are layer-cached.
COPY snapser-pb/go.mod snapser-pb/go.sum snapser-pb/
COPY metagame/go.mod metagame/go.sum metagame/
RUN cd metagame && go mod download

COPY snapser-pb/ snapser-pb/
COPY metagame/ metagame/

ARG TARGETOS TARGETARCH
ARG VERSION=dev
RUN cd metagame && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o /out/server ./cmd/server

# Static binary, nothing else — the platform readiness probe is HTTP, so no
# shell or wget is needed in the runtime image.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/server"]
