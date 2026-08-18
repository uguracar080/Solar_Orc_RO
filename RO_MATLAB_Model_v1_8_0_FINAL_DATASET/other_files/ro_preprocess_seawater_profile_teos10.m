function Profile = ro_preprocess_seawater_profile_teos10(input_csv, output_csv, cfg) % CMEMS Practical Salinity ve potential temperature verilerini TEOS-10 ile Cf [kg/m3] degerine donusturur.

%% GIRDI KONTROLLERI % File path ve configuration girdilerini tamamlar.

if nargin < 3 || isempty(cfg) % Configuration struct verilmemisse kontrol eder.
    cfg = ro_ann_config(); % Mersin CMEMS location/depth degerlerini varsayilan config'den yukler.
end % Configuration input kontrolunu sonlandirir.
if nargin < 2 || strlength(string(output_csv)) == 0 % Output CSV yolu verilmemisse kontrol eder.
    output_csv = 'seawater_profile_RO_ready.csv'; % Varsayilan RO-ready seawater profile file adini tanimlar.
end % Output-path input kontrolunu sonlandirir.

%% TEOS-10 GSW TOOLBOX KONTROLU % Publication-level salinity conversion icin gerekli resmi GSW fonksiyonlarini zorunlu tutar.

required_functions = {'gsw_p_from_z','gsw_SA_from_SP','gsw_CT_from_pt','gsw_rho'}; % Kullanilacak GSW MATLAB functions listesini tanimlar.
for i = 1:numel(required_functions) % Tum gerekli GSW functions uzerinde dongu kurar.
    if exist(required_functions{i}, 'file') ~= 2 % Mevcut function MATLAB path'te degilse kontrol eder.
        error(['TEOS-10 GSW MATLAB Toolbox bulunamadi veya tum alt klasorleri MATLAB path''ine eklenmedi. Eksik fonksiyon: ' required_functions{i}]); % Approximate conversion'a sessiz fallback yapmak yerine acik hata verir.
    end % GSW function-existence kosulunu sonlandirir.
end % GSW toolbox kontrol dongusunu sonlandirir.

%% CSV OKUMA VE TEMEL KONTROLLER % 8760-saat profile ve beklenen kolonlari dogrular.

Profile = readtable(input_csv); % User tarafindan hazirlanan seawater profile CSV dosyasini okur.
required_columns = {'Hour_Index','SeaWater_Temperature_C','Salinity_CMEMS_native'}; % Conversion icin zorunlu kolon isimlerini tanimlar.
for i = 1:numel(required_columns) % Tum zorunlu kolonlar uzerinde dongu kurar.
    if ~ismember(required_columns{i}, Profile.Properties.VariableNames) % Zorunlu kolon tabloda yoksa kontrol eder.
        error('Input CSV icinde gerekli kolon bulunamadi: %s', required_columns{i}); % Eksik column icin acik hata mesaji verir.
    end % Required-column kosulunu sonlandirir.
end % Required-column kontrol dongusunu sonlandirir.
if height(Profile) ~= 8760 || any(Profile.Hour_Index(:) ~= (1:8760).') % Hour index ve row count tam yil ile uyumlu degilse kontrol eder.
    error('Seawater profile 8760 satir ve Hour_Index=1:8760 yapisinda olmali.'); % Time alignment bozuksa conversion'i durdurur.
end % 8760-hour kontrolunu sonlandirir.

%% CMEMS NATIVE VARIABLES % CMEMS salinity ve potential-temperature series degerlerini vector olarak alir.

SP = Profile.Salinity_CMEMS_native; % CMEMS sea-water salinity degerlerini Practical Salinity inputu olarak alir.
pt0_C = Profile.SeaWater_Temperature_C; % MEDSEA product sea-water potential temperature degerlerini surface-reference potential temperature olarak alir.
lat = cfg.site.latitude_deg; % CMEMS ortak grid latitude degerini alir.
lon = cfg.site.longitude_deg; % CMEMS ortak grid longitude degerini alir.
depth_m = cfg.site.depth_m; % CMEMS native vertical level depth degerini alir.

%% TEOS-10 SALINITY VE DENSITY % Practical Salinity -> Absolute Salinity -> density zincirini resmi GSW routines ile hesaplar.

p_dbar = gsw_p_from_z(-depth_m, lat); % Pozitif depth'i TEOS-10 z<0 convention ile sea pressure [dbar] degerine cevirir.
p_vector_dbar = repmat(p_dbar, height(Profile), 1); % Sabit native depth pressure degerini 8760-saat vector boyutuna genisletir.
SA_g_kg = gsw_SA_from_SP(SP, p_vector_dbar, lon, lat); % Practical Salinity'den location-dependent Absolute Salinity [g/kg] hesaplar.
CT_C = gsw_CT_from_pt(SA_g_kg, pt0_C); % CMEMS potential temperature'dan TEOS-10 Conservative Temperature degerini hesaplar.
rho_kg_m3 = gsw_rho(SA_g_kg, CT_C, p_vector_dbar); % Absolute Salinity, CT ve pressure kullanarak in-situ density [kg/m3] hesaplar.
Cf_kg_m3 = rho_kg_m3 .* SA_g_kg / 1000.0; % Salt mass fraction ile solution density'yi carparak physical salt concentration [kg/m3] hesaplar.
SR_g_kg = (35.16504 / 35.0) .* SP; % Traceability icin Practical Salinity'den Reference Salinity [g/kg] degerini ayrica hesaplar.

%% OUTPUT KOLONLARI % Native CMEMS degerlerini koruyarak conversion audit kolonlarini profile ekler.

Profile.Reference_Salinity_g_kg = SR_g_kg; % TEOS-10 Reference Salinity degerini yeni kolona kaydeder.
Profile.Absolute_Salinity_g_kg = SA_g_kg; % TEOS-10 Absolute Salinity degerini yeni kolona kaydeder.
Profile.Conservative_Temperature_C = CT_C; % TEOS-10 Conservative Temperature degerini yeni kolona kaydeder.
Profile.SeaPressure_dbar = p_vector_dbar; % Native depth icin sea pressure degerini yeni kolona kaydeder.
Profile.SeaWater_Density_TEOS10_kg_m3 = rho_kg_m3; % TEOS-10 density degerini yeni kolona kaydeder.
Profile.Cf_kg_m3 = Cf_kg_m3; % Detailed Du RO modeline verilecek feed concentration degerini yeni kolona kaydeder.
Profile.Cf_Conversion_Method = repmat("TEOS10_SP_to_SA_rho", height(Profile), 1); % Conversion method bilgisini her row'da traceable olarak kaydeder.

%% DOSYA VE RANGE RAPORU % RO-ready CSV dosyasini yazar ve domain kontrolu icin conversion range degerlerini raporlar.

writetable(Profile, output_csv); % Native + converted 8760-hour profile'i yeni CSV file olarak kaydeder.
fprintf('TEOS-10 conversion tamamlandi.\n'); % Conversion completion mesajini yazdirir.
fprintf('SP range : %.6f - %.6f\n', min(SP), max(SP)); % Native Practical Salinity range degerini yazdirir.
fprintf('SA range : %.6f - %.6f g/kg\n', min(SA_g_kg), max(SA_g_kg)); % Absolute Salinity range degerini yazdirir.
fprintf('Cf range : %.6f - %.6f kg/m3\n', min(Cf_kg_m3), max(Cf_kg_m3)); % Final physical feed concentration range degerini yazdirir.
fprintf('T range  : %.6f - %.6f C\n', min(pt0_C), max(pt0_C)); % Native potential-temperature range degerini yazdirir.

end % TEOS-10 seawater-profile preprocessing fonksiyonunu sonlandirir.
