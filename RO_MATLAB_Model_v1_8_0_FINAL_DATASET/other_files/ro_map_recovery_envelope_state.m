function [env, ProbeTable] = ro_map_recovery_envelope_state(State_ID, State_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, cfg) % Tek Qf-T-Cf state icin feasible recovery bandini coarse scan + bisection ile haritalar.

%% BASLANGIC % Envelope output, probe log ve analytic recovery cap degerlerini baslatir.

t_state = tic; % Tek base-state toplam wall-clock runtime olcumunu baslatir.
env = envelope_row_template(); % Sabit field sirali envelope result struct'ini olusturur.
env.State_ID = State_ID; % Base-state kimligini kaydeder.
env.State_Type = string(State_Type); % Base-state sampling stratum label'ini kaydeder.
env.Qf_train_m3h = Qf_train_m3h; % Feed-flow state inputunu kaydeder.
env.T_RO_in_C = T_RO_in_C; % Temperature state inputunu kaydeder.
env.Cf_kg_m3 = Cf_kg_m3; % Concentration state inputunu kaydeder.
ProbeRows = repmat(probe_row_template(), 0, 1); % Tum optimizer probe'larini kaydedecek bos struct array'i olusturur.
probe_counter = 0; % State icindeki truth-optimizer probe sayacini sifirdan baslatir.

sc0 = ro_analytic_screen_train_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, cfg.domain.R_min, cfg); % Pressure optimization'dan bagimsiz analytic recovery upper envelope degerini hesaplar.
env.Rmax_analytic = sc0.Rmax_analytic; % Raw analytic upper recovery degerini envelope output'a kaydeder.
Rlo = cfg.domain.R_min; % Global recovery-domain alt sinirini scan alt siniri yapar.
Rhi_raw = min(cfg.domain.R_max, sc0.Rmax_analytic); % Global ve analytic recovery upper bound'larinin minimumunu alir.
Rhi = Rhi_raw - cfg.envelope.R_upper_guard; % Exact analytic boundary'nin biraz altina numerical guard uygular.
env.R_scan_low = Rlo; % Kullanilan scan alt recovery degerini kaydeder.
env.R_scan_high = Rhi; % Kullanilan scan ust recovery degerini kaydeder.

if ~isfinite(Rhi) || Rhi <= Rlo + cfg.envelope.R_boundary_tolerance % Kullanilabilir recovery span'i yoksa kontrol eder.
    env.HasFeasibleBand = false; % State'i feasible band bulunamamis olarak isaretler.
    env.BoundaryStatus = "Analytic_no_recovery_span"; % Analitik envelope kaynakli no-band durumunu kaydeder.
    env.Runtime_s = toc(t_state); % Kisa state runtime degerini kaydeder.
    ProbeTable = struct2table(ProbeRows); % Bos probe log'u sabit kolonlu table'a cevirir.
    return; % Detailed optimizer cagrisi yapmadan fonksiyondan cikar.
end % Analitik span kontrolunu sonlandirir.

%% COARSE RECOVERY SCAN % Feasible adayi olan recovery adasini kaybetmemek icin tum recovery span'ini deterministic olarak tarar.

Rcoarse = linspace(Rlo, Rhi, cfg.envelope.n_R_coarse).'; % Global lower bound ile conditional analytic cap arasinda uniform recovery probe'lari olusturur.
CoarseRows = repmat(ro_dataset_row_template(), numel(Rcoarse), 1); % Coarse optimizer output struct array'ini preallocate eder.
for k = 1:numel(Rcoarse) % Tum coarse recovery probe'lari uzerinde dongu kurar.
    [CoarseRows(k), ProbeRows, probe_counter] = evaluate_probe(State_ID, State_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, Rcoarse(k), "Coarse", probe_counter, ProbeRows, cfg); % FASTSEARCH optimizer ile tek recovery probe'unu cozer ve loglar.
end % Coarse scan loop'unu sonlandirir.
valid_mask = arrayfun(@(x) logical(x.DatasetValid), CoarseRows).'; % Coarse scan'deki regression-valid recovery noktalarini logical vector olarak cikarir.
env.CoarseProbeCount = numel(Rcoarse); % Coarse recovery probe sayisini kaydeder.
env.CoarseValidCount = sum(valid_mask); % Coarse scan'de bulunan valid probe sayisini kaydeder.

if ~any(valid_mask) % Coarse scan hic valid recovery bulamadiysa kontrol eder.
    env.HasFeasibleBand = false; % State'i feasible recovery band bulunamamis olarak isaretler.
    env.BoundaryStatus = "No_valid_recovery_in_coarse_scan"; % Coarse scan no-band durumunu kaydeder.
    env.DominantFailureReason = dominant_failure_string(string({CoarseRows.FailureReason}).'); % En sik coarse failure nedenini diagnostic olarak kaydeder.
    env.TotalProbeCount = probe_counter; % Toplam optimizer probe sayisini kaydeder.
    env.TotalValidProbeCount = sum([ProbeRows.DatasetValid]); % Tum probe logundaki valid nokta sayisini kaydeder.
    env.Runtime_s = toc(t_state); % Base-state toplam runtime degerini kaydeder.
    ProbeTable = struct2table(ProbeRows); % Probe struct array'ini table'a cevirir.
    return; % Boundary refinement yapmadan fonksiyondan cikar.
end % Coarse valid-existence kontrolunu sonlandirir.

%% FEASIBLE ADAY ADASI % Coarse scan'de numerical/optimizer hole varsa en uzun contiguous valid recovery adasini secerek yanlis band birlestirmesini onler.

[run_start, run_end, n_runs] = longest_true_run(valid_mask); % Coarse valid-mask icindeki en uzun contiguous run'i bulur.
env.NonContiguousCoarse = n_runs > 1; % Birden fazla valid ada gorulup gorulmedigini diagnostic flag olarak kaydeder.
env.CoarseValidRuns = n_runs; % Coarse valid ada sayisini kaydeder.
first_valid = run_start; % Secilen valid adanin ilk coarse indexini alir.
last_valid = run_end; % Secilen valid adanin son coarse indexini alir.
first_valid_row = CoarseRows(first_valid); % Lower-bound refinement icin ilk valid optimizer sonucunu alir.
last_valid_row = CoarseRows(last_valid); % Upper-bound refinement icin son valid optimizer sonucunu alir.

%% ALT RECOVERY BOUNDARY % Quality-limited veya pressure/recovery-limited alt feasibility sinirini invalid-valid bracket ile refine eder.

if first_valid == 1 % Global R floor'daki ilk coarse probe valid ise kontrol eder.
    Rmin_feasible = Rcoarse(1); % Feasible lower boundary'yi global domain floor olarak tanimlar.
    lower_valid_row = first_valid_row; % Boundary representative valid row olarak ilk coarse sonucu kullanir.
    lower_fail_reason = ""; % Invalid tarafta bracket olmadigi icin failure reason'i bos birakir.
    lower_status = "Global_R_floor_valid"; % Lower-bound status label'ini kaydeder.
else % Ilk valid probe'un altinda en az bir invalid coarse nokta varsa bu dali kullanir.
    Rinv = Rcoarse(first_valid - 1); % Lower bracket'in invalid recovery ucunu alir.
    Rval = Rcoarse(first_valid); % Lower bracket'in valid recovery ucunu alir.
    invalid_row = CoarseRows(first_valid - 1); % Boundary'nin invalid-side failure bilgisini alir.
    lower_valid_row = first_valid_row; % Mevcut en dusuk valid row'u baslatir.
    for ib = 1:cfg.envelope.n_bisection % Lower boundary bisection refinement dongusunu kurar.
        if Rval - Rinv <= cfg.envelope.R_boundary_tolerance % Recovery bracket yeterince daraldiysa kontrol eder.
            break; % Gereksiz truth-model cagrilarini onlemek icin refinement'i sonlandirir.
        end % Bracket-width termination kosulunu sonlandirir.
        Rmid = 0.5 * (Rinv + Rval); % Invalid-valid bracket'in orta recovery degerini hesaplar.
        [mid_row, ProbeRows, probe_counter] = evaluate_probe(State_ID, State_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, Rmid, "LowerBisect", probe_counter, ProbeRows, cfg); % Midpoint'i FASTSEARCH ile cozer.
        if mid_row.DatasetValid % Midpoint feasible ise kontrol eder.
            Rval = Rmid; % Feasible upper bracket ucunu daha dusuk recovery'ye indirir.
            lower_valid_row = mid_row; % En dusuk yeni valid row'u boundary representative yapar.
        else % Midpoint infeasible ise bu dali kullanir.
            Rinv = Rmid; % Invalid lower bracket ucunu yukari tasir.
            invalid_row = mid_row; % En yakin invalid-side failure bilgisini gunceller.
        end % Lower bisection feasibility kararini sonlandirir.
    end % Lower boundary bisection dongusunu sonlandirir.
    Rmin_feasible = Rval; % Refined lower feasible recovery boundary degerini en dusuk valid bracket ucu olarak kaydeder.
    lower_fail_reason = string(invalid_row.FailureReason); % Boundary'nin invalid tarafindaki son failure reason'i kaydeder.
    lower_status = "Refined_invalid_to_valid"; % Lower-bound refinement status label'ini kaydeder.
end % Lower-bound branch'ini sonlandirir.

%% UST RECOVERY BOUNDARY % Flux, brine, dP veya pressure-limited ust feasibility sinirini valid-invalid bracket ile refine eder.

if last_valid == numel(Rcoarse) % Conditional analytic-cap'a en yakin coarse endpoint valid ise kontrol eder.
    Rmax_feasible = Rcoarse(end); % Feasible upper boundary'yi tested analytic/global cap olarak tanimlar.
    upper_valid_row = last_valid_row; % Boundary representative valid row olarak endpoint sonucunu kullanir.
    upper_fail_reason = ""; % Invalid-side bracket olmadigi icin failure reason'i bos birakir.
    if abs(Rhi_raw - cfg.domain.R_max) <= 5.0e-6 % Global R=0.60 cap analytic envelope'den daha aktifse kontrol eder.
        upper_status = "Global_R_cap_valid"; % Upper-bound status'u global domain cap olarak kaydeder.
    else % Analitik necessary constraint upper cap daha dusukse bu dali kullanir.
        upper_status = "Analytic_R_cap_valid"; % Upper-bound status'u analytic cap olarak kaydeder.
    end % Upper cap source secimini sonlandirir.
else % Secilen valid adanin ustunde invalid coarse probe varsa bu dali kullanir.
    Rval = Rcoarse(last_valid); % Upper bracket'in valid recovery ucunu alir.
    Rinv = Rcoarse(last_valid + 1); % Upper bracket'in invalid recovery ucunu alir.
    upper_valid_row = last_valid_row; % Mevcut en yuksek valid row'u baslatir.
    invalid_row = CoarseRows(last_valid + 1); % Boundary'nin invalid-side failure bilgisini alir.
    for ib = 1:cfg.envelope.n_bisection % Upper boundary bisection refinement dongusunu kurar.
        if Rinv - Rval <= cfg.envelope.R_boundary_tolerance % Recovery bracket yeterince daraldiysa kontrol eder.
            break; % Gereksiz truth-model cagrilarini onlemek icin refinement'i sonlandirir.
        end % Bracket-width termination kosulunu sonlandirir.
        Rmid = 0.5 * (Rval + Rinv); % Valid-invalid bracket'in orta recovery degerini hesaplar.
        [mid_row, ProbeRows, probe_counter] = evaluate_probe(State_ID, State_Type, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, Rmid, "UpperBisect", probe_counter, ProbeRows, cfg); % Midpoint'i FASTSEARCH ile cozer.
        if mid_row.DatasetValid % Midpoint feasible ise kontrol eder.
            Rval = Rmid; % Feasible lower bracket ucunu daha yuksek recovery'ye tasir.
            upper_valid_row = mid_row; % En yuksek yeni valid row'u boundary representative yapar.
        else % Midpoint infeasible ise bu dali kullanir.
            Rinv = Rmid; % Invalid upper bracket ucunu asagi tasir.
            invalid_row = mid_row; % En yakin invalid-side failure bilgisini gunceller.
        end % Upper bisection feasibility kararini sonlandirir.
    end % Upper boundary bisection dongusunu sonlandirir.
    Rmax_feasible = Rval; % Refined upper feasible recovery boundary degerini en yuksek valid bracket ucu olarak kaydeder.
    upper_fail_reason = string(invalid_row.FailureReason); % Boundary'nin invalid tarafindaki son failure reason'i kaydeder.
    upper_status = "Refined_valid_to_invalid"; % Upper-bound refinement status label'ini kaydeder.
end % Upper-bound branch'ini sonlandirir.

%% ENVELOPE OUTPUT % Refined feasible recovery bandini ve boundary representative operating points'i kaydeder.

env.HasFeasibleBand = Rmax_feasible >= Rmin_feasible - cfg.envelope.R_boundary_tolerance; % Refined band'in fiziksel olarak kapanmamis olup olmadigini kontrol eder.
env.Rmin_feasible = Rmin_feasible; % Refined minimum feasible recovery degerini kaydeder.
env.Rmax_feasible = Rmax_feasible; % Refined maximum feasible recovery degerini kaydeder.
env.FeasibleBandWidth = max(Rmax_feasible - Rmin_feasible, 0.0); % Feasible recovery-band genisligini hesaplar.
env.Rmin_lower_invalid_reason = lower_fail_reason; % Lower boundary invalid-side failure reason'ini kaydeder.
env.Rmax_upper_invalid_reason = upper_fail_reason; % Upper boundary invalid-side failure reason'ini kaydeder.
env.Rmin_status = lower_status; % Lower-bound mapping status label'ini kaydeder.
env.Rmax_status = upper_status; % Upper-bound mapping status label'ini kaydeder.
env.BoundaryStatus = "Mapped"; % State envelope mapping'in tamamlandigini kaydeder.
env.Rmin_P1_MPa = lower_valid_row.P1_opt_gauge_MPa; % Lower feasible boundary'deki optimum Stage-1 pressure degerini kaydeder.
env.Rmin_P2_MPa = lower_valid_row.P2_opt_gauge_MPa; % Lower feasible boundary'deki optimum Stage-2 pressure degerini kaydeder.
env.Rmin_Cp_mg_L = lower_valid_row.Cp_mg_L; % Lower feasible boundary'deki product salinity degerini kaydeder.
env.Rmin_W_kW = lower_valid_row.W_RO_train_kW; % Lower feasible boundary'deki train power degerini kaydeder.
env.Rmax_P1_MPa = upper_valid_row.P1_opt_gauge_MPa; % Upper feasible boundary'deki optimum Stage-1 pressure degerini kaydeder.
env.Rmax_P2_MPa = upper_valid_row.P2_opt_gauge_MPa; % Upper feasible boundary'deki optimum Stage-2 pressure degerini kaydeder.
env.Rmax_Cp_mg_L = upper_valid_row.Cp_mg_L; % Upper feasible boundary'deki product salinity degerini kaydeder.
env.Rmax_W_kW = upper_valid_row.W_RO_train_kW; % Upper feasible boundary'deki train power degerini kaydeder.
env.DominantFailureReason = dominant_failure_string(string({CoarseRows(~valid_mask).FailureReason}).'); % Coarse infeasible probe'lar arasindaki en sik failure reason'i kaydeder.
env.TotalProbeCount = probe_counter; % Coarse+bisection toplam optimizer probe sayisini kaydeder.
env.TotalValidProbeCount = sum([ProbeRows.DatasetValid]); % Tum probe logundaki valid optimizer sonuc sayisini kaydeder.
env.Runtime_s = toc(t_state); % Tek base-state toplam wall-clock runtime degerini kaydeder.
ProbeTable = struct2table(ProbeRows); % Tum detailed probe diagnostics struct array'ini table'a cevirir.

end % Tek-state recovery-envelope mapper fonksiyonunu sonlandirir.

function [row, ProbeRows, probe_counter] = evaluate_probe(State_ID, State_Type, Qf, T, Cf, R, Phase, probe_counter, ProbeRows, cfg) % Tek recovery target'i mevcut validated FASTSEARCH optimizer ile cozer ve compact probe log'a ekler.
probe_counter = probe_counter + 1; % State icindeki unique probe counter degerini bir arttirir.
DOE_ID = State_ID * 1000 + probe_counter; % Optimizer dataset row icin state/probe tabanli unique numeric ID olusturur.
row = ro_optimize_train_point_hybrid(DOE_ID, "Envelope_" + string(Phase), Qf, T, Cf, R, cfg); % v1.6.7 ile benchmark'i gecen optimizer'i hic degistirmeden cagirir.
p = probe_row_template(); % Compact probe diagnostic struct'ini olusturur.
p.State_ID = State_ID; % Parent state kimligini kaydeder.
p.State_Type = string(State_Type); % Parent state sampling stratum label'ini kaydeder.
p.Probe_Index = probe_counter; % State icindeki probe sirasini kaydeder.
p.Probe_Phase = string(Phase); % Coarse/lower-bisect/upper-bisect phase label'ini kaydeder.
p.R_target = R; % Requested recovery target degerini kaydeder.
p.DatasetValid = logical(row.DatasetValid); % Regression-validity flag degerini kaydeder.
p.PhysicalFeasible = logical(row.PhysicalFeasible); % Recovery haric fiziksel feasibility flag degerini kaydeder.
p.RecoveryTargetMet = logical(row.RecoveryTargetMet); % Recovery-target acceptance flag degerini kaydeder.
p.Recovery_actual = row.Recovery_actual; % Actual recovery degerini kaydeder.
p.Recovery_error = row.Recovery_error; % Recovery residual degerini kaydeder.
p.P1_MPa = row.P1_opt_gauge_MPa; % Optimum Stage-1 pressure degerini kaydeder.
p.P2_MPa = row.P2_opt_gauge_MPa; % Optimum Stage-2 pressure degerini kaydeder.
p.W_kW = row.W_RO_train_kW; % Train power degerini kaydeder.
p.Cp_mg_L = row.Cp_mg_L; % Product salinity degerini kaydeder.
p.dP1_MPa = row.dP_stage1_MPa; % Stage-1 pressure drop degerini kaydeder.
p.Jfirst1_LMH = row.Jfirst_stage1_LMH; % Stage-1 first-element flux degerini kaydeder.
p.ExitFlag = row.ExitFlag; % Optimizer exit flag degerini kaydeder.
p.Runtime_s = row.Runtime_s; % Tek optimizer probe runtime degerini kaydeder.
p.FailureReason = string(row.FailureReason); % Failure reason string'ini kaydeder.
ProbeRows(end + 1, 1) = p; % Probe diagnostic struct'ini log'un sonuna ekler.
end % Probe evaluation helper fonksiyonunu sonlandirir.

function [run_start, run_end, n_runs] = longest_true_run(mask) % Logical vector icindeki en uzun contiguous true run'in baslangic ve bitis indexlerini bulur.
mask = logical(mask(:)); % Input mask'i column logical vector haline getirir.
d = diff([false; mask; false]); % True-run baslangic ve bitislerini bulmak icin padded difference vectorunu hesaplar.
starts = find(d == 1); % Tum true-run baslangic indexlerini bulur.
ends = find(d == -1) - 1; % Tum true-run bitis indexlerini bulur.
n_runs = numel(starts); % Toplam valid ada sayisini hesaplar.
lengths = ends - starts + 1; % Her valid adanin coarse-grid uzunlugunu hesaplar.
[~, ibest] = max(lengths); % En uzun valid adanin indexini secer.
run_start = starts(ibest); % Secilen valid adanin baslangic indexini dondurur.
run_end = ends(ibest); % Secilen valid adanin bitis indexini dondurur.
end % Longest-run helper fonksiyonunu sonlandirir.

function s = dominant_failure_string(reasons) % Bos olmayan failure strings arasinda en sik gorulen nedeni dondurur.
reasons = string(reasons(:)); % Input neden listesini column string vector haline getirir.
reasons = reasons(strlength(reasons) > 0); % Bos failure reason kayitlarini analizden cikarir.
if isempty(reasons) % Kullanilabilir failure reason yoksa kontrol eder.
    s = ""; % Bos diagnostic string dondurur.
    return; % Helper fonksiyonundan cikar.
end % Empty-reasons kontrolunu sonlandirir.
[u, ~, ic] = unique(reasons); % Unique failure reason degerlerini ve group indexlerini hesaplar.
counts = accumarray(ic, 1); % Her unique failure reason'in frekansini hesaplar.
[~, imax] = max(counts); % En sik failure reason indexini bulur.
s = u(imax); % Dominant failure reason string'ini dondurur.
end % Dominant-failure helper fonksiyonunu sonlandirir.

function env = envelope_row_template() % State-level envelope output icin sabit field sirali struct template olusturur.
env = struct( ...
    'State_ID', NaN, ...
    'State_Type', "", ...
    'Qf_train_m3h', NaN, ...
    'T_RO_in_C', NaN, ...
    'Cf_kg_m3', NaN, ...
    'Rmax_analytic', NaN, ...
    'R_scan_low', NaN, ...
    'R_scan_high', NaN, ...
    'HasFeasibleBand', false, ...
    'Rmin_feasible', NaN, ...
    'Rmax_feasible', NaN, ...
    'FeasibleBandWidth', NaN, ...
    'Rmin_status', "", ...
    'Rmax_status', "", ...
    'Rmin_lower_invalid_reason', "", ...
    'Rmax_upper_invalid_reason', "", ...
    'Rmin_P1_MPa', NaN, ...
    'Rmin_P2_MPa', NaN, ...
    'Rmin_Cp_mg_L', NaN, ...
    'Rmin_W_kW', NaN, ...
    'Rmax_P1_MPa', NaN, ...
    'Rmax_P2_MPa', NaN, ...
    'Rmax_Cp_mg_L', NaN, ...
    'Rmax_W_kW', NaN, ...
    'CoarseProbeCount', 0, ...
    'CoarseValidCount', 0, ...
    'CoarseValidRuns', 0, ...
    'NonContiguousCoarse', false, ...
    'TotalProbeCount', 0, ...
    'TotalValidProbeCount', 0, ...
    'DominantFailureReason', "", ...
    'BoundaryStatus', "", ...
    'Runtime_s', NaN); % Envelope CSV'sinde tutulacak tum state-level fields'i tanimlar.
end % Envelope-row template helper fonksiyonunu sonlandirir.

function p = probe_row_template() % Her recovery optimizer cagrisi icin compact diagnostic struct template olusturur.
p = struct( ...
    'State_ID', NaN, ...
    'State_Type', "", ...
    'Probe_Index', NaN, ...
    'Probe_Phase', "", ...
    'R_target', NaN, ...
    'DatasetValid', false, ...
    'PhysicalFeasible', false, ...
    'RecoveryTargetMet', false, ...
    'Recovery_actual', NaN, ...
    'Recovery_error', NaN, ...
    'P1_MPa', NaN, ...
    'P2_MPa', NaN, ...
    'W_kW', NaN, ...
    'Cp_mg_L', NaN, ...
    'dP1_MPa', NaN, ...
    'Jfirst1_LMH', NaN, ...
    'ExitFlag', NaN, ...
    'Runtime_s', NaN, ...
    'FailureReason', ""); % Probe-level diagnostics kolonlarini sabit sirayla tanimlar.
end % Probe-row template helper fonksiyonunu sonlandirir.
