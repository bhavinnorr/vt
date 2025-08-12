# Stage 1: Build frontend
FROM node:22 AS frontend-builder
WORKDIR /app

# Copy only package files first for better caching
COPY package*.json ./
RUN npm install

# Copy the rest of the source
COPY . .

# Build frontend (default output is in ./dist)
RUN npm run build

# Stage 2: Backend with built frontend
FROM node:22

WORKDIR /app

# Copy only backend dependencies first for caching
COPY backend/package*.json ./backend/
RUN cd backend && npm install

# Copy backend code
COPY server ./server
COPY backend ./backend

# Copy built frontend into backend's public dir
COPY --from=frontend-builder /app/dist ./backend/public

EXPOSE 3000

WORKDIR /app/backend
CMD ["npm", "start"]
