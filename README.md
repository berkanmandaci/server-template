# Nakama Sunucu Şablonu

Bu proje, Unity oyun projeleriniz için yerel geliştirme ortamında Nakama sunucusunu Docker kullanarak çalıştırmanızı sağlar.

## Gereksinimler

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows, macOS veya Linux)
- [Docker Compose](https://docs.docker.com/compose/install/) (Docker Desktop ile birlikte gelir)

## Kurulum

1. Bu projeyi bilgisayarınıza klonlayın veya indirin
2. Proje klasörüne gidin:
   ```bash
   cd NakamaServerTemplate
   ```

## Sunucuyu Başlatma

Nakama sunucusunu başlatmak için:

```bash
docker-compose up -d
```

Bu komut:
- PostgreSQL veritabanını başlatır
- Nakama sunucusunu başlatır
- Gerekli veritabanı tablolarını oluşturur

## Sunucu Durumunu Kontrol Etme

Sunucunun çalışıp çalışmadığını kontrol etmek için:

```bash
docker ps
```

Bu komut çalışan konteynerleri listeler. `nakama` ve `postgres` konteynerlerinin durumunu görebilirsiniz.

## Logları Görüntüleme

Nakama sunucusunun loglarını görüntülemek için:

```bash
docker logs nakama
```

## Sunucuya Erişim

Nakama sunucusuna şu adreslerden erişebilirsiniz:

- **API Sunucusu**: http://127.0.0.1:7350
- **Admin Paneli**: http://127.0.0.1:7351
  - Kullanıcı adı: `admin`
  - Şifre: `password`

## Unity Projesi İçin Bağlantı Ayarları

Unity projenizde Nakama istemcisini yapılandırmak için şu ayarları kullanın:

```csharp
const string Scheme = "http";
const string Host = "127.0.0.1";
const int Port = 7350;
const string ServerKey = "defaultkey";
```

## Test Etme

Projede bulunan `TestNakama.cs` dosyası, sunucuya bağlantıyı test etmek için kullanılabilir. Bu test:

1. Nakama sunucusuna bağlanır
2. Test kullanıcısı oluşturur veya var olan kullanıcıya giriş yapar
3. Basit bir RPC çağrısı yapar

## Sorun Giderme

### Sunucuyu Yeniden Başlatma

Sorun yaşıyorsanız, sunucuyu yeniden başlatabilirsiniz:

```bash
docker-compose restart
```

### Tüm Verileri Temizleme

Eğer sıfırdan başlamak istiyorsanız:

```bash
docker-compose down -v
```

Bu komut tüm konteynerları ve veritabanı verilerini siler.

### Yaygın Sorunlar

1. **Port Çakışması**: Eğer 7350, 7351 veya 5432 portları başka uygulamalar tarafından kullanılıyorsa, `docker-compose.yml` dosyasındaki port numaralarını değiştirebilirsiniz.

2. **Bağlantı Hatası**: Unity projenizden sunucuya bağlanamıyorsanız, şunları kontrol edin:
   - Docker Desktop'ın çalıştığından emin olun
   - `docker ps` komutu ile konteynerlerin çalıştığını doğrulayın
   - Unity projenizdeki bağlantı ayarlarının doğru olduğundan emin olun

## Güvenlik Notları

Bu yapılandırma sadece yerel geliştirme için tasarlanmıştır. Üretim ortamında:

1. Admin paneli için güçlü bir şifre kullanın
2. `defaultkey` yerine güvenli bir sunucu anahtarı kullanın
3. HTTPS kullanın
4. Güvenlik duvarı kurallarını yapılandırın

## Daha Fazla Bilgi

- [Nakama Resmi Dokümantasyonu](https://heroiclabs.com/docs/nakama/getting-started/)
- [Docker Compose Dokümantasyonu](https://docs.docker.com/compose/)
- [Nakama Unity SDK](https://github.com/heroiclabs/nakama-unity) 