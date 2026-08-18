function DOE = ro_generate_doe_final_guided(n_points, cfg, envelope_csv, probes_csv, pilot_csv) % Final ANN truth dataset icin probe+pilot guided, scalable maximin ve reproducible 4-D DOE olusturur.

%% GIRDI VE FINAL AYARLAR % Varsayilan dataset boyutu, config ve prior dosyalarini tamamlar.
if nargin < 1 || isempty(n_points) % Final truth point sayisi verilmemisse kontrol eder.
    n_points = cfg_or_default_final_n([]); % Default final dataset boyutunu helper ile alir.
end % Final-size default kontrolunu sonlandirir.
if nargin < 2 || isempty(cfg) % Configuration verilmemisse kontrol eder.
    cfg = ro_ann_config(); % Validated RO truth-model ve guided sampling config'ini yukler.
end % Config default kontrolunu sonlandirir.
if nargin < 3 || strlength(string(envelope_csv)) == 0 % Envelope CSV path'i verilmemisse kontrol eder.
    envelope_csv = 'RO_feasibility_envelope.csv'; % Varsayilan envelope dosya adini tanimlar.
end % Envelope-path default kontrolunu sonlandirir.
if nargin < 4 || strlength(string(probes_csv)) == 0 % Probe CSV path'i verilmemisse kontrol eder.
    probes_csv = 'RO_feasibility_envelope_probes.csv'; % Varsayilan probe-log dosya adini tanimlar.
end % Probe-path default kontrolunu sonlandirir.
if nargin < 5 || strlength(string(pilot_csv)) == 0 % Pilot CSV path'i verilmemisse kontrol eder.
    pilot_csv = 'RO_ANN_probe_guided_pilot.csv'; % Basarili guided pilotu additional proposal prior yapar.
end % Pilot-path default kontrolunu sonlandirir.
if exist('sobolset', 'file') ~= 2 % Sobol sequence fonksiyonu mevcut degilse kontrol eder.
    error('sobolset bulunamadi. Final DOE icin Statistics and Machine Learning Toolbox Sobol fonksiyonu gereklidir.'); % Tool availability hatasini bildirir.
end % Sobol availability kontrolunu sonlandirir.

%% FINAL CONFIG DEFAULTLARI % Eski config ile de calisabilmek icin final section eksikse local defaultlar tanimlar.
if ~isfield(cfg, 'final') % v1.8.0 final settings struct'i yoksa kontrol eder.
    cfg.final = struct(); % Bos final settings struct'i olusturur.
end % Final-settings struct kontrolunu sonlandirir.
if ~isfield(cfg.final, 'n_truth') || isempty(cfg.final.n_truth), cfg.final.n_truth = 2400; end % Default final truth dataset boyutunu tanimlar.
if ~isfield(cfg.final, 'candidate_pool_size') || isempty(cfg.final.candidate_pool_size), cfg.final.candidate_pool_size = 60000; end % Scalable maximin icin candidate pool boyutunu tanimlar.
if ~isfield(cfg.final, 'frac_lowT') || isempty(cfg.final.frac_lowT), cfg.final.frac_lowT = 200/2400; end % Low-T challenge fraction'ini tanimlar.
if ~isfield(cfg.final, 'frac_flow_edge') || isempty(cfg.final.frac_flow_edge), cfg.final.frac_flow_edge = 200/2400; end % Flow-edge challenge fraction'ini tanimlar.
if ~isfield(cfg.final, 'frac_score_boundary') || isempty(cfg.final.frac_score_boundary), cfg.final.frac_score_boundary = 400/2400; end % Score-boundary fraction'ini tanimlar.
if ~isfield(cfg.final, 'rng_seed') || isempty(cfg.final.rng_seed), cfg.final.rng_seed = 20260812; end % Reproducible candidate/split RNG seed'ini tanimlar.
if ~isfield(cfg.final, 'min_prior_distance') || isempty(cfg.final.min_prior_distance), cfg.final.min_prior_distance = 0.015; end % Near-duplicate prior noktalarini proposal'dan dislayan minimum normalized distance'i tanimlar.
if ~isfield(cfg.final, 'train_fraction') || isempty(cfg.final.train_fraction), cfg.final.train_fraction = 0.70; end % Train split fraction'ini tanimlar.
if ~isfield(cfg.final, 'validation_fraction') || isempty(cfg.final.validation_fraction), cfg.final.validation_fraction = 0.15; end % Validation split fraction'ini tanimlar.
if ~isfield(cfg.final, 'test_fraction') || isempty(cfg.final.test_fraction), cfg.final.test_fraction = 0.15; end % Blind test split fraction'ini tanimlar.

n_points = max(round(n_points), 400); % Final production DOE icin minimum 400 point zorunlu tutar.
rng(cfg.final.rng_seed, 'twister'); % Sobol scramble ve split assignment icin global RNG state'ini reproducible hale getirir.

%% PRIOR LABELS % 622 envelope probe ve varsa 120-point successful pilotu proposal evidence olarak birlestirir.
[PriorX, PriorY, PriorSource] = ro_build_guided_prior(envelope_csv, probes_csv, pilot_csv); % Final proposal prior input/label/source dizilerini olusturur.

%% STRATUM SAYILARI % 2400 point icin pilotta dogrulanan 1600/400/200/200 dagilimini genel n_points'e olcekler.
n_lowT = round(cfg.final.frac_lowT * n_points); % Low-temperature challenge point sayisini hesaplar.
n_flowEdge = round(cfg.final.frac_flow_edge * n_points); % Flow-edge challenge point sayisini hesaplar.
n_boundary = round(cfg.final.frac_score_boundary * n_points); % Score-boundary classifier enrichment point sayisini hesaplar.
n_core = n_points - n_lowT - n_flowEdge - n_boundary; % Kalan point'leri high-confidence performance core'a ayirir.

%% SOBOL CANDIDATE POOL % Pilot ile ayni fiziksel candidate domain'inde daha buyuk reproducible low-discrepancy havuz olusturur.
n_pool = max(round(cfg.final.candidate_pool_size), 20 * n_points); % Final selection icin en az 20 candidate/selected-point oranini korur.
p = sobolset(4, 'Skip', cfg.doe.skip + 65536, 'Leap', cfg.doe.leap); % Pilot sequence bolgesinden uzak final Sobol sequence baslangicini tanimlar.
p = scramble(p, cfg.doe.scramble_method); % Fixed RNG seed ile reproducible Owen-style scrambling uygular.
U = net(p, n_pool); % [0,1]^4 final candidate matrixini uretir.
Qf = cfg.guided.Qf_min_m3h + U(:, 1) * (cfg.guided.Qf_max_m3h - cfg.guided.Qf_min_m3h); % Feed-flow candidate degerlerini map eder.
T = cfg.guided.T_min_C + U(:, 2) * (cfg.guided.T_max_C - cfg.guided.T_min_C); % RO inlet-temperature candidate degerlerini map eder.
Cf = cfg.guided.Cf_min_kg_m3 + U(:, 3) * (cfg.guided.Cf_max_kg_m3 - cfg.guided.Cf_min_kg_m3); % Feed-concentration candidate degerlerini map eder.
R = NaN(n_pool, 1); % State-conditioned candidate recovery vectorunu preallocate eder.
RmaxA = NaN(n_pool, 1); % Analytic recovery upper cap diagnostic vectorunu preallocate eder.
CandidateUsable = false(n_pool, 1); % Necessary recovery span bulunan candidate state'leri isaretleyecek mask'i baslatir.
for i = 1:n_pool % Tum candidate Qf-T-Cf state'lerini gezer.
    sc = ro_analytic_screen_train_point(Qf(i), T(i), Cf(i), cfg.guided.R_candidate_floor, cfg); % Basinctan bagimsiz analytic recovery upper bound'i hesaplar.
    Rhi = min(cfg.domain.R_max, sc.Rmax_analytic) - cfg.guided.R_analytic_guard; % Analytic cap'in kucuk bir guard altindaki proposal upper recovery'sini tanimlar.
    Rlo = max(cfg.domain.R_min, cfg.guided.R_candidate_floor); % Pilot/envelope ile verimsiz oldugu gorulen recovery floor'unu proposal lower bound yapar.
    if isfinite(Rhi) && Rhi > Rlo + cfg.guided.R_min_span % Candidate state'te anlamli recovery span varsa kontrol eder.
        R(i) = Rlo + U(i, 4) * (Rhi - Rlo); % Dördüncü Sobol dimension'i state-conditioned recovery araligina map eder.
        RmaxA(i) = Rhi; % Candidate'in analytic guarded Rmax degerini kaydeder.
        CandidateUsable(i) = true; % Candidate'i proposal scoring icin uygun olarak isaretler.
    end % Necessary recovery span kontrolunu sonlandirir.
end % Candidate recovery mapping loop'unu sonlandirir.
CandidateX = [Qf, T, Cf, R]; % Candidate 4-D input matrixini olusturur.
CandidateX = CandidateX(CandidateUsable, :); % Recovery span'i olmayan candidate'lari cikartir.
RmaxA = RmaxA(CandidateUsable); % Analytic cap vectorunu ayni mask ile filtreler.

%% PROPOSAL SCORE % Prior truth labels uzerinden yalnızca sampling gate olarak kNN feasibility score hesaplar.
[Score, NearestDist] = ro_knn_probe_feasibility_score(CandidateX, PriorX, PriorY, cfg); % Candidate feasibility proposal score ve nearest-prior distance'larini hesaplar.
NormX = normalize_final(CandidateX, cfg); % Scalable maximin diversity icin candidate inputlarini normalize eder.
Selected = false(size(CandidateX, 1), 1); % Candidate tekrar secimini onleyen selected mask'i baslatir.
MinD2 = inf(size(CandidateX, 1), 1); % Secilmis sete minimum squared distance degerini incremental maximin icin baslatir.
SelectedIndex = zeros(0, 1); % Global selected candidate index listesini baslatir.
SelectedType = strings(0, 1); % Selected sampling-stratum label listesini baslatir.
base_support = NearestDist >= cfg.final.min_prior_distance & NearestDist <= cfg.guided.max_nearest_distance; % Asiri duplicate veya extrapolative candidate'lari ortak support mask'i ile eler.

%% LOW-T CHALLENGE % Annual operation'da kritik dusuk temperature feasibility/performance bolgesini bilincli olarak zenginlestirir.
mask = base_support & CandidateX(:, 2) <= cfg.guided.lowT_max_C & Score >= cfg.guided.challenge_score_min; % Low-T supported candidate mask'ini olusturur.
[idx, Selected, MinD2] = pick_diverse_fast(mask, n_lowT, Selected, MinD2, NormX, Score); % Incremental maximin ile low-T point'leri secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Selected low-T indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("LowTemperatureChallenge", numel(idx), 1)]; %#ok<AGROW> % Low-T stratum label'larini ekler.

%% FLOW-EDGE CHALLENGE % Train turndown ve high-flow hydraulic sinirlarina yakin noktalarla classifier/performance coverage'i korur.
flow_edge = CandidateX(:, 1) <= cfg.guided.Qf_low_edge_max_m3h | CandidateX(:, 1) >= cfg.guided.Qf_high_edge_min_m3h; % Low/high Qf edge candidate'larini tanimlar.
mask = base_support & flow_edge & Score >= cfg.guided.challenge_score_min; % Prior-supported flow-edge candidate mask'ini olusturur.
[idx, Selected, MinD2] = pick_diverse_fast(mask, n_flowEdge, Selected, MinD2, NormX, Score); % Incremental maximin ile flow-edge point'leri secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Flow-edge indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("FlowEdgeChallenge", numel(idx), 1)]; %#ok<AGROW> % Flow-edge stratum label'larini ekler.

%% SCORE-BOUNDARY ENRICHMENT % Feasibility classifier icin valid/invalid gecis bolgesini kontrollu bicimde ornekler.
mask = base_support & Score >= cfg.guided.boundary_score_low & Score < cfg.guided.core_score_min; % 0.50-0.65 proposal score bandini boundary pool yapar.
[idx, Selected, MinD2] = pick_diverse_fast(mask, n_boundary, Selected, MinD2, NormX, Score); % Boundary candidates arasindan 4-D maximin point'leri secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Boundary indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("ScoreBoundaryProbe", numel(idx), 1)]; %#ok<AGROW> % Boundary stratum label'larini ekler.

%% HIGH-CONFIDENCE CORE % Performance ANN icin pilotta %97.5 valid veren ana feasible interior'i space-filling olarak doldurur.
mask = base_support & Score >= cfg.guided.core_score_min; % High-confidence core candidate pool'unu tanimlar.
[idx, Selected, MinD2] = pick_diverse_fast(mask, n_core, Selected, MinD2, NormX, Score); % Core candidate'lari incremental maximin ile secer.
SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Core indexlerini global listeye ekler.
SelectedType = [SelectedType; repmat("HighConfidenceCore", numel(idx), 1)]; %#ok<AGROW> % Core stratum label'larini ekler.

%% FALLBACK % Bir stratum pool'u yetersizse kalan satirlari yeterli prior support'lu candidates ile tamamlar.
n_missing = n_points - numel(SelectedIndex); % Hedef final dataset boyutuna gore eksik point sayisini hesaplar.
if n_missing > 0 % Eksik point varsa kontrol eder.
    mask = base_support & Score >= cfg.guided.fallback_score_min; % Daha gevsek fakat hala prior-supported fallback pool'u tanimlar.
    [idx, Selected, MinD2] = pick_diverse_fast(mask, n_missing, Selected, MinD2, NormX, Score); % Kalan point'leri maximin fallback ile tamamlar.
    SelectedIndex = [SelectedIndex; idx]; %#ok<AGROW> % Fallback indexlerini global listeye ekler.
    SelectedType = [SelectedType; repmat("GuidedFallback", numel(idx), 1)]; %#ok<AGROW> % Fallback stratum label'larini ekler.
end % Fallback kosulunu sonlandirir.
if numel(SelectedIndex) < n_points % Candidate pool hedef point sayisini dolduramadiysa kontrol eder.
    error('Final guided candidate pool %d hedef noktayi dolduramadi; yalnizca %d point secildi.', n_points, numel(SelectedIndex)); % Sampling parameterlerinin yeniden ayarlanmasi gerektigini bildirir.
end % Final sample-count kontrolunu sonlandirir.

%% FINAL DOE TABLE % Truth-model run ve daha sonra ANN splitleri icin reproducible metadata kolonlarini olusturur.
SelectedIndex = SelectedIndex(1:n_points); % Selected index listesini hedef boyutuna kirpar.
SelectedType = SelectedType(1:n_points); % Type label listesini hedef boyutuna kirpar.
Xs = CandidateX(SelectedIndex, :); % Selected 4-D input matrixini alir.
Scores = Score(SelectedIndex); % Selected proposal-score vectorunu alir.
Dnear = NearestDist(SelectedIndex); % Selected nearest-prior distance vectorunu alir.
RmaxSel = RmaxA(SelectedIndex); % Selected analytic guarded Rmax vectorunu alir.
DOE_ID = (1:n_points).'; % Sequential DOE ID vectorunu olusturur.
DataSplit = assign_stratified_split(SelectedType, cfg.final.train_fraction, cfg.final.validation_fraction, cfg.final.test_fraction, cfg.final.rng_seed + 17); % DOE_Type icinde fixed 70/15/15 train-validation-test split atar.
DOE = table(DOE_ID, SelectedType, DataSplit, Xs(:, 1), Xs(:, 2), Xs(:, 3), Xs(:, 4), Scores, Dnear, RmaxSel); % Final truth DOE table'ini olusturur.
DOE.Properties.VariableNames = {'DOE_ID','DOE_Type','DataSplit','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'ProposalFeasibilityScore','NearestPriorDistance','Rmax_analytic_design'}; % Reproducible final DOE kolon adlarini tanimlar.

%% COMMAND-WINDOW OZETI % Pahali truth run'dan once final proposal coverage ve split dagilimini raporlar.
fprintf('Final guided DOE olusturuldu : %d point\n', height(DOE)); % Final selected point sayisini yazdirir.
fprintf('Prior labeled points         : %d | valid %d | invalid %d\n', numel(PriorY), sum(PriorY == 1), sum(PriorY == 0)); % Proposal prior class dagilimini yazdirir.
fprintf('Prior source envelope/pilot  : %d / %d\n', sum(PriorSource == "EnvelopeProbe"), sum(PriorSource == "GuidedPilot")); % Prior source katkilarini yazdirir.
fprintf('Candidate pool usable        : %d\n', size(CandidateX, 1)); % Analytic recovery span'i gecen candidate sayisini yazdirir.
fprintf('Proposal score range         : %.3f - %.3f\n', min(DOE.ProposalFeasibilityScore), max(DOE.ProposalFeasibilityScore)); % Selected proposal-score range'ini yazdirir.
fprintf('Nearest prior dist range     : %.3f - %.3f\n', min(DOE.NearestPriorDistance), max(DOE.NearestPriorDistance)); % Selected support-distance range'ini yazdirir.
disp(groupcounts(DOE, 'DOE_Type')); % Final sampling-stratum sayilarini R2023b-compatible groupcounts ile gosterir.
disp(groupcounts(DOE, 'DataSplit')); % Train-validation-test point sayilarini R2023b-compatible groupcounts ile gosterir.

end % Final guided DOE generator fonksiyonunu sonlandirir.

function n = cfg_or_default_final_n(cfg) % Config henuz yuklenmeden n_points default'u istenirse guvenli final boyutu dondurur.
if nargin >= 1 && isstruct(cfg) && isfield(cfg, 'final') && isfield(cfg.final, 'n_truth') % Kullanilabilir final config varsa kontrol eder.
    n = cfg.final.n_truth; % Config icindeki final truth size degerini dondurur.
else % Config yoksa bu dali kullanir.
    n = 2400; % Pilot sonrasi secilen default final truth dataset boyutunu dondurur.
end % Default-size branch'ini sonlandirir.
end % Helper fonksiyonunu sonlandirir.

function Xn = normalize_final(X, cfg) % Final maximin distance hesabinda dort input'u ayni dimensionless olcege getirir.
lb = double(cfg.guided.norm_lb(:).'); % Normalization lower reference vectorunu alir.
ub = double(cfg.guided.norm_ub(:).'); % Normalization upper reference vectorunu alir.
Xn = (double(X) - lb) ./ max(ub - lb, 1.0e-12); % Input matrixini dimension-wise normalize eder.
end % Final normalization helper fonksiyonunu sonlandirir.

function [idx, selected, minD2] = pick_diverse_fast(mask, n_pick, selected, minD2, Xn, score) % Buyuk candidate pool'da O(Nselected*Ncandidate) incremental maximin point secimi yapar.
idx = zeros(0, 1); % Bu stratum icin selected global candidate index listesini baslatir.
if n_pick <= 0 % Bu stratum icin point istenmiyorsa kontrol eder.
    return; % Secim yapmadan helper'dan cikar.
end % Zero-pick kontrolunu sonlandirir.
for k = 1:n_pick % Istenen point sayisi kadar greedy maximin iteration yapar.
    pool = find(mask & ~selected); % Henuz secilmemis uygun candidate indexlerini alir.
    if isempty(pool) % Uygun candidate pool tukendiyse kontrol eder.
        break; % Mevcut stratum secimini erken sonlandirir.
    end % Empty-pool kontrolunu sonlandirir.
    if ~any(selected) % Tum DOE'de henuz hic point secilmediyse kontrol eder.
        utility = score(pool); % Ilk point icin proposal score'u tek utility kriteri yapar.
    else % En az bir point daha once secildiyse bu dali kullanir.
        score_weight = 0.75 + 0.25 * score(pool); % Diversity'yi ana, proposal confidence'i ikincil yapan bounded score agirligini hesaplar.
        utility = sqrt(minD2(pool)) .* score_weight; % Selected sete minimum mesafe ve score destegini birlestirir.
    end % First-point utility branch'ini sonlandirir.
    [~, jbest] = max(utility); % En yuksek utility candidate'in pool-local indexini bulur.
    chosen = pool(jbest); % Secilen global candidate indexini alir.
    idx(end + 1, 1) = chosen; %#ok<AGROW> % Secilen candidate'i stratum index listesine ekler.
    selected(chosen) = true; % Candidate'i global selected mask'te isaretler.
    d2new = sum((Xn - Xn(chosen, :)).^2, 2); % Tum candidates'in yeni selected point'e squared distance'ini tek vectorized adimda hesaplar.
    minD2 = min(minD2, d2new); % Her candidate icin selected sete en yakin squared distance'i incremental gunceller.
    minD2(selected) = 0.0; % Secilmis point'lerin tekrar utility kazanmasini onlemek icin distance'larini sifirlar.
end % Greedy incremental maximin loop'unu sonlandirir.
end % Scalable maximin helper fonksiyonunu sonlandirir.

function Split = assign_stratified_split(Type, fTrain, fVal, fTest, seed) % Her DOE stratum icinde reproducible train-validation-test split olusturur.
if abs((fTrain + fVal + fTest) - 1.0) > 1.0e-9 % Split fractions toplami 1 degilse kontrol eder.
    error('Train/validation/test fractions toplami 1 olmalidir.'); % Yanlis split configuration'ini bildirir.
end % Split-fraction kontrolunu sonlandirir.
rng(seed, 'twister'); % Split assignment'i reproducible hale getirir.
Type = string(Type); % Sampling type vectorunu string tipine cevirir.
Split = strings(numel(Type), 1); % Her DOE row icin bos split label vectorunu preallocate eder.
types = unique(Type, 'stable'); % Mevcut sampling strata label'larini alir.
for i = 1:numel(types) % Her stratum'u ayri gezer.
    rows = find(Type == types(i)); % Mevcut stratum row indexlerini alir.
    rows = rows(randperm(numel(rows))); % Stratum icinde fixed-seed random permutation uygular.
    n = numel(rows); % Mevcut stratum row sayisini alir.
    nTrain = floor(fTrain * n); % Train row sayisini hesaplar.
    nVal = floor(fVal * n); % Validation row sayisini hesaplar.
    nTest = n - nTrain - nVal; % Kalan rowlari test splitine ayirir.
    Split(rows(1:nTrain)) = "Train"; % Ilk block'u train olarak etiketler.
    Split(rows(nTrain + (1:nVal))) = "Validation"; % Ikinci block'u validation olarak etiketler.
    Split(rows(nTrain + nVal + (1:nTest))) = "Test"; % Son block'u blind test olarak etiketler.
end % Stratum split loop'unu sonlandirir.
end % Stratified split helper fonksiyonunu sonlandirir.
