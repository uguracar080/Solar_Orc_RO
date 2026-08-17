function out = test_Du2014_energy_noERD() % Du-2014 without-ERD case icin pump energy ve SEC verification testini yapar.

%% TEST BASLIGI % Command Window'da energy verification basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 5 - DU 2014 WITHOUT-ERD ENERGY / SEC VERIFICATION (LEGACY v1.4)\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% PUBLISHED DU-2014 CASE INPUTLARI % Table 3-4 degerlerini tanimlar.

Qf_total_m3h = 195.3; % Du-2014 system feed flow degerini tanimlar.
Cf_kg_m3 = 35.0; % Du-2014 feed seawater salinity degerini tanimlar.
T_C = 20.0; % Du-2014 feed water temperature degerini tanimlar.
P1_gauge_MPa = 6.55; % Verification sonucuyla uyumlu stage-1 gauge operating pressure degerini tanimlar.
P2_gauge_MPa = 7.79; % Verification sonucuyla uyumlu stage-2 gauge operating pressure degerini tanimlar.
N_PV_stage1 = 22; % Du-2014 stage-1 PV sayisini tanimlar.
N_PV_stage2 = 14; % Du-2014 stage-2 PV sayisini tanimlar.
n_elements_stage1 = 3; % Du-2014 stage-1 element/PV sayisini tanimlar.
n_elements_stage2 = 7; % Du-2014 stage-2 element/PV sayisini tanimlar.
age_years = 3.0; % Du-2014 design period ile uyumlu membrane age degerini tanimlar.

%% PUBLISHED ENERJI PARAMETRELERI % Du-2014 Table 3 pump ve motor verimlerini tanimlar.

P_SWIP_MPa = 0.5; % Du-2014 SWIP outlet pressure degerini tanimlar.
eta_SWIP = 0.65; % Du-2014 SWIP/centrifugal pump efficiency degerini tanimlar.
eta_HPP = 0.75; % Du-2014 high-pressure pump efficiency degerini tanimlar.
eta_BP = 0.65; % Du-2014 booster pump efficiency degerini tanimlar.
eta_motor = 0.98; % Du-2014 electric motor efficiency degerini tanimlar.

%% PUBLISHED REFERENCE OUTPUTLARI % Table 4-5 enerji performans degerlerini tanimlar.

SEC_ref_kWh_m3 = 4.88; % Du-2014 without-ERD specific energy consumption degerini tanimlar.
Power_ref_kW = 585.66; % Du-2014 Table 5 exergy-input/power-input degerini secondary reference olarak tanimlar.

%% N=30 PUBLISHED-GRID MODEL COZUMU % Published Du verification ile ayni discretization ve aging ayarlarini uygular.

mem_base = ro_membrane_SW30XLE400(); % SW30XLE-400 base parametrelerini yukler.
mem = ro_apply_membrane_age_du2014(mem_base, age_years); % Du-2014 3-yillik aging parametrelerini uygular.
P1_abs_MPa = P1_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-1 gauge pressure degerini absolute basinca cevirir.
P2_abs_MPa = P2_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-2 gauge pressure degerini absolute basinca cevirir.
sys = ro_system_two_stage_interstage_pressure(Qf_total_m3h, Cf_kg_m3, P1_abs_MPa, P2_abs_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, 30, mem); % Du published N=30 grid ile iki-stage sistemi cozer.

%% SWIP PUMP GUC HESABI % Du-2014 Eq.97 ilk terimi ile seawater intake pump gucunu hesaplar.

W_SWIP_kW = P_SWIP_MPa * Qf_total_m3h / (3.6 * eta_SWIP * eta_motor); % SWIP pump elektrik gucunu kW olarak hesaplar.

%% HIGH-PRESSURE PUMP GUC HESABI % Du-2014 Eq.97 ikinci terimi ile ana HPP gucunu hesaplar.

W_HPP_kW = P1_gauge_MPa * Qf_total_m3h / (3.6 * eta_HPP * eta_motor); % Main high-pressure pump elektrik gucunu kW olarak hesaplar.

%% INTERSTAGE BOOSTER PUMP GUC HESABI % Stage-1 brine basinç cikisini stage-2 operating pressure'a yukseltmek icin gereken gucu hesaplar.

P1out_gauge_MPa = sys.stage1_PV.Pout_abs_MPa - mem.permeate_pressure_abs_MPa; % Stage-1 PV cikis basincini gauge MPa birimine cevirir.
deltaP_BP_MPa = max(P2_gauge_MPa - P1out_gauge_MPa, 0.0); % Interstage booster pump pressure rise degerini hesaplar.
Q_BP_m3h = sys.stage1_PV.Qb_m3h * N_PV_stage1; % Interstage booster pump'tan gecen toplam stage-1 brine debisini hesaplar.
W_BP_kW = deltaP_BP_MPa * Q_BP_m3h / (3.6 * eta_BP * eta_motor); % Interstage booster pump elektrik gucunu kW olarak hesaplar.

%% TOPLAM ELEKTRIK VE SEC % Without-ERD sistem toplam pump power ve specific energy consumption degerlerini hesaplar.

W_total_kW = W_SWIP_kW + W_HPP_kW + W_BP_kW; % SWIP, HPP ve interstage booster pump guclerini toplar.
SEC_model_kWh_m3 = W_total_kW / max(sys.Qp_total_m3h, 1.0e-12); % Toplam elektrik gucunu permeate debisine bolerek SEC degerini hesaplar.

%% HATA HESAPLARI % Published Du energy sonuclarina gore relative error degerlerini hesaplar.

Error_SEC_pct = 100.0 * (SEC_model_kWh_m3 - SEC_ref_kWh_m3) / SEC_ref_kWh_m3; % SEC relative error degerini hesaplar.
Error_Power_pct = 100.0 * (W_total_kW - Power_ref_kW) / Power_ref_kW; % Power-input relative error degerini hesaplar.

%% SONUC TABLOSU % Energy verification sonuclarini tablo halinde gosterir.

Parameter = {'SWIP pump power [kW]'; 'HPP power [kW]'; 'Interstage booster power [kW]'; 'Total pump power [kW]'; 'SEC [kWh/m3]'}; % Energy sonuc parametre adlarini tanimlar.
Reference = [NaN; NaN; NaN; Power_ref_kW; SEC_ref_kWh_m3]; % Published reference degerlerini tanimlar.
Model = [W_SWIP_kW; W_HPP_kW; W_BP_kW; W_total_kW; SEC_model_kWh_m3]; % Model enerji degerlerini tanimlar.
result_table = table(Parameter, Reference, Model); % Energy verification sonuc tablosunu olusturur.
disp(result_table); % Energy verification tablosunu Command Window'da gosterir.

fprintf('Stage-1 brine flow to booster : %.3f m3/h\n', Q_BP_m3h); % Interstage booster pump debisini yazdirir.
fprintf('Stage-1 outlet pressure       : %.4f MPa(g)\n', P1out_gauge_MPa); % Stage-1 cikis gauge pressure degerini yazdirir.
fprintf('Booster pressure rise         : %.4f MPa\n', deltaP_BP_MPa); % Booster pressure rise degerini yazdirir.
fprintf('SEC relative error            : %.3f %%\n', Error_SEC_pct); % SEC relative error degerini yazdirir.
fprintf('Total-power relative error    : %.3f %%\n', Error_Power_pct); % Total power relative error degerini yazdirir.
fprintf('Not: Total-power karsilastirmasinda Du Table 5 exergy input degeri secondary reference olarak kullanilmistir.\n'); % Power reference yorumunu aciklar.

%% CIKTI YAPISI % Test sonucunu struct olarak dondurur.

out.result_table = result_table; % Energy verification sonuc tablosunu kaydeder.
out.SEC_model_kWh_m3 = SEC_model_kWh_m3; % Model SEC degerini kaydeder.
out.SEC_reference_kWh_m3 = SEC_ref_kWh_m3; % Published SEC degerini kaydeder.
out.SEC_error_pct = Error_SEC_pct; % SEC relative error degerini kaydeder.
out.total_power_kW = W_total_kW; % Model total pump power degerini kaydeder.
out.power_reference_kW = Power_ref_kW; % Secondary power reference degerini kaydeder.
out.power_error_pct = Error_Power_pct; % Power relative error degerini kaydeder.
out.system = sys; % Ayrintili Du system sonucunu kaydeder.

end % Fonksiyonu sonlandirir.
