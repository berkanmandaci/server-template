# Ubuntu 22.04 LTS base image
FROM ubuntu:22.04

# Gerekli paketleri yükleme
RUN apt-get update && apt-get install -y \
    libc6 \
    libglib2.0-0 \
    libgtk-3-0 \
    libx11-6 \
    libxcb1 \
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
    libnss3 \
    libasound2 \
    netcat \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Çalışma dizinini oluştur
WORKDIR /app

# Sunucu dosyalarını kopyala
COPY LinuxServer/ /app/

# Script dosyalarını kopyala
COPY scripts/start-server.sh /app/
COPY scripts/health-check.sh /app/

# Çalıştırma izinlerini ayarla
RUN chmod +x /app/ServerBuild.x86_64 \
    && chmod +x /app/start-server.sh \
    && chmod +x /app/health-check.sh

# Port açma
EXPOSE 7777

# Sunucuyu başlat
CMD ["./start-server.sh"] 