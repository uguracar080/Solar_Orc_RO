function screen = ro_analytic_screen_train_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg) % Detailed RO modelini cagirmadan kesin necessary-condition kontrollerini uygular.

%% BASLANGIC % Tum screening outputlarini acik ve izlenebilir bir struct icinde baslatir.

screen.pass = true; % Varsayilan olarak noktanin analitik screening'i gectigini kabul eder.
screen.reasons = strings(0, 1); % Ihmal edilemeyecek analitik infeasibility nedenlerini bos string dizisi olarak baslatir.
screen.Qp_target_m3h = Qf_train_m3h * R_target; % Recovery target'in gerektirdigi toplam permeate debisini hesaplar.
screen.Javg_target_LMH = NaN; % Hedef average flux degerini baslangicta NaN tanimlar.
screen.Rmax_flux = NaN; % Average-flux constraint'inden gelen recovery ust sinirini baslangicta NaN tanimlar.
screen.Rmax_stage2_brine = NaN; % Final brine/PV constraint'inden gelen recovery ust sinirini baslangicta NaN tanimlar.
screen.Rmax_Cb_raw = NaN; % Raw-feed salt balance'dan gelen necessary recovery ust sinirini baslangicta NaN tanimlar.
screen.Rmax_analytic = NaN; % Tum analitik ust sinirlarin minimumunu baslangicta NaN tanimlar.

%% GIRDI SONLULUK KONTROLU % NaN/Inf veya fiziksel olmayan inputlari detailed modele gondermez.

input_vector = [Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target]; % Tum scalar inputlari tek vector icinde toplar.
if any(~isfinite(input_vector)) % Herhangi bir input NaN veya Inf ise kontrol eder.
    screen.pass = false; % Noktayi analitik olarak gecersiz yapar.
    screen.reasons(end + 1, 1) = "Analytic_nonfinite_input"; % Failure reason listesine finite-number problemini ekler.
    screen.reason = strjoin(cellstr(screen.reasons), ';'); % Failure reason listesini tek string haline getirir.
    return; % Daha ileri screening hesaplarini yapmadan fonksiyondan cikar.
end % Finite-input kontrolunu sonlandirir.

if Qf_train_m3h <= 0.0 || Cf_kg_m3 < 0.0 || R_target <= 0.0 || R_target >= 1.0 % Temel fiziksel input araliklarini kontrol eder.
    screen.pass = false; % Noktayi analitik olarak gecersiz yapar.
    screen.reasons(end + 1, 1) = "Analytic_invalid_input_range"; % Fiziksel input-range failure nedenini kaydeder.
end % Input-range kontrolunu sonlandirir.

%% MEMBRAN VE GEOMETRI % Analitik flux ve flow sinirlari icin ayni membrane/geometry degerlerini yukler.

mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Truth model ile ayni aged membrane struct'ini yukler.
A_total_m2 = (cfg.geometry.N_PV_stage1 * cfg.geometry.n_elements_stage1 + ...
    cfg.geometry.N_PV_stage2 * cfg.geometry.n_elements_stage2) * mem.active_area_m2; % Tek train toplam aktif membran alanini hesaplar.

%% SICAKLIK VE STAGE-1 FEED NECESSARY CONDITIONS % Pressure optimization'dan bagimsiz kesin limitleri kontrol eder.

if T_RO_in_C > cfg.constraints.T_max_C + cfg.root.analytic_tolerance % Membrane maximum continuous temperature limitini kontrol eder.
    screen.pass = false; % Limit asilmis ise noktayi kesin infeasible yapar.
    screen.reasons(end + 1, 1) = "Analytic_temperature_max"; % Analitik temperature failure nedenini kaydeder.
end % Temperature screening'ini sonlandirir.

Qf_PV_stage1_m3h = Qf_train_m3h / cfg.geometry.N_PV_stage1; % Stage-1 feed debisini PV basina hesaplar.
if Qf_PV_stage1_m3h > mem.feed_flow_max_m3h + cfg.root.analytic_tolerance % Stage-1 feed/PV maximum limitini kontrol eder.
    screen.pass = false; % Geometri nedeniyle kesin infeasible ise noktayi eler.
    screen.reasons(end + 1, 1) = "Analytic_stage1_feed_per_PV_max"; % Feed-flow failure nedenini kaydeder.
end % Stage-1 feed screening'ini sonlandirir.

%% SYSTEM-AVERAGE FLUX NECESSARY CONDITION % Recovery target sabitken Qp ve average flux dogrudan bellidir.

Qp_flux_max_m3h = mem.max_system_average_flux_LMH * A_total_m2 / 1000.0; % 20 LMH limitinden tek train maksimum permeate debisini hesaplar.
screen.Javg_target_LMH = screen.Qp_target_m3h * 1000.0 / A_total_m2; % Target recovery icin zorunlu system-average flux degerini hesaplar.
screen.Rmax_flux = Qp_flux_max_m3h / Qf_train_m3h; % Average-flux limitinin izin verdigi recovery ust sinirini hesaplar.
if screen.Javg_target_LMH > mem.max_system_average_flux_LMH + cfg.root.analytic_tolerance % Target flux 20 LMH limitini asiyorsa kontrol eder.
    screen.pass = false; % Basinctan bagimsiz olarak kesin infeasible noktayi eler.
    screen.reasons(end + 1, 1) = "Analytic_system_average_flux_max"; % Average-flux failure nedenini kaydeder.
end % Average-flux screening'ini sonlandirir.

%% FINAL STAGE-2 BRINE NECESSARY CONDITION % Overall mass balance ile final brine/PV minimumunu pressure cozumunden once kontrol eder.

Qb_final_target_m3h = Qf_train_m3h * (1.0 - R_target); % Recovery target saglandiginda kalmasi gereken toplam final brine debisini hesaplar.
Qb_PV_stage2_target_m3h = Qb_final_target_m3h / cfg.geometry.N_PV_stage2; % Final brine debisini Stage-2 PV basina hesaplar.
screen.Rmax_stage2_brine = 1.0 - cfg.geometry.N_PV_stage2 * mem.min_brine_flow_m3h / Qf_train_m3h; % Minimum final brine/PV limitinin izin verdigi recovery ust sinirini hesaplar.
if Qb_PV_stage2_target_m3h < mem.min_brine_flow_m3h - cfg.root.analytic_tolerance % Stage-2 minimum brine/PV target tarafindan zaten ihlal ediliyorsa kontrol eder.
    screen.pass = false; % Pressure optimization ile duzeltilemeyecek noktayi eler.
    screen.reasons(end + 1, 1) = "Analytic_stage2_brine_per_PV_min"; % Final-brine failure nedenini kaydeder.
end % Stage-2 brine screening'ini sonlandirir.

%% RAW-FEED SALT-BALANCE NECESSARY CONDITION % PX mixing gercekte saliniteyi arttirdigi icin iyimser raw-feed lower bound ile Cb<=90 gerekliligini kontrol eder.

Cp_best_kg_m3 = cfg.constraints.Cp_max_kg_m3; % Brine concentration'i minimize eden izinli en yuksek product concentration degerini kullanir.
Cb_raw_best_kg_m3 = (Cf_kg_m3 - R_target * Cp_best_kg_m3) / max(1.0 - R_target, 1.0e-12); % Raw-feed bazli en iyimser final brine concentration lower bound'unu hesaplar.
screen.Cb_raw_best_kg_m3 = Cb_raw_best_kg_m3; % Hesaplanan iyimser brine concentration degerini diagnostic olarak kaydeder.
screen.Rmax_Cb_raw = (cfg.constraints.Cb_max_kg_m3 - Cf_kg_m3) / ...
    max(cfg.constraints.Cb_max_kg_m3 - Cp_best_kg_m3, 1.0e-12); % Cb<=90 ve Cp<=0.5 icin raw-feed necessary recovery ust sinirini hesaplar.
if Cb_raw_best_kg_m3 > cfg.constraints.Cb_max_kg_m3 + cfg.root.analytic_tolerance % Iyimser durumda bile Cb limiti asiliyorsa kontrol eder.
    screen.pass = false; % PX mixing yalnizca daha kotu yapacagi icin noktayi kesin infeasible kabul eder.
    screen.reasons(end + 1, 1) = "Analytic_bulk_brine_concentration_max"; % Salt-balance failure nedenini kaydeder.
end % Raw-feed salt-balance screening'ini sonlandirir.

%% TOPLAM ANALITIK RECOVERY UST SINIRI % DOE tasariminda da kullanilabilecek tek bir necessary upper-envelope degeri olusturur.

screen.Rmax_analytic = min([cfg.domain.R_max, screen.Rmax_flux, screen.Rmax_stage2_brine, screen.Rmax_Cb_raw]); % Bilinen tum analitik recovery ust sinirlarinin minimumunu alir.
if R_target > screen.Rmax_analytic + cfg.root.analytic_tolerance % Target recovery analitik envelope'un uzerindeyse kontrol eder.
    screen.pass = false; % Noktayi kesin infeasible kabul eder.
    if ~any(startsWith(screen.reasons, "Analytic_")) % Ozel neden daha once eklenmemisse genel upper-envelope nedenini ekler.
        screen.reasons(end + 1, 1) = "Analytic_recovery_upper_envelope"; % Genel analitik recovery failure nedenini kaydeder.
    end % Genel neden ekleme kosulunu sonlandirir.
end % Recovery-envelope kontrolunu sonlandirir.

%% FAILURE STRING % Tum analitik nedenleri dataset'te tek okunabilir string olarak dondurur.

if isempty(screen.reasons) % Hicbir screening ihlali yoksa kontrol eder.
    screen.reason = ""; % Basarili screening icin failure reason alanini bos birakir.
else % En az bir ihlal varsa bu dali kullanir.
    screen.reason = string(strjoin(cellstr(screen.reasons), ';')); % Birden cok nedeni noktalivirgulle birlestirir.
end % Failure-string olusturmayi sonlandirir.

end % Analitik screening fonksiyonunu sonlandirir.
