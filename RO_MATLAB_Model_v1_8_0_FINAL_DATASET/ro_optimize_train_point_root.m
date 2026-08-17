function row = ro_optimize_train_point_root(DOE_ID, DOE_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg) % Recovery equality'yi P2-root ile saglayip P1 boyunca minimum-power feasible train noktasini bulur.

%% OUTPUT VE TIMER % Her durumda sabit kolonlu dataset row ve runtime diagnostic uretir.

row = ro_dataset_row_template(); % Dataset kolonlarini sabit field sirasi ile baslatir.
row.DOE_ID = DOE_ID; % DOE index degerini kaydeder.
row.DOE_Type = string(DOE_Type); % DOE sample tipini kaydeder.
row.Qf_train_m3h = Qf_train_m3h; % Feed-flow inputunu kaydeder.
row.T_RO_in_C = T_RO_in_C; % RO inlet temperature inputunu kaydeder.
row.Cf_kg_m3 = Cf_kg_m3; % Feed concentration inputunu kaydeder.
row.R_target = R_target; % Recovery target inputunu kaydeder.
row.OptimizerMethod = "root1d"; % Bu satirin recovery-conditioned root optimizer ile uretildigini kaydeder.
t_start = tic; % Tek DOE point wall-clock runtime olcumunu baslatir.

%% ANALITIK SCREENING % Pressure optimization'dan bagimsiz kesin infeasible noktalar icin detailed modeli hic cagirmadan cikis yapar.

screen = ro_analytic_screen_train_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg); % Necessary-condition screening sonucunu hesaplar.
row.AnalyticScreenPassed = screen.pass; % Screening pass/fail flag degerini dataset row'a kaydeder.
row.AnalyticRmax = screen.Rmax_analytic; % Bilinen analitik recovery upper-envelope degerini dataset row'a kaydeder.
row.AnalyticJavgTarget_LMH = screen.Javg_target_LMH; % Recovery target'in zorunlu kildigi average flux degerini kaydeder.
if ~screen.pass % Analitik olarak kesin infeasible ise kontrol eder.
    row.ExitFlag = -10; % Analytic-screened noktalar icin ozel negatif exit flag atar.
    row.FailureReason = screen.reason; % Analitik failure nedenlerini kaydeder.
    row.Runtime_s = toc(t_start); % Model cagrisi yapmadan gecen kisa runtime degerini kaydeder.
    return; % Bu DOE point icin pressure search yapmadan fonksiyondan cikar.
end % Analitik screening failure kosulunu sonlandirir.

%% COARSE N=30 P1 TARAMASI % Her P1 icin P2'yi recovery root ile bulur ve feasible-manifold uzerinde power/constraint score olusturur.

P1_grid = linspace(cfg.root.P1_lb_MPa, cfg.root.P1_ub_MPa, cfg.root.n_P1_coarse); % Tum Stage-1 pressure search araligini coarse noktalara boler.
coarse_candidates = empty_candidate_array(); % Coarse recovery-root candidate listesini bos struct array olarak baslatir.
coarse_eval_count = 0; % N=30 detailed model evaluation sayacini sifirlar.

for k = 1:numel(P1_grid) % Tum coarse P1 noktalarini sirayla gezer.
    rr = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, P1_grid(k), cfg, cfg.root.coarse_N_segments, NaN); % Sabit P1 icin N=30 recovery root P2 degerini bulur.
    coarse_eval_count = coarse_eval_count + rr.n_evaluations; % Root aramasinda kullanilan model evaluation sayisini toplar.
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success % Recovery target'i saglayan finite bir coarse root varsa kontrol eder.
        coarse_candidates(end + 1) = make_candidate(P1_grid(k), rr, candidate_score(rr.ev)); %#ok<AGROW> % P1, P2, model ve score bilgilerini candidate listesine ekler.
    end % Coarse-root acceptance kosulunu sonlandirir.
end % Coarse P1 taramasini sonlandirir.

%% COARSE LOCAL P1 REFINEMENT % En iyi coarse pressure bolgesini daha sik P1 noktalariyla ikinci kez tarar.

if ~isempty(coarse_candidates) % En az bir recovery-matched coarse P1 bulunduysa kontrol eder.
    [~, ibest_coarse] = min([coarse_candidates.score]); % Constraint-penalized power score'a gore en iyi coarse candidate'i bulur.
    P1_best_coarse = coarse_candidates(ibest_coarse).P1; % En iyi coarse Stage-1 pressure degerini alir.
    coarse_spacing = (cfg.root.P1_ub_MPa - cfg.root.P1_lb_MPa) / max(cfg.root.n_P1_coarse - 1, 1); % Coarse P1 grid spacing degerini hesaplar.
    refine_lb = max(cfg.root.P1_lb_MPa, P1_best_coarse - coarse_spacing); % Local refinement alt pressure sinirini olusturur.
    refine_ub = min(cfg.root.P1_ub_MPa, P1_best_coarse + coarse_spacing); % Local refinement ust pressure sinirini olusturur.
    P1_refine = linspace(refine_lb, refine_ub, cfg.root.n_P1_refine); % En iyi coarse bolgede daha sik P1 grid vectoru olusturur.

    for k = 1:numel(P1_refine) % Local refinement P1 noktalarini sirayla gezer.
        if any(abs(P1_refine(k) - [coarse_candidates.P1]) < 1.0e-10) % Ayni P1 daha once coarse gridde cozulduyse kontrol eder.
            continue; % Duplicate root cozumunu atlayarak gereksiz model cagrisini engeller.
        end % Duplicate-P1 kosulunu sonlandirir.
        [~, nearest_idx] = min(abs([coarse_candidates.P1] - P1_refine(k))); % Yeni P1'e en yakin mevcut coarse candidate'i bulur.
        P2_hint = coarse_candidates(nearest_idx).P2; % Yakindaki recovery root'tan P2 hint degerini alir.
        rr = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, P1_refine(k), cfg, cfg.root.coarse_N_segments, P2_hint); % Hint destekli N=30 recovery root cozumunu yapar.
        coarse_eval_count = coarse_eval_count + rr.n_evaluations; % Root aramasinin detailed model evaluation sayisini toplar.
        if rr.target_met && ~isempty(rr.ev) && rr.ev.success % Finite recovery-matched root bulunduysa kontrol eder.
            coarse_candidates(end + 1) = make_candidate(P1_refine(k), rr, candidate_score(rr.ev)); %#ok<AGROW> % Refined candidate'i listeye ekler.
        end % Refined-root acceptance kosulunu sonlandirir.
    end % Local P1 refinement dongusunu sonlandirir.
end % Coarse-candidate availability kosulunu sonlandirir.

row.RootEvalCountCoarse = coarse_eval_count; % Toplam N=30 model evaluation sayisini dataset row'a kaydeder.

%% COARSE ROOT YOKSA FAILURE % P1 araliginin hicbir yerinde recovery target bracketlenmediyse pahali N=150 modeline gecmez.

if isempty(coarse_candidates) % Hic recovery-matched N=30 candidate yoksa kontrol eder.
    row.ExitFlag = -11; % Coarse recovery-root bulunamama durumuna ozel exit flag atar.
    row.FailureReason = "Recovery_root_not_found_N30"; % Failure reason alanina acik root failure nedenini kaydeder.
    row.Runtime_s = toc(t_start); % Noktanin toplam runtime degerini kaydeder.
    return; % N=150 final dogrulamaya gecmeden fonksiyondan cikar.
end % Coarse-root availability kontrolunu sonlandirir.

%% FINAL SEED SECIMI % En iyi coarse candidate'leri N=150 truth modeline tasir.

[~, order] = sort([coarse_candidates.score], 'ascend'); % Candidate listesini constraint-penalized score'a gore siralar.
n_seed = min(cfg.root.n_final_seeds, numel(order)); % Gercekte final dogrulamaya tasinacak seed sayisini sinirlar.
seed_idx = order(1:n_seed); % En iyi coarse candidate indexlerini secer.
final_candidates = empty_candidate_array(); % N=150 final candidate listesini bos baslatir.
final_eval_count = 0; % N=150 detailed model evaluation sayacini sifirlar.

for s = 1:n_seed % Secilen coarse seed'leri final truth-gridde cozer.
    c0 = coarse_candidates(seed_idx(s)); % Mevcut coarse seed candidate struct'ini alir.
    rr = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, c0.P1, cfg, cfg.root.final_N_segments, c0.P2); % N=150 modelde ayni P1 icin P2 recovery root'u yeniden bulur.
    final_eval_count = final_eval_count + rr.n_evaluations; % Final root model evaluation sayisini toplar.
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success % N=150 root finite ve recovery-matched ise kontrol eder.
        final_candidates(end + 1) = make_candidate(c0.P1, rr, candidate_score(rr.ev)); %#ok<AGROW> % Final candidate'i listeye ekler.
    end % N=150 seed acceptance kosulunu sonlandirir.
end % Final seed dogrulama dongusunu sonlandirir.

%% FINAL LOCAL P1 REFINEMENT % N=150'de en iyi aday etrafinda iki ek P1 noktasi ile coarse-grid bias'ini azaltir.

if ~isempty(final_candidates) % En az bir finite N=150 recovery root varsa kontrol eder.
    [~, ibest_final0] = min([final_candidates.score]); % Mevcut N=150 candidate'ler arasinda en iyi score'u bulur.
    P1_center = final_candidates(ibest_final0).P1; % Local refinement merkez pressure degerini alir.
    P2_center = final_candidates(ibest_final0).P2; % Local refinement icin P2 hint degerini alir.
    offsets = cfg.root.final_P1_offsets_MPa; % Coarse-grid bias'ini azaltan cok-olcekli iki yonlu local P1 refinement offset vectorunu alir.

    for k = 1:numel(offsets) % Iki local pressure offset'ini sirayla gezer.
        P1_try = min(max(P1_center + offsets(k), cfg.root.P1_lb_MPa), cfg.root.P1_ub_MPa); % Local P1 degerini search bounds icine clip eder.
        if any(abs(P1_try - [final_candidates.P1]) < 1.0e-10) % Ayni final P1 daha once cozulduyse kontrol eder.
            continue; % Duplicate N=150 root cozumunu atlar.
        end % Duplicate-final-P1 kontrolunu sonlandirir.
        rr = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, P1_try, cfg, cfg.root.final_N_segments, P2_center); % Offset P1 icin N=150 recovery root'u bulur.
        final_eval_count = final_eval_count + rr.n_evaluations; % Final evaluation sayisini toplar.
        if rr.target_met && ~isempty(rr.ev) && rr.ev.success % Finite recovery-matched local root bulunduysa kontrol eder.
            final_candidates(end + 1) = make_candidate(P1_try, rr, candidate_score(rr.ev)); %#ok<AGROW> % Local N=150 candidate'i listeye ekler.
        end % Local final-root acceptance kosulunu sonlandirir.
    end % Final local P1 refinement dongusunu sonlandirir.
end % Final-candidate availability kosulunu sonlandirir.

row.RootEvalCountFinal = final_eval_count; % Toplam N=150 model evaluation sayisini dataset row'a kaydeder.

%% FINAL ROOT YOKSA FAILURE % N=30 seed bulundu halde N=150 modelde target recovery bracketlenmezse acik failure kaydeder.

if isempty(final_candidates) % Hic N=150 recovery-matched candidate yoksa kontrol eder.
    row.ExitFlag = -12; % Final recovery-root failure durumuna ozel exit flag atar.
    row.FailureReason = "Recovery_root_not_found_N150"; % N=150 root failure nedenini kaydeder.
    row.Runtime_s = toc(t_start); % Noktanin toplam runtime degerini kaydeder.
    return; % Dataset row'u failure olarak dondurur.
end % Final-root availability kontrolunu sonlandirir.

%% EN IYI FINAL NOKTANIN SECIMI % Once physical-feasible minimum-power noktayi, yoksa en az constraint-violation'li diagnostic noktayi secer.

is_feasible = arrayfun(@(c) c.ev.physical_feasible, final_candidates); % Tum final candidate'lerin physical-feasible flag vectorunu olusturur.
if any(is_feasible) % En az bir physical-feasible recovery-matched candidate varsa kontrol eder.
    feasible_idx = find(is_feasible); % Feasible final candidate indexlerini bulur.
    powers = arrayfun(@(c) c.ev.W_RO_kW, final_candidates(feasible_idx)); % Feasible candidate power degerlerini vector olarak alir.
    [~, ilocal] = min(powers); % Feasible candidate'ler arasinda minimum power indexini bulur.
    ibest = feasible_idx(ilocal); % Global final candidate indexini elde eder.
    exitflag = 1; % Basarili root-based optimum icin pozitif exit flag atar.
else % Recovery-matched fakat tum candidate'ler en az bir physical constraint ihlal ediyorsa bu dali kullanir.
    diagnostic_scores = arrayfun(@(c) diagnostic_score(c.ev), final_candidates); % Infeasible candidate'ler icin violation-oncelikli diagnostic score hesaplar.
    [~, ibest] = min(diagnostic_scores); % En az kotu physical point'i diagnostic output icin secer.
    exitflag = 0; % Recovery root var ancak physical-feasible optimum yok durumunu sifir exit flag ile temsil eder.
end % Final candidate secim kosulunu sonlandirir.

best = final_candidates(ibest); % Secilen final candidate struct'ini alir.
ev = best.ev; % Secilen N=150 detailed evaluation struct'ini alir.

%% FLAT DATASET ROW % Secilen final truth-model sonucunu ANN dataset kolonlarina aktarir.

row.Qp_train_m3h = ev.Qp_train_m3h; % Actual permeate production degerini kaydeder.
row.Recovery_actual = ev.Recovery; % Actual recovery degerini kaydeder.
row.Recovery_error = ev.Recovery - R_target; % Target recovery residual degerini kaydeder.
row.Cp_mg_L = ev.Cp_mg_L; % Product concentration degerini mg/L olarak kaydeder.
row.W_RO_train_kW = ev.W_RO_kW; % Total train electrical power degerini kaydeder.
row.SEC_kWh_m3 = ev.SEC_kWh_m3; % SEC degerini diagnostic output olarak kaydeder.
row.P1_opt_gauge_MPa = best.P1; % Secilen Stage-1 gauge pressure degerini kaydeder.
row.P2_opt_gauge_MPa = best.P2; % Recovery root ile bulunan Stage-2 gauge pressure degerini kaydeder.
row.Javg_LMH = ev.Javg_LMH; % System-average flux degerini kaydeder.
row.Jfirst_stage1_LMH = ev.Jfirst_stage1_LMH; % Stage-1 first-element average flux degerini kaydeder.
row.Jfirst_stage2_LMH = ev.Jfirst_stage2_LMH; % Stage-2 first-element average flux degerini kaydeder.
row.Jmax_local_stage1_LMH = ev.Jmax_local_stage1_LMH; % Stage-1 maximum local flux degerini kaydeder.
row.Jmax_local_stage2_LMH = ev.Jmax_local_stage2_LMH; % Stage-2 maximum local flux degerini kaydeder.
row.CPFmax_stage1 = ev.CPFmax_stage1; % Stage-1 maximum CPF degerini kaydeder.
row.CPFmax_stage2 = ev.CPFmax_stage2; % Stage-2 maximum CPF degerini kaydeder.
row.dP_stage1_MPa = ev.dP_stage1_MPa; % Stage-1 pressure-drop degerini kaydeder.
row.dP_stage2_MPa = ev.dP_stage2_MPa; % Stage-2 pressure-drop degerini kaydeder.
row.Cb_max_kg_m3 = ev.Cb_max_kg_m3; % Maximum bulk/brine concentration degerini kaydeder.
row.Qf_PV_stage1_m3h = ev.Qf_PV_stage1_m3h; % Stage-1 feed/PV degerini kaydeder.
row.Qf_PV_stage2_m3h = ev.Qf_PV_stage2_m3h; % Stage-2 feed/PV degerini kaydeder.
row.Qb_PV_stage1_m3h = ev.Qb_PV_stage1_m3h; % Stage-1 brine/PV degerini kaydeder.
row.Qb_PV_stage2_m3h = ev.Qb_PV_stage2_m3h; % Stage-2 brine/PV degerini kaydeder.
row.Qhpp_m3h = ev.Qhpp_m3h; % HPP feed flow degerini kaydeder.
row.PXout_gauge_MPa = ev.PXout_gauge_MPa; % PX high-pressure outlet pressure degerini kaydeder.
row.PX_excess_pressure_MPa = ev.PX_excess_pressure_MPa; % PX excess pressure diagnostic degerini kaydeder.
row.PX_booster_deltaP_MPa = ev.PX_booster_deltaP_MPa; % PX booster pressure-rise diagnostic degerini kaydeder.
row.PX_leakage_pct = ev.PX_leakage_pct; % PX leakage percentage degerini kaydeder.
row.PX_mix_pct = ev.PX_mix_pct; % PX mixing percentage degerini kaydeder.
row.PX_iterations = ev.PX_iterations; % Coupled PX-network iteration sayisini kaydeder.
row.PhysicalFeasible = ev.physical_feasible; % Recovery target disindaki hard physical/numerical feasibility flag degerini kaydeder.
row.RecoveryTargetMet = abs(row.Recovery_error) <= cfg.optim.recovery_accept_tolerance; % Final dataset acceptance toleransi ile recovery target flag degerini hesaplar.
row.DatasetValid = row.PhysicalFeasible && row.RecoveryTargetMet; % Regression ANN'ye girecek valid point flag degerini hesaplar.
row.FeasibilityMarginScaled = ev.feasibility_margin_scaled; % En yakin normalized constraint margin degerini kaydeder.
row.MaxConstraintViolationScaled = ev.max_constraint_violation_scaled; % En buyuk normalized constraint violation degerini kaydeder.
row.ExitFlag = exitflag; % Root optimizer final status code degerini kaydeder.
row.LocalStartsAttempted = 0; % Root optimizer fmincon multi-start kullanmadigi icin legacy field'i sifirlar.
row.Runtime_s = toc(t_start); % Tek DOE point toplam wall-clock runtime degerini saniye olarak kaydeder.

%% FAILURE REASON % Recovery matched ancak physical infeasible noktada gercek hard-constraint nedenlerini kaydeder.

if row.DatasetValid % Final point regression dataset icin valid ise kontrol eder.
    row.FailureReason = ""; % Valid noktada failure reason alanini bos birakir.
else % Final point physical infeasible veya final recovery acceptance disindaysa bu dali kullanir.
    physical_tol = cfg.root.physical_constraint_accept_tolerance; % Normalized physical constraint acceptance toleransini alir.
    violated = ev.constraint_names(ev.c_scaled > physical_tol); % Round-off toleransini asan gercek hard-constraint isimlerini secer.
    if ~row.RecoveryTargetMet % Final recovery acceptance toleransi ayrica saglanmadiysa kontrol eder.
        violated{end + 1} = 'Recovery_target_mismatch'; % Recovery mismatch nedenini failure listesine ekler.
    end % Recovery failure kosulunu sonlandirir.
    if isempty(violated) % Acik violation adi kalmadiysa kontrol eder.
        row.FailureReason = "root_optimizer_not_accepted"; % Genel acceptance failure reason tanimlar.
    else % Bir veya daha fazla gercek violation varsa bu dali kullanir.
        row.FailureReason = string(strjoin(violated, ';')); % Constraint isimlerini tek failure string halinde birlestirir.
    end % Failure-string kosulunu sonlandirir.
end % Dataset-validity failure reason kosulunu sonlandirir.

    function s = candidate_score(ev_local) % Coarse/final ranking'de feasibility'yi power'dan onceleyen tek scalar score hesaplar.
        violation = max(ev_local.max_constraint_violation_scaled, 0.0); % En buyuk normalized hard-constraint violation degerini negatif olmayacak sekilde alir.
        s = ev_local.W_RO_kW + cfg.root.coarse_constraint_penalty * violation; % Physical violation'lari yuksek ceza ile power objective'e ekler.
    end % Candidate-score helper fonksiyonunu sonlandirir.

    function s = diagnostic_score(ev_local) % Hic feasible candidate yoksa en az kotu fiziksel noktayi secmek icin score hesaplar.
        violation = max(ev_local.max_constraint_violation_scaled, 0.0); % Maximum normalized constraint violation degerini alir.
        s = 1.0e6 * violation + ev_local.W_RO_kW; % Constraint violation'i power'dan cok daha agir tartarak diagnostic score olusturur.
    end % Diagnostic-score helper fonksiyonunu sonlandirir.

    function c = make_candidate(P1_value, rr_value, score_value) % Recovery-root sonucunu sabit field'li optimizer candidate struct'ina cevirir.
        c.P1 = P1_value; % Candidate Stage-1 pressure degerini kaydeder.
        c.P2 = rr_value.P2_gauge_MPa; % Candidate Stage-2 recovery-root pressure degerini kaydeder.
        c.ev = rr_value.ev; % Candidate detailed evaluation struct'ini kaydeder.
        c.score = score_value; % Candidate ranking score degerini kaydeder.
        c.root_evals = rr_value.n_evaluations; % Bu candidate root aramasindaki evaluation sayisini diagnostic olarak kaydeder.
    end % Candidate-construction helper fonksiyonunu sonlandirir.

    function a = empty_candidate_array() % Dynamic candidate eklemeye uygun bos struct array olusturur.
        a = struct('P1', {}, 'P2', {}, 'ev', {}, 'score', {}, 'root_evals', {}); % Candidate field schema'sini bos struct array olarak tanimlar.
    end % Empty-candidate helper fonksiyonunu sonlandirir.

end % Root-based tek DOE point optimizer fonksiyonunu sonlandirir.
