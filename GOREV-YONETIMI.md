# Görev yönetimi

- Görevlerim: Aktif, Bugün ve Bitenler görünümleri; başlık veya kategori araması.
- Göreve dokun: başlık, kategori, önem ve isteğe bağlı tarih düzenlenir.
- Yuvarlak onay düğmesi: tamamlar veya tamamlamayı geri alır.
- Sola kaydır veya uzun bas: düzenleme ve silme. Silme önce onay ister; liste kapanana kadar son silinen görev Geri al ile kurtarılır.
- Bugün: bugüne planlanan ve geciken aktif görevler. Tarihsiz görevler Aktif görünümündedir.
- Tarihe göre sıralama; aynı gün içinde önem derecesi yüksek olanlar önce gelir.
- Tamamlanan görevde kategori/önem değişince bitki güncellenir. Geri alınan veya silinen görevin bitkisi kaldırılır. Tekrar tamamlanan görev kendi yerini korur.
- Veriler cihazda saklanır; önceki kayıt biçimi desteklenir.

## Tekrar ve hatırlatma

- Planla bölümünde Tekrar yok / Her gün / Her hafta seçilir. Tekrar seçilince tarih zorunludur.
- Her tamamlama, kendi bitkisini koruyan bir geçmiş kaydı ve bir sonraki aktif görevi üretir. Kaçırılan tekrarlar biriktirilmez; sonraki tarih bugünden ileridedir. Haftalık tekrar aynı haftanın gününü korur.
- Hatırlat anahtarı ile seçilen gün ve saatte tek bir yerel bildirim planlanır. İlk hatırlatmalı kayıt sırasında sistem izni istenir. Sonraki tekrarın bildirimi önceki görev tamamlanınca planlanır; gecikmiş görev için her gün tekrar bildirim gönderilmez.
- Tamamlanan veya silinen görevlerin bekleyen bildirimleri kaldırılır; düzenleme ve silmeyi geri alma programı günceller. Bildirim izni kapalıysa görevler kaydedilir ve ayarlar bağlantısı görünür.
- Tamamlamayı geri almak sonraki aktif tekrarı (düzenlemeleri dahil) kaldıracağı için onay ister. Seride daha yeni tamamlanan bir görev varsa önce o geri alınır. Çift aktif görev oluşturacak silmeyi geri alma işlemleri engellenir.
- Aktif tekrar silinince seri durur; önceki bitkiler kalır. Tamamlanan eski kaydı silmek sonraki aktif tekrarı durdurmaz.
- En yakın 60 hatırlatma planlanır; uygulama açıldığında veya görev değiştiğinde program yenilenir. Daha fazla hatırlatma varsa arayüzde açıklama görünür.
- Bildirimler için sunucu, internet veya ücretli geliştirici üyeliği gerekmez. iOS bildirim izinleri ve kullanıcının Odak ayarları geçerlidir.

Bu sürümde iCloud eşitleme yoktur.

Tekrar doğrulaması: work/tests/build_recurrence_checks.py güncel model ve işlemlerden work/tests/RecurrenceChecks.swift oluşturur. Eski kayıt geçişi, günlük/haftalık ve erken/gecikmiş tamamlama, yıl geçişi, tekrar dokunma, geri alma, silinen tekrarı güvenli geri getirme, seriyi durdurma, kalıcı kayıt, geçmiş hatırlatma süzme ve yaz saati kontrol edildi. iOS Simulator derlemesi başarılı. Gerçek bildirim teslimi cihazda kullanıcı izninin ardından ayrıca denenmelidir.

Doğrulama: iOS Simulator için xcodebuild başarılı. Eski kayıttan geçiş, kalıcı tarih/kategori/önem değişiklikleri, tamamlamayı geri alma, tekrar tamamlama ve konum koruma kontrolleri work/tests/TaskChecks.swift içinde çalıştırıldı.

## Orman günlüğü

Ormandaki grafik düğmesi haftalık/aylık günlüğü açar. Yerel takvim ve saat dilimi kullanılır; haftalar pazartesi başlar. Önceki kayıtlı dönemlere geçilebilir, gelecek dönem seçilemez. Tamamlanan görev, büyüyen bitki (görev başına bir), aktif gün, önem derecelerinin toplamı olan emek puanı, günlük çubuk grafik ve kategori dağılımı gösterilir. Dönem görevine dokunmak bitki ayrıntısını açar.

Hesaplar mevcut görevlerin `done` ve `completedAt` alanlarından türetilir; yeni kayıt formatı veya veri göçü yoktur. Tarihsiz eski görevler ayrı notla belirtilir; tamamlanmamış, geleceğe tarihli, silinmiş veya tamamlanması geri alınmış görevler sayılmaz. Bu ekran kalıcı silme geçmişi tutan bir arşiv değildir.

JournalChecks: hafta/ay toplamları, kategori, puan, boş durum, yarı açık tarih aralıkları, önceki ay/yıl, şubat 29, yaz/kış saati ve geri alma kontrolleri geçti. iOS derlemesi başarılı.
