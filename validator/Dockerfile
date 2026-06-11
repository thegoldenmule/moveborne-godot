# Workspace-aware image for the validator BYOSnap.
# Build context MUST be the `validator/` directory (the Bun workspace root) so the
# @spyre-io/moveborne-logic workspace dependency resolves.
FROM oven/bun:1.3-slim

WORKDIR /app

# wget for container health checks
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Copy the workspace root + each member's manifest first so `bun install` can resolve
# the `workspace:*` link before the rest of the source is copied (better layer caching).
COPY package.json bun.lock ./
COPY src/validator/package.json ./src/validator/package.json
COPY src/logic/package.json ./src/logic/package.json

# Install + link the workspace. --production drops dev-only deps (client example, build/test
# tooling); the logic package ships a prebuilt dist so no build step is needed.
RUN bun install --frozen-lockfile --production

# Copy the rest of the source (includes src/logic/dist and src/validator code).
COPY . .

# Run the validator from its package dir so process.cwd()-relative paths match local.
WORKDIR /app/src/validator

# HTTP on :8080 (gateway ingress + platform probe, as the original deploy);
# the gRPC ValidatorService is additive on the internal :8081 port.
ENV PORT=8080
ENV GRPC_PORT=8081
EXPOSE 8080
EXPOSE 8081

CMD ["bun", "run", "index.ts"]
