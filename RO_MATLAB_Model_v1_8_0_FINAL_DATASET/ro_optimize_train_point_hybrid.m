function row = ro_optimize_train_point_hybrid(DOE_ID, DOE_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg) % Recovery-root ile feasible seed bulup tek lokal fmincon ile N=150 minimum-power refinement yapan hibrit optimizer.

%% OUTPUT VE TIMER % Her durumda sabit kolonlu dataset row ve runtime diagnostic uretir.

row = ro_dataset_row_template(); % Dataset kolonlarini sabit field sirasi ile baslatir.
row.DOE_ID = DOE_ID; % DOE index degerini kaydeder.
row.DOE_Type = string(DOE_Type); % DOE sample tipini kaydeder.
row.Qf_train_m3h = Qf_train_m3h; % Feed-flow inputunu kaydeder.
row.T_RO_in_C = T_RO_in_C; % RO inlet temperature inputunu kaydeder.
row.Cf_kg_m3 = Cf_kg_m3; % Feed concentration inputunu kaydeder.
row.R_target = R_target; % Recovery target inputunu kaydeder.
row.OptimizerMethod = "root_seeded_fmincon"; % Kullanilan hibrit optimizer yontemini dataset'e kaydeder.
t_start = tic; % Tek DOE point wall-clock runtime olcumunu baslatir.

%% TOOLBOX KONTROLU % Final refinement icin gerekli fmincon fonksiyonunun kullanilabilirligini kontrol eder.

if exist('fmincon', 'file') ~= 2 % Optimization Toolbox fmincon fonksiyonunun path'te olup olmadigini kontrol eder.
    row.ExitFlag = -20; % Toolbox eksikligi icin ozel negatif exit flag atar.
    row.FailureReason = "fmincon_missing"; % Failure reason alanina toolbox eksikligini kaydeder.
    row.ErrorMessage = "Optimization Toolbox / fmincon bulunamadi."; % Kullaniciya acik hata mesaji kaydeder.
    row.Runtime_s = toc(t_start); % Kisa runtime degerini kaydeder.
    return; % Bu DOE noktasi icin fonksiyondan cikar.
end % fmincon availability kontrolunu sonlandirir.

%% ANALITIK SCREENING % Kesin infeasible noktalar icin detailed modeli hic cagirmadan cikis yapar.

screen = ro_analytic_screen_train_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg); % Necessary-condition screening sonucunu hesaplar.
row.AnalyticScreenPassed = screen.pass; % Screening pass/fail flag degerini dataset row'a kaydeder.
row.AnalyticRmax = screen.Rmax_analytic; % Analitik recovery upper-envelope degerini kaydeder.
row.AnalyticJavgTarget_LMH = screen.Javg_target_LMH; % Target recovery'nin zorunlu kildigi average flux degerini kaydeder.
if ~screen.pass % Analitik olarak kesin infeasible ise kontrol eder.
    row.ExitFlag = -10; % Analytic-screened noktalar icin ozel negatif exit flag atar.
    row.FailureReason = screen.reason; % Analitik failure nedenlerini kaydeder.
    row.Runtime_s = toc(t_start); % Model cagrisi yapmadan gecen runtime degerini kaydeder.
    return; % Pressure search yapmadan fonksiyondan cikar.
end % Analitik screening failure kosulunu sonlandirir.

%% HIZLI N=30 ROOT SEED TARAMASI % Tum 2-D pressure duzlemi yerine fiziksel olarak anlamli dinamik P1 araliginda recovery-matched P2 kokleri arar.

mem_search = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Osmotic-pressure search bound icin truth model ile ayni aged membrane struct'ini yukler.
pi_feed_MPa = ro_osmotic_pressure_du2014(T_RO_in_C, Cf_kg_m3, mem_search); % Raw feed osmotic pressure degerini Du korelasyonu ile hesaplar.
P1_lb_dynamic = max(cfg.hybrid.P1_lb_MPa, pi_feed_MPa + cfg.hybrid.P1_osmotic_margin_MPa); % P1 coarse search lower bound'unu feed osmotic pressure + modest NDP marji ile dinamik belirler.
P1_lb_dynamic = min(P1_lb_dynamic, cfg.hybrid.P1_ub_MPa); % Degisken lower bound'u manufacturer maximum pressure'i asmayacak sekilde sinirlar.
P1_seed_grid = linspace(cfg.hybrid.P1_ub_MPa, P1_lb_dynamic, cfg.hybrid.n_P1_seed); % Seed gridini yuksek P1'den asagiya dogru olusturarak target reachability kaybolunca erken durmaya izin verir.
seed_candidates = struct('P1', {}, 'P2', {}, 'ev', {}, 'score', {}); % Recovery-matched seed candidate listesini bos struct array olarak baslatir.
seed_eval_count = 0; % N=30 detailed evaluation sayacini sifirlar.

for k = 1:numel(P1_seed_grid) % Tum coarse P1 seed noktalarini yuksek basinctan asagiya sirayla gezer.
    rr = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, P1_seed_grid(k), cfg, cfg.hybrid.seed_N_segments, NaN); % Sabit P1 icin N=30 recovery root P2 degerini bulur.
    seed_eval_count = seed_eval_count + rr.n_evaluations; % Root aramasinda kullanilan model evaluation sayisini toplar.
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success % Finite ve recovery-matched root bulunduysa kontrol eder.
        c.P1 = P1_seed_grid(k); % Candidate Stage-1 pressure degerini kaydeder.
        c.P2 = rr.P2_gauge_MPa; % Candidate Stage-2 recovery-root pressure degerini kaydeder.
        c.ev = rr.ev; % Candidate detailed evaluation struct'ini kaydeder.
        c.score = seed_score(rr.ev); % Feasibility-agirlikli seed score degerini hesaplar.
        seed_candidates(end + 1) = c; %#ok<AGROW> % Candidate'i listeye ekler.
    elseif cfg.hybrid.break_after_recovery_unreachable && rr.failure_reason == "recovery_unreachable_at_P2_max" % P2 max'ta bile target ulasilamiyor ve P1 azalan sirada ise kontrol eder.
        break; % Daha dusuk P1 noktalarinda target recovery'nin yeniden ulasilmasi beklenmedigi icin coarse taramayi erken sonlandirir.
    end % Seed-root acceptance/early-break kosulunu sonlandirir.
end % Coarse P1 seed taramasini sonlandirir.

row.RootEvalCountCoarse = seed_eval_count; % Toplam N=30 model evaluation sayisini dataset row'a kaydeder.

if isempty(seed_candidates) % Hic recovery-matched N=30 seed bulunamadiysa kontrol eder.
    row.ExitFlag = -11; % Recovery root bulunamama durumuna ozel exit flag atar.
    row.FailureReason = "Recovery_root_not_found_N30"; % Failure reason alanina acik root failure nedenini kaydeder.
    row.Runtime_s = toc(t_start); % Noktanin toplam runtime degerini kaydeder.
    return; % N=150 refinement'a gecmeden fonksiyondan cikar.
end % Seed availability kontrolunu sonlandirir.

%% N=150 MULTI-SEED TRANSFER % N=30 gridde en iyi gorunen tek adaya guvenmek yerine sirali adaylari truth-grid'e aktararak grid-shift kaynakli yalanci seed failure'ini onler.

[~, seed_order] = sort([seed_candidates.score], 'ascend'); % N=30 adaylarini feasibility-agirlikli score'a gore en iyiden kotuye siralar.
n_trials = min(cfg.hybrid.n_N150_seed_trials, numel(seed_order)); % Truth-grid'e aktarilacak maksimum N=30 aday sayisini belirler.
transfer_candidates = struct('rank', {}, 'seed30', {}, 'rr150', {}, 'score', {}); % Basarili N=150 transfer adaylarini bos struct array olarak baslatir.
transfer_eval_count = 0; % Tum N=150 seed-transfer evaluation sayacini sifirlar.
transfer_messages = strings(0, 1); % Basarisiz seed transferlerinin diagnostic ozetlerini toplar.

for j = 1:n_trials % Siralanmis en iyi N=30 seed adaylarini N=150 truth-grid'e aktarmayi dener.
    idx = seed_order(j); % Mevcut N=30 aday indexini alir.
    seed_try = seed_candidates(idx); % Mevcut N=30 seed struct'ini alir.
    rr_try = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, seed_try.P1, cfg, cfg.hybrid.final_N_segments, seed_try.P2, cfg.hybrid.seed_transfer_recovery_tol); % Ayni P1'de N=150 recovery root'u daha ekonomik seed-transfer toleransiyla arar.
    transfer_eval_count = transfer_eval_count + rr_try.n_evaluations; % Bu transfer denemesindeki truth-model evaluation sayisini toplar.
    if rr_try.target_met && ~isempty(rr_try.ev) && rr_try.ev.success % Truth-grid recovery-matched finite seed bulunduysa kontrol eder.
        tc.rank = j; % N=30 score siralamasindaki seed rank degerini kaydeder.
        tc.seed30 = seed_try; % Ilgili N=30 seed struct'ini kaydeder.
        tc.rr150 = rr_try; % Truth-grid root sonucunu kaydeder.
        tc.score = seed_score(rr_try.ev); % N=150 physical feasibility ve power ile transfer score degerini hesaplar.
        transfer_candidates(end + 1) = tc; %#ok<AGROW> % Basarili transfer adayini listeye ekler.
        if rr_try.ev.physical_feasible % Ilk fiziksel-feasible truth-grid seed bulunduysa kontrol eder.
            break; % fmincon icin yeterince guvenli seed elde edildiginden gereksiz N=150 transferlerini durdurur.
        end % Physical-feasible early-stop kosulunu sonlandirir.
    else % Mevcut N=30 seed truth-grid'e aktarılamadiysa bu dali kullanir.
        transfer_messages(end + 1, 1) = sprintf('rank%d P1=%.5f P2hint=%.5f: %s (Rerr=%+.3e)', j, seed_try.P1, seed_try.P2, char(string(rr_try.failure_reason)), rr_try.recovery_error); %#ok<AGROW> % Failure nedenini diagnostic metin olarak kaydeder.
    end % N=150 transfer acceptance kosulunu sonlandirir.
end % Multi-seed truth-grid transfer dongusunu sonlandirir.

row.RootEvalCountFinal = transfer_eval_count; % Tum N=150 seed-transfer evaluation sayisini dataset row'a kaydeder.
row.HybridN150SeedTrials = n_trials; % Planlanan/denenen maximum seed-transfer sayisini diagnostic alana kaydeder.

if isempty(transfer_candidates) % Ilk truth-grid transfer denemelerinin hicbiri recovery-matched seed uretemediyse kontrol eder.
    row.ExitFlag = -12; % Truth-grid recovery-root failure durumuna ozel exit flag atar.
    row.FailureReason = "Recovery_root_not_found_N150_seed"; % Failure reason alanina acik root failure nedenini kaydeder.
    if ~isempty(transfer_messages) % Seed-transfer diagnostic mesajlari varsa kontrol eder.
        row.ErrorMessage = strjoin(transfer_messages, " | "); % Tum denenmis seed nedenlerini tek diagnostic string olarak kaydeder.
    end % Diagnostic-message kosulunu sonlandirir.
    row.Runtime_s = toc(t_start); % Noktanin toplam runtime degerini kaydeder.
    return; % fmincon refinement'a gecmeden fonksiyondan cikar.
end % Truth-grid seed availability kontrolunu sonlandirir.

[~, i_transfer] = min([transfer_candidates.score]); % Basarili truth-grid transferleri arasindan en dusuk feasibility-agirlikli score'a sahip adayi secer.
selected_transfer = transfer_candidates(i_transfer); % Secilen truth-grid seed-transfer struct'ini alir.
seed30 = selected_transfer.seed30; % Secilen N=30 seed diagnostic struct'ini alir.
rr150 = selected_transfer.rr150; % Secilen N=150 recovery-root sonucunu alir.
row.HybridSeedRankUsed = selected_transfer.rank; % Kullanilan N=30 seed rank degerini kaydeder.
row.HybridSeedP1_N30_MPa = seed30.P1; % Kullanilan N=30 Stage-1 seed pressure degerini kaydeder.
row.HybridSeedP2_N30_MPa = seed30.P2; % Kullanilan N=30 Stage-2 seed pressure degerini kaydeder.

x_seed = [seed30.P1, rr150.P2_gauge_MPa]; % Equality-manifold'a oturan final-grid initial pressure vectorunu olusturur.
ev_seed150 = rr150.ev; % N=150 root seed detailed evaluation struct'ini kaydeder.

%% LOCAL SEARCH BOUNDS % Root seed etrafinda yalnizca lokal bir basinç kutusu acarak gereksiz global fmincon gezintisini engeller.

lb_global = [P1_lb_dynamic, cfg.hybrid.P2_lb_MPa]; % Local fmincon Stage-1 lower boundunda ayni dinamik osmotic search boundunu korur.
ub_global = [cfg.hybrid.P1_ub_MPa, cfg.hybrid.P2_ub_MPa]; % Global pressure upper-bound vectorunu olusturur.
lb_local = [max(lb_global(1), x_seed(1) - cfg.hybrid.P1_halfwidth_MPa), max(lb_global(2), x_seed(2) - cfg.hybrid.P2_halfwidth_MPa)]; % Seed merkezli local lower-bound vectorunu hesaplar.
ub_local = [min(ub_global(1), x_seed(1) + cfg.hybrid.P1_halfwidth_MPa), min(ub_global(2), x_seed(2) + cfg.hybrid.P2_halfwidth_MPa)]; % Seed merkezli local upper-bound vectorunu hesaplar.

%% SINGLE FMINCON REFINEMENT % Root-matched seed'den tek SQP solve ile minimum-power feasible N=150 noktayi refine eder.

last_x = [NaN, NaN]; % Objective ve constraint cagrilari arasinda duplicate evaluation'i engelleyen cache key tanimlar.
last_ev = []; % Cached detailed evaluation struct'ini bos baslatir.

options = optimoptions('fmincon', ...
    'Algorithm', 'sqp', ... % Kucuk boyutlu nonlinear constrained problem icin SQP algoritmasini kullanir.
    'Display', 'off', ... % Dataset uretiminde Command Window kalabaligini engeller.
    'MaxIterations', cfg.hybrid.max_iterations, ... % Maximum local SQP iteration sayisini configuration'dan alir.
    'MaxFunctionEvaluations', cfg.hybrid.max_function_evaluations, ... % Maximum truth-model evaluation sayisini sinirlar.
    'ConstraintTolerance', cfg.hybrid.constraint_tolerance, ... % Nonlinear constraint toleransini configuration'dan alir.
    'StepTolerance', cfg.hybrid.step_tolerance, ... % Step toleransini configuration'dan alir.
    'OptimalityTolerance', cfg.hybrid.optimality_tolerance, ... % First-order optimality toleransini configuration'dan alir.
    'UseParallel', false); % Outer DOE parfor kullanacagi icin nested parallelism'i kapatir.

x_opt = x_seed; % fmincon exception durumunda fallback icin pressure vectorunu root seed ile baslatir.
exitflag = 0; % Baslangic exitflag degerini sifirlar.
output = struct('iterations', 0, 'funcCount', 0); % Baslangic optimizer diagnostic struct'ini tanimlar.

try % Tek local SQP solve sayisal hata verse bile root seed sonucunu kaybetmemek icin try-catch kullanir.
    [x_trial, ~, exitflag_trial, output_trial] = fmincon(@objective_cached, x_seed, [], [], [], [], lb_local, ub_local, @constraints_cached, options); % Root-seeded tek local constrained power minimization yapar.
    ev_trial = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, x_trial(1), x_trial(2), cfg); % fmincon final noktasini bagimsiz bir kez dogrular.
    if ev_trial.success % Final truth-model evaluation finite ise kontrol eder.
        x_opt = x_trial; % Candidate optimum pressure vectorunu kaydeder.
        exitflag = exitflag_trial; % Candidate fmincon exitflag degerini kaydeder.
        output = output_trial; % Candidate optimizer diagnostics struct'ini kaydeder.
    end % Finite fmincon endpoint acceptance kosulunu sonlandirir.
catch ME % fmincon veya truth-model exception durumunda bu dali kullanir.
    row.ErrorMessage = string(ME.message); % Exception mesajini diagnostic field'a kaydeder.
end % Single local refinement try-catch blogunu sonlandirir.

%% ROOT-SEED VE FMINCON SONUCUNU KARSILASTIR % Refinement daha kotu veya gecersizse equality-matched root seed'i guvenli fallback olarak korur.

ev_opt = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, x_opt(1), x_opt(2), cfg); % Secilen fmincon endpoint'ini final-grid modelde hesaplar.
seed_valid = ev_seed150.physical_feasible && abs(ev_seed150.Recovery - R_target) <= cfg.optim.recovery_accept_tolerance; % Root seed'in regression-valid olup olmadigini hesaplar.
opt_valid = ev_opt.success && ev_opt.physical_feasible && abs(ev_opt.Recovery - R_target) <= cfg.optim.recovery_accept_tolerance; % fmincon endpoint'in regression-valid olup olmadigini hesaplar.

if seed_valid && (~opt_valid || ev_seed150.W_RO_kW < ev_opt.W_RO_kW) % Root seed valid ve fmincon daha kotu/gecersiz ise kontrol eder.
    best_ev = ev_seed150; % Daha iyi root-seed detailed evaluation'i final sonuc yapar.
    best_x = x_seed; % Root-seed pressure vectorunu final sonuc yapar.
    final_exitflag = max(exitflag, 1); % Valid fallback icin pozitif status degeri kullanir.
else % fmincon endpoint daha iyi veya tek gecerli aday ise bu dali kullanir.
    best_ev = ev_opt; % fmincon detailed evaluation'i final sonuc yapar.
    best_x = x_opt; % fmincon pressure vectorunu final sonuc yapar.
    final_exitflag = exitflag; % fmincon exitflag degerini korur.
end % Final candidate secimini sonlandirir.

%% FLAT DATASET ROW % Secilen final truth-model sonucunu ANN dataset kolonlarina aktarir.

row.Qp_train_m3h = best_ev.Qp_train_m3h; % Actual permeate production degerini kaydeder.
row.Recovery_actual = best_ev.Recovery; % Actual recovery degerini kaydeder.
row.Recovery_error = best_ev.Recovery - R_target; % Target recovery residual degerini kaydeder.
row.Cp_mg_L = best_ev.Cp_mg_L; % Product concentration degerini mg/L olarak kaydeder.
row.W_RO_train_kW = best_ev.W_RO_kW; % Total train electrical power degerini kaydeder.
row.SEC_kWh_m3 = best_ev.SEC_kWh_m3; % SEC degerini diagnostic output olarak kaydeder.
row.P1_opt_gauge_MPa = best_x(1); % Secilen Stage-1 gauge pressure degerini kaydeder.
row.P2_opt_gauge_MPa = best_x(2); % Secilen Stage-2 gauge pressure degerini kaydeder.
row.Javg_LMH = best_ev.Javg_LMH; % System-average flux degerini kaydeder.
row.Jfirst_stage1_LMH = best_ev.Jfirst_stage1_LMH; % Stage-1 first-element average flux degerini kaydeder.
row.Jfirst_stage2_LMH = best_ev.Jfirst_stage2_LMH; % Stage-2 first-element average flux degerini kaydeder.
row.Jmax_local_stage1_LMH = best_ev.Jmax_local_stage1_LMH; % Stage-1 maximum local flux degerini kaydeder.
row.Jmax_local_stage2_LMH = best_ev.Jmax_local_stage2_LMH; % Stage-2 maximum local flux degerini kaydeder.
row.CPFmax_stage1 = best_ev.CPFmax_stage1; % Stage-1 maximum CPF degerini kaydeder.
row.CPFmax_stage2 = best_ev.CPFmax_stage2; % Stage-2 maximum CPF degerini kaydeder.
row.dP_stage1_MPa = best_ev.dP_stage1_MPa; % Stage-1 pressure-drop degerini kaydeder.
row.dP_stage2_MPa = best_ev.dP_stage2_MPa; % Stage-2 pressure-drop degerini kaydeder.
row.Cb_max_kg_m3 = best_ev.Cb_max_kg_m3; % Maximum bulk/brine concentration degerini kaydeder.
row.Qf_PV_stage1_m3h = best_ev.Qf_PV_stage1_m3h; % Stage-1 feed/PV degerini kaydeder.
row.Qf_PV_stage2_m3h = best_ev.Qf_PV_stage2_m3h; % Stage-2 feed/PV degerini kaydeder.
row.Qb_PV_stage1_m3h = best_ev.Qb_PV_stage1_m3h; % Stage-1 brine/PV degerini kaydeder.
row.Qb_PV_stage2_m3h = best_ev.Qb_PV_stage2_m3h; % Stage-2 brine/PV degerini kaydeder.
row.Qhpp_m3h = best_ev.Qhpp_m3h; % HPP feed flow degerini kaydeder.
row.PXout_gauge_MPa = best_ev.PXout_gauge_MPa; % PX high-pressure outlet pressure degerini kaydeder.
row.PX_excess_pressure_MPa = best_ev.PX_excess_pressure_MPa; % PX excess pressure diagnostic degerini kaydeder.
row.PX_booster_deltaP_MPa = best_ev.PX_booster_deltaP_MPa; % PX booster pressure-rise diagnostic degerini kaydeder.
row.PX_leakage_pct = best_ev.PX_leakage_pct; % PX leakage percentage degerini kaydeder.
row.PX_mix_pct = best_ev.PX_mix_pct; % PX mixing percentage degerini kaydeder.
row.PX_iterations = best_ev.PX_iterations; % Coupled PX-network iteration sayisini kaydeder.
row.PhysicalFeasible = best_ev.physical_feasible; % Recovery target haric hard physical/numerical feasibility flag degerini kaydeder.
row.RecoveryTargetMet = abs(row.Recovery_error) <= cfg.optim.recovery_accept_tolerance; % Final recovery acceptance flag degerini hesaplar.
row.DatasetValid = row.PhysicalFeasible && row.RecoveryTargetMet; % Regression ANN'ye girecek valid-point flag degerini hesaplar.
row.FeasibilityMarginScaled = best_ev.feasibility_margin_scaled; % En yakin normalized constraint margin degerini kaydeder.
row.MaxConstraintViolationScaled = best_ev.max_constraint_violation_scaled; % En buyuk normalized constraint violation degerini kaydeder.
row.ExitFlag = final_exitflag; % Hibrit optimizer final status code degerini kaydeder.
row.FminconIterations = get_output_field(output, 'iterations'); % Tek local fmincon iteration sayisini kaydeder.
row.FminconFunctionCount = get_output_field(output, 'funcCount'); % Tek local fmincon function-count degerini kaydeder.
row.LocalStartsAttempted = 1; % Hibrit optimizer yalnizca tek root-seeded local solve kullandigi icin bir degerini kaydeder.
row.Runtime_s = toc(t_start); % Tek DOE point toplam wall-clock runtime degerini saniye olarak kaydeder.

%% FAILURE REASON % Final nokta valid degilse gercek hard-constraint veya recovery nedenlerini kaydeder.

if row.DatasetValid % Final point regression dataset icin valid ise kontrol eder.
    row.FailureReason = ""; % Valid noktada failure reason alanini bos birakir.
else % Final point physical infeasible veya recovery acceptance disindaysa bu dali kullanir.
    violated = best_ev.constraint_names(best_ev.c_scaled > cfg.root.physical_constraint_accept_tolerance); % Round-off toleransini asan hard-constraint isimlerini secer.
    if ~row.RecoveryTargetMet % Recovery target ayrica saglanmadiysa kontrol eder.
        violated{end + 1} = 'Recovery_target_mismatch'; % Recovery mismatch nedenini failure listesine ekler.
    end % Recovery failure kosulunu sonlandirir.
    if isempty(violated) % Acik violation adi kalmadiysa kontrol eder.
        row.FailureReason = "hybrid_optimizer_not_accepted"; % Genel acceptance failure reason tanimlar.
    else % Bir veya daha fazla gercek violation varsa bu dali kullanir.
        row.FailureReason = string(strjoin(violated, ';')); % Constraint isimlerini tek failure string halinde birlestirir.
    end % Failure-string kosulunu sonlandirir.
end % Dataset-validity failure reason kosulunu sonlandirir.

    function s = seed_score(ev_local) % Hızli root seed ranking'de feasibility'yi recovery-matched power'dan onceleyen scalar score hesaplar.
        violation = max(ev_local.max_constraint_violation_scaled, 0.0); % Maximum normalized physical constraint violation degerini negatif olmayacak sekilde alir.
        s = ev_local.W_RO_kW + cfg.hybrid.seed_constraint_penalty * violation; % Physical violation'lari yuksek ceza ile power objective'e ekler.
    end % Seed-score helper fonksiyonunu sonlandirir.

    function f = objective_cached(x) % fmincon objective icin cached N=150 detailed model evaluation kullanir.
        ev_local = get_cached_evaluation(x); % Mevcut pressure vectoru icin truth-model sonucunu cache'den alir veya hesaplar.
        if ev_local.success && isfinite(ev_local.W_RO_kW) % Kullanilabilir power degeri varsa kontrol eder.
            f = ev_local.W_RO_kW; % Objective olarak total RO train electrical power degerini minimize eder.
        else % Detailed evaluation sayisal olarak gecersizse bu dali kullanir.
            f = 1.0e9; % Optimizer'i gecersiz noktadan uzaklastiracak buyuk objective degeri dondurur.
        end % Objective-validity kosulunu sonlandirir.
    end % Cached objective nested fonksiyonunu sonlandirir.

    function [c, ceq] = constraints_cached(x) % fmincon nonlinear hard constraints ve recovery equality constraint'ini dondurur.
        ev_local = get_cached_evaluation(x); % Mevcut pressure vectoru icin truth-model sonucunu cache'den alir veya hesaplar.
        if ev_local.success % Detailed evaluation finite ise kontrol eder.
            c = ev_local.c_scaled; % Tum technical/numerical inequality constraints'i c<=0 formunda dondurur.
            ceq = ev_local.Recovery - R_target; % Actual recovery'yi target recovery'ye esit olmaya zorlayan equality constraint'i tanimlar.
        else % Detailed evaluation basarisizsa bu dali kullanir.
            c = ones(numel(ro_constraint_names()), 1); % Tum inequality constraints'i gecersiz noktada pozitif violation yapar.
            ceq = 1.0; % Buyuk equality violation ile optimizer'i bu noktadan uzaklastirir.
        end % Constraint-validity kosulunu sonlandirir.
    end % Cached nonlinear-constraint nested fonksiyonunu sonlandirir.

    function ev_local = get_cached_evaluation(x) % Objective ve constraint calls arasinda ayni pressure noktasini tekrar cozmemek icin tek-nokta cache uygular.
        if isempty(last_ev) || any(~isfinite(last_x)) || max(abs(x(:).' - last_x)) > 1.0e-12 % Cache key degerinin mevcut pressure vectoruyla ayni olup olmadigini kontrol eder.
            last_x = x(:).'; % Yeni pressure vectorunu cache key olarak kaydeder.
            last_ev = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, last_x(1), last_x(2), cfg); % N=150 detailed evaluation'i bir kez hesaplar.
        end % Cache yenileme kosulunu sonlandirir.
        ev_local = last_ev; % Cached detailed evaluation struct'ini dondurur.
    end % Cached-evaluation nested fonksiyonunu sonlandirir.

end % Root-seeded hybrid optimizer fonksiyonunu sonlandirir.

function value = get_output_field(output, field_name) % fmincon output struct'inda field varsa degerini, yoksa NaN dondurur.

if isstruct(output) && isfield(output, field_name) % Istenen output field mevcutsa kontrol eder.
    value = output.(field_name); % Mevcut field degerini dondurur.
else % Field mevcut degilse bu dali kullanir.
    value = NaN; % Eksik output field icin NaN dondurur.
end % Field-existence kosulunu sonlandirir.

end % Yardimci output-field fonksiyonunu sonlandirir.
