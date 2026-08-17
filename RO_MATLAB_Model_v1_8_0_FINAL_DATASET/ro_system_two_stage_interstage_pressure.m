function sys = ro_system_two_stage_interstage_pressure(Qf_total_m3h, Cf_kg_m3, Pf1_abs_MPa, Pf2_abs_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, mem) % Iki-stage RO sistemini bagimsiz stage basinclari ile cozer.

%% GIRDI KONTROLU % Membran struct'i ve integer stage parametrelerini kontrol eder.

if nargin < 11 % Membran struct'i verilmediyse kontrol eder.
    mem = ro_membrane_SW30XLE400(); % Varsayilan SW30XLE-400 membran verilerini yukler.
end % Membran giris kontrolunu sonlandirir.

N_PV_stage1 = max(round(N_PV_stage1), 1); % Stage-1 PV sayisini pozitif tam sayiya cevirir.
N_PV_stage2 = max(round(N_PV_stage2), 1); % Stage-2 PV sayisini pozitif tam sayiya cevirir.
n_elements_stage1 = max(round(n_elements_stage1), 1); % Stage-1 element/PV sayisini pozitif tam sayiya cevirir.
n_elements_stage2 = max(round(n_elements_stage2), 1); % Stage-2 element/PV sayisini pozitif tam sayiya cevirir.

%% STAGE 1 % Birinci kademedeki representative pressure vessel'i cozer.

Qf_PV1_m3h = Qf_total_m3h / N_PV_stage1; % Stage-1 representative PV feed debisini hesaplar.
stage1_PV = ro_pv_du2014(Qf_PV1_m3h, Cf_kg_m3, Pf1_abs_MPa, T_C, n_elements_stage1, N_segments, mem); % Stage-1 representative PV cozumunu yapar.
Qp_stage1_m3h = stage1_PV.Qp_m3h * N_PV_stage1; % Stage-1 toplam permeate debisini hesaplar.
Qb_stage1_m3h = stage1_PV.Qb_m3h * N_PV_stage1; % Stage-1 toplam brine debisini hesaplar.

%% INTERSTAGE BOOST % Stage-1 brine akimini belirtilen ikinci-stage basincina yukseltir.

Qf_PV2_m3h = Qb_stage1_m3h / N_PV_stage2; % Stage-2 representative PV feed debisini hesaplar.
stage2_PV = ro_pv_du2014(Qf_PV2_m3h, stage1_PV.Cb_kg_m3, Pf2_abs_MPa, T_C, n_elements_stage2, N_segments, mem); % Stage-2 representative PV cozumunu bagimsiz basinc ile yapar.
Qp_stage2_m3h = stage2_PV.Qp_m3h * N_PV_stage2; % Stage-2 toplam permeate debisini hesaplar.
Qb_stage2_m3h = stage2_PV.Qb_m3h * N_PV_stage2; % Stage-2 toplam final brine debisini hesaplar.

%% TOPLAM PERMEATE % Iki stage permeate akimlarini debi agirlikli olarak birlestirir.

Qp_total_m3h = Qp_stage1_m3h + Qp_stage2_m3h; % Sistem toplam permeate debisini hesaplar.
salt_product = Qp_stage1_m3h * stage1_PV.Cp_kg_m3 + Qp_stage2_m3h * stage2_PV.Cp_kg_m3; % Permeate salt-flow agirlikli toplam degerini hesaplar.
Cp_total_kg_m3 = salt_product / max(Qp_total_m3h, 1.0e-12); % Karisik permeate concentration degerini hesaplar.
overall_recovery = Qp_total_m3h / Qf_total_m3h; % Sistem overall recovery ratio degerini hesaplar.

%% ORTALAMA SISTEM FLUX % Toplam aktif membran alani uzerinden average flux degerini hesaplar.

A_stage1_m2 = N_PV_stage1 * n_elements_stage1 * mem.active_area_m2; % Stage-1 toplam aktif membran alanini hesaplar.
A_stage2_m2 = N_PV_stage2 * n_elements_stage2 * mem.active_area_m2; % Stage-2 toplam aktif membran alanini hesaplar.
A_total_m2 = A_stage1_m2 + A_stage2_m2; % Iki stage toplam aktif membran alanini hesaplar.
average_flux_LMH = Qp_total_m3h * 1000.0 / A_total_m2; % Sistem average permeate flux degerini LMH cinsinden hesaplar.

%% CIKTI YAPISI % Iki-stage sistem sonucunu struct icinde toplar.

sys.Qf_total_m3h = Qf_total_m3h; % Sistem feed debisini kaydeder.
sys.Cf_kg_m3 = Cf_kg_m3; % Sistem feed concentration degerini kaydeder.
sys.Pf1_abs_MPa = Pf1_abs_MPa; % Stage-1 feed pressure degerini kaydeder.
sys.Pf2_abs_MPa = Pf2_abs_MPa; % Stage-2 feed pressure degerini kaydeder.
sys.P1_gauge_MPa = Pf1_abs_MPa - mem.permeate_pressure_abs_MPa; % Stage-1 feed basincini gauge MPa olarak kaydeder.
sys.P2_gauge_MPa = Pf2_abs_MPa - mem.permeate_pressure_abs_MPa; % Stage-2 feed basincini gauge MPa olarak kaydeder.
sys.T_C = T_C; % Sistem temperature degerini kaydeder.
sys.N_PV_stage1 = N_PV_stage1; % Stage-1 PV sayisini kaydeder.
sys.N_PV_stage2 = N_PV_stage2; % Stage-2 PV sayisini kaydeder.
sys.n_elements_stage1 = n_elements_stage1; % Stage-1 element/PV sayisini kaydeder.
sys.n_elements_stage2 = n_elements_stage2; % Stage-2 element/PV sayisini kaydeder.
sys.Qp_stage1_m3h = Qp_stage1_m3h; % Stage-1 permeate debisini kaydeder.
sys.Qp_stage2_m3h = Qp_stage2_m3h; % Stage-2 permeate debisini kaydeder.
sys.Qp_total_m3h = Qp_total_m3h; % Sistem toplam permeate debisini kaydeder.
sys.Qb_final_m3h = Qb_stage2_m3h; % Sistem final brine debisini kaydeder.
sys.Cp_kg_m3 = Cp_total_kg_m3; % Sistem permeate concentration degerini kaydeder.
sys.Cb_final_kg_m3 = stage2_PV.Cb_kg_m3; % Sistem final brine concentration degerini kaydeder.
sys.overall_recovery = overall_recovery; % Sistem overall recovery degerini kaydeder.
sys.average_flux_LMH = average_flux_LMH; % Sistem average permeate flux degerini kaydeder.
sys.stage1_PV = stage1_PV; % Stage-1 representative PV sonucunu kaydeder.
sys.stage2_PV = stage2_PV; % Stage-2 representative PV sonucunu kaydeder.

end % Fonksiyonu sonlandirir.
