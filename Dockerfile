FROM node:20-bookworm-slim AS web-builder

WORKDIR /repo

COPY package.json package-lock.json ./
COPY shared/package.json ./shared/package.json
COPY backend/package.json ./backend/package.json
COPY web/package.json ./web/package.json

RUN npm ci

COPY shared ./shared
COPY web ./web

RUN npm run build --workspace=web

FROM node:20-bookworm-slim

ENV NODE_ENV=production
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV GRAIN_PYTHON_BIN=python3
ENV WEB_DIST_DIR=/app/backend/public

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-pip libglib2.0-0 libgl1 \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY shared/package.json ./shared/package.json
COPY backend/package.json ./backend/package.json
COPY web/package.json ./web/package.json

RUN npm ci --omit=dev

COPY shared ./shared
COPY backend ./backend
COPY --from=web-builder /repo/web/dist ./backend/public

RUN pip3 install --break-system-packages --no-cache-dir -r backend/python/requirements.txt

WORKDIR /app

EXPOSE 3000

CMD ["npm", "start", "--workspace=backend"]
