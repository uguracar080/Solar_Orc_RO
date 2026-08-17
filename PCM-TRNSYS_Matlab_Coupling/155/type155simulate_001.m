% Type155 Unit ID=1 için normal zaman adımı dosyasıdır; TRNSYS simülasyon boyunca bu betiği çağırır.
global PCM_TEST_CFG PCM_TEST_LOG PCM_TEST_LAST_STATE_TIME PCM_TEST_ROW_COUNT; % Başlangıç betiğinde oluşturulan ortak değişkenlere erişir.
if isempty(PCM_TEST_CFG) % Başlangıç ayarlarının MATLAB çalışma alanında mevcut olup olmadığını kontrol eder.
    error('PCM_TEST_CFG bulunamadi; type155initialize_001.m calismamis olabilir.'); % Başlangıç dosyası çalışmadıysa simülasyonu açıklayıcı bir hatayla durdurur.
end % Başlangıç ayarı kontrol bloğunu sonlandırır.
if numel(inputs) < 7 % TRNSYS'ten MATLAB'a beklenen yedi tank çıktısının gelip gelmediğini kontrol eder.
    error('Type155 en az 7 input bekliyor; TRNSYS Type155 baglantilarini kontrol edin.'); % Eksik bağlantı varsa simülasyonu açıklayıcı bir hatayla durdurur.
end % Type155 giriş sayısı kontrol bloğunu sonlandırır.
hourInDay = mod(t + PCM_TEST_CFG.timeTolerance_h, PCM_TEST_CFG.cycleLength_h); % Mevcut TRNSYS zamanını günlük 0–24 saat aralığına indirger.
chargeOn = double(hourInDay >= PCM_TEST_CFG.chargeStart_h && hourInDay < PCM_TEST_CFG.chargeStop_h); % Günlük saat 0–6 aralığındaysa şarjı etkinleştirir.
dischargeOn = double(hourInDay >= PCM_TEST_CFG.dischargeStart_h && hourInDay < PCM_TEST_CFG.dischargeStop_h); % Günlük saat 12–18 aralığındaysa deşarjı etkinleştirir.
chargeMassFlow_kg_h = PCM_TEST_CFG.activeMassFlow_kg_h * chargeOn; % DP1 şarj debisini aktif durumda 3600 kg/h, diğer zamanlarda 0 kg/h yapar.
dischargeMassFlow_kg_h = PCM_TEST_CFG.activeMassFlow_kg_h * dischargeOn; % DP2 deşarj debisini aktif durumda 3600 kg/h, diğer zamanlarda 0 kg/h yapar.
outputs = [PCM_TEST_CFG.chargeTemperature_C, chargeMassFlow_kg_h, PCM_TEST_CFG.dischargeTemperature_C, dischargeMassFlow_kg_h]; % Type840'a gönderilecek dört canlı MATLAB çıkışını oluşturur.
timeStep_h = info(18); % TRNSYS zaman adımını saat biriminde INFO dizisinin 18. elemanından okur.
simulationStart_h = info(16); % TRNSYS simülasyon başlangıç zamanını saat biriminde INFO dizisinin 16. elemanından okur.
stateTime_h = max(t - timeStep_h, simulationStart_h); % Controller modunda inputs önceki yakınsamış adıma ait olduğundan tank durumunun gerçek zaman etiketini bir adım geriye kaydırır.
dp1OutletTemperature_C = inputs(1); % Type840 DP1 çıkış sıcaklığını Type155'in birinci girişinden okur.
dp2OutletTemperature_C = inputs(2); % Type840 DP2 çıkış sıcaklığını Type155'in ikinci girişinden okur.
pcmEnergy_kWh = inputs(3); % Type840 PCM1 enerji içeriğini Type155'in üçüncü girişinden okur.
tankMidTemperature_C = inputs(4); % Type840 tank orta nokta sıcaklığını Type155'in dördüncü girişinden okur.
totalStoreEnergy_kWh = inputs(5); % Type840 toplam depo enerjisini Type155'in beşinci girişinden okur.
dp1Power_kW = inputs(6); % Type840 DP1 üzerinden aktarılan gücü Type155'in altıncı girişinden okur.
dp2Power_kW = inputs(7); % Type840 DP2 üzerinden aktarılan gücü Type155'in yedinci girişinden okur.
isNewState = stateTime_h > PCM_TEST_LAST_STATE_TIME + PCM_TEST_CFG.timeTolerance_h; % Aynı zaman noktasının daha önce kaydedilip kaydedilmediğini kontrol eder.
if isNewState % Tank durumu yeni bir zaman noktasına aitse kayıt işlemini başlatır.
    newRow = [t, stateTime_h, PCM_TEST_CFG.chargeTemperature_C, chargeMassFlow_kg_h, PCM_TEST_CFG.dischargeTemperature_C, dischargeMassFlow_kg_h, dp1OutletTemperature_C, dp2OutletTemperature_C, pcmEnergy_kWh, tankMidTemperature_C, totalStoreEnergy_kWh, dp1Power_kW, dp2Power_kW]; % Mevcut komutları ve önceki yakınsamış tank durumunu tek bir sonuç satırında toplar.
    PCM_TEST_LOG(end + 1, :) = newRow; % Yeni sonuç satırını sonuç matrisinin sonuna ekler.
    PCM_TEST_LAST_STATE_TIME = stateTime_h; % En son kaydedilen tank durumunun zamanını günceller.
    PCM_TEST_ROW_COUNT = PCM_TEST_ROW_COUNT + 1; % Toplam kayıt satırı sayacını bir artırır.
end % Yeni zaman noktası kayıt bloğunu sonlandırır.
if PCM_TEST_ROW_COUNT > 0 && mod(PCM_TEST_ROW_COUNT, 600) == 0 % Her 600 yeni satırda bir ara yedek zamanı gelip gelmediğini kontrol eder.
    save(PCM_TEST_CFG.checkpointFile, 'PCM_TEST_CFG', 'PCM_TEST_LOG'); % O ana kadarki sonuçları simülasyon kesilmesine karşı ara yedek dosyasına kaydeder.
end % Periyodik ara yedek bloğunu sonlandırır.
