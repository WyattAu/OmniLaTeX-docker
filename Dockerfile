# syntax=docker/dockerfile:1.6
ARG BASE_IMAGE=node:20-bookworm-slim

# Stage 1: Build
FROM --platform=$BUILDPLATFORM ${BASE_IMAGE} AS build
WORKDIR /app
COPY package*.json ./
RUN --mount=type=secret,id=npm,target=/root/.npmrc \
    npm ci --omit=dev --ignore-scripts
COPY . .

# Stage 2: Production
FROM ${BASE_IMAGE}
WORKDIR /app
COPY --from=build --chown=node:node /app /app
USER node:node
EXPOSE 8080
ENV NODE_ENV=production
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:8080/health || exit 1
CMD ["node", "server.js"]