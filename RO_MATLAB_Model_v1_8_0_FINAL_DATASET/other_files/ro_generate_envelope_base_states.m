function BaseStates = ro_generate_envelope_base_states(n_states, cfg) % Qf-T-Cf uzayinda recovery-envelope mapping icin stratified Sobol base state'leri olusturur.

%% GIRDI KONTROLU % Configuration ve toplam state sayisini guvenli varsayilanlarla yukler.

if nargin < 2 || isempty(cfg) % Configuration verilmediyse kontrol eder.
    cfg = ro_ann_config(); % Merkezi RO/ANN configuration struct'ini yukler.
end % Configuration kontrolunu sonlandirir.
if nargin < 1 || isempty(n_states) % State sayisi verilmediyse kontrol eder.
    n_states = cfg.envelope.n_states; % v1.7.0 varsayilan 48 base state sayisini kullanir.
end % State-count kontrolunu sonlandirir.
n_states = max(round(n_states), 24); % Stratification'in anlamsiz derecede kuculmesini engeller.
if exist('sobolset', 'file') ~= 2 % Low-discrepancy sampling fonksiyonunun mevcut olup olmadigini kontrol eder.
    error('sobolset bulunamadi. Statistics and Machine Learning Toolbox kurulumunu/path durumunu kontrol edin.'); % Sessiz random fallback yerine acik hata verir.
end % Sobol availability kontrolunu sonlandirir.

%% STRATUM SAYILARI % Core, Qf boundary, temperature edge ve known-feasible anchor state sayilarini belirler.

n_anchor = min(6, max(0, round(0.125 * n_states))); % Onceki 6-point benchmark'tan en fazla alti known-feasible state ekler.
n_lowQ = max(3, round(0.15 * n_states)); % Dusuk-Qf boundary probe state sayisini belirler.
n_highQ = max(3, round(0.15 * n_states)); % Yuksek-Qf boundary probe state sayisini belirler.
n_lowT = max(2, round(0.10 * n_states)); % Dusuk-temperature edge state sayisini belirler.
n_highT = max(2, round(0.10 * n_states)); % Yuksek-temperature edge state sayisini belirler.
n_core = n_states - n_anchor - n_lowQ - n_highQ - n_lowT - n_highT; % Kalan state'leri 3-D core coverage'a ayirir.
if n_core < 6 % Core sample sayisi yeterli degilse kontrol eder.
    deficit = 6 - n_core; % Core'a aktarilmasi gereken state sayisini hesaplar.
    n_lowQ = max(2, n_lowQ - ceil(deficit / 2)); % Dusuk-Qf stratum'undan kontrollu azaltma yapar.
    n_highQ = max(2, n_highQ - floor(deficit / 2)); % Yuksek-Qf stratum'undan kontrollu azaltma yapar.
    n_core = n_states - n_anchor - n_lowQ - n_highQ - n_lowT - n_highT; % Duzenlenmis core sayisini yeniden hesaplar.
end % Minimum-core kontrolunu sonlandirir.
n_generated = n_states - n_anchor; % Sobol ile olusturulacak generated state sayisini hesaplar.

%% REPRODUCIBLE SOBOL % Generated state'ler icin 3-D low-discrepancy koordinatlari olusturur.

p = sobolset(3, 'Skip', cfg.doe.skip + 4096, 'Leap', cfg.doe.leap); % Pilot DOE'den farkli deterministic Sobol bolgesi kullanir.
p = scramble(p, cfg.doe.scramble_method); % Aynı Matousek-Affine-Owen scrambling yontemini kullanir.
U = net(p, n_generated); % Qf, T ve Cf koordinatlari icin unit-cube sample degerlerini uretir.
Qf = NaN(n_states, 1); % Feed-flow vectorunu preallocate eder.
T = NaN(n_states, 1); % Temperature vectorunu preallocate eder.
Cf = NaN(n_states, 1); % Feed-concentration vectorunu preallocate eder.
StateType = strings(n_states, 1); % Sampling-stratum label vectorunu olusturur.

%% CORE 3-D COVERAGE % Qf=49-61 bandinda tam T ve Cf domain'ini birlikte kapsar.

idx0 = 0; % Generated stratum row counter'ini sifirdan baslatir.
idx = idx0 + (1:n_core); % Core-state indexlerini tanimlar.
Qf(idx) = map_unit(U(idx, 1), cfg.envelope.Qf_core_min_m3h, cfg.envelope.Qf_core_max_m3h); % Core Qf degerlerini map eder.
T(idx) = map_unit(U(idx, 2), cfg.domain.T_min_C, cfg.domain.T_max_C); % Core temperature degerlerini tam domain'e map eder.
Cf(idx) = map_unit(U(idx, 3), cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Core concentration degerlerini tam domain'e map eder.
StateType(idx) = "Core3D"; % Core-state label'ini kaydeder.
idx0 = idx0 + n_core; % Stratum counter'ini ilerletir.

%% DUSUK Qf BOUNDARY % 46-50 m3/h bandinda turndown feasibility sinirini zenginlestirir.

idx = idx0 + (1:n_lowQ); % Dusuk-Qf state indexlerini tanimlar.
Qf(idx) = map_unit(U(idx, 1), cfg.envelope.Qf_low_min_m3h, cfg.envelope.Qf_low_max_m3h); % Boundary Qf degerlerini map eder.
T(idx) = map_unit(U(idx, 2), cfg.domain.T_min_C, cfg.domain.T_max_C); % Temperature'i tam domain'de tutar.
Cf(idx) = map_unit(U(idx, 3), cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Salinity-concentration'i tam domain'de tutar.
StateType(idx) = "QfLowBoundary"; % Dusuk-flow boundary label'ini kaydeder.
idx0 = idx0 + n_lowQ; % Stratum counter'ini ilerletir.

%% YUKSEK Qf BOUNDARY % 61-64 m3/h bandinda Stage-1 hydraulic boundary'yi zenginlestirir.

idx = idx0 + (1:n_highQ); % Yuksek-Qf state indexlerini tanimlar.
Qf(idx) = map_unit(U(idx, 1), cfg.envelope.Qf_high_min_m3h, cfg.envelope.Qf_high_max_m3h); % Boundary Qf degerlerini map eder.
T(idx) = map_unit(U(idx, 2), cfg.domain.T_min_C, cfg.domain.T_max_C); % Temperature'i tam domain'de tutar.
Cf(idx) = map_unit(U(idx, 3), cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Concentration'i tam domain'de tutar.
StateType(idx) = "QfHighBoundary"; % Yuksek-flow boundary label'ini kaydeder.
idx0 = idx0 + n_highQ; % Stratum counter'ini ilerletir.

%% DUSUK SICAKLIK EDGE % 15-24 C bandinda quality-limited feasibility sinirini hedefler.

idx = idx0 + (1:n_lowT); % Dusuk-temperature state indexlerini tanimlar.
Qf(idx) = map_unit(U(idx, 1), cfg.envelope.Qf_core_min_m3h, cfg.envelope.Qf_high_max_m3h); % Qf'yi ana fiziksel ilgi bandinda map eder.
T(idx) = map_unit(U(idx, 2), cfg.domain.T_min_C, cfg.envelope.T_low_max_C); % Dusuk-temperature edge bandini map eder.
Cf(idx) = map_unit(U(idx, 3), cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Concentration'i tam domain'de tutar.
StateType(idx) = "LowTemperatureEdge"; % Dusuk-temperature edge label'ini kaydeder.
idx0 = idx0 + n_lowT; % Stratum counter'ini ilerletir.

%% YUKSEK SICAKLIK EDGE % 39-45 C bandinda quality marji ve hydraulic-limited optimum rejimini kapsar.

idx = idx0 + (1:n_highT); % Yuksek-temperature state indexlerini tanimlar.
Qf(idx) = map_unit(U(idx, 1), cfg.envelope.Qf_core_min_m3h, cfg.envelope.Qf_high_max_m3h); % Qf'yi ana fiziksel ilgi bandinda map eder.
T(idx) = map_unit(U(idx, 2), cfg.envelope.T_high_min_C, cfg.domain.T_max_C); % Yuksek-temperature edge bandini map eder.
Cf(idx) = map_unit(U(idx, 3), cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Concentration'i tam domain'de tutar.
StateType(idx) = "HighTemperatureEdge"; % Yuksek-temperature edge label'ini kaydeder.

%% KNOWN-FEASIBLE ANCHORS % v1.6.8 benchmark'ta N=150 FASTSEARCH ile 6/6 kabul edilen Qf-T-Cf state'leri ekler.

Anchor_Qf = [61.442891; 54.410224; 59.628889; 51.854958; 52.865870; 54.638007]; % Benchmark feed-flow degerlerini tanimlar.
Anchor_T = [38.365489; 24.701405; 44.503512; 30.033322; 41.786613; 40.666479]; % Benchmark temperature degerlerini tanimlar.
Anchor_Cf = [39.645051; 39.249560; 40.543472; 40.521768; 39.692320; 39.441435]; % Benchmark concentration degerlerini tanimlar.
if n_anchor > 0 % Anchor inclusion etkinse kontrol eder.
    idx = n_generated + (1:n_anchor); % Final anchor row indexlerini tanimlar.
    Qf(idx) = Anchor_Qf(1:n_anchor); % Anchor feed-flow degerlerini yerlestirir.
    T(idx) = Anchor_T(1:n_anchor); % Anchor temperature degerlerini yerlestirir.
    Cf(idx) = Anchor_Cf(1:n_anchor); % Anchor concentration degerlerini yerlestirir.
    StateType(idx) = "KnownFeasibleAnchor"; % Anchor label'larini kaydeder.
end % Anchor inclusion kosulunu sonlandirir.

%% ANALITIK UST ENVELOPE % Her base state icin pressure optimization'dan bagimsiz necessary Rmax degerini hesaplar.

RmaxAnalytic = NaN(n_states, 1); % Analitik recovery upper-envelope vectorunu preallocate eder.
for i = 1:n_states % Tum Qf-T-Cf state'ler uzerinde dongu kurar.
    sc = ro_analytic_screen_train_point(Qf(i), T(i), Cf(i), cfg.domain.R_min, cfg); % Necessary recovery upper envelope degerini hesaplar.
    RmaxAnalytic(i) = sc.Rmax_analytic; % State'e ait analytic Rmax degerini kaydeder.
end % Analitik envelope loop'unu sonlandirir.

%% FINAL TABLE % State kimlikleri ve diagnostics kolonlariyla traceable base-state tablosunu olusturur.

State_ID = (1:n_states).'; % Her base state icin unique integer ID olusturur.
BaseStates = table(State_ID, StateType, Qf, T, Cf, RmaxAnalytic); % Envelope mapper'a verilecek base-state tablosunu olusturur.
BaseStates.Properties.VariableNames = {'State_ID','State_Type','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','Rmax_analytic'}; % Acik kolon isimlerini tanimlar.

end % Base-state generator fonksiyonunu sonlandirir.

function x = map_unit(u, xmin, xmax) % Unit interval sample'ini verilen fiziksel araliga lineer map eder.
x = xmin + u .* (xmax - xmin); % Lineer affine mapping islemini uygular.
end % Unit-map helper fonksiyonunu sonlandirir.
