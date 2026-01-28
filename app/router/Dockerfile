FROM node:20-alpine AS build

# Use node's home dir as workspace
WORKDIR /home/node/app

# Install build dependencies
# RUN apk add --no-cache python3 make g++

# Copy source
COPY app/router/. ./

# Install dependencies
RUN npm install --maxsockets 1
# RUN npm install


# ---------- Runtime ----------
FROM node:20-alpine

# Set working directory
WORKDIR /home/node/app

# Copy build artifacts with correct ownership
COPY --chown=node:node --from=build /home/node/app ./

# Switch to non-root 'node' user
USER 1000:1000

# Expose port (optional if needed, e.g. 5000 or 3000)

# Start application
CMD ["npm", "start"]