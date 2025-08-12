# -------------------------
# Stage 1: Build
# -------------------------
FROM node:22-bookworm AS build
WORKDIR /home/build

ENV CI=true

# Install git
RUN \
  --mount=type=cache,target=/var/cache/apt \
  apt-get update && \
  apt-get install -y --no-install-recommends git && \
  rm -rf /var/cache/apt/archives /var/lib/apt/lists/*

# Clone the ViewTube repository
RUN git clone --depth=1 https://github.com/ViewTube/viewtube.git .

# Install pnpm
RUN npm install -g pnpm@10.12

# Install all dependencies
RUN pnpm install --frozen-lockfile

# Generate buildMetadata.json with full metadata
RUN node -e "\
  const { execSync } = require('child_process'); \
  const commit = execSync('git rev-parse HEAD').toString().trim(); \
  const abbreviated_commit = execSync('git rev-parse --short HEAD').toString().trim(); \
  const subject = execSync('git log -1 --pretty=%s').toString().trim(); \
  const buildDate = new Date().toISOString(); \
  const fs = require('fs'); \
  fs.writeFileSync( \
    'client/buildMetadata.json', \
    JSON.stringify({ commit, abbreviated_commit, subject, buildDate }, null, 2) \
  ); \
"

# Build the project
RUN pnpm run build

# Clean up dev dependencies and cache
RUN rm -rf node_modules client/node_modules server/node_modules shared/node_modules "$(pnpm store path)"

# Install production-only dependencies for server & client
RUN CI=true pnpm --filter=./server --filter=./client install --frozen-lockfile --prod


# -------------------------
# Stage 2: Runtime
# -------------------------
FROM node:22-bookworm-slim AS runtime
WORKDIR /home/app

ENV NODE_ENV=production

# Copy necessary package files
COPY --from=build /home/build/package.json ./
COPY --from=build /home/build/client/package.json ./client/
COPY --from=build /home/build/server/package.json ./server/
COPY --from=build /home/build/shared/package.json ./shared/

# Copy node_modules
COPY --from=build /home/build/node_modules ./node_modules
COPY --from=build /home/build/server/node_modules ./server/node_modules

# Copy build artifacts
COPY --from=build /home/build/server/dist ./server/dist/
COPY --from=build /home/build/shared/dist ./shared/dist/
COPY --from=build /home/build/client/.output ./client/.output/

# Install minimal OS dependencies for runtime
RUN \
  --mount=type=cache,target=/var/cache/apt \
  apt-get update && \
  apt-get install -y --no-install-recommends curl ca-certificates && \
  rm -rf /var/cache/apt/archives /var/lib/apt/lists/*

ENV VIEWTUBE_BASE_DIR=/home/app

HEALTHCHECK --interval=30s --timeout=20s --start-period=60s --retries=5 \
  CMD curl --fail http://localhost:8066/ || exit 1

EXPOSE 8066

CMD ["node", "/home/app/server/dist/main.js"]
