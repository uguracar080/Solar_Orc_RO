% Type155 Unit ID=1 için sonlandırma dosyasıdır; TRNSYS simülasyonun son çağrısında bu betiği çalıştırır.
global PCM_TEST_CFG PCM_TEST_LOG PCM_TEST_LAST_STATE_TIME PCM_TEST_ROW_COUNT; % Simülasyon boyunca oluşturulan ortak ayar ve sonuç değişkenlerine erişir.
if isempty(PCM_TEST_CFG) % Başlangıç ayarlarının hâlâ MATLAB çalışma alanında bulunup bulunmadığını kontrol eder.
    error('PCM_TEST_CFG sonlandirma sirasinda bulunamadi.'); % Ayarlar yoksa sonuçların güvenilir biçimde kaydedilemeyeceğini belirten hata üretir.
end % Başlangıç ayarı kontrol bloğunu sonlandırır.
hourInDay = mod(t + PCM_TEST_CFG.timeTolerance_h, PCM_TEST_CFG.cycleLength_h); % Son TRNSYS zamanını günlük 0–24 saat aralığına dönüştürür.
chargeOn = double(hourInDay >= PCM_TEST_CFG.chargeStart_h && hourInDay < PCM_TEST_CFG.chargeStop_h); % Son zamanda şarj komutunun etkin olup olmadığını belirler.
dischargeOn = double(hourInDay >= PCM_TEST_CFG.dischargeStart_h && hourInDay < PCM_TEST_CFG.dischargeStop_h); % Son zamanda deşarj komutunun etkin olup olmadığını belirler.
chargeMassFlow_kg_h = PCM_TEST_CFG.activeMassFlow_kg_h * chargeOn; % Son zamandaki DP1 şarj debisini hesaplar.
dischargeMassFlow_kg_h = PCM_TEST_CFG.activeMassFlow_kg_h * dischargeOn; % Son zamandaki DP2 deşarj debisini hesaplar.
outputs = [PCM_TEST_CFG.chargeTemperature_C, chargeMassFlow_kg_h, PCM_TEST_CFG.dischargeTemperature_C, dischargeMassFlow_kg_h]; % Type155'in son çağrısında da dört çıkış değişkeninin geçerli olmasını sağlar.
if numel(inputs) >= 7 % Son çağrıda yedi Type840 çıktısının erişilebilir olup olmadığını kontrol eder.
    finalStateTime_h = t; % Son çağrıdaki tank durumunu simülasyon bitiş zamanı ile etiketler.
    finalStateIsNew = finalStateTime_h > PCM_TEST_LAST_STATE_TIME + PCM_TEST_CFG.timeTolerance_h; % Son tank durumunun daha önce kaydedilip kaydedilmediğini kontrol eder.
    if finalStateIsNew % Son tank durumu yeni ise son satırı eklemeye başlar.
        finalRow = [t, finalStateTime_h, PCM_TEST_CFG.chargeTemperature_C, chargeMassFlow_kg_h, PCM_TEST_CFG.dischargeTemperature_C, dischargeMassFlow_kg_h, inputs(1), inputs(2), inputs(3), inputs(4), inputs(5), inputs(6), inputs(7)]; % Son komutları ve son Type840 çıktılarını tek bir sonuç satırında toplar.
        PCM_TEST_LOG(end + 1, :) = finalRow; % Son sonuç satırını sonuç matrisine ekler.
        PCM_TEST_LAST_STATE_TIME = finalStateTime_h; % En son kaydedilen durum zamanını simülasyon bitiş zamanı olarak günceller.
        PCM_TEST_ROW_COUNT = PCM_TEST_ROW_COUNT + 1; % Toplam sonuç satırı sayısını bir artırır.
    end % Son durum kayıt bloğunu sonlandırır.
end % Son çağrı girişleri kontrol bloğunu sonlandırır.
columnNames = {'CommandTime_h', 'StateTime_h', 'TchargeIn_C', 'Mcharge_kg_h', 'TdischargeIn_C', 'Mdischarge_kg_h', 'Tdp1Out_C', 'Tdp2Out_C', 'Epcm1_kWh', 'TtankMid_C', 'Estore_kWh', 'Pdp1_kW', 'Pdp2_kW'}; % Sonuç tablosunda kullanılacak açıklayıcı sütun adlarını tanımlar.
resultTable = array2table(PCM_TEST_LOG, 'VariableNames', columnNames); % Sayısal sonuç matrisini sütun adlarına sahip MATLAB tablosuna dönüştürür.
save(PCM_TEST_CFG.resultMatFile, 'PCM_TEST_CFG', 'PCM_TEST_LOG', 'resultTable'); % Ayarları, ham matrisi ve tabloyu MAT dosyasına kaydeder.
writetable(resultTable, PCM_TEST_CFG.resultCsvFile); % Sonuç tablosunu Excel ve diğer programlarda açılabilecek CSV dosyasına yazar.
temperatureFigure = figure('Visible', 'off'); % Tank orta sıcaklığını çizmek için ekranda görünmeyen bir grafik penceresi oluşturur.
plot(resultTable.StateTime_h, resultTable.TtankMid_C, 'LineWidth', 1.2); % Tank orta nokta sıcaklığını gerçek tank durum zamanına karşı çizer.
grid on; % Sıcaklık grafiğinde okuma kolaylığı için ızgarayı açar.
xlabel('Simulation time [h]'); % Sıcaklık grafiğinin yatay eksen başlığını tanımlar.
ylabel('Tank midpoint temperature [°C]'); % Sıcaklık grafiğinin düşey eksen başlığını tanımlar.
title('MATLAB–TRNSYS Type840 Test 2: Tank midpoint temperature'); % Sıcaklık grafiğine açıklayıcı bir başlık ekler.
saveas(temperatureFigure, fullfile(pwd, 'pcm_test2_tank_temperature.png')); % Sıcaklık grafiğini proje klasörüne PNG dosyası olarak kaydeder.
close(temperatureFigure); % Bellekte açık kalan sıcaklık grafik penceresini kapatır.
energyFigure = figure('Visible', 'off'); % PCM enerji içeriğini çizmek için ekranda görünmeyen ikinci grafik penceresi oluşturur.
plot(resultTable.StateTime_h, resultTable.Epcm1_kWh, 'LineWidth', 1.2); % PCM1 enerji içeriğini gerçek tank durum zamanına karşı çizer.
grid on; % PCM enerji grafiğinde okuma kolaylığı için ızgarayı açar.
xlabel('Simulation time [h]'); % PCM enerji grafiğinin yatay eksen başlığını tanımlar.
ylabel('Energy in PCM module 1 [kWh]'); % PCM enerji grafiğinin düşey eksen başlığını doğru fiziksel birimle tanımlar.
title('MATLAB–TRNSYS Type840 Test 2: PCM energy'); % PCM enerji grafiğine açıklayıcı bir başlık ekler.
saveas(energyFigure, fullfile(pwd, 'pcm_test2_pcm_energy.png')); % PCM enerji grafiğini proje klasörüne PNG dosyası olarak kaydeder.
close(energyFigure); % Bellekte açık kalan PCM enerji grafik penceresini kapatır.
if exist(PCM_TEST_CFG.checkpointFile, 'file') == 2 % Simülasyon başarıyla bittikten sonra ara yedek dosyasının bulunup bulunmadığını kontrol eder.
    delete(PCM_TEST_CFG.checkpointFile); % Nihai sonuçlar kaydedildiği için artık gerekli olmayan ara yedek dosyasını siler.
end % Ara yedek temizleme bloğunu sonlandırır.
fprintf('Type155 PCM Test 2 tamamlandi: %d satir kaydedildi.\n', height(resultTable)); % MATLAB komut penceresine kaydedilen toplam sonuç satırı sayısını yazar.
fprintf('CSV sonucu: %s\n', PCM_TEST_CFG.resultCsvFile); % Oluşturulan CSV sonuç dosyasının tam yolunu MATLAB komut penceresine yazar.
fprintf('MAT sonucu: %s\n', PCM_TEST_CFG.resultMatFile); % Oluşturulan MAT sonuç dosyasının tam yolunu MATLAB komut penceresine yazar.
