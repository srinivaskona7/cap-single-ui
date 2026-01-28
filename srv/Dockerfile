FROM node:20-alpine AS build

# Use node's home dir as workspace
WORKDIR /home/node/app

# Install build dependencies for native modules
# RUN apk add --no-cache python3 make g++

# Copy source
COPY gen/srv ./

# Install only production dependencies
RUN npm ci --omit=dev --maxsockets 1


# ---------- Runtime ----------
FROM node:20-alpine

# Set working directory
WORKDIR /home/node/app

# Copy build artifacts with correct ownership for non-root user
COPY --chown=node:node --from=build /home/node/app ./

# Switch to non-root 'node' user
USER 1000:1000

# Start app
CMD ["npm", "run", "start"]