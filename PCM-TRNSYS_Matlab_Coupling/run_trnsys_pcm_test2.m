% Bu betik TRNSYS'i MATLAB içinden bir kez başlatır, simülasyon bitene kadar bekler ve Type155 sonuçlarını okur.

%% TRNSYS ve deck dosyası yollarının tanımlanması

trnExe = 'C:\TRNSYS18\Exe\TRNExe.exe'; % Bilgisayarınızdaki TRNSYS 18 çalıştırılabilir dosyasının tam yolunu tanımlar.
deckFile = 'F:\PAPERS\SOLAR-ORC Optimizasyon\pcm\GSHP_V8_0_MATLAB.dck'; % Type155 eklenmiş Test 2 deck dosyasının tam yolunu tanımlar.

%% TRNSYS ve deck dosyası yollarının doğrulanması

if exist(trnExe, 'file') ~= 2 % TRNSYS çalıştırılabilir dosyasının belirtilen konumda bulunup bulunmadığını kontrol eder.
    error('TRNExe.exe bulunamadi: %s', trnExe); % TRNSYS yolu yanlışsa açıklayıcı bir hata üretir.
end % TRNSYS çalıştırılabilir dosyası kontrol bloğunu sonlandırır.
if exist(deckFile, 'file') ~= 2 % Test 2 deck dosyasının belirtilen konumda bulunup bulunmadığını kontrol eder.
    error('TRNSYS deck dosyasi bulunamadi: %s', deckFile); % Deck yolu yanlışsa açıklayıcı bir hata üretir.
end % Deck dosyası kontrol bloğunu sonlandırır.

%% MATLAB çalışma klasörünün proje klasörüne geçirilmesi

projectFolder = fileparts(deckFile); % Deck dosyasının bulunduğu proje klasörünü belirler.
oldFolder = pwd; % Betik bittikten sonra geri dönebilmek için mevcut MATLAB klasörünü saklar.
folderCleanup = onCleanup(@() cd(oldFolder)); % Betik hata verse bile MATLAB'ın eski klasöre dönmesini garanti eden temizlik nesnesi oluşturur.
cd(projectFolder); % Type155 betiklerinin ve sonuç dosyalarının bulunacağı TRNSYS proje klasörüne geçer.

%% Gerekli Type155 betiklerinin kontrol edilmesi

requiredFiles = {'type155initialize_001.m', 'type155simulate_001.m', 'type155terminate_001.m'}; % Type155'in çalışması için gerekli üç MATLAB dosyasının adlarını tanımlar.
for fileIndex = 1:numel(requiredFiles) % Gerekli Type155 dosyalarının her birini sırayla kontrol eden döngüyü başlatır.
    if exist(fullfile(projectFolder, requiredFiles{fileIndex}), 'file') ~= 2 % İlgili Type155 dosyasının proje klasöründe bulunup bulunmadığını kontrol eder.
        error('Gerekli Type155 dosyasi bulunamadi: %s', requiredFiles{fileIndex}); % Eksik Type155 dosyasının adını belirten açıklayıcı hata üretir.
    end % Tek bir Type155 dosyası kontrol bloğunu sonlandırır.
end % Bütün Type155 dosyalarını kontrol eden döngüyü sonlandırır.

%% Önceki çalışmadan kalan sonuç dosyalarının temizlenmesi

resultMatFile = fullfile(projectFolder, 'pcm_test2_results.mat'); % Simülasyon sonunda beklenen MAT sonuç dosyasının tam yolunu oluşturur.
resultCsvFile = fullfile(projectFolder, 'pcm_test2_results.csv'); % Simülasyon sonunda beklenen CSV sonuç dosyasının tam yolunu oluşturur.
if exist(resultMatFile, 'file') == 2 % Önceki çalışmadan kalmış MAT sonuç dosyasının bulunup bulunmadığını kontrol eder.
    delete(resultMatFile); % Yeni çalışmanın sonucuyla karışmaması için eski MAT dosyasını siler.
end % Eski MAT dosyası temizleme bloğunu sonlandırır.
if exist(resultCsvFile, 'file') == 2 % Önceki çalışmadan kalmış CSV sonuç dosyasının bulunup bulunmadığını kontrol eder.
    delete(resultCsvFile); % Yeni çalışmanın sonucuyla karışmaması için eski CSV dosyasını siler.
end % Eski CSV dosyası temizleme bloğunu sonlandırır.

%% TRNSYS simülasyonunun başlatılması ve tamamlanmasının beklenmesi

command = sprintf('start "" /wait /b "%s" "%s" /n', trnExe, deckFile); % TRNSYS'i arka planda başlatıp bitene kadar MATLAB'ı bekletecek Windows komutunu oluşturur.
fprintf('TRNSYS baslatiliyor:\n%s\n', command); % Çalıştırılacak TRNSYS komutunu MATLAB komut penceresine yazar.
[status, consoleText] = system(command); % TRNSYS sürecini başlatır, simülasyon tamamlanana kadar bekler ve çıkış durumunu alır.
fprintf('%s\n', consoleText); % TRNSYS tarafından komut satırına yazılan metni MATLAB komut penceresinde gösterir.
if status ~= 0 % TRNSYS sürecinin hata koduyla kapanıp kapanmadığını kontrol eder.
    error('TRNSYS hata kodu %d ile sonlandi; .log ve .lst dosyalarini kontrol edin.', status); % Başarısız çalışmada hata kodunu göstererek betiği durdurur.
end % TRNSYS süreç durumu kontrol bloğunu sonlandırır.

%% Simülasyon sonucunun oluşturulduğunun doğrulanması

if exist(resultMatFile, 'file') ~= 2 % Type155 sonlandırma betiğinin beklenen MAT sonucunu üretip üretmediğini kontrol eder.
    error('TRNSYS bitti ancak %s olusmadi; Type155 kurulumunu ve MATLAB uyumlulugunu kontrol edin.', resultMatFile); % Sonuç dosyası yoksa Type155 bağlantısına işaret eden açıklayıcı hata üretir.
end % MAT sonuç dosyası kontrol bloğunu sonlandırır.

%% Sonuç tablosunun yüklenmesi ve hızlı kontrolü

loadedResults = load(resultMatFile, 'resultTable'); % Type155 tarafından kaydedilen sonuç tablosunu MAT dosyasından yükler.
resultTable = loadedResults.resultTable; % Yüklenen yapı içindeki sonuç tablosunu kolay kullanım için ayrı bir değişkene aktarır.
fprintf('Simülasyon basariyla tamamlandi ve %d sonuc satiri okundu.\n', height(resultTable)); % Başarılı çalışmayı ve toplam sonuç satırı sayısını bildirir.
disp(resultTable(1:min(5, height(resultTable)), :)); % Sonuç tablosunun ilk beş satırını hızlı kontrol amacıyla komut penceresinde gösterir.
disp(resultTable(max(1, height(resultTable) - 4):height(resultTable), :)); % Sonuç tablosunun son beş satırını simülasyon bitişini kontrol etmek için gösterir.

%% Tank sıcaklığı ve PCM enerjisinin birlikte çizdirilmesi

figure; % MATLAB'da kullanıcıya gösterilecek yeni bir grafik penceresi oluşturur.
yyaxis left; % Çift eksenli grafiğin sol düşey eksenini etkinleştirir.
plot(resultTable.StateTime_h, resultTable.TtankMid_C, 'LineWidth', 1.2); % Tank orta nokta sıcaklığını sol eksende zamana karşı çizer.
ylabel('Tank midpoint temperature [°C]'); % Sol düşey eksenin fiziksel büyüklüğünü ve birimini tanımlar.
yyaxis right; % Çift eksenli grafiğin sağ düşey eksenini etkinleştirir.
plot(resultTable.StateTime_h, resultTable.Epcm1_kWh, 'LineWidth', 1.2); % PCM1 enerji içeriğini sağ eksende zamana karşı çizer.
ylabel('Energy in PCM module 1 [kWh]'); % Sağ düşey eksenin fiziksel büyüklüğünü ve birimini tanımlar.
xlabel('Simulation time [h]'); % Grafiğin yatay eksenini simülasyon zamanı olarak etiketler.
title('MATLAB–TRNSYS Type840 Test 2'); % Grafiğe testin amacını belirten açıklayıcı bir başlık ekler.
grid on; % Eğrilerin daha kolay okunması için grafik ızgarasını açar.
