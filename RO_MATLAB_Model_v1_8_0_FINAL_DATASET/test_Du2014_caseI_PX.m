function out = test_Du2014_caseI_PX() % Du-2014 Case Study I pressure-exchanger konfigürasyonunu published Table 4'e karsi test eder.

%% TEST BASLIGI % Command Window'da PX verification basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 6 - DU 2014 CASE I / PX VERIFICATION\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% PUBLISHED PX CASE INPUTLARI % Du-2014 Table 3-4 PX case degerlerini tanimlar.

Qf_total_m3h = 206.6; % Published system feed flow degerini tanimlar.
Cf_kg_m3 = 35.0; % Published feed seawater salinity degerini tanimlar.
T_C = 20.0; % Published feed temperature degerini tanimlar.
P1_gauge_MPa = 7.14; % Published stage-1 operating pressure degerini gauge yorumuyla tanimlar.
P2_gauge_MPa = 7.49; % Published stage-2 operating pressure degerini gauge yorumuyla tanimlar.
N_PV_stage1 = 20; % Published stage-1 PV sayisini tanimlar.
N_PV_stage2 = 16; % Published stage-2 PV sayisini tanimlar.
n_elements_stage1 = 5; % Published stage-1 element/PV sayisini tanimlar.
n_elements_stage2 = 4; % Published stage-2 element/PV sayisini tanimlar.
age_years = 3.0; % Du design-period membrane age degerini tanimlar.
N_segments = 30; % Published Du case-study integration grid sayisini tanimlar.
eta_px = 0.95; % Published pressure-exchanger efficiency degerini tanimlar.
Qhpp_ref_m3h = 121.1; % Published high-pressure-pump feed flow degerini tanimlar.
R_ref = 0.5808; % Published overall recovery fraction degerini tanimlar.
Cp_ref_mgL = 500.0; % Published product concentration degerini tanimlar.
Javg_ref_LMH = 19.67; % Published system average flux degerini tanimlar.
SEC_ref_kWh_m3 = 3.22; % Published PX specific energy consumption degerini tanimlar.

%% PUMP VE PRETREATMENT PARAMETRELERI % Du-2014 Table 3 energy inputlarini tanimlar.

P_SWIP_MPa = 0.5; % SWIP outlet pressure degerini tanimlar.
filter_loss_MPa = 0.3; % Pretreatment pressure-loss degerini tanimlar.
eta_SWIP = 0.65; % SWIP pump efficiency degerini tanimlar.
eta_HPP = 0.75; % High-pressure pump efficiency degerini tanimlar.
eta_BP = 0.65; % Booster pump efficiency degerini tanimlar.
eta_motor = 0.98; % Electric motor efficiency degerini tanimlar.

%% PX EMPIRIK BELIRSIZLIK SENARYOLARI % Eq.50 pressure unit ve Eq.94 low-side pressure yorumlarini tarar.

LeakageUnit = {'MPa'; 'MPa'; 'bar'; 'bar'}; % Eq.50 pressure-unit yorumlarini tanimlar.
PpxLowIn_MPa = [0.0; 0.2; 0.0; 0.2]; % Eq.94 PX low-pressure inlet gauge pressure senaryolarini tanimlar.

%% SONUC DIZILERI % Dort PX senaryosunun published metrics sonuclarini saklar.

Recovery_pct = zeros(4, 1); % Model overall recovery sonuc dizisini olusturur.
Cp_mgL = zeros(4, 1); % Model product concentration sonuc dizisini olusturur.
AverageFlux_LMH = zeros(4, 1); % Model average flux sonuc dizisini olusturur.
Qhpp_m3h = zeros(4, 1); % Model HPP feed-flow sonuc dizisini olusturur.
SEC_kWh_m3 = zeros(4, 1); % Model SEC sonuc dizisini olusturur.
PXoutPressure_MPa = zeros(4, 1); % PX high-side outlet pressure sonuc dizisini olusturur.
Leakage_pct = zeros(4, 1); % PX leakage/lubrication sonuc dizisini olusturur.
Mix_pct = zeros(4, 1); % PX volumetric mixing sonuc dizisini olusturur.
Feasible = false(4, 1); % Membrane-side feasibility sonuc dizisini olusturur.
Score = zeros(4, 1); % Published metrics combined-score sonuc dizisini olusturur.

%% SENARYO TARAMASI % Dort PX empirical interpretation kombinasyonunu detailed model ile cozer.

for i = 1:4 % Tum PX diagnostic senaryolarini sirayla cozer.
    sys = ro_system_two_stage_px_du2014(Qf_total_m3h, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, age_years, LeakageUnit{i}, PpxLowIn_MPa(i)); % Mevcut PX interpretation ile coupled membrane-PX system cozumunu yapar.
    energy = ro_energy_du2014(sys, P_SWIP_MPa, filter_loss_MPa, eta_SWIP, eta_HPP, eta_BP, eta_motor, true); % Mevcut PX system icin physical pump-energy ve SEC degerlerini hesaplar.
    Recovery_pct(i) = 100.0 * sys.overall_recovery; % Overall recovery degerini yuzde olarak kaydeder.
    Cp_mgL(i) = sys.Cp_kg_m3 * 1000.0; % Product concentration degerini mg/L olarak kaydeder.
    AverageFlux_LMH(i) = sys.average_flux_LMH; % System average flux degerini kaydeder.
    Qhpp_m3h(i) = sys.Qhpp_m3h; % Main HPP feed flow degerini kaydeder.
    SEC_kWh_m3(i) = energy.SEC_kWh_m3; % Specific energy consumption degerini kaydeder.
    PXoutPressure_MPa(i) = sys.px.Ppxhout_gauge_MPa; % PX high-side outlet gauge pressure degerini kaydeder.
    Leakage_pct(i) = sys.px.Lpx_pct; % PX leakage/lubrication yuzdesini kaydeder.
    Mix_pct(i) = sys.px.Mix_pct; % PX volumetric mixing yuzdesini kaydeder.
    Feasible(i) = sys.feasible; % Membrane-side feasibility flag degerini kaydeder.
    eR = 100.0 * (sys.overall_recovery - R_ref) / R_ref; % Recovery relative error degerini hesaplar.
    eCp = 100.0 * (Cp_mgL(i) - Cp_ref_mgL) / Cp_ref_mgL; % Product concentration relative error degerini hesaplar.
    eJ = 100.0 * (AverageFlux_LMH(i) - Javg_ref_LMH) / Javg_ref_LMH; % Average flux relative error degerini hesaplar.
    eQhpp = 100.0 * (Qhpp_m3h(i) - Qhpp_ref_m3h) / Qhpp_ref_m3h; % HPP feed-flow relative error degerini hesaplar.
    eSEC = 100.0 * (SEC_kWh_m3(i) - SEC_ref_kWh_m3) / SEC_ref_kWh_m3; % SEC relative error degerini hesaplar.
    Score(i) = sqrt(eR^2 + eCp^2 + eJ^2 + eQhpp^2 + eSEC^2); % Bes published metricten combined verification score degerini hesaplar.
end % PX senaryo tarama dongusunu sonlandirir.

%% SONUC TABLOSU % Published PX benchmark'a gore tum senaryolari karsilastirir.

result_table = table(LeakageUnit, PpxLowIn_MPa, Recovery_pct, Cp_mgL, AverageFlux_LMH, Qhpp_m3h, SEC_kWh_m3, PXoutPressure_MPa, Leakage_pct, Mix_pct, Feasible, Score); % PX verification sonuc tablosunu olusturur.
result_table = sortrows(result_table, 'Score', 'ascend'); % Combined score degerine gore en iyi senaryoyu en uste tasir.
disp(result_table); % PX verification sonuc tablosunu Command Window'da gosterir.

fprintf('Published reference : R = %.2f %%, Cp = %.1f mg/L, Javg = %.2f LMH, Qhpp = %.1f m3/h, SEC = %.2f kWh/m3\n', 100.0 * R_ref, Cp_ref_mgL, Javg_ref_LMH, Qhpp_ref_m3h, SEC_ref_kWh_m3); % Published PX benchmark degerlerini yazdirir.
fprintf('PX efficiency        : %.1f %%\n', 100.0 * eta_px); % Published PX efficiency degerini yazdirir.
fprintf('Not: Eq.50 pressure unit kaynakta acik etiketlenmedigi icin MPa ve bar yorumlari ayri test edilmektedir.\n'); % Leakage correlation unit belirsizligini aciklar.
fprintf('Not: Eq.94 low-side pressure icin 0 ve post-filter 0.2 MPa(g) yorumlari ayri test edilmektedir.\n'); % PX low-side pressure belirsizligini aciklar.

%% CIKTI YAPISI % PX verification sonucunu struct olarak dondurur.

out.result_table = result_table; % Siralanmis PX verification sonuc tablosunu kaydeder.
out.best_case = result_table(1, :); % En iyi combined-score senaryosunu kaydeder.
out.reference_recovery_pct = 100.0 * R_ref; % Published recovery reference degerini kaydeder.
out.reference_Cp_mgL = Cp_ref_mgL; % Published product concentration reference degerini kaydeder.
out.reference_flux_LMH = Javg_ref_LMH; % Published average flux reference degerini kaydeder.
out.reference_Qhpp_m3h = Qhpp_ref_m3h; % Published HPP feed-flow reference degerini kaydeder.
out.reference_SEC_kWh_m3 = SEC_ref_kWh_m3; % Published SEC reference degerini kaydeder.

end % Fonksiyonu sonlandirir.
