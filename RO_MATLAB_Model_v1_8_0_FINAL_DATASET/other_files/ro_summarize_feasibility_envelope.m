function Summary = ro_summarize_feasibility_envelope(Envelope, ProbeLog, prefix) % Recovery-envelope map sonucunu state types, boundaries, failures ve runtime acisindan ozetler.

%% GIRDI % Output prefix verilmediyse varsayilan dosya adini tanimlar.

if nargin < 3 || strlength(string(prefix)) == 0 % Prefix inputu bos mu kontrol eder.
    prefix = "RO_feasibility_envelope"; % Varsayilan report prefix'ini tanimlar.
else % Kullanici prefix verdiyse bu dali kullanir.
    prefix = string(prefix); % Dosya-adi birlestirmelerinde tutarli string tipini kullanir.
end % Prefix kontrolunu sonlandirir.

%% OVERALL METRICS % Feasible-band bulunma orani, recovery-range ve runtime metriklerini hesaplar.

n_states = height(Envelope); % Toplam base-state sayisini hesaplar.
feasible_mask = logical(Envelope.HasFeasibleBand); % Feasible recovery bandi bulunan state'leri logical mask olarak alir.
n_feasible = sum(feasible_mask); % Feasible-band bulunan state sayisini hesaplar.
Summary = table(); % Overall summary table'ini olusturur.
Summary.StateCount = n_states; % Toplam state sayisini kaydeder.
Summary.FeasibleBandCount = n_feasible; % Feasible-band state sayisini kaydeder.
Summary.FeasibleBandPct = 100.0 * n_feasible / max(n_states, 1); % Feasible-band yuzdesini hesaplar.
Summary.NonContiguousCoarseCount = sum(Envelope.NonContiguousCoarse); % Birden fazla coarse valid ada gorulen state sayisini kaydeder.
Summary.TotalOptimizerProbes = sum(Envelope.TotalProbeCount); % Tum state'lerde kullanilan optimizer probe sayisini toplar.
Summary.TotalRuntime_s = sum(Envelope.Runtime_s); % State runtime'larinin toplam CPU-like wall duration degerini toplar.
Summary.MeanStateRuntime_s = mean(Envelope.Runtime_s, 'omitnan'); % Ortalama base-state runtime degerini hesaplar.
Summary.MaxStateRuntime_s = max(Envelope.Runtime_s, [], 'omitnan'); % Maksimum base-state runtime degerini hesaplar.
if n_feasible > 0 % En az bir feasible state varsa recovery-band statistics hesaplar.
    Summary.RminObservedMin = min(Envelope.Rmin_feasible(feasible_mask)); % Gozlenen en dusuk feasible Rmin degerini kaydeder.
    Summary.RminObservedMax = max(Envelope.Rmin_feasible(feasible_mask)); % State'ler arasindaki en yuksek Rmin degerini kaydeder.
    Summary.RmaxObservedMin = min(Envelope.Rmax_feasible(feasible_mask)); % State'ler arasindaki en dusuk Rmax degerini kaydeder.
    Summary.RmaxObservedMax = max(Envelope.Rmax_feasible(feasible_mask)); % Gozlenen en yuksek feasible Rmax degerini kaydeder.
    Summary.MeanBandWidth = mean(Envelope.FeasibleBandWidth(feasible_mask), 'omitnan'); % Ortalama feasible recovery-band genisligini hesaplar.
else % Hic feasible state yoksa bu dali kullanir.
    Summary.RminObservedMin = NaN; % Recovery statistic'lerini NaN yapar.
    Summary.RminObservedMax = NaN; % Recovery statistic'lerini NaN yapar.
    Summary.RmaxObservedMin = NaN; % Recovery statistic'lerini NaN yapar.
    Summary.RmaxObservedMax = NaN; % Recovery statistic'lerini NaN yapar.
    Summary.MeanBandWidth = NaN; % Band-width statistic'ini NaN yapar.
end % Feasible-state statistics kosulunu sonlandirir.

%% TYPE SUMMARY % Sampling stratum bazinda feasible-band bulunma orani ve runtime ozetini hesaplar.

TypeSummary = groupsummary(Envelope, 'State_Type', {'sum','mean'}, {'HasFeasibleBand','Runtime_s'}); % State-type bazinda count, feasibility sum ve mean runtime hesaplar.
TypeSummary.FeasiblePct = 100.0 * TypeSummary.sum_HasFeasibleBand ./ TypeSummary.GroupCount; % Her state type icin feasible-band yuzdesini hesaplar.

%% BOUNDARY FAILURE SUMMARY % Lower ve upper boundary invalid-side failure nedenlerini ayri tablolar halinde sayar.

LowerReasons = Envelope.Rmin_lower_invalid_reason(feasible_mask); % Feasible state'lerin lower-bound invalid-side reasons degerlerini alir.
LowerReasons = LowerReasons(strlength(LowerReasons) > 0); % Global-floor-valid state'lerdeki bos reason kayitlarini cikarir.
if isempty(LowerReasons) % Lower boundary failure reason yoksa kontrol eder.
    LowerSummary = table(strings(0,1), zeros(0,1), 'VariableNames', {'FailureReason','Count'}); % Bos ama kolonlari sabit lower summary table olusturur.
else % En az bir lower failure reason varsa bu dali kullanir.
    LowerSummary = groupcounts(table(LowerReasons, 'VariableNames', {'FailureReason'}), 'FailureReason'); % Lower failure reasons frekanslarini hesaplar.
    LowerSummary.Properties.VariableNames{'GroupCount'} = 'Count'; % Frequency kolonunu okunabilir adla yeniden adlandirir.
    if ismember('Percent', LowerSummary.Properties.VariableNames) % MATLAB version'i Percent kolonu eklediyse kontrol eder.
        LowerSummary.Percent = []; % Sadece count raporlamak icin otomatik Percent kolonunu siler.
    end % Optional Percent kolon kontrolunu sonlandirir.
end % Lower-summary branch'ini sonlandirir.
UpperReasons = Envelope.Rmax_upper_invalid_reason(feasible_mask); % Feasible state'lerin upper-bound invalid-side reasons degerlerini alir.
UpperReasons = UpperReasons(strlength(UpperReasons) > 0); % Analytic/global-cap-valid state'lerdeki bos reason kayitlarini cikarir.
if isempty(UpperReasons) % Upper boundary failure reason yoksa kontrol eder.
    UpperSummary = table(strings(0,1), zeros(0,1), 'VariableNames', {'FailureReason','Count'}); % Bos ama kolonlari sabit upper summary table olusturur.
else % En az bir upper failure reason varsa bu dali kullanir.
    UpperSummary = groupcounts(table(UpperReasons, 'VariableNames', {'FailureReason'}), 'FailureReason'); % Upper failure reasons frekanslarini hesaplar.
    UpperSummary.Properties.VariableNames{'GroupCount'} = 'Count'; % Frequency kolonunu okunabilir adla yeniden adlandirir.
    if ismember('Percent', UpperSummary.Properties.VariableNames) % MATLAB version'i Percent kolonu eklediyse kontrol eder.
        UpperSummary.Percent = []; % Sadece count raporlamak icin otomatik Percent kolonunu siler.
    end % Optional Percent kolon kontrolunu sonlandirir.
end % Upper-summary branch'ini sonlandirir.

%% PROBE SUMMARY % Optimizer calls icinde validity, physical feasibility ve explicit root failures gibi diagnostics hesaplar.

ProbeSummary = table(); % Probe-level overall summary table'ini olusturur.
ProbeSummary.ProbeCount = height(ProbeLog); % Toplam optimizer probe sayisini kaydeder.
if height(ProbeLog) > 0 % Probe log bos degilse kontrol eder.
    ProbeSummary.ValidProbeCount = sum(ProbeLog.DatasetValid); % Valid optimizer probe sayisini hesaplar.
    ProbeSummary.PhysicalFeasibleProbeCount = sum(ProbeLog.PhysicalFeasible); % Physical feasible probe sayisini hesaplar.
    ProbeSummary.RecoveryTargetMetProbeCount = sum(ProbeLog.RecoveryTargetMet); % Recovery target met probe sayisini hesaplar.
    ProbeSummary.MeanProbeRuntime_s = mean(ProbeLog.Runtime_s, 'omitnan'); % Ortalama optimizer probe runtime degerini hesaplar.
    ProbeSummary.MaxProbeRuntime_s = max(ProbeLog.Runtime_s, [], 'omitnan'); % Maksimum optimizer probe runtime degerini hesaplar.
    ProbeSummary.RootFailureCount = sum(contains(ProbeLog.FailureReason, "Recovery_root_not_found")); % Explicit N30/N150 root failure probe sayisini hesaplar.
else % Probe log bos ise bu dali kullanir.
    ProbeSummary.ValidProbeCount = 0; % Valid probe sayisini sifir yapar.
    ProbeSummary.PhysicalFeasibleProbeCount = 0; % Physical feasible probe sayisini sifir yapar.
    ProbeSummary.RecoveryTargetMetProbeCount = 0; % Recovery target met probe sayisini sifir yapar.
    ProbeSummary.MeanProbeRuntime_s = NaN; % Mean runtime'i NaN yapar.
    ProbeSummary.MaxProbeRuntime_s = NaN; % Max runtime'i NaN yapar.
    ProbeSummary.RootFailureCount = 0; % Root failure sayisini sifir yapar.
end % Probe-summary branch'ini sonlandirir.

%% CSV OUTPUTS % Tum summary tablolarini ayri traceable CSV dosyalarina yazar.

writetable(Summary, prefix + "_overall_summary.csv"); % Overall envelope summary CSV dosyasini yazar.
writetable(TypeSummary, prefix + "_type_summary.csv"); % State-type summary CSV dosyasini yazar.
writetable(LowerSummary, prefix + "_lower_boundary_failures.csv"); % Lower-boundary failure summary CSV dosyasini yazar.
writetable(UpperSummary, prefix + "_upper_boundary_failures.csv"); % Upper-boundary failure summary CSV dosyasini yazar.
writetable(ProbeSummary, prefix + "_probe_summary.csv"); % Probe-level summary CSV dosyasini yazar.

%% COMMAND WINDOW % Kullaniciya training-domain kararinda gerekli ana metrikleri kompakt olarak yazdirir.

fprintf('\n============================================================\n'); % Summary baslangic ayiricisini yazdirir.
fprintf('FEASIBILITY ENVELOPE SUMMARY\n'); % Summary basligini yazdirir.
fprintf('============================================================\n'); % Baslik alt ayiricisini yazdirir.
fprintf('States mapped             : %d\n', n_states); % Toplam mapped state sayisini yazdirir.
fprintf('Feasible recovery band    : %d / %d (%.1f %%)\n', n_feasible, n_states, Summary.FeasibleBandPct); % Feasible-band bulunma oranini yazdirir.
fprintf('Non-contiguous coarse     : %d\n', Summary.NonContiguousCoarseCount); % Non-contiguous valid-island sayisini yazdirir.
fprintf('Total optimizer probes    : %d\n', Summary.TotalOptimizerProbes); % Toplam optimizer probe sayisini yazdirir.
fprintf('Mean / max state runtime  : %.2f / %.2f s\n', Summary.MeanStateRuntime_s, Summary.MaxStateRuntime_s); % State runtime statistics yazdirir.
if n_feasible > 0 % Feasible state varsa recovery ranges yazdirir.
    fprintf('Observed Rmin range        : %.4f - %.4f\n', Summary.RminObservedMin, Summary.RminObservedMax); % Gozlenen Rmin range'ini yazdirir.
    fprintf('Observed Rmax range        : %.4f - %.4f\n', Summary.RmaxObservedMin, Summary.RmaxObservedMax); % Gozlenen Rmax range'ini yazdirir.
    fprintf('Mean feasible band width  : %.4f\n', Summary.MeanBandWidth); % Ortalama recovery band genisligini yazdirir.
end % Recovery-range print kosulunu sonlandirir.
fprintf('Explicit root failures    : %d / %d probes\n', ProbeSummary.RootFailureCount, ProbeSummary.ProbeCount); % Root-failure diagnostic oranini yazdirir.
fprintf('\nValidity by state type:\n'); % Type-summary alt basligini yazdirir.
disp(TypeSummary(:, {'State_Type','GroupCount','sum_HasFeasibleBand','FeasiblePct','mean_Runtime_s'})); % State type bazli ana metrikleri gosterir.
fprintf('============================================================\n'); % Summary bitis ayiricisini yazdirir.

end % Feasibility-envelope summarizer fonksiyonunu sonlandirir.
