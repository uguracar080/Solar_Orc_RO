function out = test_SW30XLE400_datasheet() % SW30XLE-400 nominal manufacturer verilerine karsi tek-element consistency testi yapar.

%% TEST BASLIGI % Command Window'da test basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 1 - SW30XLE-400 SINGLE-ELEMENT CONSISTENCY\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% MEMBRAN VE STANDARD TEST GIRDISI % Manufacturer nominal test kosullarini tanimlar.

mem = ro_membrane_SW30XLE400(); % SW30XLE-400 membran parametrelerini yukler.
Qp_ref_m3h = mem.nominal_permeate_m3_day / 24.0; % Nominal permeate debisini m3/h birimine cevirir.
Qf_test_m3h = Qp_ref_m3h / mem.standard_test_recovery; % Standard recovery kullanarak test feed debisini hesaplar.
feed_above_range = Qf_test_m3h > mem.feed_flow_max_m3h; % Standard testten turetilen feed debisinin Lu/Du tasarim araligini asip asmadigini kontrol eder.
Cf_test_kg_m3 = mem.standard_test_feed_kg_m3; % Standard feed salinity degerini tanimlar.
Pf_test_abs_MPa = mem.standard_test_pressure_abs_MPa; % Standard feed pressure degerini tanimlar.
T_test_C = mem.standard_test_temperature_C; % Standard feed temperature degerini tanimlar.
N_segments = 70; % Baslangic consistency testi icin axial segment sayisini tanimlar.

%% TEK-ELEMENT COZUMU % Bir adet SW30XLE-400 elementini detailed model ile cozer.

pv = ro_pv_du2014(Qf_test_m3h, Cf_test_kg_m3, Pf_test_abs_MPa, T_test_C, 1, N_segments, mem); % Tek-element PV cozumunu calistirir.

%% PERFORMANS GOSTERGELERI % Model sonucunu nominal manufacturer degerleri ile karsilastirir.

Qp_model_m3_day = pv.Qp_m3h * 24.0; % Model permeate debisini m3/day birimine cevirir.
rejection_model = 1.0 - pv.Cp_kg_m3 / Cf_test_kg_m3; % Model salt rejection fraction degerini hesaplar.
error_Qp_pct = 100.0 * (Qp_model_m3_day - mem.nominal_permeate_m3_day) / mem.nominal_permeate_m3_day; % Nominal permeate flow relative error degerini hesaplar.
error_rejection_point = 100.0 * (rejection_model - mem.nominal_rejection_fraction); % Salt rejection yuzde-puan farkini hesaplar.

%% SONUC TABLOSU % Reference ve model degerlerini tablo halinde yazdirir.

Parameter = {'Permeate flow [m3/day]'; 'Salt rejection [%]'; 'Element recovery [%]'; 'PV pressure drop [MPa]'}; % Sonuc tablosu parametre adlarini tanimlar.
Reference = [mem.nominal_permeate_m3_day; 100.0 * mem.nominal_rejection_fraction; 100.0 * mem.standard_test_recovery; NaN]; % Reference degerlerini tanimlar.
Model = [Qp_model_m3_day; 100.0 * rejection_model; 100.0 * pv.recovery; pv.pressure_drop_MPa]; % Model degerlerini tanimlar.
result_table = table(Parameter, Reference, Model); % Sonuc karsilastirma tablosunu olusturur.
disp(result_table); % Sonuc tablosunu Command Window'da gosterir.

fprintf('Permeate flow relative error : %.3f %%\n', error_Qp_pct); % Permeate flow relative error degerini yazdirir.
fprintf('Rejection percentage-point   : %.4f point\n', error_rejection_point); % Rejection yuzde-puan farkini yazdirir.
fprintf('Standard testten turetilen feed: %.3f m3/h; Lu/Du nominal tasarim ust siniri: %.3f m3/h.\n', Qf_test_m3h, mem.feed_flow_max_m3h); % Test feed debisi ile kaynak tasarim araligini yazdirir.
if feed_above_range % Standard test feed debisi tasarim araligini asiyorsa kontrol eder.
    fprintf('UYARI: Bu consistency noktasinda feed debisi Lu/Du 0.8-16 m3/h tasarim araliginin ustundedir.\n'); % Debi araligi uyarisini yazdirir.
end % Debi araligi uyarisini sonlandirir.
fprintf('Not: Bu test exact WAVE/ROSA validasyonu degil, manufacturer consistency kontroludur.\n'); % Testin amacini aciklayan notu yazdirir.
fprintf('Not: Du-2014, Aref degerinin transmembrane osmotic pressure ile degisebildigini; veri yoksa sabit Aref kullaniminin ilk yaklasim oldugunu belirtir.\n'); % Sabit Aref yaklasiminin sinirlamasini aciklar.

%% CIKTI YAPISI % Sonuclari daha sonra kullanmak icin struct icine toplar.

out.result_table = result_table; % Karsilastirma tablosunu kaydeder.
out.Qf_test_m3h = Qf_test_m3h; % Test feed debisini kaydeder.
out.model_Qp_m3_day = Qp_model_m3_day; % Model permeate debisini kaydeder.
out.model_rejection_pct = 100.0 * rejection_model; % Model salt rejection degerini yuzde olarak kaydeder.
out.error_Qp_pct = error_Qp_pct; % Permeate flow relative error degerini kaydeder.
out.error_rejection_point = error_rejection_point; % Rejection yuzde-puan farkini kaydeder.
out.pv = pv; % Ayrintili PV sonucunu kaydeder.

end % Fonksiyonu sonlandirir.
