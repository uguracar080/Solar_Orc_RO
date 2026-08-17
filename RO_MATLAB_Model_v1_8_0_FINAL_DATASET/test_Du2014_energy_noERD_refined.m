function out = test_Du2014_energy_noERD_refined() % Du-2014 without-ERD case icin physical pressure-rise energy accounting testini yapar.

%% TEST BASLIGI % Command Window'da refined no-ERD enerji test basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 5B - DU 2014 WITHOUT-ERD REFINED ENERGY ACCOUNTING\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% PUBLISHED DU CASE % Du-2014 Table 3-4 no-ERD input ve reference degerlerini tanimlar.

Qf_total_m3h = 195.3; % Published system feed flow degerini tanimlar.
Cf_kg_m3 = 35.0; % Published feed seawater salinity degerini tanimlar.
T_C = 20.0; % Published feed temperature degerini tanimlar.
P1_gauge_MPa = 6.55; % Published stage-1 operating pressure degerini gauge yorumuyla tanimlar.
P2_gauge_MPa = 7.79; % Published stage-2 operating pressure degerini gauge yorumuyla tanimlar.
N_PV_stage1 = 22; % Published stage-1 PV sayisini tanimlar.
N_PV_stage2 = 14; % Published stage-2 PV sayisini tanimlar.
n_elements_stage1 = 3; % Published stage-1 element/PV sayisini tanimlar.
n_elements_stage2 = 7; % Published stage-2 element/PV sayisini tanimlar.
age_years = 3.0; % Du design-period aging degerini tanimlar.
N_segments = 30; % Published Du verification grid sayisini tanimlar.
SEC_ref = 4.88; % Published without-ERD SEC degerini tanimlar.
W_ref = 585.66; % Du Table 5 published power/exergy-input reference degerini tanimlar.

%% PUMP PARAMETRELERI % Du-2014 Table 3 pressure-loss ve pump efficiency degerlerini tanimlar.

P_SWIP_MPa = 0.5; % SWIP outlet pressure degerini tanimlar.
filter_loss_MPa = 0.3; % Pretreatment filter pressure-loss degerini tanimlar.
eta_SWIP = 0.65; % SWIP pump efficiency degerini tanimlar.
eta_HPP = 0.75; % Main HPP efficiency degerini tanimlar.
eta_BP = 0.65; % Booster pump efficiency degerini tanimlar.
eta_motor = 0.98; % Electric motor efficiency degerini tanimlar.

%% MEMBRAN SYSTEM COZUMU % Du aged membrane ile published no-ERD configuration'i cozer.

mem_base = ro_membrane_SW30XLE400(); % SW30XLE-400 base parametrelerini yukler.
mem = ro_apply_membrane_age_du2014(mem_base, age_years); % Du-2014 membrane aging parametrelerini uygular.
P1_abs_MPa = P1_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-1 pressure degerini internal absolute basinca cevirir.
P2_abs_MPa = P2_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-2 pressure degerini internal absolute basinca cevirir.
sys = ro_system_two_stage_interstage_pressure(Qf_total_m3h, Cf_kg_m3, P1_abs_MPa, P2_abs_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, mem); % Detailed no-ERD membrane system cozumunu yapar.

%% PHYSICAL ENERGY MODEL % Actual pressure rises kullanarak system pump power ve SEC degerlerini hesaplar.

energy = ro_energy_du2014(sys, P_SWIP_MPa, filter_loss_MPa, eta_SWIP, eta_HPP, eta_BP, eta_motor, false); % Physical pressure-rise energy accounting fonksiyonunu calistirir.

%% NETWORK-LEVEL ALTERNATIF % Du optimization stage-pressure farki yorumunu secondary diagnostic olarak hesaplar.

P_pre_gauge_MPa = max(P_SWIP_MPa - filter_loss_MPa, 0.0); % HPP inlet pretreated-feed basincini hesaplar.
W_SWIP_network_kW = P_SWIP_MPa * Qf_total_m3h / (3.6 * eta_SWIP * eta_motor); % SWIP pump power degerini hesaplar.
W_HPP_network_kW = max(P1_gauge_MPa - P_pre_gauge_MPa, 0.0) * Qf_total_m3h / (3.6 * eta_HPP * eta_motor); % Main HPP physical pressure rise gucunu hesaplar.
Q_interstage_m3h = sys.stage1_PV.Qb_m3h * N_PV_stage1; % Interstage pump debisini detailed membrane modelinden alir.
W_BP_stagepressure_kW = max(P2_gauge_MPa - P1_gauge_MPa, 0.0) * Q_interstage_m3h / (3.6 * eta_BP * eta_motor); % Booster power degerini stage operating-pressure difference ile hesaplar.
W_total_stagepressure_kW = W_SWIP_network_kW + W_HPP_network_kW + W_BP_stagepressure_kW; % Stage-pressure interpretation toplam gucunu hesaplar.
SEC_stagepressure = W_total_stagepressure_kW / max(sys.Qp_total_m3h, 1.0e-12); % Stage-pressure interpretation SEC degerini hesaplar.

%% SONUC TABLOSU % Published reference ile iki energy-accounting yorumunu karsilastirir.

Accounting = {'Physical PV-outlet pressure rise'; 'Stage operating-pressure difference'}; % Energy accounting senaryo adlarini tanimlar.
TotalPower_kW = [energy.W_total_kW; W_total_stagepressure_kW]; % Iki senaryonun toplam power degerlerini tanimlar.
SEC_kWh_m3 = [energy.SEC_kWh_m3; SEC_stagepressure]; % Iki senaryonun SEC degerlerini tanimlar.
PowerError_pct = 100.0 * (TotalPower_kW - W_ref) / W_ref; % Published total power'a gore relative error degerlerini hesaplar.
SECError_pct = 100.0 * (SEC_kWh_m3 - SEC_ref) / SEC_ref; % Published SEC degerine gore relative error degerlerini hesaplar.
result_table = table(Accounting, TotalPower_kW, SEC_kWh_m3, PowerError_pct, SECError_pct); % Refined energy-accounting karsilastirma tablosunu olusturur.
disp(result_table); % Refined energy-accounting tablosunu Command Window'da gosterir.

fprintf('Published reference power : %.3f kW\n', W_ref); % Published power reference degerini yazdirir.
fprintf('Published reference SEC   : %.3f kWh/m3\n', SEC_ref); % Published SEC reference degerini yazdirir.
fprintf('Detailed stage-1 brine    : %.3f m3/h\n', Q_interstage_m3h); % Detailed model interstage flow degerini yazdirir.
fprintf('Not: Iki accounting yorumu ayri raporlanir; published sonucu zorla tutturmak icin model parametresi kalibre edilmez.\n'); % Diagnostic amaci aciklar.

%% CIKTI YAPISI % Refined no-ERD energy test sonuclarini struct olarak dondurur.

out.result_table = result_table; % Refined energy result tablosunu kaydeder.
out.energy_physical = energy; % Physical energy-model sonucunu kaydeder.
out.SEC_reference = SEC_ref; % Published SEC reference degerini kaydeder.
out.power_reference = W_ref; % Published power reference degerini kaydeder.

end % Fonksiyonu sonlandirir.
