#!/bin/bash

# Sunucunun çalışıp çalışmadığını kontrol et
nc -z localhost ${SERVER_PORT:-7777}

# Nakama bağlantısını kontrol et
curl -s http://${NAKAMA_HOST}:${NAKAMA_PORT}/healthz > /dev/null 