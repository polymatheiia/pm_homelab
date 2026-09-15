# Local build wrapper around PlakarKorp/plakar's upstream Dockerfile.
#
# Upstream's own Dockerfile (https://github.com/PlakarKorp/plakar/blob/main/Dockerfile)
# has 4 stages: a shared base, a "goreleaser" stage that expects a pre-built
# binary injected by GoReleaser's CI pipeline (COPY ${TARGETPLATFORM}/plakar),
# and a "build from source" stage pair meant for manual `docker build`.
#
# This host has no buildx/BuildKit installed, so `docker compose build` falls
# back to the legacy builder, which builds every FROM-stage in the Dockerfile
# top to bottom regardless of what the final stage actually depends on — and
# the goreleaser stage's COPY fails outside GoReleaser's own build context.
#
# This Dockerfile reproduces just the documented "build from source" path
# (upstream's stage 3 + 4) standalone, cloning the source instead of relying
# on git build-context semantics, so it builds cleanly with the legacy
# builder. Keep it in sync with upstream if their build steps change.
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
RUN git clone --depth 1 https://github.com/PlakarKorp/plakar.git .
RUN go mod download
RUN CGO_ENABLED=0 go build -trimpath -v -o /plakar .

FROM alpine:3.23
RUN apk add --no-cache ca-certificates
RUN addgroup -S plakar && adduser -S -G plakar -h /home/plakar plakar
USER plakar
WORKDIR /home/plakar
COPY --from=builder /plakar /usr/local/bin/plakar
ENTRYPOINT ["plakar"]
