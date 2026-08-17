function out = test_Mokhtari2016() % Mokhtari-2016 optimum RO noktasini reconstruction benchmark olarak test eder.

%% TEST BASLIGI % Command Window'da benchmark basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 2 - MOKHTARI 2016 OPTIMUM RO RECONSTRUCTION\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% REFERENCE BENCHMARK % Mokhtari-2016 Table 11 ve ilgili metindeki optimum degerleri tanimlar.

Qf_ref_m3h = 223.27; % Mokhtari optimum total feed flow degerini tanimlar.
Pf_ref_abs_MPa = 4.68; % Mokhtari optimum feed pressure degerini absolute MPa olarak kullanir.
N_PV_total = 45; % Mokhtari optimum toplam PV sayisini tanimlar.
n_elements_per_PV = 5; % Mokhtari optimum element/PV sayisini tanimlar.
R_ref = 0.7614; % Mokhtari optimum overall recovery fraction degerini tanimlar.
Cp_ref_mgL = 183.34; % Mokhtari optimum permeate concentration degerini tanimlar.
W_ref_kW = 362.2; % Mokhtari optimum high-pressure pump power degerini tanimlar.

%% RECONSTRUCTION KABULLERI % Makalede tam verilmeyen case parametrelerini acik sekilde tanimlar.

Cf_reconstructed_kg_m3 = 13.0; % Makaledeki maksimum Caspian TDS=13000 ppm bilgisini feed salinity olarak kullanir.
T_reconstructed_C = 25.0; % Makalenin RO reference temperature degeri olan 25 C'yi kullanir.
P_in_abs_MPa = 0.101325; % High-pressure pump girisini atmosfer basinci olarak tanimlar.
eta_pump = 0.80; % Mokhtari power-cycle metnindeki pump efficiency degerini tanimlar.
eta_motor = 0.98; % Mokhtari power-cycle metnindeki shaft/motor efficiency degerini tanimlar.
N_segments = 150; % Grid-independence sonucuna dayanarak refined reconstruction testinde 150 axial segment kullanir.

%% STAGE PV DAGILIMI % Overall recovery ve toplam PV sayisindan integer stage dagilimi yeniden kurar.

allocation = ro_allocate_two_stage_pvs(N_PV_total, R_ref); % Stage-ratio fikrine gore iki-stage PV dagilimini hesaplar.
N_PV_stage1 = allocation.N_stage1; % Yeniden kurulan stage-1 PV sayisini alir.
N_PV_stage2 = allocation.N_stage2; % Yeniden kurulan stage-2 PV sayisini alir.

fprintf('Reconstructed PV allocation : Stage-1 = %d, Stage-2 = %d\n', N_PV_stage1, N_PV_stage2); % Yeniden kurulan stage dagilimini yazdirir.
fprintf('Target stage ratio          : %.4f\n', allocation.RR_target); % Mokhtari stage-ratio hedefini yazdirir.
fprintf('Integer stage ratio         : %.4f\n', allocation.RR_integer); % Integer dagilimda gerceklesen stage ratio degerini yazdirir.

%% IKI-STAGE RO COZUMU % Detailed Du-2014 PV solver ile Mokhtari sistem konfigurasyonunu cozer.

mem = ro_membrane_SW30XLE400(); % SW30XLE-400 membran parametrelerini yukler.
sys = ro_system_two_stage(Qf_ref_m3h, Cf_reconstructed_kg_m3, Pf_ref_abs_MPa, T_reconstructed_C, N_PV_stage1, N_PV_stage2, n_elements_per_PV, n_elements_per_PV, N_segments, mem); % Iki-stage detailed RO cozumunu calistirir.

%% PUMP POWER KONTROLU % Mokhtari 362.2 kW sonucunu ayni basinc/debi/verimlerle yeniden hesaplar.

W_model_kW = ro_pump_power(Qf_ref_m3h, P_in_abs_MPa, Pf_ref_abs_MPa, eta_pump, eta_motor); % High-pressure pump elektrik gucunu hesaplar.

%% MODEL SONUCLARI % Sistem recovery ve permeate concentration degerlerini rapor birimlerine cevirir.

R_model = sys.overall_recovery; % Detailed model overall recovery fraction degerini alir.
Cp_model_mgL = sys.Cp_kg_m3 * 1000.0; % Permeate concentration degerini mg/L birimine cevirir.
Qp_model_m3h = sys.Qp_total_m3h; % Toplam permeate debisini kaydeder.

%% HATA HESAPLARI % Reference benchmark'a gore relative error degerlerini hesaplar.

error_R_pct = 100.0 * (R_model - R_ref) / R_ref; % Overall recovery relative error degerini hesaplar.
error_Cp_pct = 100.0 * (Cp_model_mgL - Cp_ref_mgL) / Cp_ref_mgL; % Permeate concentration relative error degerini hesaplar.
error_W_pct = 100.0 * (W_model_kW - W_ref_kW) / W_ref_kW; % Pump power relative error degerini hesaplar.

%% SONUC TABLOSU % Reference ve model benchmark degerlerini karsilastirir.

Parameter = {'Overall recovery [%]'; 'Permeate concentration [mg/L]'; 'HPP electrical power [kW]'; 'Permeate flow [m3/h]'}; % Benchmark parametre adlarini tanimlar.
Reference = [100.0 * R_ref; Cp_ref_mgL; W_ref_kW; Qf_ref_m3h * R_ref]; % Makaledeki reference degerleri hesaplar.
Model = [100.0 * R_model; Cp_model_mgL; W_model_kW; Qp_model_m3h]; % Detailed model degerlerini tanimlar.
RelativeError_pct = [error_R_pct; error_Cp_pct; error_W_pct; 100.0 * (Qp_model_m3h - Qf_ref_m3h * R_ref) / (Qf_ref_m3h * R_ref)]; % Her parametre icin relative error degerini hesaplar.
result_table = table(Parameter, Reference, Model, RelativeError_pct); % Benchmark karsilastirma tablosunu olusturur.
disp(result_table); % Benchmark karsilastirma tablosunu Command Window'da gosterir.

%% TEKNIK KONTROLLER % PV bazli isletme sinirlarini hizli olarak raporlar.

fprintf('Stage-1 feed/PV             : %.4f m3/h\n', sys.stage1_PV.Qf_m3h); % Stage-1 representative PV feed debisini yazdirir.
fprintf('Stage-2 feed/PV             : %.4f m3/h\n', sys.stage2_PV.Qf_m3h); % Stage-2 representative PV feed debisini yazdirir.
fprintf('Stage-1 pressure drop       : %.4f MPa\n', sys.stage1_PV.pressure_drop_MPa); % Stage-1 PV pressure drop degerini yazdirir.
fprintf('Stage-2 pressure drop       : %.4f MPa\n', sys.stage2_PV.pressure_drop_MPa); % Stage-2 PV pressure drop degerini yazdirir.
fprintf('Stage-1 maximum CPF         : %.4f\n', sys.stage1_PV.max_CPF); % Stage-1 maximum CPF degerini yazdirir.
fprintf('Stage-2 maximum CPF         : %.4f\n', sys.stage2_PV.max_CPF); % Stage-2 maximum CPF degerini yazdirir.
fprintf('Not: Recovery/Cp testi bir reconstruction validation testidir; stage split ve exact feed salinity makalede acik verilmemistir.\n'); % Benchmark sinirlamasini aciklar.
fprintf('Not: Pump-power kontrolu ise Q, Pin, Pf, eta_pump ve eta_motor ile dogrudan yeniden uretilmektedir.\n'); % Pump power kontrolunun daha dogrudan oldugunu belirtir.

%% CIKTI YAPISI % Test sonuclarini struct icinde toplar.

out.result_table = result_table; % Benchmark karsilastirma tablosunu kaydeder.
out.model_recovery_pct = 100.0 * R_model; % Model recovery degerini yuzde olarak kaydeder.
out.model_Cp_mgL = Cp_model_mgL; % Model permeate concentration degerini kaydeder.
out.model_pump_kW = W_model_kW; % Model pump power degerini kaydeder.
out.error_recovery_pct = error_R_pct; % Recovery relative error degerini kaydeder.
out.error_Cp_pct = error_Cp_pct; % Permeate concentration relative error degerini kaydeder.
out.error_pump_pct = error_W_pct; % Pump power relative error degerini kaydeder.
out.allocation = allocation; % Reconstructed stage PV dagilimini kaydeder.
out.system = sys; % Ayrintili iki-stage RO sonucunu kaydeder.

end % Fonksiyonu sonlandirir.
