# ── Build Stage ───────────────────────────────────────────────────────────────
# Use official Go image to compile the binary.
# Multi-stage build — compiler stays in build stage, only binary
# is copied to the final image. Keeps the production image small.

FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy dependency files first — Docker caches this layer if they
# do not change, avoiding repeated module downloads on rebuilds.
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o stratum-service .

# ── Final Stage ───────────────────────────────────────────────────────────────
# Distroless image — no shell, no package manager, no unnecessary
# tools. Contains only the binary and its runtime dependencies.
# Significantly reduces attack surface compared to a full OS image.

FROM gcr.io/distroless/static-debian12

WORKDIR /app

COPY --from=builder /app/stratum-service .

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/app/stratum-service"]