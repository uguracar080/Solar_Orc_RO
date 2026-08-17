function DOE = ro_generate_doe_feasibility_aware(n_points, cfg) % FASTSEARCH icin 4-D feasibility-aware Sobol pilot DOE olusturur.

%% GIRDI VE TOOLBOX KONTROLU % Pilot boyutunu ve Sobol fonksiyonunun kullanilabilirligini kontrol eder.

if nargin < 2 || isempty(cfg) % Configuration struct verilmediyse kontrol eder.
    cfg = ro_ann_config(); % Varsayilan ANN/RO configuration degerlerini yukler.
end % Configuration input kontrolunu sonlandirir.

n_points = max(round(n_points), cfg.doe.feas_n_known_anchors + 20); % Anchor'lara ek olarak anlamli sayida generated nokta kalmasini saglar.
if exist('sobolset', 'file') ~= 2 % Statistics and Machine Learning Toolbox Sobol fonksiyonunu kontrol eder.
    error('sobolset bulunamadi. Statistics and Machine Learning Toolbox kurulumunu/path durumunu kontrol edin.'); % Belirsiz random fallback yerine acik hata verir.
end % Sobol availability kontrolunu sonlandirir.

%% NOKTA SAYILARI % Pilot sample'larini core, low-R, outer-Qf, upper-R ve known-anchor katmanlarina ayirir.

n_anchor = min(cfg.doe.feas_n_known_anchors, 6); % Mevcut pakette tanimli alti known-feasible anchor'dan kullanilacak sayiyi belirler.
n_generated = n_points - n_anchor; % Sobol ile uretilecek toplam generated sample sayisini hesaplar.
n_core = round(cfg.doe.feas_core_fraction * n_generated); % Core feasibility bandi sample sayisini hesaplar.
n_lowR = round(cfg.doe.feas_lowR_fraction * n_generated); % Dusuk-recovery probe sample sayisini hesaplar.
n_outerQ = round(cfg.doe.feas_outerQ_fraction * n_generated); % Outer-Qf probe sample sayisini hesaplar.
n_upperR = n_generated - n_core - n_lowR - n_outerQ; % Kalan generated noktalarini upper-recovery boundary probe'a ayirir.

if min([n_core, n_lowR, n_outerQ, n_upperR]) < 1 % Her sampling katmaninda en az bir nokta olup olmadigini kontrol eder.
    error('Feasibility-aware DOE point sayisi secilen sampling fractions icin cok kucuk.'); % Anlamsiz stratification durumunda acik hata verir.
end % Stratum-size kontrolunu sonlandirir.

%% SCRAMBLED SOBOL % Qf, T, Cf ve conditional-recovery koordinatlari icin reproducible low-discrepancy unit-cube sample uretir.

p = sobolset(4, 'Skip', cfg.doe.skip, 'Leap', cfg.doe.leap); % Dört boyutlu Sobol sequence object'ini olusturur.
p = scramble(p, cfg.doe.scramble_method); % Matousek-Affine-Owen scrambling ile sequence artefact riskini azaltir.
U = net(p, n_generated); % Tum generated pilot noktalarinin unit-cube coordinates degerlerini uretir.

Qf = NaN(n_generated, 1); % Generated feed-flow vectorunu preallocate eder.
T = NaN(n_generated, 1); % Generated inlet-temperature vectorunu preallocate eder.
Cf = NaN(n_generated, 1); % Generated feed-concentration vectorunu preallocate eder.
Rtarget = NaN(n_generated, 1); % Generated recovery-target vectorunu preallocate eder.
RmaxAnalyticDesign = NaN(n_generated, 1); % Sampling sirasinda hesaplanan necessary recovery upper envelope vectorunu preallocate eder.
Rfraction = NaN(n_generated, 1); % Her noktanin conditional recovery span icindeki normalize konumunu kaydetmek icin vector olusturur.
DOE_Type = strings(n_generated, 1); % Sampling stratum label vectorunu olusturur.

%% ORTAK T VE Cf MAP % Tum generated sample'larda seawater/preheat temperature ve salinity domain'lerini tam olarak kapsar.

T(:) = cfg.domain.T_min_C + U(:, 2) * (cfg.domain.T_max_C - cfg.domain.T_min_C); % Temperature samples degerlerini tum 15-45 C domain'ine map eder.
Cf(:) = cfg.domain.Cf_min_kg_m3 + U(:, 3) * (cfg.domain.Cf_max_kg_m3 - cfg.domain.Cf_min_kg_m3); % Feed concentration samples degerlerini tum CMEMS-derived domain'e map eder.

%% CORE STRATUM % Eski pilotta feasible sinyal bulunan ancak final hard domain olmayan 47-64 m3/h bandinda conditional recovery sample uretir.

idx_core = 1:n_core; % Core stratum row indexlerini tanimlar.
Qf(idx_core) = cfg.doe.feas_Qf_core_min_m3h + U(idx_core, 1) * ...
    (cfg.doe.feas_Qf_core_max_m3h - cfg.doe.feas_Qf_core_min_m3h); % Core Qf degerlerini low-discrepancy olarak map eder.
DOE_Type(idx_core) = "CoreConditional"; % Core sample label'ini kaydeder.

%% LOW-RECOVERY STRATUM % R=0.34-0.42 bandinin gercekten infeasible olup olmadigini yeni robust optimizer ile yeniden probe eder.

idx_lowR = n_core + (1:n_lowR); % Low-recovery stratum row indexlerini tanimlar.
Qf(idx_lowR) = cfg.doe.feas_Qf_core_min_m3h + U(idx_lowR, 1) * ...
    (cfg.doe.feas_Qf_core_max_m3h - cfg.doe.feas_Qf_core_min_m3h); % Dusuk-recovery probe'u core Qf bandinda yapar.
DOE_Type(idx_lowR) = "LowRecoveryProbe"; % Dusuk-recovery sample label'ini kaydeder.

%% OUTER-Qf STRATUM % Turndown ve yuksek-flow feasibility boundary'lerini kaybetmemek icin core band disini bilerek probe eder.

idx_outer = n_core + n_lowR + (1:n_outerQ); % Outer-Qf stratum row indexlerini tanimlar.
n_outer_low = ceil(n_outerQ / 2); % Outer-Qf noktalarinin yaklasik yarisini turndown tarafina ayirir.
idx_outer_low = idx_outer(1:n_outer_low); % Dusuk-Qf outer sample indexlerini alir.
idx_outer_high = idx_outer(n_outer_low + 1:end); % Yuksek-Qf outer sample indexlerini alir.
Qf(idx_outer_low) = cfg.domain.Qf_min_m3h + U(idx_outer_low, 1) * ...
    (cfg.doe.feas_Qf_core_min_m3h - cfg.domain.Qf_min_m3h); % 35-47 m3/h turndown bandini map eder.
Qf(idx_outer_high) = cfg.doe.feas_Qf_core_max_m3h + U(idx_outer_high, 1) * ...
    (cfg.domain.Qf_max_m3h - cfg.doe.feas_Qf_core_max_m3h); % 64-75 m3/h high-flow bandini map eder.
DOE_Type(idx_outer_low) = "OuterQfLowProbe"; % Dusuk-Qf probe label'ini kaydeder.
DOE_Type(idx_outer_high) = "OuterQfHighProbe"; % Yuksek-Qf probe label'ini kaydeder.

%% UPPER-RECOVERY STRATUM % Analitik necessary recovery upper-envelope yakinindaki constraint boundary'lerini bilincli olarak probe eder.

idx_upperR = n_core + n_lowR + n_outerQ + (1:n_upperR); % Upper-recovery stratum row indexlerini tanimlar.
Qf(idx_upperR) = cfg.doe.feas_Qf_core_min_m3h + U(idx_upperR, 1) * ...
    (cfg.doe.feas_Qf_core_max_m3h - cfg.doe.feas_Qf_core_min_m3h); % Upper-R probe'u core Qf bandinda yapar.
DOE_Type(idx_upperR) = "UpperRecoveryProbe"; % Upper-recovery sample label'ini kaydeder.

%% CONDITIONAL RECOVERY MAP % Her Qf-Cf noktasinda pressure optimization'dan bagimsiz necessary Rmax degerini hesaplar ve Rtarget'i buna kosullu uretir.

for i = 1:n_generated % Tum generated sample'lar uzerinde conditional recovery dongusu kurar.
    screen0 = ro_analytic_screen_train_point(Qf(i), T(i), Cf(i), cfg.domain.R_min, cfg); % Aynı model/geometry limitleriyle analytic recovery envelope degerini hesaplar.
    Rmax_i = min(cfg.domain.R_max, screen0.Rmax_analytic) - cfg.doe.feas_R_upper_margin; % Exact analytic boundary'nin biraz altinda sampling upper limit olusturur.
    Rmax_i = min(max(Rmax_i, cfg.domain.R_min), cfg.domain.R_max); % Numerical guvenlik icin upper limit'i global recovery domain'ine clip eder.
    RmaxAnalyticDesign(i) = Rmax_i; % Samplingde kullanilan R upper limitini diagnostic olarak kaydeder.

    if DOE_Type(i) == "LowRecoveryProbe" % Dusuk-recovery feasibility stratum'u icin kontrol eder.
        Rlo = cfg.domain.R_min; % Global 0.34 recovery alt sinirini korur.
        Rhi = min(cfg.doe.feas_R_low_probe_max, Rmax_i); % Low-R probe ust limitini analitik envelope ile sinirlar.
        if Rhi <= Rlo + 1.0e-6 % Conditional band numerik olarak kapanmissa kontrol eder.
            Rtarget(i) = Rlo; % En dusuk recovery noktasini kullanir.
            Rfraction(i) = 0.0; % Conditional span fraction degerini sifir kaydeder.
        else % Kullanilabilir low-R band varsa bu dali kullanir.
            Rtarget(i) = Rlo + U(i, 4) * (Rhi - Rlo); % Low-discrepancy recovery sample degerini 0.34-0.42 bandina map eder.
            Rfraction(i) = (Rtarget(i) - Rlo) / (Rhi - Rlo); % Band icindeki normalize recovery konumunu hesaplar.
        end % Low-R conditional band kosulunu sonlandirir.
    elseif DOE_Type(i) == "UpperRecoveryProbe" % Analitik upper-envelope probe stratum'u icin kontrol eder.
        Rlo = max(cfg.doe.feas_R_core_min, cfg.domain.R_min); % Upper-envelope probe span'inin alt referansini core recovery floor olarak tanimlar.
        if Rmax_i <= Rlo + 1.0e-6 % Analitik upper envelope core floor'un altindaysa kontrol eder.
            Rlo = cfg.domain.R_min; % Dar feasible necessary span'i kaybetmemek icin global lower recovery degerine geri doner.
        end % Upper-probe lower-bound adjustment kosulunu sonlandirir.
        alpha = 0.90 + 0.095 * U(i, 4); % Recovery span'inin ust %10'luk bolgesini 0.90-0.995 fraction ile probe eder.
        Rtarget(i) = Rlo + alpha * max(Rmax_i - Rlo, 0.0); % Analitik upper envelope'e yakin recovery target degerini olusturur.
        Rfraction(i) = alpha; % Upper-envelope fraction degerini diagnostic olarak kaydeder.
    else % CoreConditional ve OuterQf probe stratum'lari icin ortak conditional recovery map kullanir.
        Rlo = max(cfg.doe.feas_R_core_min, cfg.domain.R_min); % Normal conditional sampling icin recovery floor degerini tanimlar.
        if Rmax_i <= Rlo + 1.0e-6 % Analitik envelope core floor'un altinda ise kontrol eder.
            Rlo = cfg.domain.R_min; % Outer veya dar necessary span'i yine de probe etmek icin global lower recovery'ye iner.
        end % Conditional lower-bound adjustment kosulunu sonlandirir.
        Rtarget(i) = Rlo + U(i, 4) * max(Rmax_i - Rlo, 0.0); % Rtarget'i her Qf-Cf noktasinin kendi analytic upper envelope'ine kosullu map eder.
        if Rmax_i > Rlo + 1.0e-12 % Normalize recovery fraction icin pozitif span olup olmadigini kontrol eder.
            Rfraction(i) = (Rtarget(i) - Rlo) / (Rmax_i - Rlo); % Conditional recovery span icindeki konumu kaydeder.
        else % Recovery span numerik olarak sifirsa bu dali kullanir.
            Rfraction(i) = 0.0; % Normalize fraction'i sifir yapar.
        end % Recovery-fraction hesap kosulunu sonlandirir.
    end % Sampling-stratum recovery mapping secimini sonlandirir.
end % Conditional recovery loop'unu sonlandirir.

%% KNOWN-FEASIBLE ANCHORS % v1.6.8 multi-region benchmark'ta N=150 FASTSEARCH ile yeniden dogrulanan alti noktayi pilot icine ekler.

Anchor_Qf = [61.442891; 54.410224; 59.628889; 51.854958; 52.865870; 54.638007]; % Known-feasible anchor feed-flow degerlerini tanimlar.
Anchor_T = [38.365489; 24.701405; 44.503512; 30.033322; 41.786613; 40.666479]; % Known-feasible anchor temperature degerlerini tanimlar.
Anchor_Cf = [39.645051; 39.249560; 40.543472; 40.521768; 39.692320; 39.441435]; % Known-feasible anchor salinity-concentration degerlerini tanimlar.
Anchor_R = [0.435757; 0.533372; 0.508160; 0.493386; 0.545766; 0.439749]; % Known-feasible anchor recovery target degerlerini tanimlar.

if n_anchor > 0 % Anchor inclusion etkinse kontrol eder.
    Qf = [Qf; Anchor_Qf(1:n_anchor)]; % Generated ve known-feasible feed-flow degerlerini birlestirir.
    T = [T; Anchor_T(1:n_anchor)]; % Generated ve known-feasible temperature degerlerini birlestirir.
    Cf = [Cf; Anchor_Cf(1:n_anchor)]; % Generated ve known-feasible concentration degerlerini birlestirir.
    Rtarget = [Rtarget; Anchor_R(1:n_anchor)]; % Generated ve known-feasible recovery target degerlerini birlestirir.
    DOE_Type = [DOE_Type; repmat("KnownFeasibleAnchor", n_anchor, 1)]; % Anchor sample source label'larini ekler.

    Anchor_Rmax = NaN(n_anchor, 1); % Anchor analytic recovery upper-limit diagnostics vectorunu olusturur.
    Anchor_Rfraction = NaN(n_anchor, 1); % Anchor conditional recovery-fraction diagnostics vectorunu olusturur.
    for k = 1:n_anchor % Her anchor icin analytic upper envelope diagnostic degerini hesaplar.
        sc = ro_analytic_screen_train_point(Anchor_Qf(k), Anchor_T(k), Anchor_Cf(k), Anchor_R(k), cfg); % Anchor analytic screening sonucunu hesaplar.
        Anchor_Rmax(k) = sc.Rmax_analytic; % Anchor analytic upper recovery degerini kaydeder.
    end % Anchor diagnostics loop'unu sonlandirir.
    RmaxAnalyticDesign = [RmaxAnalyticDesign; Anchor_Rmax]; % Generated ve anchor Rmax diagnostics degerlerini birlestirir.
    Rfraction = [Rfraction; Anchor_Rfraction]; % Anchor'larda conditional sampling fraction uygulanmadigi icin NaN degerleri ekler.
end % Anchor inclusion kosulunu sonlandirir.

%% DOE TABLOSU VE ANALYTIC SCREEN CHECK % Final pilot tablosunu olusturur ve conditional map'in necessary constraints'i gercekten sagladigini kontrol eder.

DOE_ID = (1:numel(Qf)).'; % Tum generated+anchor sample'lar icin unique DOE index degerlerini olusturur.
AnalyticScreenExpectedPass = false(numel(Qf), 1); % Analytic-screen precheck flag vectorunu olusturur.
for i = 1:numel(Qf) % Tum final DOE sample'larini analytic screen ile yeniden kontrol eder.
    sc = ro_analytic_screen_train_point(Qf(i), T(i), Cf(i), Rtarget(i), cfg); % Final sample'in analytic necessary-condition sonucunu hesaplar.
    AnalyticScreenExpectedPass(i) = sc.pass; % Analytic-screen pass flag degerini kaydeder.
end % Final DOE analytic-screen verification loop'unu sonlandirir.

DOE = table(DOE_ID, DOE_Type, Qf, T, Cf, Rtarget, RmaxAnalyticDesign, Rfraction, AnalyticScreenExpectedPass); % Dataset generator'a verilecek pilot DOE tablosunu olusturur.
DOE.Properties.VariableNames = {'DOE_ID','DOE_Type','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'Rmax_analytic_design','R_fraction_conditional','AnalyticScreenExpectedPass'}; % Acik ve traceable DOE kolon isimlerini tanimlar.

end % Feasibility-aware DOE generator fonksiyonunu sonlandirir.
