function Summary = ro_summarize_final_dataset(Dataset, DOE, output_stem) % Final truth dataset validity, split, stratum, score calibration ve failure diagnostics ozetlerini R2023b-compatible hesaplar.

%% GIRDI % Output stem varsayilanini tamamlar ve Dataset-DOE satir eslesmesini kontrol eder.
if nargin < 3 || strlength(string(output_stem)) == 0 % Output stem verilmemisse kontrol eder.
    output_stem = 'RO_ANN_final_truth_dataset'; % Varsayilan final dataset stem degerini tanimlar.
end % Output-stem default kontrolunu sonlandirir.
output_stem = char(output_stem); % File naming icin output stem'i char tipine cevirir.
if height(Dataset) ~= height(DOE) % Dataset ve DOE satir sayilari farkliysa kontrol eder.
    error('Dataset ve DOE satir sayilari eslesmiyor.'); % Yanlis join/summary riskini onler.
end % Row-count kontrolunu sonlandirir.
if any(Dataset.DOE_ID ~= DOE.DOE_ID) % DOE_ID sirasi eslesmiyorsa kontrol eder.
    error('Dataset ve DOE DOE_ID sirasi eslesmiyor.'); % Metadata'nin yanlis satira baglanmasini onler.
end % DOE-ID consistency kontrolunu sonlandirir.

%% MERGED ANALYSIS TABLE % Proposal metadata ve truth labels'i tek diagnostic tabloda birlestirir.
T = Dataset; % Truth dataset tablosunu analysis base table yapar.
T.DataSplit = string(DOE.DataSplit); % Preassigned train-validation-test label'larini ekler.
T.ProposalScore = DOE.ProposalFeasibilityScore; % Proposal feasibility score diagnostic kolonunu ekler.
T.NearestPriorDistance = DOE.NearestPriorDistance; % Proposal support distance diagnostic kolonunu ekler.

%% OVERALL SUMMARY % Final production run'un temel validity ve runtime metriklerini hesaplar.
n = height(T); % Toplam truth point sayisini alir.
nValid = sum(T.DatasetValid); % Performance regressor icin valid truth-point sayisini hesaplar.
nPhys = sum(T.PhysicalFeasible); % Physical hard constraints'i saglayan point sayisini hesaplar.
nR = sum(T.RecoveryTargetMet); % Recovery target'i kabul toleransinda saglayan point sayisini hesaplar.
rootFail = contains(string(T.FailureReason), 'Recovery_root_not_found'); % Explicit root failure satirlarini isaretler.
nRootFail = sum(rootFail); % Explicit root failure sayisini hesaplar.
Overall = table(n, nValid, 100*nValid/n, nPhys, nR, mean(T.Runtime_s,'omitnan'), median(T.Runtime_s,'omitnan'), max(T.Runtime_s,[],'omitnan'), nRootFail, 100*nRootFail/n); % Overall metrics table'ini olusturur.
Overall.Properties.VariableNames = {'TotalCount','ValidCount','ValidPct','PhysicalFeasibleCount','RecoveryTargetMetCount','MeanRuntime_s','MedianRuntime_s','MaxRuntime_s','RootFailureCount','RootFailurePct'}; % Overall kolon adlarini tanimlar.

%% STRATUM SUMMARY % groupsummary kullanmadan her DOE_Type icin count/valid/runtime metrics hesaplar.
TypeSummary = summarize_groups(string(T.DOE_Type), T); % Sampling-stratum bazli manual summary table'ini hesaplar.
SplitSummary = summarize_groups(string(T.DataSplit), T); % Train-validation-test bazli manual summary table'ini hesaplar.

%% SCORE CALIBRATION % Pilot ile ayni score bins uzerinde final truth-valid precision'ini manual hesaplar.
edges = [-Inf,0.50,0.60,0.70,0.80,0.90,Inf]; % Proposal-score calibration bin edge'lerini tanimlar.
labels = ["<0.50","0.50-0.60","0.60-0.70","0.70-0.80","0.80-0.90",">=0.90"]; % Score-bin display label'larini tanimlar.
ScoreBin = strings(n,1); % Her truth row icin bos score-bin label vectorunu preallocate eder.
for i = 1:numel(labels) % Tum score binlerini gezer.
    if i < numel(labels) % Son bin disindaki half-open araliklari uygular.
        mask = T.ProposalScore >= edges(i) & T.ProposalScore < edges(i+1); % Mevcut score bin mask'ini hesaplar.
    else % Son score bin icin bu dali kullanir.
        mask = T.ProposalScore >= edges(i) & T.ProposalScore <= edges(i+1); % >=0.90 final bin mask'ini hesaplar.
    end % Score-bin interval branch'ini sonlandirir.
    ScoreBin(mask) = labels(i); % Mevcut bin label'ini ilgili row'lara atar.
end % Score-bin assignment loop'unu sonlandirir.
Calibration = summarize_score_bins(ScoreBin, T, labels); % Score-bin truth-valid calibration tablosunu hesaplar.

%% FAILURE SUMMARY % Invalid rows icindeki failure-reason frekanslarini manual hesaplar.
invalidReason = string(T.FailureReason(~T.DatasetValid)); % Yalnizca invalid rows'un failure reason string'lerini alir.
invalidReason(strlength(strtrim(invalidReason)) == 0) = "<blank>"; % Bos failure reason satirlarini gorunur label ile degistirir.
if isempty(invalidReason) % Tum final points validse kontrol eder.
    FailureSummary = table(strings(0,1), zeros(0,1), 'VariableNames', {'FailureReason','Count'}); % Bos failure-summary table olusturur.
else % En az bir invalid row varsa bu dali kullanir.
    reasons = unique(invalidReason, 'stable'); % Unique failure reason label'larini alir.
    counts = zeros(numel(reasons),1); % Failure reason count vectorunu preallocate eder.
    for i = 1:numel(reasons) % Her unique failure reason'i gezer.
        counts(i) = sum(invalidReason == reasons(i)); % Mevcut failure reason frekansini hesaplar.
    end % Failure-count loop'unu sonlandirir.
    [counts, order] = sort(counts, 'descend'); % Failure reasons'i azalan count siralamasina dizer.
    reasons = reasons(order); % Reason label'larini ayni siralamaya uygular.
    FailureSummary = table(reasons, counts, 'VariableNames', {'FailureReason','Count'}); % Failure summary table'ini olusturur.
end % Failure-summary branch'ini sonlandirir.

%% VALID PERFORMANCE RANGES % Performance ANN'in fiilen kapsadigi valid input/output araliklarini raporlar.
V = T(T.DatasetValid, :); % Yalnizca valid truth rows'u secer.
if isempty(V) % Hic valid row yoksa kontrol eder.
    ValidRanges = table(); % Bos valid-range table olusturur.
else % En az bir valid row varsa bu dali kullanir.
    names = ["Qf_train_m3h","T_RO_in_C","Cf_kg_m3","R_target","Qp_train_m3h","W_RO_train_kW","Cp_mg_L","SEC_kWh_m3","P1_opt_gauge_MPa","P2_opt_gauge_MPa"]; % Raporlanacak numeric variable listini tanimlar.
    Variable = strings(numel(names),1); Min = NaN(numel(names),1); Max = NaN(numel(names),1); Mean = NaN(numel(names),1); % Valid-range table kolonlarini preallocate eder.
    for i = 1:numel(names) % Her rapor variable'ini gezer.
        Variable(i) = names(i); % Variable adini kaydeder.
        x = V.(char(names(i))); % Mevcut numeric valid-data vectorunu alir.
        Min(i) = min(x,[],'omitnan'); Max(i) = max(x,[],'omitnan'); Mean(i) = mean(x,'omitnan'); % Min/max/mean metrics degerlerini hesaplar.
    end % Valid-range loop'unu sonlandirir.
    ValidRanges = table(Variable, Min, Max, Mean); % Valid input/output range summary table'ini olusturur.
end % Valid-range branch'ini sonlandirir.

%% DOSYALAR % Final diagnostics tablolarini ayri CSV files olarak yazar.
writetable(Overall, [output_stem '_overall_summary.csv']); % Overall summary CSV'yi yazar.
writetable(TypeSummary, [output_stem '_type_summary.csv']); % Sampling-stratum summary CSV'yi yazar.
writetable(SplitSummary, [output_stem '_split_summary.csv']); % Train-validation-test summary CSV'yi yazar.
writetable(Calibration, [output_stem '_score_calibration.csv']); % Proposal-score calibration CSV'yi yazar.
writetable(FailureSummary, [output_stem '_failure_summary.csv']); % Failure reason summary CSV'yi yazar.
if ~isempty(ValidRanges), writetable(ValidRanges, [output_stem '_valid_ranges.csv']); end % Valid range summary mevcutsa CSV'ye yazar.

%% COMMAND-WINDOW RAPORU % Final truth production run'un karar vermek icin gerekli ozetini gosterir.
fprintf('\nFINAL GUIDED TRUTH DATASET SUMMARY\n'); % Summary header'ini yazdirir.
fprintf('Valid                   : %d / %d (%.1f %%)\n', nValid, n, 100*nValid/n); % Overall valid rate'i yazdirir.
fprintf('Physical feasible       : %d / %d\n', nPhys, n); % Physical-feasible count'u yazdirir.
fprintf('Recovery target met     : %d / %d\n', nR, n); % Recovery-target-met count'u yazdirir.
fprintf('Mean/median runtime     : %.2f / %.2f s\n', mean(T.Runtime_s,'omitnan'), median(T.Runtime_s,'omitnan')); % Runtime merkezi metrics degerlerini yazdirir.
fprintf('Max runtime             : %.2f s\n', max(T.Runtime_s,[],'omitnan')); % Max point runtime degerini yazdirir.
fprintf('Explicit root failures  : %d / %d (%.2f %%)\n', nRootFail, n, 100*nRootFail/n); % Explicit root failure oranini yazdirir.
fprintf('\nValidity by sampling stratum:\n'); disp(TypeSummary); % DOE-type validity summary'yi gosterir.
fprintf('\nValidity by preassigned split:\n'); disp(SplitSummary); % Train-validation-test truth validity dagilimini gosterir.
fprintf('\nProposal-score calibration:\n'); disp(Calibration); % Proposal score calibration tablosunu gosterir.
if ~isempty(FailureSummary) % En az bir invalid row varsa kontrol eder.
    fprintf('\nTop failure reasons:\n'); disp(FailureSummary(1:min(10,height(FailureSummary)),:)); % En sik ilk 10 failure reason'i gosterir.
end % Failure display kosulunu sonlandirir.

Summary = struct('Overall',Overall,'TypeSummary',TypeSummary,'SplitSummary',SplitSummary,'Calibration',Calibration,'FailureSummary',FailureSummary,'ValidRanges',ValidRanges); % Tum summary tablolarini tek struct halinde dondurur.

end % Final dataset summarizer fonksiyonunu sonlandirir.

function S = summarize_groups(Group, T) % DOE_Type veya DataSplit bazinda groupsummary kullanmadan manual metrics table olusturur.
Group = string(Group); % Group labels'i string tipine cevirir.
labels = unique(Group, 'stable'); % Unique group label'larini occurrence order ile alir.
GroupCount = zeros(numel(labels),1); ValidCount = zeros(numel(labels),1); ValidPct = NaN(numel(labels),1); PhysicalFeasibleCount = zeros(numel(labels),1); RecoveryTargetMetCount = zeros(numel(labels),1); MeanProposalScore = NaN(numel(labels),1); MeanNearestPriorDistance = NaN(numel(labels),1); MeanRuntime_s = NaN(numel(labels),1); MaxRuntime_s = NaN(numel(labels),1); % Summary kolonlarini preallocate eder.
for i = 1:numel(labels) % Her group label'ini gezer.
    m = Group == labels(i); % Mevcut group row mask'ini hesaplar.
    GroupCount(i) = sum(m); % Group row sayisini hesaplar.
    ValidCount(i) = sum(T.DatasetValid(m)); % Group valid row sayisini hesaplar.
    ValidPct(i) = 100 * ValidCount(i) / max(GroupCount(i),1); % Group valid percent degerini hesaplar.
    PhysicalFeasibleCount(i) = sum(T.PhysicalFeasible(m)); % Group physical-feasible row sayisini hesaplar.
    RecoveryTargetMetCount(i) = sum(T.RecoveryTargetMet(m)); % Group recovery-target-met row sayisini hesaplar.
    MeanProposalScore(i) = mean(T.ProposalScore(m),'omitnan'); % Group mean proposal score degerini hesaplar.
    MeanNearestPriorDistance(i) = mean(T.NearestPriorDistance(m),'omitnan'); % Group mean prior-support distance degerini hesaplar.
    MeanRuntime_s(i) = mean(T.Runtime_s(m),'omitnan'); % Group mean runtime degerini hesaplar.
    MaxRuntime_s(i) = max(T.Runtime_s(m),[],'omitnan'); % Group max runtime degerini hesaplar.
end % Manual group-summary loop'unu sonlandirir.
S = table(labels, GroupCount, ValidCount, ValidPct, PhysicalFeasibleCount, RecoveryTargetMetCount, MeanProposalScore, MeanNearestPriorDistance, MeanRuntime_s, MaxRuntime_s); % Group summary table'ini olusturur.
S.Properties.VariableNames{1} = 'Group'; % Generic first-column adini Group olarak tanimlar.
end % Manual group-summary helper fonksiyonunu sonlandirir.

function C = summarize_score_bins(ScoreBin, T, labels) % Fixed score bins icin manual calibration table olusturur.
GroupCount = zeros(numel(labels),1); ValidCount = zeros(numel(labels),1); ValidPct = NaN(numel(labels),1); MeanScore = NaN(numel(labels),1); MeanRuntime_s = NaN(numel(labels),1); % Calibration kolonlarini preallocate eder.
for i = 1:numel(labels) % Tum fixed score labels'ini gezer.
    m = ScoreBin == labels(i); % Mevcut score bin row mask'ini hesaplar.
    GroupCount(i) = sum(m); % Bin row sayisini hesaplar.
    ValidCount(i) = sum(T.DatasetValid(m)); % Bin valid row sayisini hesaplar.
    if GroupCount(i) > 0 % Bin bos degilse kontrol eder.
        ValidPct(i) = 100 * ValidCount(i) / GroupCount(i); % Truth-valid percent degerini hesaplar.
        MeanScore(i) = mean(T.ProposalScore(m),'omitnan'); % Bin mean proposal score degerini hesaplar.
        MeanRuntime_s(i) = mean(T.Runtime_s(m),'omitnan'); % Bin mean runtime degerini hesaplar.
    end % Nonempty-bin metrics kontrolunu sonlandirir.
end % Score calibration loop'unu sonlandirir.
C = table(labels(:), GroupCount, ValidCount, ValidPct, MeanScore, MeanRuntime_s); % Calibration table'ini olusturur.
C.Properties.VariableNames = {'ScoreBin','GroupCount','ValidCount','ValidPct','MeanScore','MeanRuntime_s'}; % Calibration kolon adlarini tanimlar.
end % Score calibration helper fonksiyonunu sonlandirir.
