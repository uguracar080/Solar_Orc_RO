function row = ro_optimize_train_point(DOE_ID, DOE_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg) % Bir DOE noktasi icin P1-P2 optimum feasible operating point'i bulur.

%% OUTPUT TEMPLATE % Basarisiz noktalarda bile tam kolonlu dataset row dondurur.

row = ro_dataset_row_template(); % Sabit alanli bos dataset row'u yukler.
row.DOE_ID = DOE_ID; % DOE index degerini kaydeder.
row.DOE_Type = string(DOE_Type); % DOE sample tipini kaydeder.
row.Qf_train_m3h = Qf_train_m3h; % Feed flow inputunu kaydeder.
row.T_RO_in_C = T_RO_in_C; % RO inlet temperature inputunu kaydeder.
row.Cf_kg_m3 = Cf_kg_m3; % Feed concentration inputunu kaydeder.
row.R_target = R_target; % Recovery target inputunu kaydeder.

%% OPTIMIZATION TOOLBOX KONTROLU % fmincon mevcut degilse acik hata mesaji ile noktayi gecersiz yapar.

if exist('fmincon', 'file') ~= 2 % MATLAB Optimization Toolbox fmincon fonksiyonunun path'te olup olmadigini kontrol eder.
    row.FailureReason = "fmincon_missing"; % Failure reason alanina toolbox eksikligini kaydeder.
    row.ErrorMessage = "Optimization Toolbox / fmincon bulunamadi."; % Kullaniciya acik hata mesajini kaydeder.
    return; % Bu DOE noktasini sonlandirir.
end % fmincon kontrolunu sonlandirir.

%% PRESSURE BOUNDS % Iki pressure decision variable icin search bounds tanimlar.

lb = [cfg.optim.P1_lb_MPa, cfg.optim.P2_lb_MPa]; % P1-P2 lower bound vectorunu olusturur.
ub = [cfg.optim.P1_ub_MPa, cfg.optim.P2_ub_MPa]; % P1-P2 upper bound vectorunu olusturur.

%% COARSE SEED TARAMASI % Hizli N=30 model ile pressure duzleminde iyi initial guesses bulur.

cfg_seed = cfg; % Final configuration struct'ini seed taramasi icin kopyalar.
cfg_seed.model.N_segments = cfg.optim.coarse_N_segments; % Sadece coarse taramada daha hizli axial grid kullanir.
n_axis = cfg.optim.coarse_points_per_axis; % Her pressure eksenindeki coarse nokta sayisini alir.
P1_grid = linspace(lb(1), ub(1), n_axis); % Coarse Stage-1 pressure grid vectorunu olusturur.
P2_grid = linspace(lb(2), ub(2), n_axis); % Coarse Stage-2 pressure grid vectorunu olusturur.
seed_list = zeros(n_axis * n_axis, 2); % Tum coarse pressure kombinasyonlarini saklayacak matrix olusturur.
seed_score = inf(n_axis * n_axis, 1); % Coarse seed quality score vectorunu sonsuzla baslatir.
seed_counter = 0; % Coarse grid index sayacini baslatir.

for i = 1:n_axis % Tum Stage-1 coarse pressures uzerinde dongu kurar.
    for j = 1:n_axis % Tum Stage-2 coarse pressures uzerinde dongu kurar.
        seed_counter = seed_counter + 1; % Coarse combination index degerini bir arttirir.
        x_seed = [P1_grid(i), P2_grid(j)]; % Mevcut P1-P2 coarse combination degerini olusturur.
        ev_seed = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, x_seed(1), x_seed(2), cfg_seed); % Hizli detailed model ile coarse noktayi degerlendirir.
        seed_list(seed_counter, :) = x_seed; % Coarse pressure combination degerini kaydeder.
        if ev_seed.success % Coarse model finite bir sonuc verdiyse score hesaplar.
            recovery_term = abs(ev_seed.Recovery - R_target) / 0.01; % Recovery mismatch'i 1 percentage-point olceginde normalize eder.
            constraint_term = sum(max(ev_seed.c_scaled, 0.0).^2); % Hard constraint violation'larinin kare toplamını hesaplar.
            power_term = ev_seed.W_RO_kW / 1000.0; % Power degerini seed siralamasinda cok kucuk tie-breaker terim olarak kullanir.
            seed_score(seed_counter) = recovery_term + 100.0 * constraint_term + power_term; % Recovery ve feasibility agirlikli toplam seed score degerini hesaplar.
        end % Coarse model basari kosulunu sonlandirir.
    end % Stage-2 pressure grid dongusunu sonlandirir.
end % Stage-1 pressure grid dongusunu sonlandirir.

[~, seed_order] = sort(seed_score, 'ascend'); % Coarse pressure combinations'i en iyi score'dan en kotuye siralar.
n_starts = min(cfg.optim.n_local_starts, size(seed_list, 1)); % Gercekte calistirilacak local optimization sayisini sinirlar.
starts = seed_list(seed_order(1:n_starts), :); % En iyi coarse seed pressure kombinasyonlarini secer.

%% FMINCON OPTIONS % Iki-degiskenli nonlinear constrained optimization icin deterministic ayarlari tanimlar.

options = optimoptions('fmincon', ...
    'Algorithm', 'sqp', ... % Kucuk boyutlu nonlinear constrained problem icin SQP algoritmasini kullanir.
    'Display', 'off', ... % Binlerce DOE noktasinda Command Window cikti kalabaligini engeller.
    'MaxIterations', cfg.optim.max_iterations, ... % Maximum iteration limitini configuration'dan alir.
    'MaxFunctionEvaluations', cfg.optim.max_function_evaluations, ... % Maximum function-evaluation limitini configuration'dan alir.
    'ConstraintTolerance', cfg.optim.constraint_tolerance, ... % Nonlinear constraint toleransini configuration'dan alir.
    'StepTolerance', cfg.optim.step_tolerance, ... % Step toleransini configuration'dan alir.
    'OptimalityTolerance', cfg.optim.optimality_tolerance, ... % First-order optimality toleransini configuration'dan alir.
    'UseParallel', false); % Outer DOE parfor ile calisacagi icin fmincon icinde nested parallelism'i kapatir.

%% MULTI-START LOCAL OPTIMIZATION % Coarse taramadan secilen birkaç seed'i final N=150 truth model ile refine eder.

best_valid_power = inf; % En iyi valid local optimum power degerini sonsuzla baslatir.
best_any_score = inf; % Valid cozum bulunamazsa en az kotu diagnostic noktayi saklamak icin score degerini baslatir.
best_eval = []; % En iyi final detailed evaluation struct'i icin bos deger tanimlar.
best_x = [NaN, NaN]; % En iyi P1-P2 vectorunu baslangicta NaN tanimlar.
best_exitflag = NaN; % En iyi local optimization exitflag degerini baslangicta NaN tanimlar.
best_output = struct('iterations', NaN, 'funcCount', NaN); % En iyi local optimization output degerlerini baslangicta NaN tanimlar.

for s = 1:n_starts % Secilen tum local start noktalarini sirayla cozer.
    last_x = [NaN, NaN]; % Nested objective/constraint calls arasinda duplicate truth-model evaluation'i engelleyen cache key tanimlar.
    last_ev = []; % Cached detailed evaluation struct'ini bos tanimlar.

    try % Bir local optimization sayisal hata verse bile diger seed'lerin denenmesini saglar.
        [x_opt, ~, exitflag, output] = fmincon(@objective_cached, starts(s, :), [], [], [], [], lb, ub, @constraints_cached, options); % Final N=150 truth model uzerinde constrained power minimization yapar.
        ev_opt = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, x_opt(1), x_opt(2), cfg); % fmincon final noktasini cache'den bagimsiz bir kez daha dogrular.
    catch ME % fmincon veya truth-model hata verirse bu dali kullanir.
        ev_opt = []; % Bu start icin gecerli detailed evaluation olmadigini isaretler.
        exitflag = -999; % Catch durumunu ozel negatif exitflag ile kaydeder.
        output = struct('iterations', NaN, 'funcCount', NaN); % Catch durumunda output alanlarini NaN yapar.
        if strlength(row.ErrorMessage) == 0 % Ilk error message henuz kaydedilmemisse kontrol eder.
            row.ErrorMessage = string(ME.message); % Ilk local optimization hata mesajini diagnostic olarak kaydeder.
        end % Error-message kosulunu sonlandirir.
    end % Local optimization try-catch blogunu sonlandirir.

    if isempty(ev_opt) || ~isfield(ev_opt, 'success') || ~ev_opt.success % Final evaluation basarisizsa bu start'i atlar.
        continue; % Sonraki local start'a gecer.
    end % Final evaluation basari kontrolunu sonlandirir.

    recovery_error = ev_opt.Recovery - R_target; % Final actual recovery ile target arasindaki farki hesaplar.
    target_met = abs(recovery_error) <= cfg.optim.recovery_accept_tolerance; % Recovery target'in final acceptance toleransinda saglanip saglanmadigini kontrol eder.
    valid_now = ev_opt.physical_feasible && target_met; % Bu local optimum'un regression dataset icin valid olup olmadigini hesaplar.

    if valid_now && ev_opt.W_RO_kW < best_valid_power % Daha dusuk power'li valid cozum bulunup bulunmadigini kontrol eder.
        best_valid_power = ev_opt.W_RO_kW; % En iyi valid power degerini gunceller.
        best_eval = ev_opt; % En iyi detailed evaluation struct'ini gunceller.
        best_x = x_opt; % En iyi pressure vectorunu gunceller.
        best_exitflag = exitflag; % En iyi local optimization exitflag degerini gunceller.
        best_output = output; % En iyi local optimization output struct'ini gunceller.
    end % Valid-best update kosulunu sonlandirir.

    diagnostic_score = 1000.0 * ev_opt.max_constraint_violation_scaled + 100.0 * abs(recovery_error) + ev_opt.W_RO_kW / 1000.0; % Infeasible noktalarda en az kotu diagnostic final point score degerini hesaplar.
    if ~isfinite(best_valid_power) && diagnostic_score < best_any_score % Henuz valid cozum yokken daha iyi diagnostic nokta bulunduysa kontrol eder.
        best_any_score = diagnostic_score; % En iyi diagnostic score degerini gunceller.
        best_eval = ev_opt; % En iyi diagnostic detailed evaluation'i kaydeder.
        best_x = x_opt; % En iyi diagnostic pressure vectorunu kaydeder.
        best_exitflag = exitflag; % Diagnostic exitflag degerini kaydeder.
        best_output = output; % Diagnostic fmincon output struct'ini kaydeder.
    end % Diagnostic-best update kosulunu sonlandirir.
end % Multi-start local optimization dongusunu sonlandirir.

%% SONUC YOKSA FAILURE ROW % Tum local starts sayisal olarak basarisiz olduysa acik failure reason kaydeder.

if isempty(best_eval) % Hicbir local start finite final evaluation uretemediyse kontrol eder.
    row.LocalStartsAttempted = n_starts; % Denenen local start sayisini kaydeder.
    row.FailureReason = "no_finite_optimizer_solution"; % Failure reason degerini kaydeder.
    return; % Bu DOE noktasi icin sonucu dondurur.
end % Bos sonuc kontrolunu sonlandirir.

%% FLAT DATASET ROW % En iyi final operating point'in tum primary ve diagnostic outputlarini tablo satirina aktarir.

row.Qp_train_m3h = best_eval.Qp_train_m3h; % Actual permeate production degerini kaydeder.
row.Recovery_actual = best_eval.Recovery; % Actual recovery degerini kaydeder.
row.Recovery_error = best_eval.Recovery - R_target; % Target recovery error degerini kaydeder.
row.Cp_mg_L = best_eval.Cp_mg_L; % Product concentration degerini kaydeder.
row.W_RO_train_kW = best_eval.W_RO_kW; % Total train electrical power degerini kaydeder.
row.SEC_kWh_m3 = best_eval.SEC_kWh_m3; % Actual SEC degerini diagnostic olarak kaydeder.
row.P1_opt_gauge_MPa = best_x(1); % Optimum Stage-1 gauge pressure degerini kaydeder.
row.P2_opt_gauge_MPa = best_x(2); % Optimum Stage-2 gauge pressure degerini kaydeder.
row.Javg_LMH = best_eval.Javg_LMH; % System-average flux degerini kaydeder.
row.Jfirst_stage1_LMH = best_eval.Jfirst_stage1_LMH; % Stage-1 first-element average flux degerini kaydeder.
row.Jfirst_stage2_LMH = best_eval.Jfirst_stage2_LMH; % Stage-2 first-element average flux degerini kaydeder.
row.Jmax_local_stage1_LMH = best_eval.Jmax_local_stage1_LMH; % Stage-1 maximum local segment flux degerini kaydeder.
row.Jmax_local_stage2_LMH = best_eval.Jmax_local_stage2_LMH; % Stage-2 maximum local segment flux degerini kaydeder.
row.CPFmax_stage1 = best_eval.CPFmax_stage1; % Stage-1 CPFmax degerini kaydeder.
row.CPFmax_stage2 = best_eval.CPFmax_stage2; % Stage-2 CPFmax degerini kaydeder.
row.dP_stage1_MPa = best_eval.dP_stage1_MPa; % Stage-1 pressure drop degerini kaydeder.
row.dP_stage2_MPa = best_eval.dP_stage2_MPa; % Stage-2 pressure drop degerini kaydeder.
row.Cb_max_kg_m3 = best_eval.Cb_max_kg_m3; % Maximum bulk/brine concentration degerini kaydeder.
row.Qf_PV_stage1_m3h = best_eval.Qf_PV_stage1_m3h; % Stage-1 feed flow/PV degerini kaydeder.
row.Qf_PV_stage2_m3h = best_eval.Qf_PV_stage2_m3h; % Stage-2 feed flow/PV degerini kaydeder.
row.Qb_PV_stage1_m3h = best_eval.Qb_PV_stage1_m3h; % Stage-1 brine flow/PV degerini kaydeder.
row.Qb_PV_stage2_m3h = best_eval.Qb_PV_stage2_m3h; % Stage-2 brine flow/PV degerini kaydeder.
row.Qhpp_m3h = best_eval.Qhpp_m3h; % HPP flow degerini kaydeder.
row.PXout_gauge_MPa = best_eval.PXout_gauge_MPa; % PX high-pressure outlet pressure degerini kaydeder.
row.PX_excess_pressure_MPa = best_eval.PX_excess_pressure_MPa; % PX outlet pressure Stage-1 pressure'dan yuksekse throttling excess degerini kaydeder.
row.PX_booster_deltaP_MPa = best_eval.PX_booster_deltaP_MPa; % PX outlet pressure Stage-1 pressure'dan dusukse booster deltaP degerini kaydeder.
row.PX_leakage_pct = best_eval.PX_leakage_pct; % PX leakage percentage degerini kaydeder.
row.PX_mix_pct = best_eval.PX_mix_pct; % PX mixing percentage degerini kaydeder.
row.PX_iterations = best_eval.PX_iterations; % Coupled PX iteration sayisini kaydeder.
row.PhysicalFeasible = best_eval.physical_feasible; % Recovery target haric hard feasibility flag degerini kaydeder.
row.RecoveryTargetMet = abs(row.Recovery_error) <= cfg.optim.recovery_accept_tolerance; % Recovery target acceptance flag degerini kaydeder.
row.DatasetValid = row.PhysicalFeasible && row.RecoveryTargetMet; % Regression ANN'ye girecek valid point flag degerini kaydeder.
row.FeasibilityMarginScaled = best_eval.feasibility_margin_scaled; % En yakin normalized hard-constraint margin degerini kaydeder.
row.MaxConstraintViolationScaled = best_eval.max_constraint_violation_scaled; % En buyuk normalized hard-constraint violation degerini kaydeder.
row.ExitFlag = best_exitflag; % Secilen fmincon solution exitflag degerini kaydeder.
row.FminconIterations = get_output_field(best_output, 'iterations'); % Secilen fmincon iteration sayisini kaydeder.
row.FminconFunctionCount = get_output_field(best_output, 'funcCount'); % Secilen fmincon function-evaluation sayisini kaydeder.
row.LocalStartsAttempted = n_starts; % Denenen local start sayisini kaydeder.

if row.DatasetValid % Nokta regression dataset icin valid ise failure reason bos birakir.
    row.FailureReason = ""; % Valid point icin failure reason alanini temizler.
else % Nokta infeasible veya recovery target mismatch ise failure reason olusturur.
    violated = best_eval.constraint_names(best_eval.c_scaled > 0.0); % Pozitif hard-constraint violation isimlerini secer.
    if ~row.RecoveryTargetMet % Recovery target ayrica saglanmadiysa kontrol eder.
        violated{end + 1} = 'Recovery_target_mismatch'; % Recovery mismatch nedenini listeye ekler.
    end % Recovery-target failure kosulunu sonlandirir.
    if isempty(violated) % Herhangi bir acik constraint adi yoksa kontrol eder.
        row.FailureReason = "optimizer_not_accepted"; % Genel failure reason tanimlar.
    else % Bir veya daha fazla violation varsa bu dali kullanir.
        row.FailureReason = string(strjoin(violated, ';')); % Violation isimlerini tek string halinde kaydeder.
    end % Failure-reason olusturma kosulunu sonlandirir.
end % Dataset-validity failure-reason kosulunu sonlandirir.

    function f = objective_cached(x) % fmincon objective icin cached detailed model evaluation kullanir.
        ev = get_cached_evaluation(x); % Mevcut pressure vectoru icin detailed model sonucunu cache'den alir veya hesaplar.
        if ev.success && isfinite(ev.W_RO_kW) % Physical power degeri kullanilabilir durumdaysa kontrol eder.
            f = ev.W_RO_kW; % Objective olarak total RO train electrical power degerini minimize eder.
        else % Detailed evaluation sayisal olarak gecersizse bu dali kullanir.
            f = 1.0e9; % Optimizer'i gecersiz noktadan uzaklastiracak buyuk objective degeri dondurur.
        end % Objective-validity kosulunu sonlandirir.
    end % Cached objective nested fonksiyonunu sonlandirir.

    function [c, ceq] = constraints_cached(x) % fmincon nonlinear hard constraints ve recovery equality constraint'ini dondurur.
        ev = get_cached_evaluation(x); % Mevcut pressure vectoru icin detailed model sonucunu cache'den alir veya hesaplar.
        c = ev.c_scaled; % Tum technical/numerical inequality constraints'i c<=0 formunda dondurur.
        if ev.success && isfield(ev, 'Recovery') && isfinite(ev.Recovery) % Recovery sonucu finite ise kontrol eder.
            ceq = ev.Recovery - R_target; % Actual recovery'yi target recovery'ye esit olmaya zorlayan equality constraint'i tanimlar.
        else % Detailed evaluation basarisizsa bu dali kullanir.
            ceq = 1.0; % Buyuk equality violation ile optimizer'i bu noktadan uzaklastirir.
        end % Recovery equality kosulunu sonlandirir.
    end % Cached nonlinear-constraint nested fonksiyonunu sonlandirir.

    function ev = get_cached_evaluation(x) % Objective ve constraint calls arasinda ayni pressure noktasini tekrar cozmemek icin cache uygular.
        if isempty(last_ev) || any(~isfinite(last_x)) || max(abs(x(:).' - last_x)) > 1.0e-12 % Cache'in gecerli olup olmadigini kontrol eder.
            last_x = x(:).'; % Yeni pressure vectorunu cache key olarak kaydeder.
            last_ev = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, last_x(1), last_x(2), cfg); % Final N=150 detailed evaluation'i bir kez hesaplar.
        end % Cache yenileme kosulunu sonlandirir.
        ev = last_ev; % Cached detailed evaluation struct'ini dondurur.
    end % Cached-evaluation nested fonksiyonunu sonlandirir.

end % Tek DOE noktasi pressure optimization fonksiyonunu sonlandirir.

function value = get_output_field(output, field_name) % fmincon output struct'inda field varsa degerini, yoksa NaN dondurur.

if isstruct(output) && isfield(output, field_name) % Istenen output field mevcutsa kontrol eder.
    value = output.(field_name); % Mevcut field degerini dondurur.
else % Field mevcut degilse bu dali kullanir.
    value = NaN; % Eksik output field icin NaN dondurur.
end % Field-existence kosulunu sonlandirir.

end % Yardimci output-field fonksiyonunu sonlandirir.
