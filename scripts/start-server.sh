#!/bin/bash

# Nakama bağlantısını kontrol et
until curl -s http://${NAKAMA_HOST}:${NAKAMA_PORT}/healthz > /dev/null; do
    echo "Waiting for Nakama server..."
    sleep 5
done

echo "Nakama server is ready!"

# Sunucuyu başlat
./ServerBuild.x86_64 -port ${SERVER_PORT:-7777} -name ${SERVER_NAME:-GameServer} 