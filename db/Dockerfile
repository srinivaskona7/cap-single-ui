FROM node:20-alpine AS build

# Use node's home dir as workspace
WORKDIR /home/node/app

# Install build dependencies
#RUN apk add --no-cache python3 make g++

# Copy source
COPY gen/db ./

# Install deps (can add --registry if private registry needed)
RUN npm install


# ---------- Runtime ----------
FROM node:20-alpine

# Set working directory
WORKDIR /home/node/app

# Copy artifacts with correct ownership for non-root user
COPY --chown=node:node --from=build /home/node/app ./

# Switch to non-root 'node' user
USER 1000:1000

# Expose port (optional if your app listens on e.g. 3000)

# Start app
CMD ["npm", "start"]