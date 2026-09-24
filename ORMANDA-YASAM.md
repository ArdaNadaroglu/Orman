# Ormanda yaşam

- Yaprak kümeleri yaklaşık 1,3 derecelik yumuşak salınım yapar; gövdeler ve zemin sabittir. En fazla 100 bitki eşzamanlı hareket eder.
- Dokuz kelebek gündüz ve açık/bulutlu görünümde farklı rotalarda uçar. Gece, sis ve yağışta gizlenirler. Hava verisi yoksa telefon saatine göre görünürler.
- İki küçük ceylan birbirinden bağımsız rastgele hedefler ve hızlar seçerek ormanda dolaşır; hedefler arasında 1,5–5,5 saniye durup otlar. Dönüşler yumuşaktır. Gövdelerden 1,05 birim, ada kenarından 1,2 birim uzak kalırlar. Yeni bitkiler ve değişen ada boyutu hareket sırasında hesaba katılır. Gece de dolaşırlar.
- Hareketi Azalt ayarı animasyonları durdurur. Uygulama etkin değilken animasyonlar durur. Düşük Güç Modu'nda sahne 30 FPS hedefler.
- Alttaki hoparlör düğmesi isteğe bağlı sesi açar/kapatır. Her yeni uygulama oturumunda ses kapalı başlar. Tüm ses katmanları uygulama arka plana gidince durur; kulaklık çıkarılınca tamamen kapanır. Telefonun sessiz anahtarına uyar ve diğer uygulamaların sesini kesmez.
- work/make_sound_layers.py ile üretilen ForestWind, ForestBirds, ForestNight ve ForestRiver.wav dosyaları 25 saniyelik özgün sentetik ses döngüleridir. Harici ses kaydı kullanılmaz. Dört dosya da uygulama paketine dahil edilir; internet gerekmez. Önceki ForestAmbience kaynağı artık çalınmaz.

Kontroller: iOS Simulator derlemesi başarılı; ses kaynağının pakete dahil olduğu doğrulandı. Sayısal ses tepe/döngü kontrolü geçti. work/tests/build_life_checks.py güncel SceneKit davranışından test oluşturur; 100 güncellemede nesne birikmemesi, durdurma/yeniden başlatma, Hareketi Azalt, gece ve hava koşulları test edildi. Gerçek cihazda sesin işitsel kalitesi ve görsel hareket hissi ayrıca değerlendirilmelidir.

Ceylan kontrolleri: 14, 30 ve 60 birim ada yarıçapında iki bağımsız ceylanın 20 dakikalık hareketi sayısal olarak kontrol edildi: ada sınırı, gövde mesafesi, adım büyüklüğü, farklı uzaklıklara dağılma, animasyon zamanının yeniden başlaması ve ada küçülmesi. Sabit rota kaldırıldı. iOS Simulator derlemesi başarılı.


## Dere ve boyut dengesi

- En küçük bitki 1,92 birim, en büyük ağaç 4,296 birim yüksekliğindedir; tüm bitkiler önceki sürüme göre her eksende tam yüzde 20 büyütülmüştür. Ceylan geometrisinin üzerinde en az yüzde 10 yükseklik payı, 120 bitki varyantında kontrol edildi. Yatay bitki boyutu en fazla 3,84 birimdir.
- Ormanın içinden kıvrımlı, turkuaz bir dere geçer. Kıyıda taşlar ve açık renkli bir yatak bulunur. Su parıltıları akış yönünde ilerler; arka plan ve Hareketi Azalt durumunda durur.
- Görev kayıtları ve bitki türleri korunur; dikim yuvaları dereye yer açan sabit kuru alanlara yerleşir. Ada büyüdükçe dere uzar. 1000 dikim yuvasının kuru alanda ve sıra genişletildiğinde sabit kaldığı kontrol edildi.
- Ceylanlar dereyi ahşap köprü üzerinden geçer. Gövdelerden kaçınan yol bulma, köprü girişlerine yönlendirir. Köprü üstünde ayak yüksekliği döşemeyi takip eder; suya ve korkuluklara girmezler. Köprüye yaklaşım alanları dikime kapalıdır.
- Arazi değişimlerinde tek dere nesnesi kalması ve akış animasyonlarının durdurulması test edildi.


## Serbest kelebek uçuşu

Dokuz kelebek bağımsız rastgele hedeflere yumuşak eğriler üzerinden uçar. Uçuş yüksekliği 0,9–5,5 birim arasında değişir. Her hedefte yeni yön ve süre seçilir; sabit yörünge tekrarlanmaz. Gece ve kötü havada gizlenme, arka planda ve Hareketi Azalt ile durma davranışları korunur. 14, 30, 60 birim adalarda dokuz kelebeğin yükseklik değişimi, sınırlar, süre döngüsü birleşimi ve durdurma/yeniden başlatma kontrolleri geçti.


## Katmanlı ve konumsal ses; ceylan anatomisi

- Rüzgâr, gündüz kuşları ve gece böcekleri bağımsız AVAudioPlayer döngüleridir. Gündüz/gece değişiminde kuş ve böcek katmanları 2,5 saniyede geçiş yapar.
- Dere boyunca üç SCNAudioSource/SCNAudioPlayer konumsal kaynağı bulunur. Kamera dinleyicidir; SceneKit uzaklık ve yönü miksler. Kaynakların oynatma hızları hafif farklıdır. Ada boyutu değiştiğinde ses konumları güncellenir. Yakın mesafede aşırı ses oluşmaması için kaynak ses seviyeleri sınırlıdır.
- Ses ilk açılışta kapalıdır. Sessiz anahtarına uyar, diğer müziklerle karışabilir. Arka plan, ses kesintisi ve kulaklık çıkarma olaylarında durdurma uygulanır. Gerçek cihazda kulaklıkla yön/uzaklık algısı ve ses dengesi kullanıcı tarafından dinlenerek değerlendirilmelidir.
- Ceylan modeli hâlâ kodla oluşturulur; dışarıdan gerçekçi bir 3D model kullanılmamıştır. Daha ince gövde, omuz/kalça hacmi, karın ve yan çizgiler, yüz işaretleri, göz/ burun materyalleri, iç kulak, kıvrımlı boynuzlar ve eklemli bacaklar eklendi. Arka dizler adım sırasında bükülür; ön bacaklar omuzdan toynağa düz kalır.
- Doğrulama: iOS Simulator derlemesi, dört ses dosyasının pakete dahil olması, mono PCM/tepe ve döngü sınırı kontrolleri, köprü rotaları ve 120 bitki varyantında ceylan/bitki boyut dengesi geçti.


## Ceylan yürüyüşü: yere basma ve eklemler

- Dünya konumunda tutulan ayak hedefleri sayesinde basma sırasında ayak kaymaz. Dört ayak sırayla adım atar; fazla gerilmek üzere olan ayağa öncelik verilir. Havada ayağın konumu yumuşak geçişle ilerler.
- İki parçalı bacak çözümü diz konumunu hesaplar. Köprü eğiminde gövde yüksekliği ayarlanarak kemik boylarının değişmesi önlenir. Ayak yüksekliği dar yürüme hattı yerine fiziksel döşeme genişliğini takip eder.
- Gövde ağırlık aktarımı, hafif baş hareketi, hızlanma/yavaşlama ve dönüşte adımlama eklendi. Kaydedilen görevler ve bitki büyüklükleri değişmez.
- GaitChecks.swift: dört ayağın adım atması, en az üç basan ayağın dünya konumunda kalması, köprü döşemesine basma, durma ve 15 dakikalık rastgele dolaşmada bacak uzunluklarının korunması kontrol edildi. Bu prosedürel animasyondur; hareket yakalama verisi kullanılmaz. Cihazda görsel değerlendirme gerekir.

## Dokunmaya tepki

- Ceylana dokununca yürüyüş 2,2 saniye durur; boyun kameraya doğru anatomik açı sınırı içinde döner, iki kulak hafifçe oynar ve başlangıç pozuna döner.
- Her tepkinin üçte birinde mevcut yol bulma sistemiyle 0,7–1,8 birim uzaklaşma denenir. Güvenli yol yoksa uzaklaşmaz. Dere, köprü, ağaç ve ada sınırı kontrolleri korunur.
- Tepki sürerken yeni dokunuşlar birikmez. Hareket azaltma veya arka plana geçiş tepkileri iptal eder ve pozu sıfırlar.
- DeerTouchChecks: durma, baş/kulak hareketi, temizleme, hareketsiz durumda tepki engeli ve 408 güvenli uzaklaşma hedefi doğrulandı. Ön bacak düzlüğü ve arka bacak uzunlukları ayrıca StraightFrontLegChecks ile kontrol edildi.

## Ormanı ortalama

- Ortala düğmesi kamera sürükleme ivmesini durdurur; yakınlaştırma, görüş açısı, dönüş ve kontrol hedefini birlikte sıfırlar.
- Kamera mesafesi ada yarıçapı ve ekran oranından hesaplanır; başlık ve alt kontroller için dikey boşluk ayrılır. İlk yerleşimde ve ekran boyutu değişince yeniden kadrajlanır; normal görev/saat güncellemeleri kullanıcının kamerasını sıfırlamaz.
- CameraFitChecks: 12 ekran/yarıçap birleşimi, 240 ardışık sıfırlama, kamera sayısı, hedef/görüş açısı ve ada/ağaç sınırlarının kadraja sığması doğrulandı.

## Su içme ve ceylan sesi

- Ceylanlar zaman zaman kendi kıyılarındaki ulaşılabilir ve ağaçlardan uzak noktalara gider; suya doğru dönüp yaklaşık yedi saniyelik baş eğme/içme/kaldırma hareketi yapar. Ayakları karada kalır. Dokunma su içmeyi keser; normal dolaşma sonrasında devam eder.
- Dokunmada ForestDeer.wav adlı özgün, sentezlenmiş 0,85 saniyelik yumuşak ses konumsal olarak çalınır. Gerçek ceylan kaydı değildir. Ses seviyesi 0,28; global tekrar aralığı en az 2,5 saniyedir. Doğa sesi kapalıyken, sessiz modda, arka planda veya ses kesintisinde çalmaz.
- DeerDrinkChecks: 15 dakikalık dolaşmada suya baş uzatma, kuru ve sabit ayaklar, yeniden yürüyüş, kıyı/ağaç kontrolleri geçti. WAV mono, düşük tepe seviyeli ve paket içinde doğrulandı.

## Arazi genişlemesi ve beyaz tavşanlar

- Ada yarıçapı önceki formülün 1,20 katıdır; genişlik ve derinlik %20 artar. Ağaç boyutları ve kayıtlı görevler korunur. Kamera, dere ve hayvanların dolaşma sınırları yeni yarıçapı kullanır.
- Ceylan kök ölçeği tüm eksenlerde 0,95 yapıldı. Su içme pozundaki baş uzanması yeni ölçeğe göre ayarlandı.
- Üç beyaz, pembe iç kulaklı tavşan bağımsız rastgele kısa sıçrayışlarla dolaşır. Dere, köprü korkuluğu, ağaç gövdeleri ve ada sınırları mevcut yol kontrolünü kullanır. Arka plan ve hareket azaltmada dururlar. Ayrıntılı davranış/etkileşim eklenmedi.
- RabbitChecks: beş dakikalık üç bağımsız rota, kuru zemin, sınırlar, döngü geçişi, durdurma/yeniden başlatma ve çoğalmama geçti. Küçülen ceylanla 15 dakikalık su içme/dolaşma kontrolü de geçti.

## Yuva yaklaşımı, bağlı boyun ve dere yüzeyi

- Uzun tavşan hedefleri en fazla 1 birimlik, 0,6 saniyelik sıçrayışlara bölünür; aralarda kısa duraklama vardır. Yuvaya yalnızca son adım tamamlanınca girilir. Dokunma sonrası uzaklaşma da aynı hız sınırını kullanır.
- Ceylan içerken boyun pivotu (0, 0,66, -0,30) sabit kalır. Gövde ve bacak bağlantıları birlikte 0,22 birime kadar alçalır; boyun 1,72 radyan öne eğilir. Ağız sığ kıyı yüzeyine ulaşır, ayaklar karada kalır.
- Sığ kıyı şeridi 1,14 yarı genişliğinde; ana su yüzeyinde 128×128 üretilmiş renk ve normal dokuları, düşük pürüzlülük ve yavaş kayan dalgalar vardır. Parıltılar inceltildi; arka plan/hareket azaltmada animasyonlar durur.
- PolishChecks: uzun yuvaya normal adımlarla ulaşma (50 ms içinde en çok 0,124 birim), sabit boyun bağlantısı ve suya uzanma, UV/doku varlığı, su animasyonu yaşam döngüsü geçti. iOS derlemesi başarılı.
