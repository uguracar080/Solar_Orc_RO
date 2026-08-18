function Summary = ro_summarize_feasibility_pilot(Dataset, output_stem) % Feasibility-aware pilot dataset icin validity, runtime, failure ve active-constraint ozetlerini olusturur.

%% GIRDI KONTROLU % Dataset ve output stem girdilerini kontrol eder.

if nargin < 2 || strlength(string(output_stem)) == 0 % Output stem verilmediyse kontrol eder.
    output_stem = 'RO_ANN_feasibility_pilot'; % Varsayilan ozet dosya stem degerini tanimlar.
end % Output-stem kontrolunu sonlandirir.
output_stem = char(output_stem); % File-name birlestirmeleri icin stem degerini char tipine cevirir.

if ~istable(Dataset) % Dataset inputunun MATLAB table olup olmadigini kontrol eder.
    error('Dataset bir MATLAB table olmali.'); % Yanlis input tipinde acik hata verir.
end % Dataset-type kontrolunu sonlandirir.

%% OVERALL METRICS % Pilotun temel validity, optimizer ve runtime gostergelerini hesaplar.

n_total = height(Dataset); % Toplam pilot sample sayisini alir.
n_valid = sum(Dataset.DatasetValid); % Regression surrogate icin valid sample sayisini hesaplar.
n_physical = sum(Dataset.PhysicalFeasible); % Recovery target haric physical feasible sample sayisini hesaplar.
n_recovery = sum(Dataset.RecoveryTargetMet); % Recovery target'i kabul toleransinda saglayan sample sayisini hesaplar.
n_analytic = sum(Dataset.AnalyticScreenPassed); % Analytic necessary-condition screen'ini gecen sample sayisini hesaplar.
mean_runtime = mean(Dataset.Runtime_s, 'omitnan'); % Ortalama tek-point runtime degerini hesaplar.
median_runtime = median(Dataset.Runtime_s, 'omitnan'); % Runtime outlier etkisini gormek icin median degeri hesaplar.
max_runtime = max(Dataset.Runtime_s, [], 'omitnan'); % En yavas operating point runtime degerini hesaplar.

valid_residual = abs(Dataset.Recovery_error(Dataset.DatasetValid)); % Yalnizca valid sample'larin absolute recovery residual degerlerini alir.
if isempty(valid_residual) % Hic valid sample yoksa kontrol eder.
    max_valid_recovery_error = NaN; % Recovery residual ozetini NaN yapar.
else % En az bir valid point varsa bu dali kullanir.
    max_valid_recovery_error = max(valid_residual); % Valid sample'larda maximum absolute recovery error degerini hesaplar.
end % Valid residual kosulunu sonlandirir.

Metric = ["Total_points"; "Valid_points"; "Valid_fraction_pct"; "Physical_feasible_points"; ...
    "Recovery_target_met_points"; "Analytic_screen_pass_points"; "Mean_runtime_s"; "Median_runtime_s"; ...
    "Max_runtime_s"; "Max_abs_recovery_error_valid"]; % Overall metric isimlerini olusturur.
Value = [n_total; n_valid; 100.0 * n_valid / max(n_total, 1); n_physical; n_recovery; n_analytic; ...
    mean_runtime; median_runtime; max_runtime; max_valid_recovery_error]; % Overall metric degerlerini ayni sirayla olusturur.
Overall = table(Metric, Value); % Overall ozet table object'ini olusturur.
writetable(Overall, [output_stem '_overall_summary.csv']); % Overall metrikleri CSV dosyasina kaydeder.

%% DOE-TYPE SUMMARY % Her sampling stratum'unun valid fraction ve runtime davranisini ayri raporlar.

Types = unique(string(Dataset.DOE_Type), 'stable'); % Dataset'te bulunan sampling source label'larini alir.
Type = strings(numel(Types), 1); % Type summary label vectorunu preallocate eder.
Count = zeros(numel(Types), 1); % Her stratum sample sayisini preallocate eder.
ValidCount = zeros(numel(Types), 1); % Her stratum valid sample sayisini preallocate eder.
ValidPct = zeros(numel(Types), 1); % Her stratum valid percentage vectorunu preallocate eder.
MeanRuntime_s = NaN(numel(Types), 1); % Her stratum average runtime vectorunu preallocate eder.
for k = 1:numel(Types) % Tum sampling strata uzerinde dongu kurar.
    mask = string(Dataset.DOE_Type) == Types(k); % Mevcut stratum satirlarini secer.
    Type(k) = Types(k); % Stratum label degerini kaydeder.
    Count(k) = sum(mask); % Stratum sample sayisini hesaplar.
    ValidCount(k) = sum(Dataset.DatasetValid(mask)); % Stratum valid sample sayisini hesaplar.
    ValidPct(k) = 100.0 * ValidCount(k) / max(Count(k), 1); % Stratum valid oranini hesaplar.
    MeanRuntime_s(k) = mean(Dataset.Runtime_s(mask), 'omitnan'); % Stratum average runtime degerini hesaplar.
end % DOE-type summary loop'unu sonlandirir.
TypeSummary = table(Type, Count, ValidCount, ValidPct, MeanRuntime_s); % DOE-type summary table object'ini olusturur.
writetable(TypeSummary, [output_stem '_type_summary.csv']); % Sampling stratum ozetini CSV dosyasina kaydeder.

%% FAILURE SUMMARY % Valid olmayan sample'larda failure reason kombinasyonlarini sikliga gore raporlar.

FailureText = string(Dataset.FailureReason(~Dataset.DatasetValid)); % Invalid sample'larin failure reason string'lerini alir.
if isempty(FailureText) % Tum sample'lar valid ise kontrol eder.
    FailureSummary = table(strings(0,1), zeros(0,1), 'VariableNames', {'FailureReason','Count'}); % Bos failure summary table olusturur.
else % En az bir invalid sample varsa bu dali kullanir.
    [uFailure, ~, ic] = unique(FailureText); % Unique failure strings ve group indexlerini hesaplar.
    fCount = accumarray(ic, 1); % Her failure combination icin sample sayisini hesaplar.
    FailureSummary = table(uFailure, fCount, 'VariableNames', {'FailureReason','Count'}); % Failure count table object'ini olusturur.
    FailureSummary = sortrows(FailureSummary, 'Count', 'descend'); % En sik failure reason'i en uste tasir.
end % Failure-summary kosulunu sonlandirir.
writetable(FailureSummary, [output_stem '_failure_summary.csv']); % Failure-reason ozetini CSV dosyasina kaydeder.

%% VALID OUTPUT RANGE % Regression surrogate icin gercek valid input-output zarfini raporlar.

if n_valid > 0 % En az bir valid sample varsa range tablosunu olusturur.
    Dv = Dataset(Dataset.DatasetValid, :); % Valid sample subset'ini alir.
    Variable = ["Qf_train_m3h"; "T_RO_in_C"; "Cf_kg_m3"; "R_target"; "Qp_train_m3h"; ...
        "W_RO_train_kW"; "Cp_mg_L"; "SEC_kWh_m3"; "P1_opt_gauge_MPa"; "P2_opt_gauge_MPa"]; % Raporlanacak ana input-output isimlerini tanimlar.
    Minimum = [min(Dv.Qf_train_m3h); min(Dv.T_RO_in_C); min(Dv.Cf_kg_m3); min(Dv.R_target); min(Dv.Qp_train_m3h); ...
        min(Dv.W_RO_train_kW); min(Dv.Cp_mg_L); min(Dv.SEC_kWh_m3); min(Dv.P1_opt_gauge_MPa); min(Dv.P2_opt_gauge_MPa)]; % Valid minimum degerlerini hesaplar.
    Maximum = [max(Dv.Qf_train_m3h); max(Dv.T_RO_in_C); max(Dv.Cf_kg_m3); max(Dv.R_target); max(Dv.Qp_train_m3h); ...
        max(Dv.W_RO_train_kW); max(Dv.Cp_mg_L); max(Dv.SEC_kWh_m3); max(Dv.P1_opt_gauge_MPa); max(Dv.P2_opt_gauge_MPa)]; % Valid maximum degerlerini hesaplar.
    ValidRange = table(Variable, Minimum, Maximum); % Valid-range table object'ini olusturur.
else % Hic valid sample yoksa bu dali kullanir.
    ValidRange = table(strings(0,1), zeros(0,1), zeros(0,1), 'VariableNames', {'Variable','Minimum','Maximum'}); % Bos valid-range table olusturur.
end % Valid-range kosulunu sonlandirir.
writetable(ValidRange, [output_stem '_valid_ranges.csv']); % Valid input-output ranges degerlerini CSV dosyasina kaydeder.

%% ACTIVE-CONSTRAINT INDICATORS % Valid cozumlerin hangi hard limitlere cok yakin oldugunu pilot diagnostic olarak sayar.

if n_valid > 0 % Active-constraint diagnostics icin valid sample olup olmadigini kontrol eder.
    Dv = Dataset(Dataset.DatasetValid, :); % Valid sample subset'ini alir.
    Constraint = ["Cp_near_500mgL"; "Javg_near_20LMH"; "Stage1_first_flux_near_35LMH"; ...
        "Stage2_first_flux_near_48LMH"; "Stage1_dP_near_0p35MPa"; "Stage2_dP_near_0p35MPa"; ...
        "Cb_near_90kgm3"; "P1_near_8p3MPa"; "P2_near_8p3MPa"]; % Active-limit indicator isimlerini tanimlar.
    ActiveCount = [sum(Dv.Cp_mg_L >= 499.0); sum(Dv.Javg_LMH >= 19.9); sum(Dv.Jfirst_stage1_LMH >= 34.8); ...
        sum(Dv.Jfirst_stage2_LMH >= 47.8); sum(Dv.dP_stage1_MPa >= 0.345); sum(Dv.dP_stage2_MPa >= 0.345); ...
        sum(Dv.Cb_max_kg_m3 >= 89.5); sum(Dv.P1_opt_gauge_MPa >= 8.25); sum(Dv.P2_opt_gauge_MPa >= 8.25)]; % Her hard-limit yakininda bulunan valid sample sayisini hesaplar.
    ActivePctOfValid = 100.0 * ActiveCount / n_valid; % Active constraint oranlarini valid sample sayisina normalize eder.
    ActiveSummary = table(Constraint, ActiveCount, ActivePctOfValid); % Active-constraint summary table object'ini olusturur.
else % Hic valid sample yoksa bu dali kullanir.
    ActiveSummary = table(strings(0,1), zeros(0,1), zeros(0,1), 'VariableNames', {'Constraint','ActiveCount','ActivePctOfValid'}); % Bos active summary table olusturur.
end % Active-constraint summary kosulunu sonlandirir.
writetable(ActiveSummary, [output_stem '_active_constraint_summary.csv']); % Active-limit diagnostics CSV dosyasini kaydeder.

%% COMMAND-WINDOW OZETI % Kullaniciya pilot sonrasi hemen karar verebilecegi temel metrikleri yazdirir.

fprintf('\n============================================================\n'); % Summary header ayiricisini yazdirir.
fprintf('FEASIBILITY-AWARE PILOT SUMMARY\n'); % Summary basligini yazdirir.
fprintf('============================================================\n'); % Summary header alt ayiricisini yazdirir.
fprintf('Valid                   : %d / %d (%.1f %%)\n', n_valid, n_total, 100.0 * n_valid / max(n_total,1)); % Overall valid fraction degerini yazdirir.
fprintf('Physical feasible       : %d / %d\n', n_physical, n_total); % Physical feasible sayisini yazdirir.
fprintf('Recovery target met     : %d / %d\n', n_recovery, n_total); % Recovery-target matched sayisini yazdirir.
fprintf('Analytic screen pass    : %d / %d\n', n_analytic, n_total); % Analytic screening pass sayisini yazdirir.
fprintf('Mean / median runtime   : %.2f / %.2f s\n', mean_runtime, median_runtime); % Runtime merkezi egilim degerlerini yazdirir.
fprintf('Max runtime             : %.2f s\n', max_runtime); % En yavas point runtime degerini yazdirir.
fprintf('Max |R error| valid     : %.3e\n', max_valid_recovery_error); % Valid recovery residual maximum degerini yazdirir.
fprintf('\nValidity by sampling stratum:\n'); % Type summary basligini yazdirir.
disp(TypeSummary); % DOE-type validity table degerini Command Window'da gosterir.
fprintf('Top failure reasons:\n'); % Failure summary basligini yazdirir.
disp(FailureSummary(1:min(10,height(FailureSummary)), :)); % En sik ilk on failure reason kombinasyonunu gosterir.

Summary = struct(); % Tum summary table'larini tek output struct icinde toplamak icin bos struct olusturur.
Summary.Overall = Overall; % Overall metrics table'ini output struct'a ekler.
Summary.Type = TypeSummary; % Sampling-type summary table'ini output struct'a ekler.
Summary.Failure = FailureSummary; % Failure summary table'ini output struct'a ekler.
Summary.ValidRange = ValidRange; % Valid range table'ini output struct'a ekler.
Summary.ActiveConstraint = ActiveSummary; % Active constraint summary table'ini output struct'a ekler.

end % Feasibility-aware pilot summary fonksiyonunu sonlandirir.
