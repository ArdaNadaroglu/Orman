# Saat ve konuma göre orman

Gökyüzü telefonun yerel saatini kullanır ve dakikada bir / uygulama tekrar etkin olduğunda yenilenir. 06.00 ve 18.00 çevresindeki renkler stilize saat görünümüdür; astronomik gün doğumu/batımı hesabı değildir. Gece ağaçların seçilebilir kalması için ortam ışığı korunur.

Başlığın altındaki hava düğmesi ayarları açar. Kullanıcı konuma göre hava durumunu açtıktan sonra yalnızca kullanım sırasında konum izni istenir. Varsayılan yaklaşık doğruluk kullanılır; koordinatlar ayrıca iki ondalığa yuvarlanır. Görevler gönderilmez. Konum diske yazılmaz; arka planda izlenmez. Ağ isteği geçici URLSession ile yapılır. Konum izni kapatılırsa eldeki hava verisi temizlenir.

Open-Meteo current.temperature_2m ve current.weather_code alanları kullanılır. Bir saatten eski / beş dakikadan fazla gelecekteki veri reddedilir. Etkin kullanımda yenileme 20 dakikada bir, başarısız denemeden sonra 5 dakikada bir denenir. Kullanıcı Yenile ile tekrar deneyebilir. Bağlantı yoksa güncel mevcut veri geçerlilik süresince kalır; sonra yalnızca saat görünümü kullanılır.

WMO kodları açık, bulutlu, sisli, yağmurlu, karlı, fırtınalı görünümlere çevrilir. Yağmur/kar sınırlı parçacık sayısıyla çizilir; Hareketi Azalt açıkken parçacıklar kapalıdır. Fırtınada yanıp sönen şimşek kullanılmaz.

Kaynaklar:
- https://open-meteo.com/en/docs
- https://open-meteo.com/en/terms
- https://developer.apple.com/weatherkit/

Bu geliştirme sürümü Open-Meteo'nun ticari olmayan ücretsiz API uç noktasını kullanır. Ticari mağaza dağıtımından önce uygun ticari hizmet planı veya WeatherKit geçişi seçilmeli; sağlayıcı anahtarları uygulamaya gömülmemelidir. Mağaza gizlilik beyanı ve gizlilik politikası konumun hava sağlayıcısına iletilmesini açıklamalıdır. Uygulama içi kaynak bağlantısı eklenmiştir.

Doğrulama: work/tests/WeatherChecks.swift; yerel saat dilimi, gece/öğlen sınırları, WMO kodları, JSON okuma ve eski/gelecek verinin reddi. Fiziksel cihazdaki izin ve ağ akışı kullanıcı izninin ardından ayrıca denenmelidir.
