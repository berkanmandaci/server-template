FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required dependencies
RUN apt-get update && apt-get install -y \
    libc6 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnss3 \
    libx11-6 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libatspi2.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libnspr4 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libxcb1 \
    libxkbcommon0 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy server files
COPY LinuxServer/ /app/

# Make the server executable
RUN chmod +x /app/ServerBuild.x86_64

# Expose the default Mirror networking port
EXPOSE 7777

# Start the server
ENTRYPOINT ["/app/ServerBuild.x86_64", "-batchmode", "-nographics"] 