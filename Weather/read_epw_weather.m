function weather = read_epw_weather(epwFile)
% =========================================================================
% READ_EPW_WEATHER  (CACHE + PARFOR VERSION, PORTABLE CACHE CHECK)
% =========================================================================
%
% EPW hava verisini okur ve aşağıdaki değişkenleri üretir:
%
%  TEMPERATURE
%  ------------------------------------------------------------------------
%  T_amb_C      Dry bulb temperature [°C]
%  RH_pct       Relative humidity [%]
%  Patm_Pa      Atmospheric pressure [Pa]
%  T_wb_C       Wet bulb temperature [°C]
%
%  SOLAR RADIATION
%  ------------------------------------------------------------------------
%  GHI_Whm2     Global Horizontal Radiation
%  DNI_Whm2     Direct Normal Radiation
%  DHI_Whm2     Diffuse Horizontal Radiation
%
%  WIND
%  ------------------------------------------------------------------------
%  WindDir_deg  Wind direction [deg]
%  WindSpd_ms   Wind speed [m/s]
%
% -------------------------------------------------------------------------
% PERFORMANS
%
% • EPW sadece ilk çalıştırmada okunur
% • .mat cache oluşturulur
% • sonraki çalıştırmalarda doğrudan yüklenir
% • wetbulb hesapları parfor ile paralel yapılır
%
% -------------------------------------------------------------------------
% PORTABLE CACHE NOTU
%
% Önceki sürümde cache içindeki epwFile yolu ile mevcut epwFile yolu
% birebir strcmp ile karşılaştırılıyordu. Bu durumda proje klasörü başka
% yere taşındığında veya cache dosyası yeni Weather klasörüne kopyalandığında
% EPW dosya adı aynı olsa bile cache yeniden oluşturuluyordu.
%
% Bu sürümde cache doğrulaması taşınabilir hale getirildi:
%   - Cache içindeki epwFile ile mevcut epwFile sadece dosya adı + uzantı
%     üzerinden karşılaştırılır.
%   - Böylece aynı EPW dosyasına ait cache farklı klasöre taşınsa da
%     kullanılabilir.
%
% Kullanım:
%   weather = read_epw_weather(epwFile);
%
% Örnek:
%   epwFile = fullfile(ProjectRoot,'Weather', ...
%       'TUR_IC_Mersin.173400_TMYx.2009-2023.epw');
%   weather = read_epw_weather(epwFile);
%
% =========================================================================

%% =========================================================================
% INPUT NORMALIZATION
% =========================================================================

if nargin < 1 || isempty(epwFile)
    error('read_epw_weather requires an EPW file path.');
end

epwFile = char(epwFile);

[epw_path, epw_name, epw_ext] = fileparts(epwFile);

if isempty(epw_path)
    epw_path = pwd;
    epwFile = fullfile(epw_path, [epw_name epw_ext]);
end

cacheFile = fullfile(epw_path, [epw_name '_weather_cache.mat']);
cacheFile = char(cacheFile);

%% =========================================================================
% CACHE VAR MI?  (PORTABLE EPW DEĞİŞİM KONTROLÜ)
% =========================================================================

if isfile(cacheFile)

    S = load(cacheFile);

    % Cache içinde weather tablosu var mı?
    if isfield(S,'weather')
        cachedWeather = S.weather;
    elseif isfield(S,'WeatherData')
        cachedWeather = S.WeatherData;
    else
        fprintf("Cache file found but weather variable is missing → rebuilding cache\n");
        cachedWeather = [];
    end

    if ~isempty(cachedWeather)

        % Yeni format: cache içinde epwFile metadata varsa dosya adı ile kontrol et
        if isfield(S,'epwFile')

            if local_same_epw_file_name(S.epwFile, epwFile)

                fprintf("Loading cached weather file: %s\n", cacheFile);

                weather = cachedWeather;

                return

            else

                fprintf("EPW file changed → rebuilding weather cache\n");

            end

        else

            % Eski cache formatı: epwFile metadata yok.
            % Cache dosyası zaten mevcut epw_name üzerinden oluşturulduğu için
            % taşınabilir kullanımda cache kabul edilir.
            fprintf("Loading cached weather file without epwFile metadata: %s\n", cacheFile);

            weather = cachedWeather;

            return

        end

    end

end

%% =========================================================================
% CACHE YOK → EPW OKU
% =========================================================================

fprintf("Weather cache not found → reading EPW file\n");

%% =========================================================================
% EPW DOSYASINI AÇ
% =========================================================================

fid = fopen(epwFile,'r','n','UTF-8');

if fid == -1
    error("EPW file could not be opened: %s", epwFile);
end

%% =========================================================================
% HEADER ATLAMA
% =========================================================================

for i = 1:8
    fgetl(fid);
end

%% =========================================================================
% EPW FORMAT TANIMI
% =========================================================================
%
% Önemli EPW kolonları:
%
% 7   DryBulb
% 9   RelativeHumidity
% 10  Pressure
% 13  GlobalHorizontalRadiation
% 14  DirectNormalRadiation
% 15  DiffuseHorizontalRadiation
% 20  WindDirection
% 21  WindSpeed
%

fmt = "%f%f%f%f%f%s%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%*[^\n]";

%% =========================================================================
% TEXTSCAN İLE EPW OKU
% =========================================================================

C = textscan(fid, fmt, 'Delimiter', ',', 'ReturnOnError', false);

fclose(fid);

%% =========================================================================
% DEĞİŞKENLERİ AYIR
% =========================================================================

Year   = C{1}(:);
Month  = C{2}(:);
Day    = C{3}(:);
Hour   = C{4}(:);
Minute = C{5}(:);
Flags  = string(C{6}(:));

Tdb_C  = C{7}(:);

RH_pct = C{9}(:);

Patm_Pa = C{10}(:);

GHI_Whm2 = C{13}(:);

DNI_Whm2 = C{14}(:);

DHI_Whm2 = C{15}(:);

WindDir_deg = C{20}(:);

WindSpd_ms  = C{21}(:);

%% =========================================================================
% PLAUSIBILITY FILTERS
% =========================================================================

Tdb_C(Tdb_C < -80 | Tdb_C > 80) = NaN;

RH_pct(RH_pct < 0 | RH_pct > 100) = NaN;

Patm_Pa(Patm_Pa < 5e4 | Patm_Pa > 1.2e5) = NaN;

WindSpd_ms(WindSpd_ms < 0 | WindSpd_ms > 60) = NaN;

WindDir_deg(WindDir_deg < 0 | WindDir_deg > 360) = NaN;

%% =========================================================================
% WET BULB HESABI
% =========================================================================

fprintf("Computing wet bulb temperature using PARFOR...\n");

N = numel(Tdb_C);

Twb_C = nan(N,1);

%% =========================================================================
% PARALLEL POOL KONTROL
% =========================================================================

if isempty(gcp('nocreate'))
    parpool;
end

%% =========================================================================
% PARFOR WETBULB HESABI
% =========================================================================

parfor i = 1:N

    if isnan(Tdb_C(i)) || isnan(RH_pct(i)) || isnan(Patm_Pa(i))

        Twb_C(i) = NaN;

    else

        T_K = Tdb_C(i) + 273.15;

        RH = RH_pct(i)/100;

        P  = Patm_Pa(i);

        try

            Twb_K = HAPropsSI('Twb','T',T_K,'P',P,'R',RH);

            Twb_C(i) = Twb_K - 273.15;

        catch

            Twb_C(i) = wetbulb_stull(Tdb_C(i), RH_pct(i));

        end

    end

end

%% =========================================================================
% WEATHER TABLE OLUŞTUR
% =========================================================================

weather = table();

weather.Year    = Year;
weather.Month   = Month;
weather.Day     = Day;
weather.Hour    = Hour;
weather.Minute  = Minute;
weather.Flags   = Flags;

weather.T_amb_C = Tdb_C;

weather.RH_pct  = RH_pct;

weather.Patm_Pa = Patm_Pa;

weather.T_wb_C  = Twb_C;

weather.GHI_Whm2 = GHI_Whm2;

weather.DNI_Whm2 = DNI_Whm2;

weather.DHI_Whm2 = DHI_Whm2;

weather.WindDir_deg = WindDir_deg;

weather.WindSpd_ms  = WindSpd_ms;

%% =========================================================================
% CACHE DOSYASI KAYDET
% =========================================================================

fprintf("Saving weather cache: %s\n", cacheFile);

save(char(cacheFile), 'weather', 'epwFile', '-v7');

fprintf("Weather cache created successfully\n");

end

%% =========================================================================
% LOCAL FUNCTION: PORTABLE EPW FILE CHECK
% =========================================================================

function tf = local_same_epw_file_name(cachedEpwFile, currentEpwFile)
% Sadece dosya adı + uzantı karşılaştırılır.
% Böylece cache başka klasöre kopyalansa bile aynı EPW dosyasına aitse
% tekrar kullanılabilir.

cachedEpwFile = char(cachedEpwFile);
currentEpwFile = char(currentEpwFile);

[~, cachedName, cachedExt] = fileparts(cachedEpwFile);
[~, currentName, currentExt] = fileparts(currentEpwFile);

cachedBase = [cachedName cachedExt];
currentBase = [currentName currentExt];

tf = strcmpi(cachedBase, currentBase);

end

%% =========================================================================
% STULL WETBULB APPROXIMATION
% =========================================================================

function Twb_C = wetbulb_stull(T_C, RH_pct)

RH = RH_pct;

Twb_C = T_C*atan(0.151977*sqrt(RH+8.313659)) + ...
        atan(T_C+RH) - atan(RH-1.676331) + ...
        0.00391838*(RH^(3/2))*atan(0.023101*RH) - 4.686035;

end
