MATLAB–TRNSYS TYPE840 TEST 2 KURULUMU

Bu paket, Type155 kullanarak MATLAB'ın her TRNSYS zaman adımında şu dört değeri üretmesini sağlar:
1) DP1 giriş sıcaklığı: 55 °C
2) DP1 giriş debisi: 0–6 h arasında 3600 kg/h, diğer zamanlarda 0
3) DP2 giriş sıcaklığı: 35 °C
4) DP2 giriş debisi: 12–18 h arasında 3600 kg/h, diğer zamanlarda 0

24 saatlik profil her gün tekrar eder.

TRNSYS TYPE155 AYARLARI
- Type version: 0
- Number of inputs: 7
- Number of outputs: 4
- Callimg Mode/Component kind: 10 (real-time controller) Type155’i gerçek zamanlı denetleyici modunda çalıştırır. Bu modda MATLAB her zaman adımının ilk çağrısında, önceki zaman adımının yakınsamış Type840 çıktılarıyla çağrılır. Type155, t, inputs ve info değişkenlerini MATLAB’a gönderir; MATLAB da outputs isimli diziyi oluşturup TRNSYS’e döndürür.
- Ignore engine close: 0
- M-file ID: 1

TYPE840 -> TYPE155 BAĞLANTILARI
1) Type840 Output 1  : Outlet temperature DP1
2) Type840 Output 3  : Outlet temperature DP2
3) Type840 Output 18 : Energy in PCM module1
4) Type840 Output 48 : Fluid temperature-10 (mevcut modelinizde tank orta noktası)
5) Type840 Output 11 : Total energy of store
6) Type840 Output 24 : Power through double port1
7) Type840 Output 25 : Power through double port2

TYPE155 -> TYPE840 BAĞLANTILARI
1) Type155 Output 1 -> Type840 Input 1: Inlet temperature DP1
2) Type155 Output 2 -> Type840 Input 2: Inlet mass flow rate DP1
3) Type155 Output 3 -> Type840 Input 3: Inlet temperature DP2
4) Type155 Output 4 -> Type840 Input 4: Inlet mass flow rate DP2

TEST 2 İÇİN
- Type14, Charge pompası, Discharge pompası ve m_hourly denklemlerinin Type840 bağlantılarını kesin.
- Bunlar projede kalabilir ancak Type840 girişlerine bağlı olmamalıdır.
- STEP = 1/60 h (60 saniye) kullanın.
- STOP = 49 h veya 120 h seçebilirsiniz.
- Type840 supercooling sıcaklığını 50 °C olarak bırakın.
- Type65 online plotter otomatik MATLAB çalıştırmasında süreci bekletirse kapatın veya Shut off Online parametresini 1 yapın.
- Üç Type155 MATLAB dosyasını .dck dosyasıyla aynı klasöre kopyalayın.
- İlk denemeyi Simulation Studio içinden çalıştırın.
- Başarılı çalışmada pcm_test2_results.csv ve pcm_test2_results.mat oluşur.

ÖNEMLİ
Type155, TRNSYS tarafından ayrı bir MATLAB engine süreci açar. Type155.dll dosyasının kurulu MATLAB sürümü ve 64-bit mimariyle uyumlu olması gerekir.
Bu ilk testte zaman adımını TRNSYS ilerletir; MATLAB canlı girişleri üretir ve tank çıktılarını kaydeder.
Optimizasyon aşamasında dış MATLAB döngüsü her aday için deck parametrelerini yazacak, TRNSYS'i bir kez çalıştıracak ve yıllık sonuçları okuyacaktır.
