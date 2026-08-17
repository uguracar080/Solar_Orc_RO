function DOE = ro_generate_doe_probe_guided(n_points, cfg, envelope_csv, probes_csv) % v1.7.0 envelope/probe logunu kullanan fakat truth-model yerine gecmeyen adaptive proposal DOE olusturur.

%% GIRDI VE DOSYALAR % Varsayilan configuration, pilot boyutu ve prior artifact path'lerini tamamlar.
if nargin < 1 || isempty(n_points) % Pilot point sayisi verilmemisse kontrol eder.
    n_points = 120; % Hiz/diagnostic dengesi icin varsayilan pilot boyutunu 120 tanimlar.
end % Pilot-size default kontrolunu sonlandirir.
if nargin < 2 || isempty(cfg) % Configuration verilmemisse kontrol eder.
    cfg = ro_ann_config(); % Varsayilan RO/ANN configuration struct'ini yukler.
end % Config default kontrolunu sonlandirir.
if nargin < 3 || strlength(string(envelope_csv)) == 0 % Envelope CSV path'i verilmemisse kontrol eder.
    envelope_csv = 'RO_feasibility_envelope.csv'; % v1.7.0 final envelope file adini varsayilan yapar.
end % Envelope-path default kontrolunu sonlandirir.
if nargin < 4 || strlength(string(probes_csv)) == 0 % Probe CSV path'i verilmemisse kontrol eder.
    probes_csv = 'RO_feasibility_envelope_probes.csv'; % v1.7.0 final probe-log file adini varsayilan yapar.
end % Probe-path default kontrolunu sonlandirir.
if ~isfile(envelope_csv) || ~isfile(probes_csv) % Gerekli prior artifact'lardan biri yoksa kontrol eder.
    error('Probe-guided DOE icin %s ve %s dosyalari Current Folder icinde bulunmalidir.', envelope_csv, probes_csv); % Eksik prior dosya durumunda acik hata verir.
end % Prior-file existence kontrolunu sonlandirir.
if exist('sobolset', 'file') ~= 2 % Sobol generator fonksiyonu bulunmuyorsa kontrol eder.
    error('sobolset bulunamadi. Bu pipeline daha once kullandiginiz Sobol fonksiyonuna ihtiyac duyar.'); % Tool availability hatasini bildirir.
end % Sobol availability kontrolunu sonlandirir.

%% PRIOR PROBE DATASET % Probe log'daki State_ID degerlerini envelope state inputlariyla birlestirir.
Envelope = readtable(envelope_csv, 'TextType', 'string'); % State-level Qf-T-Cf ve mapped-band bilgilerini okur.
Probe = readtable(probes_csv, 'TextType', 'string'); % Tum recovery optimizer probe label'larini okur.
[tf, loc] = ismember(Probe.State_ID, Envelope.State_ID); % Her probe'un parent state row indexini bulur.
if ~all(tf) % Her probe icin parent state bulunamadiysa kontrol eder.
    error('Probe log icindeki bazi State_ID degerleri envelope CSV ile eslesmedi.'); % Data-consistency hatasini bildirir.
end % Parent-state mapping kontrolunu sonlandirir.
PriorX = [Envelope.Qf_train_m3h(loc), Envelope.T_RO_in_C(loc), Envelope.Cf_kg_m3(loc), Probe.R_target]; % Prior 4-D feasibility input matrixini olusturur.
PriorY = double(Probe.DatasetValid); % DatasetValid flag'lerini proposal classifier label'i olarak alir.
finite_prior = all(isfinite(PriorX), 2) & isfinite(PriorY); % Finite input/label satirlarini belirler.
PriorX = PriorX(finite_prior, :); % Nonfinite prior input satirlarini cikartir.
PriorY = PriorY(finite_prior); % Prior label vectorunu ayni mask ile filtreler.

%% PILOT STRATUM SAYILARI % Toplam 120 point'i high-confidence core ve boundary/challenge gruplarina boler.
n_points = max(round(n_points), 40); % Pilotun anlamli coverage saglamasi icin minimum 40 point zorunlu tutar.
n_lowT = round(cfg.guided.frac_lowT * n_points); % Dusuk-sicaklik challenge point sayisini hesaplar.
n_flowEdge = round(cfg.guided.frac_flow_edge * n_points); % Flow-edge challenge point sayisini hesaplar.
n_boundary = round(cfg.guided.frac_score_boundary * n_points); % Proposal-score boundary point sayisini hesaplar.
n_core = n_points - n_lowT - n_flowEdge - n_boundary; % Kalan point'leri high-confidence core grubuna ayirir.

%% SOBOL CANDIDATE POOL % Fiziksel olarak ilgili Qf-T-Cf araliginda genis candidate havuzu olusturur.
n_pool = max(round(cfg.guided.candidate_pool_size), 50 * n_points); % Candidate pool'u pilot boyutuna gore yeterince buyuk tutar.
p = sobolset(4, 'Skip', cfg.doe.skip, 'Leap', cfg.doe.leap); % Dört-boyutlu deterministic Sobol sequence'i olusturur.
p = scramble(p, cfg.doe.scramble_method); % Daha dengeli low-discrepancy coverage icin reproducible scrambling uygular.
U = net(p, n_pool); % [0,1]^4 icindeki Sobol candidate matrixini uretir.
Qf = cfg.guided.Qf_min_m3h + U(:, 1) * (cfg.guided.Qf_max_m3h - cfg.guided.Qf_min_m3h); % Candidate feed-flow degerlerini map eder.
T = cfg.guided.T_min_C + U(:, 2) * (cfg.guided.T_max_C - cfg.guided.T_min_C); % Candidate RO inlet temperature degerlerini map eder.
Cf = cfg.guided.Cf_min_kg_m3 + U(:, 3) * (cfg.guided.Cf_max_kg_m3 - cfg.guided.Cf_min_kg_m3); % Candidate feed concentration degerlerini map eder.
R = NaN(n_pool, 1); % Candidate recovery vectorunu preallocate eder.
RmaxA = NaN(n_pool, 1); % Her candidate state icin analytic recovery cap diagnostic vectorunu preallocate eder.
CandidateUsable = false(n_pool, 1); % Positive recovery span bulunan candidate'lari isaretleyecek mask'i baslatir.
for i = 1:n_pool % Tum Qf-T-Cf candidate state'lerini gezer.
    sc = ro_analytic_screen_train_point(Qf(i), T(i), Cf(i), cfg.guided.R_candidate_floor, cfg); % Basinctan bagimsiz necessary recovery upper cap'i hesaplar.
    Rhi = min(cfg.domain.R_max, sc.Rmax_analytic) - cfg.guided.R_analytic_guard; % Exact analytic cap'in biraz altinda proposal upper limit olusturur.
    Rlo = max(cfg.domain.R_min, cfg.guided.R_candidate_floor); % Envelope mappingden ogrendigimiz dusuk-recovery bolgesini candidate proposal'dan cikartir.
    if isfinite(Rhi) && Rhi > Rlo + cfg.guided.R_min_span % Candidate state'te anlamli necessary recovery span varsa kontrol eder.
        R(i) = Rlo + U(i, 4) * (Rhi - Rlo); % Sobol dorduncu boyutunu state-conditioned recovery span'ine map eder.
        RmaxA(i) = Rhi; % Kullanilan analytic upper cap degerini diagnostic olarak kaydeder.
        CandidateUsable(i) = true; % Candidate'i kNN scoring icin kullanilabilir olarak isaretler.
    end % Necessary span feasibility kosulunu sonlandirir.
end % Candidate recovery-map loop'unu sonlandirir.
CandidateX = [Qf, T, Cf, R]; % Tum candidate inputlarini 4-D matrix halinde birlestirir.
CandidateX = CandidateX(CandidateUsable, :); % Recovery span'i olmayan candidate state'leri cikartir.
RmaxA = RmaxA(CandidateUsable); % Analytic cap diagnostics vectorunu ayni mask ile filtreler.

%% PROPOSAL SCORE % 622-point prior probe log'unu yalnizca sampling verimliligini artiran kNN gate olarak kullanir.
[Score, NearestDist] = ro_knn_probe_feasibility_score(CandidateX, PriorX, PriorY, cfg); % Her candidate icin local prior-validity score ve nearest distance hesaplar.
NormX = normalize_guided(CandidateX, cfg); % Maximin diversity selection icin candidate 4-D inputlarini normalize eder.
Selected = false(size(CandidateX, 1), 1); % Daha once secilen candidate'lari tekrar kullanmamak icin logical mask baslatir.
SelectedIndex = zeros(0, 1); % Global selected candidate index listesini baslatir.
SelectedType = strings(0, 1); % Her selected candidate'in sampling stratum label listesini baslatir.

%% LOW-T CHALLENGE % Düşuk sicaklikta kNN'in hala feasible olabilecegini dusundugu noktalarla annual low-T sinirini test eder.
mask = CandidateX(:, 2) <= cfg.guided.lowT_max_C & Score >= cfg.guided.challenge_score_min & NearestDist <= cfg.guided.max_nearest_distance; % Low-T candidate pool mask'ini olusturur.
[idx, Selected] = pick_diverse(mask, n_lowT, Selected, NormX, Score); % Coverage'i koruyarak low-T point'leri secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Low-T selected indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("LowTemperatureChallenge", numel(idx), 1)]; %#ok<AGROW> % Low-T stratum label'larini ekler.

%% FLOW-EDGE CHALLENGE % Train turndown ve high-flow hydraulic sinirlarina yakin proposal noktalarini ayri olarak test eder.
flow_edge = CandidateX(:, 1) <= cfg.guided.Qf_low_edge_max_m3h | CandidateX(:, 1) >= cfg.guided.Qf_high_edge_min_m3h; % Low/high Qf edge candidate'larini isaretler.
mask = flow_edge & Score >= cfg.guided.challenge_score_min & NearestDist <= cfg.guided.max_nearest_distance; % Flow-edge icin yeterli prior support bulunan pool'u tanimlar.
[idx, Selected] = pick_diverse(mask, n_flowEdge, Selected, NormX, Score); % Diversity-aware flow-edge point secimi yapar.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Flow-edge selected indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("FlowEdgeChallenge", numel(idx), 1)]; %#ok<AGROW> % Flow-edge stratum label'larini ekler.

%% SCORE-BOUNDARY PROBES % Proposal gate'in en belirsiz fakat informative bolgesinden classifier enrichment noktalarini secer.
mask = Score >= cfg.guided.boundary_score_low & Score < cfg.guided.core_score_min & NearestDist <= cfg.guided.max_nearest_distance; % Orta confidence score bandini candidate pool olarak tanimlar.
[idx, Selected] = pick_diverse(mask, n_boundary, Selected, NormX, Score); % Boundary candidates arasindan 4-D space-filling point'leri secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Boundary selected indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("ScoreBoundaryProbe", numel(idx), 1)]; %#ok<AGROW> % Boundary stratum label'larini ekler.

%% HIGH-CONFIDENCE CORE % Performance regressor icin yuksek valid-rate beklenen ana interior noktalarini secer.
mask = Score >= cfg.guided.core_score_min & NearestDist <= cfg.guided.max_nearest_distance; % High-confidence candidate pool mask'ini olusturur.
[idx, Selected] = pick_diverse(mask, n_core, Selected, NormX, Score); % High-confidence pool'dan maximin coverage ile core point'leri secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Core selected indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("HighConfidenceCore", numel(idx), 1)]; %#ok<AGROW> % Core stratum label'larini ekler.

%% EKSIK SAYI FALLBACK % Herhangi bir challenge pool yetersiz kaldiysa kalan pilot satirlarini en iyi destekli secilmemis candidate'lardan tamamlar.
n_missing = n_points - numel(SelectedIndex); % Hedef pilot boyutuna gore eksik selected point sayisini hesaplar.
if n_missing > 0 % En az bir point eksikse kontrol eder.
    mask = Score >= cfg.guided.fallback_score_min & NearestDist <= cfg.guided.max_nearest_distance; % Daha gevsek fakat hala prior-supported fallback pool'u tanimlar.
    [idx, Selected] = pick_diverse(mask, n_missing, Selected, NormX, Score); % Eksik point'leri diversity-aware fallback ile tamamlar.
    SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Fallback selected indexlerini global listeye ekler.
    SelectedType = [SelectedType; repmat("GuidedFallback", numel(idx), 1)]; %#ok<AGROW> % Fallback stratum label'larini ekler.
end % Missing-point fallback kosulunu sonlandirir.
if numel(SelectedIndex) < n_points % Hala yeterli candidate secilemediyse kontrol eder.
    error('Probe-guided candidate pool %d hedef noktayi dolduramadi; yalnizca %d point secildi.', n_points, numel(SelectedIndex)); % Parametrelerin asiri dar oldugunu bildirir.
end % Final sample-count kontrolunu sonlandirir.

%% FINAL DOE TABLE % Truth-model generator'a verilecek inputs ve proposal diagnostics kolonlarini olusturur.
SelectedIndex = SelectedIndex(1:n_points); % Her ihtimale karsi selected index listesini tam hedef boyutuna kirpar.
SelectedType = SelectedType(1:n_points); % Type label listesini ayni hedef boyutuna kirpar.
Xs = CandidateX(SelectedIndex, :); % Secilen 4-D candidate input matrixini alir.
Scores = Score(SelectedIndex); % Secilen candidate proposal score degerlerini alir.
Dnear = NearestDist(SelectedIndex); % Secilen candidate nearest-prior distance degerlerini alir.
RmaxSel = RmaxA(SelectedIndex); % Secilen candidate analytic recovery cap degerlerini alir.
DOE_ID = (1:n_points).'; % Truth-dataset generator icin sequential unique DOE ID olusturur.
DOE = table(DOE_ID, SelectedType, Xs(:, 1), Xs(:, 2), Xs(:, 3), Xs(:, 4), Scores, Dnear, RmaxSel); % Final proposal-guided DOE table'ini olusturur.
DOE.Properties.VariableNames = {'DOE_ID','DOE_Type','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'ProposalFeasibilityScore','NearestPriorDistance','Rmax_analytic_design'}; % Acik ve reproducible kolon isimlerini tanimlar.

%% COMMAND-WINDOW OZETI % Truth run baslamadan once proposal distribution'i kullaniciya raporlar.
fprintf('Probe-guided DOE olusturuldu : %d point\n', height(DOE)); % Final DOE boyutunu yazdirir.
fprintf('Prior labeled probes          : %d\n', numel(PriorY)); % kNN proposal gate'in dayandigi prior label sayisini yazdirir.
fprintf('Candidate pool usable         : %d\n', size(CandidateX, 1)); % Necessary analytic span'i gecen candidate sayisini yazdirir.
fprintf('Proposal score range          : %.3f - %.3f\n', min(DOE.ProposalFeasibilityScore), max(DOE.ProposalFeasibilityScore)); % Selected score range'ini yazdirir.
fprintf('Nearest prior dist range      : %.3f - %.3f\n', min(DOE.NearestPriorDistance), max(DOE.NearestPriorDistance)); % Selected interpolation-support distance range'ini yazdirir.
disp(groupcounts(DOE, 'DOE_Type')); % Sampling stratum point sayilarini MATLAB R2023b ile uyumlu GroupCount tablosu halinde gosterir.

end % Probe-guided DOE generator fonksiyonunu sonlandirir.

function Xn = normalize_guided(X, cfg) % Diversity selection icin ayni 4-D normalization olcegini uygular.
lb = double(cfg.guided.norm_lb(:).'); % Normalization lower-bound vectorunu alir.
ub = double(cfg.guided.norm_ub(:).'); % Normalization upper-bound vectorunu alir.
Xn = (double(X) - lb) ./ max(ub - lb, 1.0e-12); % Input matrixini dimension-wise normalize eder.
end % Normalization helper fonksiyonunu sonlandirir.

function [idx, selected] = pick_diverse(mask, n_pick, selected, Xn, score) % Belirli candidate mask icinden score destekli greedy maximin point secimi yapar.
idx = zeros(0, 1); % Secilecek global candidate index listesini bos baslatir.
if n_pick <= 0 % Bu stratum icin point istenmiyorsa kontrol eder.
    return; % Secim yapmadan helper'dan cikar.
end % Zero-pick kontrolunu sonlandirir.
pool = find(mask & ~selected); % Daha once kullanilmamis uygun candidate indexlerini alir.
if isempty(pool) % Uygun candidate yoksa kontrol eder.
    return; % Bos secimle helper'dan cikar.
end % Empty-pool kontrolunu sonlandirir.
n_pick = min(n_pick, numel(pool)); % Pool sayisini asmayan point sayisini belirler.
selected_global = find(selected); % Onceki strata'lardan secilen global point indexlerini alir.
if isempty(selected_global) % Henuz hic point secilmemisse kontrol eder.
    [~, j0] = max(score(pool)); % Ilk point olarak proposal score'u en yuksek candidate'i secer.
    chosen = pool(j0); % Global candidate indexini alir.
    idx(end + 1, 1) = chosen; %#ok<AGROW> % Ilk selected point'i local listeye ekler.
    selected(chosen) = true; % Global selected mask'i gunceller.
else % Daha once secilmis point varsa bu dali kullanir.
    chosen = []; % Bu stratum icin local chosen list'i bos baslatir.
end % Initial-point branch'ini sonlandirir.
while numel(idx) < n_pick % Hedef stratum point sayisina ulasana kadar greedy secim yapar.
    pool = find(mask & ~selected); % Her iteration'da kalan uygun candidate pool'unu gunceller.
    if isempty(pool) % Pool tukendiyse kontrol eder.
        break; % Secim loop'unu sonlandirir.
    end % Pool exhaustion kontrolunu sonlandirir.
    refs = find(selected); % Su ana kadar tum strata'larda secilmis reference point'leri alir.
    minD2 = inf(numel(pool), 1); % Her pool candidate icin selected-set'e minimum squared distance vectorunu baslatir.
    for j = 1:numel(refs) % Selected reference point'leri gezer.
        d2 = sum((Xn(pool, :) - Xn(refs(j), :)).^2, 2); % Pool candidate'larin bu reference'a squared distance'ini hesaplar.
        minD2 = min(minD2, d2); % En yakin selected reference distance'ini gunceller.
    end % Reference-distance loop'unu sonlandirir.
    local_score = score(pool); % Pool candidate proposal scores degerlerini alir.
    score_weight = 0.75 + 0.25 * local_score; % Diversity'yi ana kriter, score'u ikincil kriter yapan bounded agirlik olusturur.
    utility = sqrt(minD2) .* score_weight; % Maximin distance ve proposal support'u birlestiren utility degerini hesaplar.
    [~, jbest] = max(utility); % En yuksek utility candidate'i secer.
    chosen = pool(jbest); % Secilen global candidate indexini alir.
    idx(end + 1, 1) = chosen; %#ok<AGROW> % Local selected index listesine ekler.
    selected(chosen) = true; % Global selected mask'te candidate'i kullanilmis olarak isaretler.
end % Greedy maximin loop'unu sonlandirir.
end % Diversity-aware selection helper fonksiyonunu sonlandirir.
