% Type155_CallingMatlab.m
% Bu tek M-file, kullanıcının TRNSYS 18 Type155 sürümünün beklediği klasik arayüzle çalışır.

mFileErrorCode = 100; % Type155 çağrısının başladığını belirtir; dosyanın sonunda bu değer mutlaka 0 yapılacaktır.

try % MATLAB tarafında oluşabilecek hataları yakalamak ve tanı dosyasına yazmak için korumalı kod bloğunu başlatır.

    nInputs = trnInfo(3); % Type155 bileşeninde tanımlanan toplam MATLAB giriş sayısını TRNSYS bilgi dizisinden okur.

    nOutputs = trnInfo(6); % Type155 bileşeninde tanımlanan toplam MATLAB çıkış sayısını TRNSYS bilgi dizisinden okur.

    if nInputs < 0 % Giriş sayısının geçersiz olup olmadığını kontrol eder.

        error('Type155 giriş sayısı geçersizdir.'); % Geçersiz giriş sayısı varsa MATLAB hatası üretir.

    end % Giriş sayısı kontrolünü tamamlar.

    if nOutputs < 4 % Bu test için gerekli dört çıkışın Type155 içinde tanımlanıp tanımlanmadığını kontrol eder.

        error('Type155 en az 4 çıkışla tanımlanmalıdır.'); % Dört çıkıştan az tanımlanmışsa MATLAB hatası üretir.

    end % Çıkış sayısı kontrolünü tamamlar.

    T_charge_C = 55.0; % Type840 DP1 girişine gönderilecek sabit şarj sıcaklığını 55 °C olarak tanımlar.

    T_discharge_C = 35.0; % Type840 DP2 girişine gönderilecek sabit deşarj sıcaklığını 35 °C olarak tanımlar.

    m_active_kg_h = 3600.0; % Şarj veya deşarj aktifken kullanılacak kütlesel debiyi 3600 kg/h olarak tanımlar.

    cycleLength_h = 24.0; % Tekrarlanan günlük işletme çevriminin süresini 24 saat olarak tanımlar.

    timeTolerance_h = 1.0e-9; % Zaman aralığı sınırlarındaki kayan nokta yuvarlama hatalarını azaltmak için küçük bir tolerans tanımlar.

    elapsedTime_h = trnTime - trnStartTime; % Simülasyonun başlangıcından itibaren geçen süreyi saat cinsinden hesaplar.

    timeInCycle_h = mod(elapsedTime_h + timeTolerance_h, cycleLength_h); % Geçen süreyi 0 ile 24 saat arasındaki günlük çevrim zamanına dönüştürür.

    chargeOn = double(timeInCycle_h >= 0.0 && timeInCycle_h < 6.0); % Günlük saat 0–6 arasındaysa şarj komutunu 1, diğer zamanlarda 0 yapar.

    dischargeOn = double(timeInCycle_h >= 12.0 && timeInCycle_h < 18.0); % Günlük saat 12–18 arasındaysa deşarj komutunu 1, diğer zamanlarda 0 yapar.

    m_charge_kg_h = m_active_kg_h * chargeOn; % DP1 şarj debisini program durumuna göre 3600 veya 0 kg/h olarak hesaplar.

    m_discharge_kg_h = m_active_kg_h * dischargeOn; % DP2 deşarj debisini program durumuna göre 3600 veya 0 kg/h olarak hesaplar.

    m_charge_kg_h = max(0.0, m_charge_kg_h); % DP1 debisinin hiçbir koşulda negatif olmamasını garanti eder.

    m_discharge_kg_h = max(0.0, m_discharge_kg_h); % DP2 debisinin hiçbir koşulda negatif olmamasını garanti eder.

    trnOutputs(1:nOutputs) = 0.0; % Type155'in bütün çıkışlarını her çağrıda güvenli başlangıç değeri olan sıfıra ayarlar.

    trnOutputs(1) = T_charge_C; % Type155 Output 1 üzerinden Type840 DP1 giriş sıcaklığına 55 °C gönderir.

    trnOutputs(2) = m_charge_kg_h; % Type155 Output 2 üzerinden Type840 DP1 giriş debisine 0 veya 3600 kg/h gönderir.

    trnOutputs(3) = T_discharge_C; % Type155 Output 3 üzerinden Type840 DP2 giriş sıcaklığına 35 °C gönderir.

    trnOutputs(4) = m_discharge_kg_h; % Type155 Output 4 üzerinden Type840 DP2 giriş debisine 0 veya 3600 kg/h gönderir.

    trnOutputs(~isfinite(trnOutputs)) = 0.0; % NaN veya sonsuz bir çıkış oluşursa Type840'a hatalı değer gitmesini önlemek için bunu sıfırlar.

    trnOutputs(2) = max(0.0, trnOutputs(2)); % DP1 kütlesel debisinin son çıkış aşamasında da negatif olmadığını garanti eder.

    trnOutputs(4) = max(0.0, trnOutputs(4)); % DP2 kütlesel debisinin son çıkış aşamasında da negatif olmadığını garanti eder.

    mFileErrorCode = 0; % M-file çağrısının başarıyla tamamlandığını Type155'e bildirir.

catch ME % Yukarıdaki işlemlerden biri hata verirse hata yakalama bölümünü başlatır.

    trnOutputs = [55.0, 0.0, 35.0, 0.0]; % Hata durumunda Type840'a negatif veya tanımsız değer yerine güvenli sıcaklık ve sıfır debi değerleri gönderir.

    diagnosticFile = fullfile(pwd, 'Type155_Matlab_Error.txt'); % MATLAB hata ayrıntılarının yazılacağı tanı dosyasının tam yolunu oluşturur.

    fileId = fopen(diagnosticFile, 'a'); % Tanı dosyasını mevcut içeriği koruyarak sonuna ekleme modunda açar.

    if fileId ~= -1 % Tanı dosyasının başarıyla açılıp açılmadığını kontrol eder.

        fprintf(fileId, 'TRNSYS time [h]: %.12f\n', trnTime); % Hatanın oluştuğu TRNSYS simülasyon zamanını tanı dosyasına yazar.

        fprintf(fileId, 'MATLAB error: %s\n', ME.message); % MATLAB'ın kısa hata mesajını tanı dosyasına yazar.

        fprintf(fileId, 'MATLAB report:\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); % Hatanın ayrıntılı MATLAB raporunu tanı dosyasına yazar.

        fprintf(fileId, '------------------------------------------------------------\n'); % Ardışık hata kayıtlarını ayırmak için çizgi ekler.

        fclose(fileId); % Tanı dosyasını güvenli biçimde kapatır.

    end % Tanı dosyası yazma kontrolünü tamamlar.

    mFileErrorCode = 900; % MATLAB tarafında hata oluştuğunu Type155'e 900 koduyla bildirir.

end % Hata yakalama bloğunu tamamlar.
