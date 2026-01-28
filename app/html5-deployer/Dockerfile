FROM node:20-alpine AS build

# Use node's home dir as workspace
WORKDIR /home/node/app

# Install build dependencies
# RUN apk add --no-cache python3 make g++

# Copy source
COPY app/html5-deployer/. ./



# Install dependencies from private registry
RUN npm install --maxsockets 1


# ---------- Runtime ----------
FROM node:20-alpine

# Set working directory
WORKDIR /home/node/app
RUN mkdir -p /home/node/app && chown -R node:node /home/node/app

# Copy build artifacts with correct ownership
COPY --chown=node:node --from=build /home/node/app ./

# Switch to non-root 'node' user


# Expose port (optional, e.g., if app listens on 5000 or 3000)
USER 1000:1000

# Start application
CMD ["npm", "start"]