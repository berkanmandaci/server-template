# Python resmi imajı
FROM python:3.11-slim

# Uygulama dizinine geç
WORKDIR /app

# Bağımlılıkları kopyala ve kur
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Uygulama dosyasını kopyala
COPY server.py .

# Port aç
EXPOSE 5000

# Flask sunucusunu başlat
CMD ["python", "server.py"]
