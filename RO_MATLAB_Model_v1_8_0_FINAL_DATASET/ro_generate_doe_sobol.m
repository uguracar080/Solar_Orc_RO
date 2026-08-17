function DOE = ro_generate_doe_sobol(n_points, cfg) % 4-D Qf-T-Cf-Rtarget domain'inde scrambled Sobol + boundary/corner DOE olusturur.

%% GIRDI KONTROLU % DOE boyutu ve Sobol fonksiyonlarinin kullanilabilirligini kontrol eder.

if nargin < 2 % Configuration struct verilmediyse kontrol eder.
    cfg = ro_ann_config(); % Varsayilan ANN configuration degerlerini yukler.
end % Configuration input kontrolunu sonlandirir.

n_points = max(round(n_points), 16); % En az 16 nokta kullanarak tum 4-D corner kombinasyonlarini kapsayabilmeyi saglar.
if exist('sobolset', 'file') ~= 2 % sobolset fonksiyonunun MATLAB path'te olup olmadigini kontrol eder.
    error('sobolset bulunamadi. Statistics and Machine Learning Toolbox kurulumunu/path durumunu kontrol edin.'); % DOE uretimini belirsiz random fallback yerine acik hata ile durdurur.
end % sobolset kontrolunu sonlandirir.

%% NOKTA SAYILARI % Interior, exact-boundary ve corner sample sayilarini belirler.

n_corners = 0; % Varsayilan corner sayisini sifir tanimlar.
if cfg.doe.include_corners % Dört-boyutlu domain corner enrichment etkinse kontrol eder.
    n_corners = 16; % 2^4 = 16 corner kombinasyonunu kullanir.
end % Corner-enrichment kosulunu sonlandirir.

n_boundary = round(cfg.doe.boundary_fraction * n_points); % Exact domain-face sample sayisini hedef boundary fraction'dan hesaplar.
n_boundary = min(n_boundary, max(n_points - n_corners - 1, 0)); % En az bir interior nokta kalacak sekilde boundary sayisini sinirlar.
n_interior = n_points - n_boundary - n_corners; % Geri kalan sample sayisini interior Sobol noktalarina ayirir.

%% SCRAMBLED SOBOL SEQUENCE % Reproducible low-discrepancy unit-hypercube noktalarini olusturur.

p = sobolset(4, 'Skip', cfg.doe.skip, 'Leap', cfg.doe.leap); % 4-boyutlu Sobol sequence nesnesini olusturur.
p = scramble(p, cfg.doe.scramble_method); % Matousek-Affine-Owen scrambling ile sequence artefact riskini azaltir.
U_base = net(p, n_interior + n_boundary); % Interior ve boundary enrichment icin gerekli Sobol unit-cube noktalarini uretir.
U_interior = U_base(1:n_interior, :); % Ilk kisimdaki noktalarin tam 4-D interior coordinates degerlerini alir.
U_boundary = U_base(n_interior + 1:end, :); % Son kisimdaki noktalarin kalan 3 boyutta low-discrepancy boundary coordinates degerlerini alir.

%% EXACT DOMAIN FACES % Boundary sample'larin bir eksenini sirali olarak 0 veya 1 degerine sabitler.

for k = 1:n_boundary % Tum boundary sample'lar uzerinde dongu kurar.
    face_id = mod(k - 1, 8) + 1; % 4 dimensions x 2 sides = 8 domain face arasinda esit dagilim yapar.
    dim_id = ceil(face_id / 2); % Mevcut face'in hangi input dimension'a ait oldugunu hesaplar.
    side_is_max = mod(face_id, 2) == 0; % Cift face id'lerini maximum side olarak tanimlar.
    U_boundary(k, dim_id) = double(side_is_max); % Secilen dimension'i exact 0 veya exact 1 boundary degerine sabitler.
end % Boundary-face enrichment dongusunu sonlandirir.

%% 4-D CORNERS % Tum min/max kombinasyonlarinin exact corner noktalarini olusturur.

U_corners = zeros(n_corners, 4); % Corner unit-cube matrix'ini olusturur.
if n_corners > 0 % Corner enrichment etkinse kontrol eder.
    bits = dec2bin(0:15, 4) - '0'; % 0-15 integer degerlerini 4-bit min/max kombinasyonlarina cevirir.
    U_corners = double(bits); % Binary character matrix'i numeric 0/1 corner matrix'ine cevirir.
end % Corner matrix kosulunu sonlandirir.

%% UNIT-CUBE NOKTALARINI BIRLESTIRME % Sample source label'lariyla tek DOE matrix'i olusturur.

U = [U_interior; U_boundary; U_corners]; % Interior, boundary ve corner unit-cube noktalarini tek matrix'te birlestirir.
DOE_Type = [repmat("Interior", n_interior, 1); repmat("Boundary", n_boundary, 1); repmat("Corner", n_corners, 1)]; % Her sample'in DOE source tipini tanimlar.

%% PHYSICAL DOMAIN'E MAP % Sobol unit-cube coordinates degerlerini Qf-T-Cf-Rtarget araliklarina donusturur.

Qf = cfg.domain.Qf_min_m3h + U(:, 1) * (cfg.domain.Qf_max_m3h - cfg.domain.Qf_min_m3h); % Feed-flow samples degerlerini m3/h domain'ine map eder.
T = cfg.domain.T_min_C + U(:, 2) * (cfg.domain.T_max_C - cfg.domain.T_min_C); % Temperature samples degerlerini Celsius domain'ine map eder.
Cf = cfg.domain.Cf_min_kg_m3 + U(:, 3) * (cfg.domain.Cf_max_kg_m3 - cfg.domain.Cf_min_kg_m3); % Feed concentration samples degerlerini kg/m3 domain'ine map eder.
Rtarget = cfg.domain.R_min + U(:, 4) * (cfg.domain.R_max - cfg.domain.R_min); % Recovery target samples degerlerini fraction domain'ine map eder.

%% ANALYTIC BRINE SCREEN DIAGNOSTIC % Stage-2 minimum brine flow'dan gelen gerekli fakat yeterli olmayan recovery upper bound'u hesaplar.

mem = ro_membrane_SW30XLE400(); % Analytic brine screen icin membrane flow limitlerini yukler.
minimum_total_brine_m3h = cfg.geometry.N_PV_stage2 * mem.min_brine_flow_m3h; % Tek train icin minimum total Stage-2 brine flow degerini hesaplar.
Rmax_brine_analytic = 1.0 - minimum_total_brine_m3h ./ Qf; % Qf*(1-R)>=14.4 necessary condition'undan analytic Rmax degerini hesaplar.
AnalyticBrinePossible = Rtarget <= Rmax_brine_analytic; % Her DOE noktasinin sadece bu necessary condition'i saglayip saglamadigini kaydeder.

%% DOE TABLE % Dataset generator'a verilecek sirali input tablosunu olusturur.

DOE_ID = (1:n_points).'; % Her sample icin unique DOE index degerini olusturur.
DOE = table(DOE_ID, DOE_Type, Qf, T, Cf, Rtarget, Rmax_brine_analytic, AnalyticBrinePossible); % DOE tablo object'ini olusturur.
DOE.Properties.VariableNames = {'DOE_ID','DOE_Type','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target','Rmax_brine_analytic','AnalyticBrinePossible'}; % Anlasilir kolon isimlerini tanimlar.

end % Sobol DOE generator fonksiyonunu sonlandirir.
