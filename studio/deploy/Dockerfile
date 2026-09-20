# Студия: Node 24 + Dart SDK (компилятор контента) + git.
FROM dart:stable AS dart

FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts && npm rebuild esbuild
COPY . .
RUN npx vite build

FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates openssh-client && rm -rf /var/lib/apt/lists/*
COPY --from=dart /usr/lib/dart /usr/lib/dart
ENV PATH="/usr/lib/dart/bin:${PATH}" PUB_CACHE=/data/pub-cache
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm rebuild sharp
COPY src/server ./src/server
COPY src/client/types.ts ./src/client/types.ts
COPY bin ./bin
COPY tsconfig.json ./
COPY --from=build /app/dist ./dist

ENV NODE_ENV=production PORT=8795 REPO_DIR=/repo DATA_DIR=/data
EXPOSE 8795
CMD ["node", "--import", "tsx", "src/server/index.ts"]
