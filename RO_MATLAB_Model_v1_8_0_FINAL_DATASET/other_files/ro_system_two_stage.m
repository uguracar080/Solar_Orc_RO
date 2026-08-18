function sys = ro_system_two_stage(Qf_total_m3h, Cf_kg_m3, Pf_abs_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, mem) % Iki-stage direct plug RO sistemini cozer.

%% GIRDI KONTROLU % Membran ve stage sayilarini kontrol eder.

if nargin < 10 % Membran struct'i verilmediyse kontrol eder.
    mem = ro_membrane_SW30XLE400(); % Varsayilan SW30XLE-400 membran verilerini yukler.
end % Membran giris kontrolunu sonlandirir.

N_PV_stage1 = max(round(N_PV_stage1), 1); % Stage-1 PV sayisini pozitif tam sayiya cevirir.
N_PV_stage2 = max(round(N_PV_stage2), 1); % Stage-2 PV sayisini pozitif tam sayiya cevirir.

%% STAGE 1 % Paralel PV'lerin ayni kosulda oldugu varsayimi ile representative PV cozer.

Qf_PV1_m3h = Qf_total_m3h / N_PV_stage1; % Stage-1 representative PV feed debisini hesaplar.
stage1_PV = ro_pv_du2014(Qf_PV1_m3h, Cf_kg_m3, Pf_abs_MPa, T_C, n_elements_stage1, N_segments, mem); % Stage-1 representative PV cozumunu yapar.
Qp_stage1_m3h = stage1_PV.Qp_m3h * N_PV_stage1; % Stage-1 toplam permeate debisini hesaplar.
Qb_stage1_m3h = stage1_PV.Qb_m3h * N_PV_stage1; % Stage-1 toplam brine debisini hesaplar.

%% STAGE 2 % Stage-1 brine akimini ikinci kademenin feed'i olarak kullanir.

Qf_PV2_m3h = Qb_stage1_m3h / N_PV_stage2; % Stage-2 representative PV feed debisini hesaplar.
stage2_PV = ro_pv_du2014(Qf_PV2_m3h, stage1_PV.Cb_kg_m3, stage1_PV.Pout_abs_MPa, T_C, n_elements_stage2, N_segments, mem); % Stage-2 representative PV cozumunu yapar.
Qp_stage2_m3h = stage2_PV.Qp_m3h * N_PV_stage2; % Stage-2 toplam permeate debisini hesaplar.
Qb_stage2_m3h = stage2_PV.Qb_m3h * N_PV_stage2; % Stage-2 toplam final brine debisini hesaplar.

%% SISTEM TOPLAM PERMEATE KALITESI % Iki stage permeate akimlarini debi agirlikli olarak karistirir.

Qp_total_m3h = Qp_stage1_m3h + Qp_stage2_m3h; % Iki stage toplam permeate debisini hesaplar.
salt_permeate_total = Qp_stage1_m3h * stage1_PV.Cp_kg_m3 + Qp_stage2_m3h * stage2_PV.Cp_kg_m3; % Iki stage permeate salt flow surrogate degerini hesaplar.
Cp_total_kg_m3 = salt_permeate_total / max(Qp_total_m3h, 1.0e-12); % Karisik permeate concentration degerini hesaplar.
overall_recovery = Qp_total_m3h / Qf_total_m3h; % Sistem overall recovery ratio degerini hesaplar.

%% CIKTI YAPISI % Iki-stage sistem sonucunu struct icinde toplar.

sys.Qf_total_m3h = Qf_total_m3h; % Sistem toplam feed debisini kaydeder.
sys.Cf_kg_m3 = Cf_kg_m3; % Sistem feed concentration degerini kaydeder.
sys.Pf_abs_MPa = Pf_abs_MPa; % Sistem feed pressure degerini kaydeder.
sys.T_C = T_C; % Sistem feed temperature degerini kaydeder.
sys.N_PV_stage1 = N_PV_stage1; % Stage-1 PV sayisini kaydeder.
sys.N_PV_stage2 = N_PV_stage2; % Stage-2 PV sayisini kaydeder.
sys.n_elements_stage1 = n_elements_stage1; % Stage-1 element/PV sayisini kaydeder.
sys.n_elements_stage2 = n_elements_stage2; % Stage-2 element/PV sayisini kaydeder.
sys.Qp_stage1_m3h = Qp_stage1_m3h; % Stage-1 permeate debisini kaydeder.
sys.Qp_stage2_m3h = Qp_stage2_m3h; % Stage-2 permeate debisini kaydeder.
sys.Qp_total_m3h = Qp_total_m3h; % Sistem toplam permeate debisini kaydeder.
sys.Qb_final_m3h = Qb_stage2_m3h; % Sistem final brine debisini kaydeder.
sys.Cp_kg_m3 = Cp_total_kg_m3; % Sistem karisik permeate concentration degerini kaydeder.
sys.Cb_final_kg_m3 = stage2_PV.Cb_kg_m3; % Sistem final brine concentration degerini kaydeder.
sys.overall_recovery = overall_recovery; % Sistem overall recovery ratio degerini kaydeder.
sys.stage1_PV = stage1_PV; % Stage-1 representative PV ayrintilarini kaydeder.
sys.stage2_PV = stage2_PV; % Stage-2 representative PV ayrintilarini kaydeder.

end % Fonksiyonu sonlandirir.
