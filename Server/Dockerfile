# Image du serveur Red Alert (aucune dépendance npm).
FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
ENV DATA_DIR=/data
VOLUME ["/data"]
EXPOSE 8080
CMD ["node", "src/index.js"]
