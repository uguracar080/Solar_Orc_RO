% Type155 Unit ID=1 için başlangıç dosyasıdır; TRNSYS ilk zaman adımının ilk çağrısında bu betiği çalıştırır.

%% Ortak değişkenlerin ve ayar yapısının hazırlanması

global PCM_TEST_CFG PCM_TEST_LOG PCM_TEST_LAST_STATE_TIME PCM_TEST_ROW_COUNT; % Üç Type155 betiği arasında kalıcı olarak paylaşılacak değişkenleri tanımlar.
PCM_TEST_CFG = struct(); % Teste ait sabit ayarları tek bir yapı içinde toplamak için boş bir yapı oluşturur.

%% Şarj ve deşarj çalışma ayarlarının tanımlanması

PCM_TEST_CFG.chargeTemperature_C = 55.0; % Şarj sırasında DP1'e gönderilecek sabit giriş sıcaklığını 55 °C olarak tanımlar.
PCM_TEST_CFG.dischargeTemperature_C = 35.0; % Deşarj sırasında DP2'ye gönderilecek sabit giriş sıcaklığını 35 °C olarak tanımlar.
PCM_TEST_CFG.activeMassFlow_kg_h = 3600.0; % Aktif şarj veya deşarj sırasında uygulanacak debiyi 3600 kg/h olarak tanımlar.
PCM_TEST_CFG.cycleLength_h = 24.0; % Günlük çalışma profilinin tekrar süresini 24 saat olarak tanımlar.
PCM_TEST_CFG.chargeStart_h = 0.0; % Günlük şarj başlangıcını saat 0 olarak tanımlar.
PCM_TEST_CFG.chargeStop_h = 6.0; % Günlük şarj bitişini saat 6 olarak tanımlar.
PCM_TEST_CFG.dischargeStart_h = 12.0; % Günlük deşarj başlangıcını saat 12 olarak tanımlar.
PCM_TEST_CFG.dischargeStop_h = 18.0; % Günlük deşarj bitişini saat 18 olarak tanımlar.
PCM_TEST_CFG.timeTolerance_h = 1.0e-9; % Zaman sınırlarında kayan nokta yuvarlama hatalarını önlemek için küçük bir tolerans tanımlar.

%% Sonuç ve ara yedek dosyalarının tanımlanması

PCM_TEST_CFG.resultMatFile = fullfile(pwd, 'pcm_test2_results.mat'); % Sonuçların kaydedileceği MAT dosyasının tam yolunu oluşturur.
PCM_TEST_CFG.resultCsvFile = fullfile(pwd, 'pcm_test2_results.csv'); % Sonuçların kaydedileceği CSV dosyasının tam yolunu oluşturur.
PCM_TEST_CFG.checkpointFile = fullfile(pwd, 'pcm_test2_checkpoint.mat'); % Simülasyon sırasında ara yedeklerin kaydedileceği dosyanın tam yolunu oluşturur.

%% Sonuç kayıt değişkenlerinin başlatılması

PCM_TEST_LOG = zeros(0, 13); % Her satırı bir zaman noktasını temsil edecek 13 sütunlu boş sonuç matrisi oluşturur.

PCM_TEST_LAST_STATE_TIME = -Inf; % Aynı tank durumunun iki kez kaydedilmesini önlemek için son kaydedilen zamanı eksi sonsuzla başlatır.

PCM_TEST_ROW_COUNT = 0; % Kaydedilmiş sonuç satırı sayacını sıfırdan başlatır.

%% Önceki çalışmadan kalan dosyaların temizlenmesi

if exist(PCM_TEST_CFG.resultMatFile, 'file') == 2 % Önceki çalışmadan kalmış MAT sonuç dosyasının bulunup bulunmadığını kontrol eder.
    delete(PCM_TEST_CFG.resultMatFile); % Eski MAT sonuç dosyasını silerek yeni testin sonuçlarıyla karışmasını önler.
end % MAT dosyası kontrol bloğunu sonlandırır.

if exist(PCM_TEST_CFG.resultCsvFile, 'file') == 2 % Önceki çalışmadan kalmış CSV sonuç dosyasının bulunup bulunmadığını kontrol eder.
    delete(PCM_TEST_CFG.resultCsvFile); % Eski CSV sonuç dosyasını silerek yeni testin sonuçlarıyla karışmasını önler.
end % CSV dosyası kontrol bloğunu sonlandırır.

if exist(PCM_TEST_CFG.checkpointFile, 'file') == 2 % Önceki çalışmadan kalmış ara yedek dosyasının bulunup bulunmadığını kontrol eder.
    delete(PCM_TEST_CFG.checkpointFile); % Eski ara yedek dosyasını siler.
end % Ara yedek dosyası kontrol bloğunu sonlandırır.

%% İlk zaman adımı için kontrol komutlarının oluşturulması

hourInDay = mod(t + PCM_TEST_CFG.timeTolerance_h, PCM_TEST_CFG.cycleLength_h); % TRNSYS zamanını 0–24 saat arasındaki günlük saate dönüştürür.
chargeOn = double(hourInDay >= PCM_TEST_CFG.chargeStart_h && hourInDay < PCM_TEST_CFG.chargeStop_h); % Günlük saat 0–6 aralığındaysa şarj komutunu 1, aksi durumda 0 yapar.
dischargeOn = double(hourInDay >= PCM_TEST_CFG.dischargeStart_h && hourInDay < PCM_TEST_CFG.dischargeStop_h); % Günlük saat 12–18 aralığındaysa deşarj komutunu 1, aksi durumda 0 yapar.
chargeMassFlow_kg_h = PCM_TEST_CFG.activeMassFlow_kg_h * chargeOn; % Şarj aktifken 3600 kg/h, pasifken 0 kg/h olacak DP1 debisini hesaplar.
dischargeMassFlow_kg_h = PCM_TEST_CFG.activeMassFlow_kg_h * dischargeOn; % Deşarj aktifken 3600 kg/h, pasifken 0 kg/h olacak DP2 debisini hesaplar.
outputs = [PCM_TEST_CFG.chargeTemperature_C, chargeMassFlow_kg_h, PCM_TEST_CFG.dischargeTemperature_C, dischargeMassFlow_kg_h]; % Type155'in dört çıkışını sırasıyla DP1 sıcaklığı, DP1 debisi, DP2 sıcaklığı ve DP2 debisi olarak oluşturur.

%% Başlangıç durumunun ara yedek dosyasına kaydedilmesi

save(PCM_TEST_CFG.checkpointFile, 'PCM_TEST_CFG', 'PCM_TEST_LOG'); % Başlangıç ayarlarını ve boş sonuç matrisini bir ara yedek dosyasına kaydeder.
