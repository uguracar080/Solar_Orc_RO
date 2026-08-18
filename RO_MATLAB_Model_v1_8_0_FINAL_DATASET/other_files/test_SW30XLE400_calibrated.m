function out = test_SW30XLE400_calibrated() % Datasheet noktasindan A ve B kalibrasyonunu yapar ve sonuclari raporlar.

%% TEST BASLIGI % Command Window'da calibration test basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 1B - SW30XLE-400 DATASHEET-BASED A/B CALIBRATION\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% KALIBRASYON % 100 segmentli detailed model ile A ve B parametrelerini kalibre eder.

cal = ro_calibrate_AB_datasheet(100); % Standard manufacturer test noktasina gore A ve B calibration islemini calistirir.

%% KARSILASTIRMA TABLOSU % Orijinal ve kalibre membran parametrelerini tablo halinde gosterir.

Parameter = {'A [kg/(m2 s Pa)]'; 'B [kg/(m2 s)]'; 'Permeate flow [m3/day]'; 'Salt rejection [%]'}; % Karsilastirma parametre adlarini tanimlar.
Original_or_Reference = [cal.A_original; cal.B_original; cal.Qp_ref_m3_day; cal.rejection_ref_pct]; % Orijinal/reference degerleri tanimlar.
Calibrated = [cal.A_calibrated; cal.B_calibrated; cal.Qp_model_m3_day; cal.rejection_model_pct]; % Kalibre/model degerlerini tanimlar.
result_table = table(Parameter, Original_or_Reference, Calibrated); % Calibration sonuc tablosunu olusturur.
disp(result_table); % Calibration sonuc tablosunu Command Window'da gosterir.

fprintf('A_cal / A_Lu-Du = %.5f\n', cal.A_ratio); % A calibration oranini yazdirir.
fprintf('B_cal / B_Lu-Du = %.5f\n', cal.B_ratio); % B calibration oranini yazdirir.
fprintf('Not: Bu islem bagimsiz validation degildir; manufacturer standard test noktasindan parameter identification yapar.\n'); % Calibration ile validation arasindaki farki aciklar.
fprintf('Not: Lu/Du A ve B degerleri literature-reproduction dali icin ayrica korunur.\n'); % Orijinal literature parametrelerinin korunacagini belirtir.

%% CIKTI YAPISI % Test sonucunu struct olarak dondurur.

out = cal; % Calibration sonuc yapisini fonksiyon ciktisi yapar.

end % Fonksiyonu sonlandirir.
