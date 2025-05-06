using System;
using System.Threading.Tasks;
using Nakama;

namespace NakamaTest
{
    class Program
    {
        private const string Scheme = "http";
        private const string Host = "127.0.0.1";
        private const int Port = 7350;
        private const string ServerKey = "defaultkey";

        static async Task Main(string[] args)
        {
            Console.WriteLine("Nakama Bağlantı Testi Başlatılıyor...");

            var client = new Client(Scheme, Host, Port, ServerKey);
            Console.WriteLine("İstemci oluşturuldu!");

            try
            {
                // Test kullanıcısı oluştur veya var ise giriş yap
                var email = "test@example.com";
                var password = "test123";
                
                Console.WriteLine($"'{email}' ile oturum açma deneniyor...");
                var session = await client.AuthenticateEmailAsync(email, password, email, true);
                
                Console.WriteLine("Başarılı! Kullanıcı kimliği: " + session.UserId);
                Console.WriteLine("Oturum anahtarı: " + session.AuthToken);
                
                // Örnek bir istemci RPC çağrısı
                Console.WriteLine("Sunucu zamanı alınıyor...");
                var rpcResult = await client.RpcAsync(session, "servertime");
                Console.WriteLine("Sunucu zamanı: " + rpcResult.Payload);
                
                Console.WriteLine("Test başarılı!");
            }
            catch (Exception ex)
            {
                Console.WriteLine("Hata: " + ex.Message);
            }

            Console.WriteLine("Test tamamlandı. Çıkmak için bir tuşa basın...");
            Console.ReadKey();
        }
    }
} 