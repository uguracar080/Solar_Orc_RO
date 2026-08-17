function Summary = ro_summarize_probe_guided_pilot(Dataset, DOE, prefix) % Probe-guided pilotun validity, proposal-score ve failure diagnostics ozetini MATLAB R2023b uyumlu olarak uretir.
% R2023b FIX v2: groupsummary kullanimi tamamen kaldirilmistir; stratum ve score-bin ozetleri manual hesaplanir.

%% GIRDI % Output prefix verilmemisse varsayilan degeri tanimlar.
if nargin < 3 || strlength(string(prefix)) == 0 % Prefix eksikse kontrol eder.
    prefix = "RO_ANN_probe_guided_pilot"; % Varsayilan summary file stem degerini tanimlar.
end % Prefix default kontrolunu sonlandirir.
prefix = string(prefix); % File naming icin prefix'i string tipine cevirir.

%% SATIR ESLESTIRME % Dataset ve DOE satirlarini DOE_ID ile guvenli bicimde eslestirir.
if ~ismember('DOE_ID', Dataset.Properties.VariableNames) || ~ismember('DOE_ID', DOE.Properties.VariableNames) % DOE_ID kolonlari yoksa kontrol eder.
    error('Dataset ve DOE tablolarinin ikisinde de DOE_ID kolonu bulunmalidir.'); % Acik schema hatasi verir.
end % DOE_ID kontrolunu sonlandirir.
[tf, loc] = ismember(Dataset.DOE_ID, DOE.DOE_ID); % Her Dataset satirinin DOE tablosundaki konumunu bulur.
if ~all(tf) % Dataset satirlarindan biri DOE ile eslesmediyse kontrol eder.
    error('Dataset icindeki bazi DOE_ID degerleri DOE tablosunda bulunamadi.'); % Data-consistency hatasi verir.
end % DOE-ID consistency kontrolunu sonlandirir.
DOEa = DOE(loc, :); % DOE satirlarini Dataset ile birebir ayni siraya dizer.

%% DOE DIAGNOSTICS % Proposal score ve nearest-prior distance kolonlarini alir.
required_doe = {'DOE_Type','ProposalFeasibilityScore','NearestPriorDistance'}; % Summary icin gerekli DOE kolonlarini tanimlar.
for k = 1:numel(required_doe) % Gerekli DOE kolonlarini gezer.
    if ~ismember(required_doe{k}, DOEa.Properties.VariableNames) % Kolon eksikse kontrol eder.
        error('DOE tablosunda gerekli kolon bulunamadi: %s', required_doe{k}); % Eksik kolon adini bildirir.
    end % Kolon-existence kontrolunu sonlandirir.
end % Gerekli DOE kolon loop'unu sonlandirir.
Score = double(DOEa.ProposalFeasibilityScore); % Her truth point icin pre-run kNN proposal score degerini alir.
Near = double(DOEa.NearestPriorDistance); % Her truth point icin nearest prior support distance degerini alir.
Type = string(DOEa.DOE_Type); % Sampling-stratum label vectorunu string olarak alir.
Valid = logical(Dataset.DatasetValid); % Regression-valid truth label vectorunu alir.
Physical = logical(Dataset.PhysicalFeasible); % Physical-feasibility truth flag vectorunu alir.
Rmet = logical(Dataset.RecoveryTargetMet); % Recovery target acceptance flag vectorunu alir.
Runtime = double(Dataset.Runtime_s); % Truth optimizer runtime vectorunu alir.

%% OVERALL SUMMARY % Sampling stratejisinin verimlilik ve optimizer saglamlik metriklerini hesaplar.
n = height(Dataset); % Toplam pilot point sayisini alir.
n_valid = sum(Valid); % Valid regression point sayisini hesaplar.
n_physical = sum(Physical); % Physical feasible point sayisini hesaplar.
n_rmet = sum(Rmet); % Recovery target'i tutan point sayisini hesaplar.
FailureText = string(Dataset.FailureReason); % Failure reason kolonunu string tipine cevirir.
FailureText(ismissing(FailureText)) = ""; % Missing failure reason'lari bos stringe cevirir.
root_fail = contains(FailureText, "Recovery_root_not_found"); % Explicit root-search failure satirlarini isaretler.
n_root_fail = sum(root_fail); % Explicit root failure sayisini hesaplar.
mean_runtime = mean(Runtime, 'omitnan'); % Mean truth optimizer runtime degerini hesaplar.
median_runtime = median(Runtime, 'omitnan'); % Median truth optimizer runtime degerini hesaplar.
max_runtime = max(Runtime, [], 'omitnan'); % Maximum truth optimizer runtime degerini hesaplar.
core_mask = Score >= 0.65; % Acceptance criterion icin high-confidence proposal region'ini tanimlar.
core_valid_pct = 100.0 * sum(Valid & core_mask) / max(sum(core_mask), 1); % High-confidence region truth precision degerini yuzde hesaplar.
overall_valid_pct = 100.0 * n_valid / max(n, 1); % Overall truth-valid fraction degerini yuzde hesaplar.
root_fail_pct = 100.0 * n_root_fail / max(n, 1); % Explicit root failure fraction degerini yuzde hesaplar.
mean_score_valid = NaN; % Valid score ortalamasi icin default tanimlar.
mean_score_invalid = NaN; % Invalid score ortalamasi icin default tanimlar.
if any(Valid) % En az bir valid point varsa kontrol eder.
    mean_score_valid = mean(Score(Valid), 'omitnan'); % Valid point proposal score ortalamasini hesaplar.
end % Valid score kontrolunu sonlandirir.
if any(~Valid) % En az bir invalid point varsa kontrol eder.
    mean_score_invalid = mean(Score(~Valid), 'omitnan'); % Invalid point proposal score ortalamasini hesaplar.
end % Invalid score kontrolunu sonlandirir.
PilotPass = overall_valid_pct >= 70.0 && core_valid_pct >= 75.0 && root_fail_pct <= 3.0; % Full DOE'ye gecis icin kabul kriterini uygular.
Summary = table(n, n_valid, overall_valid_pct, n_physical, n_rmet, mean_runtime, median_runtime, max_runtime, ...
    mean(Score, 'omitnan'), mean_score_valid, mean_score_invalid, core_valid_pct, n_root_fail, root_fail_pct, PilotPass); % Overall summary table'ini olusturur.
Summary.Properties.VariableNames = {'PointCount','ValidCount','ValidPct','PhysicalFeasibleCount','RecoveryTargetMetCount', ...
    'MeanRuntime_s','MedianRuntime_s','MaxRuntime_s','MeanProposalScore','MeanScoreValid','MeanScoreInvalid', ...
    'HighConfidenceValidPct','ExplicitRootFailureCount','ExplicitRootFailurePct','PilotPass'}; % Summary kolon isimlerini tanimlar.
writetable(Summary, prefix + "_overall_summary.csv"); % Overall summary CSV dosyasini yazar.

%% STRATUM SUMMARY % DOE_Type bazinda manual grouping yapar; groupsummary'nin version-dependent multi-method syntax'ini kullanmaz.
Types = unique(Type, 'stable'); % Sampling stratum label'larini ilk gorulme sirasinda alir.
nType = numel(Types); % Stratum sayisini hesaplar.
GroupCount = zeros(nType,1); % Her stratum point sayisi icin vektor ayirir.
ValidCount = zeros(nType,1); % Her stratum valid count icin vektor ayirir.
ValidPct = zeros(nType,1); % Her stratum valid yuzdesi icin vektor ayirir.
PhysicalFeasibleCount = zeros(nType,1); % Her stratum physical feasible count icin vektor ayirir.
RecoveryTargetMetCount = zeros(nType,1); % Her stratum recovery-target-met count icin vektor ayirir.
MeanProposalScore = NaN(nType,1); % Her stratum mean proposal score icin vektor ayirir.
MeanNearestPriorDistance = NaN(nType,1); % Her stratum mean nearest distance icin vektor ayirir.
MeanRuntime_s = NaN(nType,1); % Her stratum mean runtime icin vektor ayirir.
MaxRuntime_s = NaN(nType,1); % Her stratum max runtime icin vektor ayirir.
for i = 1:nType % Tum sampling strata'larini gezer.
    m = Type == Types(i); % Bu stratum'a ait satirlari isaretler.
    GroupCount(i) = sum(m); % Stratum point sayisini hesaplar.
    ValidCount(i) = sum(Valid(m)); % Stratum valid point sayisini hesaplar.
    ValidPct(i) = 100.0 * ValidCount(i) / max(GroupCount(i),1); % Stratum valid yuzdesini hesaplar.
    PhysicalFeasibleCount(i) = sum(Physical(m)); % Stratum physical feasible point sayisini hesaplar.
    RecoveryTargetMetCount(i) = sum(Rmet(m)); % Stratum recovery-target-met point sayisini hesaplar.
    MeanProposalScore(i) = mean(Score(m), 'omitnan'); % Stratum mean proposal score degerini hesaplar.
    MeanNearestPriorDistance(i) = mean(Near(m), 'omitnan'); % Stratum mean nearest-prior distance degerini hesaplar.
    MeanRuntime_s(i) = mean(Runtime(m), 'omitnan'); % Stratum mean runtime degerini hesaplar.
    MaxRuntime_s(i) = max(Runtime(m), [], 'omitnan'); % Stratum max runtime degerini hesaplar.
end % Stratum loop'unu sonlandirir.
TypeSummary = table(Types, GroupCount, ValidCount, ValidPct, PhysicalFeasibleCount, RecoveryTargetMetCount, ...
    MeanProposalScore, MeanNearestPriorDistance, MeanRuntime_s, MaxRuntime_s); % R2023b-uyumlu stratum summary table'ini olusturur.
TypeSummary.Properties.VariableNames{1} = 'DOE_Type'; % Ilk kolona acik stratum adini verir.
writetable(TypeSummary, prefix + "_type_summary.csv"); % Sampling-stratum summary CSV'sini yazar.

%% SCORE CALIBRATION % Proposal score bandlarinin gercek truth-valid precision degerlerini manual grouping ile olcer.
edges = [0.0, 0.50, 0.60, 0.70, 0.80, 0.90, 1.000001]; % Diagnostic proposal-score bin sinirlarini tanimlar.
labels = ["<0.50";"0.50-0.60";"0.60-0.70";"0.70-0.80";"0.80-0.90";">=0.90"]; % Score-bin okunabilir label'larini tanimlar.
nBin = numel(labels); % Score-bin sayisini alir.
BinCount = zeros(nBin,1); % Her score bin point sayisi icin vektor ayirir.
BinValidCount = zeros(nBin,1); % Her score bin valid count icin vektor ayirir.
BinValidPct = NaN(nBin,1); % Her score bin valid yuzdesi icin vektor ayirir.
BinMeanScore = NaN(nBin,1); % Her score bin mean score icin vektor ayirir.
BinMeanRuntime_s = NaN(nBin,1); % Her score bin mean runtime icin vektor ayirir.
for i = 1:nBin % Tum score bin'lerini gezer.
    m = Score >= edges(i) & Score < edges(i+1); % Bu score binine ait satirlari isaretler.
    BinCount(i) = sum(m); % Score bin point sayisini hesaplar.
    BinValidCount(i) = sum(Valid(m)); % Score bin valid point sayisini hesaplar.
    if BinCount(i) > 0 % Bin bos degilse kontrol eder.
        BinValidPct(i) = 100.0 * BinValidCount(i) / BinCount(i); % Bin truth-valid precision degerini hesaplar.
        BinMeanScore(i) = mean(Score(m), 'omitnan'); % Bin mean proposal score degerini hesaplar.
        BinMeanRuntime_s(i) = mean(Runtime(m), 'omitnan'); % Bin mean runtime degerini hesaplar.
    end % Nonempty-bin kontrolunu sonlandirir.
end % Score-bin loop'unu sonlandirir.
Calibration = table(labels, BinCount, BinValidCount, BinValidPct, BinMeanScore, BinMeanRuntime_s); % Score calibration table'ini olusturur.
Calibration.Properties.VariableNames = {'ScoreBin','GroupCount','ValidCount','ValidPct','MeanScore','MeanRuntime_s'}; % Calibration kolon isimlerini tanimlar.
writetable(Calibration, prefix + "_score_calibration.csv"); % Proposal-score calibration CSV dosyasini yazar.

%% FAILURE SUMMARY % En sik truth-model failure reason kombinasyonlarini sayar.
FailReasons = FailureText(~Valid); % Yalnizca invalid point'lerin failure reason stringlerini alir.
blank_fail = ismissing(FailReasons) | strlength(FailReasons) == 0; % Bos/missing failure reason satirlarini isaretler.
FailReasons(blank_fail) = "<blank>"; % Bos failure reason kayitlarini acik label ile degistirir.
if isempty(FailReasons) % Hic invalid point yoksa kontrol eder.
    FailureSummary = table(strings(0,1), zeros(0,1), 'VariableNames', {'FailureReason','Count'}); % Bos ama schema'li failure summary table olusturur.
else % Invalid point varsa bu dali kullanir.
    [u, ~, ic] = unique(FailReasons); % Unique failure reason kombinasyonlarini bulur.
    counts = accumarray(ic, 1); % Her unique reason icin frekans hesaplar.
    [counts, ord] = sort(counts, 'descend'); % Failure reason'lari azalan frekansa gore siralar.
    u = u(ord); % Reason stringlerini ayni siraya dizer.
    FailureSummary = table(u, counts, 'VariableNames', {'FailureReason','Count'}); % Failure summary table'ini olusturur.
end % Failure-summary branch'ini sonlandirir.
writetable(FailureSummary, prefix + "_failure_summary.csv"); % Failure summary CSV dosyasini yazar.

%% VALID RANGE SUMMARY % Performance ANN icin elde edilen feasible input/output coverage degerlerini yazar.
if any(Valid) % En az bir valid point varsa kontrol eder.
    Dv = Dataset(Valid, :); % Valid truth rows'u alir.
    ValidRanges = table(min(Dv.Qf_train_m3h), max(Dv.Qf_train_m3h), min(Dv.T_RO_in_C), max(Dv.T_RO_in_C), ...
        min(Dv.Cf_kg_m3), max(Dv.Cf_kg_m3), min(Dv.R_target), max(Dv.R_target), min(Dv.W_RO_train_kW), max(Dv.W_RO_train_kW), ...
        min(Dv.Cp_mg_L), max(Dv.Cp_mg_L), min(Dv.SEC_kWh_m3), max(Dv.SEC_kWh_m3)); % Valid input/output range row'unu olusturur.
    ValidRanges.Properties.VariableNames = {'Qf_min','Qf_max','T_min','T_max','Cf_min','Cf_max','R_min','R_max','W_min','W_max','Cp_min','Cp_max','SEC_min','SEC_max'}; % Range kolon isimlerini tanimlar.
else % Hic valid point yoksa bu dali kullanir.
    ValidRanges = table(); % Bos range table olusturur.
end % Valid-range branch'ini sonlandirir.
writetable(ValidRanges, prefix + "_valid_ranges.csv"); % Valid-range summary CSV dosyasini yazar.

%% COMMAND WINDOW % Karar vermek icin gerekli ozeti ekrana basar.
fprintf('\nPROBE-GUIDED PILOT SUMMARY\n'); % Summary basligini yazdirir.
fprintf('Valid                   : %d / %d (%.1f %%)\n', n_valid, n, overall_valid_pct); % Overall valid fraction'i yazdirir.
fprintf('Physical feasible       : %d / %d\n', n_physical, n); % Physical feasible count degerini yazdirir.
fprintf('Recovery target met     : %d / %d\n', n_rmet, n); % Recovery target-met count degerini yazdirir.
fprintf('High-conf valid rate    : %.1f %%\n', core_valid_pct); % Score>=0.65 bolgesinin truth precision degerini yazdirir.
fprintf('Mean/median runtime     : %.2f / %.2f s\n', mean_runtime, median_runtime); % Runtime central tendency metrics'i yazdirir.
fprintf('Max runtime             : %.2f s\n', max_runtime); % Maximum runtime degerini yazdirir.
fprintf('Explicit root failures  : %d / %d (%.1f %%)\n', n_root_fail, n, root_fail_pct); % Explicit root failure oranini yazdirir.
fprintf('Pilot pass              : %d\n', PilotPass); % Full DOE'ye gecis acceptance flag'ini yazdirir.
fprintf('\nValidity by sampling stratum:\n'); % Type summary basligini yazdirir.
disp(TypeSummary); % Sampling-stratum summary table'ini ekrana basar.
fprintf('\nProposal-score calibration:\n'); % Score calibration basligini yazdirir.
disp(Calibration); % Score-bin truth precision table'ini ekrana basar.
fprintf('\nTop failure reasons:\n'); % Failure summary basligini yazdirir.
disp(FailureSummary(1:min(10,height(FailureSummary)), :)); % En sik ilk 10 failure reason'i ekrana basar.

end % Probe-guided pilot summary fonksiyonunu sonlandirir.
