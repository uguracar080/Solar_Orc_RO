function out = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, cfg) % Tek RO train'i verilen pressures altinda detailed truth model ile degerlendirir.

%% BOS CIKTI VE CONSTRAINT LISTESI % Her durumda ayni output alanlarini dondurmek icin template degerlerini tanimlar.

constraint_names = ro_constraint_names(); % Hard inequality constraint isimlerini yukler.
n_constraints = numel(constraint_names); % Toplam inequality constraint sayisini hesaplar.
out = struct(); % Output struct'ini olusturur.
out.success = false; % Baslangicta model evaluation durumunu false yapar.
out.error_message = ''; % Baslangicta hata mesajini bos tanimlar.
out.PX_solver_method = "not_run"; % PX coupling solver yontemini diagnostic icin baslangicta tanimlar.
out.PX_map_evals = NaN; % PX coupled map evaluation sayisini diagnostic icin baslangicta NaN tanimlar.
out.EvalRuntime_s = NaN; % Tek operating-point evaluation wall-clock runtime degerini baslangicta NaN tanimlar.
out.c_scaled = 1.0e3 * ones(n_constraints, 1); % Basarisiz evaluation durumunda buyuk constraint violation degeri tanimlar.
out.constraint_names = constraint_names; % Constraint isimlerini output'a kaydeder.

%% DETAILED MEMBRANE-PX VE ENERGY COZUMU % Validation ile sabitlenen tek-train konfigürasyonunu cozer.

eval_timer = tic; % Tek truth-model operating-point evaluation runtime olcumunu baslatir.

try % Sayisal hata durumunda optimizer'in tamamen durmamasini saglar.
    if isfield(cfg, 'compute') && isfield(cfg.compute, 'fast_px_coupling') && cfg.compute.fast_px_coupling % ANN/optimizer run'inda accelerated PX salinity fixed-point solver isteniyorsa kontrol eder.
        if cfg.model.N_segments < cfg.root.final_N_segments % Coarse search gridinde olup olmadigini kontrol eder.
            fallback_max_iter = cfg.compute.fast_px_legacy_fallback_max_iter_coarse; % Coarse noktada pahali fallback limitini kullanir.
        else % Final N=150 veya daha yuksek resolution ise bu dali kullanir.
            fallback_max_iter = cfg.compute.fast_px_legacy_fallback_max_iter_final; % Final/refinement noktada sinirli recovery fallback limitini kullanir.
        end % Grid-bazli fallback limit secimini sonlandirir.
        sys = ro_system_two_stage_px_du2014_fast(Qf_train_m3h, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, T_RO_in_C, ...
            cfg.geometry.N_PV_stage1, cfg.geometry.N_PV_stage2, cfg.geometry.n_elements_stage1, cfg.geometry.n_elements_stage2, ...
            cfg.model.N_segments, cfg.model.age_years, cfg.model.leakage_pressure_unit, cfg.model.Ppxlin_gauge_MPa, fallback_max_iter); % Ayni fiziksel fixed-point kokunu safeguarded secant ile daha az membrane solve kullanarak hesaplar.
    else % Validation/legacy path isteniyorsa bu dali kullanir.
        sys = ro_system_two_stage_px_du2014(Qf_train_m3h, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, T_RO_in_C, ...
            cfg.geometry.N_PV_stage1, cfg.geometry.N_PV_stage2, cfg.geometry.n_elements_stage1, cfg.geometry.n_elements_stage2, ...
            cfg.model.N_segments, cfg.model.age_years, cfg.model.leakage_pressure_unit, cfg.model.Ppxlin_gauge_MPa); % Validated legacy under-relaxed PX coupled modelini calistirir.
    end % Fast-vs-legacy PX coupling solver secimini sonlandirir.

    energy = ro_energy_du2014(sys, cfg.energy.P_SWIP_MPa, cfg.energy.filter_loss_MPa, cfg.energy.eta_SWIP, ...
        cfg.energy.eta_HPP, cfg.energy.eta_BP, cfg.energy.eta_motor, true); % SWIP, HPP, interstage ve PX booster power degerlerini hesaplar.
catch ME % Truth-model evaluation herhangi bir nedenle hata verirse bu dali kullanir.
    out.error_message = ME.message; % Hata mesajini diagnostic output'a kaydeder.
    out.EvalRuntime_s = toc(eval_timer); % Basarisiz evaluation icin gecen wall-clock runtime degerini kaydeder.
    return; % Basarisiz evaluation'i optimizer'a geri dondurur.
end % Try-catch blogunu sonlandirir.

out.EvalRuntime_s = toc(eval_timer); % Basarili detailed operating-point evaluation toplam runtime degerini kaydeder.
if isfield(sys, 'px_solver_method') % Fast PX solver diagnostic alani mevcutsa kontrol eder.
    out.PX_solver_method = string(sys.px_solver_method); % Secant veya legacy_fallback solver yontemini kaydeder.
else % Legacy system function kullaniliyorsa bu dali kullanir.
    out.PX_solver_method = "legacy"; % Legacy coupling solver yontemini diagnostic olarak kaydeder.
end % PX solver-method diagnostic kosulunu sonlandirir.
out.PX_map_evals = sys.iterations; % Coupled membrane-PX map evaluation sayisini diagnostic olarak kaydeder.

%% TEMEL PERFORMANS METRIKLERI % ANN ve annual model icin gerekli physical outputlari hesaplar.

Cp_mg_L = 1000.0 * sys.Cp_kg_m3; % Product concentration degerini kg/m3'ten mg/L'ye cevirir.
P1out_gauge_MPa = max(sys.stage1_PV.Pout_abs_MPa - 0.101325, 0.0); % Stage-1 PV outlet basincini gauge MPa olarak hesaplar.
Cb_max_kg_m3 = max([sys.stage1_PV.profile.Cbulk_kg_m3; sys.stage2_PV.profile.Cbulk_kg_m3; sys.stage2_PV.Cb_kg_m3]); % Iki stage boyunca maksimum bulk/brine concentration degerini bulur.

%% NORMALIZE HARD CONSTRAINTS % fmincon icin c(x)<=0 convention'inda dimensionless constraint vector olusturur.

mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Constraint limitleri icin ayni aged membrane struct'ini yukler.
c = zeros(n_constraints, 1); % Dimensionless inequality constraint vectorunu olusturur.
c(1) = (sys.stage1_PV.Qf_m3h - mem.feed_flow_max_m3h) / mem.feed_flow_max_m3h; % Stage-1 feed/PV upper-limit constraint degerini hesaplar.
c(2) = (sys.stage2_PV.Qf_m3h - mem.feed_flow_max_m3h) / mem.feed_flow_max_m3h; % Stage-2 feed/PV upper-limit constraint degerini hesaplar.
c(3) = (mem.min_brine_flow_m3h - sys.stage1_PV.Qb_m3h) / mem.min_brine_flow_m3h; % Stage-1 brine/PV lower-limit constraint degerini hesaplar.
c(4) = (mem.min_brine_flow_m3h - sys.stage2_PV.Qb_m3h) / mem.min_brine_flow_m3h; % Stage-2 brine/PV lower-limit constraint degerini hesaplar.
c(5) = (sys.average_flux_LMH - mem.max_system_average_flux_LMH) / mem.max_system_average_flux_LMH; % System-average flux constraint degerini hesaplar.
c(6) = (sys.stage1_PV.first_element_average_flux_LMH - mem.max_first_element_flux_pass1_LMH) / mem.max_first_element_flux_pass1_LMH; % Stage-1 first-element flux constraint degerini hesaplar.
c(7) = (sys.stage2_PV.first_element_average_flux_LMH - mem.max_first_element_flux_pass2_LMH) / mem.max_first_element_flux_pass2_LMH; % Stage-2 first-element flux constraint degerini hesaplar.
c(8) = (sys.stage1_PV.max_CPF - mem.max_CPF_pass1) / mem.max_CPF_pass1; % Stage-1 CPF constraint degerini hesaplar.
c(9) = (sys.stage2_PV.max_CPF - mem.max_CPF_pass2) / mem.max_CPF_pass2; % Stage-2 CPF constraint degerini hesaplar.
c(10) = (sys.stage1_PV.pressure_drop_MPa - mem.max_PV_pressure_drop_MPa) / mem.max_PV_pressure_drop_MPa; % Stage-1 pressure-drop constraint degerini hesaplar.
c(11) = (sys.stage2_PV.pressure_drop_MPa - mem.max_PV_pressure_drop_MPa) / mem.max_PV_pressure_drop_MPa; % Stage-2 pressure-drop constraint degerini hesaplar.
c(12) = (sys.Cp_kg_m3 - cfg.constraints.Cp_max_kg_m3) / cfg.constraints.Cp_max_kg_m3; % Product salinity constraint degerini hesaplar.
c(13) = (Cb_max_kg_m3 - cfg.constraints.Cb_max_kg_m3) / cfg.constraints.Cb_max_kg_m3; % Maximum bulk concentration constraint degerini hesaplar.
c(14) = (P1_gauge_MPa - cfg.constraints.P_max_gauge_MPa) / cfg.constraints.P_max_gauge_MPa; % Stage-1 maximum operating pressure constraint degerini hesaplar.
c(15) = (P2_gauge_MPa - cfg.constraints.P_max_gauge_MPa) / cfg.constraints.P_max_gauge_MPa; % Stage-2 maximum operating pressure constraint degerini hesaplar.
c(16) = (T_RO_in_C - cfg.constraints.T_max_C) / cfg.constraints.T_max_C; % Maximum membrane inlet temperature constraint degerini hesaplar.
c(17) = (P1out_gauge_MPa - P2_gauge_MPa) / cfg.constraints.P_max_gauge_MPa; % Negative interstage booster head durumunu violation olarak tanimlar.
c(18) = 1.0 - 2.0 * double(sys.converged); % PX-network convergence false ise +1, true ise -1 degeri verir.
c(19) = 1.0 - 2.0 * double(sys.stage1_PV.all_local_converged); % Stage-1 local convergence false ise +1 degeri verir.
c(20) = 1.0 - 2.0 * double(sys.stage2_PV.all_local_converged); % Stage-2 local convergence false ise +1 degeri verir.
c(21) = 2.0 * double(sys.stage1_PV.numerical_flow_clip_active) - 1.0; % Stage-1 numerical flow clipping aktifse +1 degeri verir.
c(22) = 2.0 * double(sys.stage2_PV.numerical_flow_clip_active) - 1.0; % Stage-2 numerical flow clipping aktifse +1 degeri verir.

%% FINITE-NUMBER KONTROLU % NaN/Inf sonuclarini fiziksel olarak gecersiz kabul eder.

finite_vector = [sys.Qp_total_m3h, sys.Cp_kg_m3, sys.overall_recovery, sys.average_flux_LMH, energy.W_total_kW, energy.SEC_kWh_m3, c.']; % Kritik outputlari tek vector icinde toplar.
finite_ok = all(isfinite(finite_vector)) && sys.Qp_total_m3h > 0.0 && energy.W_total_kW >= 0.0; % Tum kritik degerlerin finite ve fiziksel isaretli olup olmadigini kontrol eder.
if ~finite_ok % Herhangi bir finite-number problemi varsa bu dali kullanir.
    c(:) = max(c, 1.0); % Noktayi hard infeasible yapacak pozitif constraint violation degeri uygular.
end % Finite-number kontrolunu sonlandirir.

%% OUTPUT STRUCT % Detailed evaluation sonucunu optimizer ve dataset icin toplar.

out.success = finite_ok; % Sayisal evaluation'in basarili olup olmadigini kaydeder.
out.sys = sys; % Detailed system struct'ini diagnostic kullanim icin kaydeder.
out.energy = energy; % Detailed energy struct'ini diagnostic kullanim icin kaydeder.
out.c_scaled = c; % Dimensionless hard inequality constraint vectorunu kaydeder.
out.constraint_names = constraint_names; % Constraint isimlerini kaydeder.
if isfield(cfg, 'root') && isfield(cfg.root, 'physical_constraint_accept_tolerance') % Root optimizer configuration'inda round-off feasibility toleransi tanimliysa kontrol eder.
    physical_tol = cfg.root.physical_constraint_accept_tolerance; % Normalized hard-constraint acceptance toleransini configuration'dan alir.
else % Legacy configuration kullaniliyorsa bu dali kullanir.
    physical_tol = 0.0; % Geriye donuk uyumluluk icin eski strict c<=0 davranisini korur.
end % Physical-feasibility tolerance secimini sonlandirir.
out.physical_feasible = finite_ok && all(c <= physical_tol); % Recovery target haric tum hard constraint'leri yalnizca round-off toleransi ile degerlendirir.
out.Qp_train_m3h = sys.Qp_total_m3h; % Tek train toplam permeate debisini kaydeder.
out.Recovery = sys.overall_recovery; % Actual overall recovery fraction degerini kaydeder.
out.Cp_mg_L = Cp_mg_L; % Product concentration degerini mg/L olarak kaydeder.
out.W_RO_kW = energy.W_total_kW; % Tek train toplam RO electrical power degerini kaydeder.
out.SEC_kWh_m3 = energy.SEC_kWh_m3; % Actual SEC degerini kaydeder.
out.P1_gauge_MPa = P1_gauge_MPa; % Stage-1 pressure degerini kaydeder.
out.P2_gauge_MPa = P2_gauge_MPa; % Stage-2 pressure degerini kaydeder.
out.P1out_gauge_MPa = P1out_gauge_MPa; % Stage-1 outlet gauge pressure degerini kaydeder.
out.PXout_gauge_MPa = sys.px.Ppxhout_gauge_MPa; % PX high-side outlet gauge pressure degerini kaydeder.
out.PX_excess_pressure_MPa = max(sys.px.Ppxhout_gauge_MPa - P1_gauge_MPa, 0.0); % PX outlet Stage-1 pressure'dan yuksekse throttling ile giderilecek excess pressure'i diagnostic olarak kaydeder.
out.PX_booster_deltaP_MPa = max(P1_gauge_MPa - sys.px.Ppxhout_gauge_MPa, 0.0); % PX outlet Stage-1 pressure'dan dusukse gerekli booster pressure rise degerini diagnostic olarak kaydeder.
out.Javg_LMH = sys.average_flux_LMH; % System-average flux degerini kaydeder.
out.Jfirst_stage1_LMH = sys.stage1_PV.first_element_average_flux_LMH; % Stage-1 first-element average flux degerini kaydeder.
out.Jfirst_stage2_LMH = sys.stage2_PV.first_element_average_flux_LMH; % Stage-2 first-element average flux degerini kaydeder.
out.Jmax_local_stage1_LMH = sys.stage1_PV.max_flux_LMH; % Stage-1 maximum local segment flux degerini diagnostic olarak kaydeder.
out.Jmax_local_stage2_LMH = sys.stage2_PV.max_flux_LMH; % Stage-2 maximum local segment flux degerini diagnostic olarak kaydeder.
out.CPFmax_stage1 = sys.stage1_PV.max_CPF; % Stage-1 maximum CPF degerini kaydeder.
out.CPFmax_stage2 = sys.stage2_PV.max_CPF; % Stage-2 maximum CPF degerini kaydeder.
out.dP_stage1_MPa = sys.stage1_PV.pressure_drop_MPa; % Stage-1 PV pressure drop degerini kaydeder.
out.dP_stage2_MPa = sys.stage2_PV.pressure_drop_MPa; % Stage-2 PV pressure drop degerini kaydeder.
out.Cb_max_kg_m3 = Cb_max_kg_m3; % Maximum bulk/brine concentration degerini kaydeder.
out.Qf_PV_stage1_m3h = sys.stage1_PV.Qf_m3h; % Stage-1 feed flow/PV degerini kaydeder.
out.Qf_PV_stage2_m3h = sys.stage2_PV.Qf_m3h; % Stage-2 feed flow/PV degerini kaydeder.
out.Qb_PV_stage1_m3h = sys.stage1_PV.Qb_m3h; % Stage-1 brine flow/PV degerini kaydeder.
out.Qb_PV_stage2_m3h = sys.stage2_PV.Qb_m3h; % Stage-2 brine flow/PV degerini kaydeder.
out.Qhpp_m3h = sys.Qhpp_m3h; % HPP feed flow degerini kaydeder.
out.PX_leakage_pct = sys.px.Lpx_pct; % PX leakage/lubrication yuzdesini kaydeder.
out.PX_mix_pct = sys.px.Mix_pct; % PX volumetric mixing yuzdesini kaydeder.
out.PX_iterations = sys.iterations; % Coupled PX-network iteration sayisini kaydeder.
out.Stage1_all_local_converged = sys.stage1_PV.all_local_converged; % Stage-1 local solver convergence flag degerini kaydeder.
out.Stage2_all_local_converged = sys.stage2_PV.all_local_converged; % Stage-2 local solver convergence flag degerini kaydeder.
out.Stage1_flow_clip_active = sys.stage1_PV.numerical_flow_clip_active; % Stage-1 numerical clipping flag degerini kaydeder.
out.Stage2_flow_clip_active = sys.stage2_PV.numerical_flow_clip_active; % Stage-2 numerical clipping flag degerini kaydeder.
out.feasibility_margin_scaled = min(-c); % Pozitifse tum inequality constraints icinde en yakin normalized marji kaydeder.
out.max_constraint_violation_scaled = max(max(c, 0.0)); % En buyuk normalized hard-constraint violation degerini kaydeder.

end % Tek-train detailed evaluation fonksiyonunu sonlandirir.
