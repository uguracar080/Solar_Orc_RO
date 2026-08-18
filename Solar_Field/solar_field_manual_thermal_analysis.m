%% SOLAR_FIELD_MANUAL_WATER_ANALYSIS
% Standalone manual PTC collector-group analysis.
%
% This script does not call the system driver, ORC, storage, RO, cooling
% tower, or the solar_field_ptc_v1 adapter. It only reads weather data from
% the Weather folder, solves the collector group hour by hour with the
% manual inputs below, and opens one figure. No result or figure file is
% saved.

clear all; 
clc;

%% Manual inputs
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);

manual = struct();
manual.start_hour = 1;
manual.end_hour = 8760;
manual.use_zero_based_hours = false;    % false: hour 1 is the first weather row
manual.show_waitbar = true;

manual.T_water_in_C = 20;           % Collector-group inlet water temp
manual.V_Lmin_1module = 56.8;           % Volumetric flow per collector module
manual.min_DNI_Wm2 = 50;
manual.min_useful_heat_W = 100;

manual.weather_cache_file = fullfile(project_root,'Weather', ...
    'TUR_IC_Mersin.173400_TMYx.2009-2023_weather_cache.mat');
manual.weather_epw_file = fullfile(project_root,'Weather', ...
    'TUR_IC_Mersin.173400_TMYx.2009-2023.epw');

% Current solar-field configuration used as the manual default.
field = struct();
field.N_series = 20;
field.N_parallel = 10;

% Current collector geometry and optical inputs used as the manual default.
ptc = struct();
ptc.W = 5.0;
ptc.L = 7.8;
ptc.Aa = 39.0;
ptc.Dri = 66e-3;
ptc.Dro = 70e-3;
ptc.Dci = 109e-3;
ptc.Dco = 115e-3;
ptc.eps_c = 0.86;
ptc.r_mirror = 0.83;
ptc.tau_cover = 0.95;
ptc.alpha_abs = 0.96;
ptc.gamma_int = 1.00;
ptc.K_theta = 1.00;

% Numerical inputs copied from the existing model.
model = struct();
model.Nusselt_multiplier = 1.0;
model.sigma = 5.670374e-8;

%% Run manual window
weather = localLoadWeatherOnly(manual.weather_cache_file,manual.weather_epw_file);
source_hour = (manual.start_hour:manual.end_hour).';
weather_row = localHourToWeatherRow(source_hour,manual.use_zero_based_hours,height(weather));

ptc = localFinalizePtc(ptc);
opts = localFsolveOptions();
n_hours = numel(source_hour);

T_water_in_C = repmat(manual.T_water_in_C,n_hours,1);
T_water_out_C = nan(n_hours,1);
DNI_Wm2 = nan(n_hours,1);
T_amb_C = nan(n_hours,1);
WindSpd_ms = nan(n_hours,1);
Q_useful_kW = zeros(n_hours,1);
mdot_water_kg_s = zeros(n_hours,1);
dP_field_kPa = zeros(n_hours,1);
status = strings(n_hours,1);

h_wait = localOpenWaitbar(manual);
waitbar_cleanup = onCleanup(@() localCloseWaitbar(h_wait));
for i = 1:n_hours
    wrow = weather_row(i);
    localUpdateWaitbar(h_wait,i,n_hours,source_hour(i));

    in = struct();
    in.DNI_Wm2 = weather.DNI_Whm2(wrow);
    in.T_amb_C = weather.T_amb_C(wrow);
    in.WindSpd_ms = weather.WindSpd_ms(wrow);
    in.T_water_in_K = manual.T_water_in_C + 273.15;
    in.V_Lmin_1module = manual.V_Lmin_1module;

    out = localSolveManualSolarHour(in,ptc,field,manual,model,opts);

    DNI_Wm2(i) = in.DNI_Wm2;
    T_amb_C(i) = in.T_amb_C;
    WindSpd_ms(i) = in.WindSpd_ms;
    T_water_out_C(i) = out.T_water_out_K - 273.15;
    Q_useful_kW(i) = out.Q_useful_W/1000;
    mdot_water_kg_s(i) = out.mdot_water_kg_s;
    dP_field_kPa(i) = out.dP_water_Pa/1000;
    status(i) = string(out.status);
end

ManualSolarResults = table(source_hour,weather_row,DNI_Wm2,T_amb_C,WindSpd_ms, ...
    T_water_in_C,T_water_out_C,Q_useful_kW,mdot_water_kg_s,dP_field_kPa,status);

localPrintSummary(ManualSolarResults,manual,field,ptc);
localCloseWaitbar(h_wait);
clear waitbar_cleanup
localPlotOutletTemperature(ManualSolarResults,manual,field);

%% Local functions
function weather = localLoadWeatherOnly(cache_file,epw_file)
if isfile(cache_file)
    S = load(cache_file);
    if isfield(S,'weather')
        weather = S.weather;
    elseif isfield(S,'WeatherData')
        weather = S.WeatherData;
    else
        error('manualSolar:WeatherCacheMissingTable', ...
            'Weather cache exists, but no weather table was found.');
    end
elseif isfile(epw_file)
    weather = localReadEpwWeatherMinimal(epw_file);
else
    error('manualSolar:WeatherMissing', ...
        'Weather cache or EPW file was not found.');
end

required = {'T_amb_C','DNI_Whm2','WindSpd_ms'};
for k = 1:numel(required)
    if ~ismember(required{k},weather.Properties.VariableNames)
        error('manualSolar:WeatherColumnMissing', ...
            'Weather data is missing column %s.',required{k});
    end
end
end

function weather = localReadEpwWeatherMinimal(epw_file)
fid = fopen(epw_file,'r','n','UTF-8');
if fid == -1
    error('manualSolar:EpwOpenFailed','EPW file could not be opened: %s',epw_file);
end
cleanup = onCleanup(@() fclose(fid));
for i = 1:8
    fgetl(fid);
end

fmt = '%f%f%f%f%f%s%f%f%f%f%f%f%f%f%f%f%f%f%f%f%f%*[^\n]';
C = textscan(fid,fmt,'Delimiter',',','ReturnOnError',false);

weather = table();
weather.Year = C{1}(:);
weather.Month = C{2}(:);
weather.Day = C{3}(:);
weather.Hour = C{4}(:);
weather.Minute = C{5}(:);
weather.Flags = string(C{6}(:));
weather.T_amb_C = C{7}(:);
weather.RH_pct = C{9}(:);
weather.Patm_Pa = C{10}(:);
weather.GHI_Whm2 = C{13}(:);
weather.DNI_Whm2 = C{14}(:);
weather.DHI_Whm2 = C{15}(:);
weather.WindDir_deg = C{20}(:);
weather.WindSpd_ms = C{21}(:);
end

function weather_row = localHourToWeatherRow(source_hour,use_zero_based,n_available)
if use_zero_based
    weather_row = round(source_hour) + 1;
else
    weather_row = round(source_hour);
end

if any(abs(source_hour - round(source_hour)) > 1e-9)
    error('manualSolar:NonIntegerHour', ...
        'This standalone script expects integer hour inputs.');
end

if any(weather_row < 1) || any(weather_row > n_available)
    error('manualSolar:HourWindowOutOfRange', ...
        ['Requested hour window is outside the available weather rows 1 to %d. ' ...
        'Use manual.use_zero_based_hours = false for 1:8760, or true for 0:8759.'], ...
        n_available);
end
end

function h_wait = localOpenWaitbar(manual)
h_wait = [];
if ~isfield(manual,'show_waitbar') || ~manual.show_waitbar || ~usejava('desktop')
    return
end

try
    h_wait = waitbar(0,'Starting manual solar-field analysis...', ...
        'Name','Manual solar-field analysis');
    waitbar(0,h_wait,'Simulating hour ...');
catch
    h_wait = [];
end
end

function localUpdateWaitbar(h_wait,i,n_hours,source_hour)
if isempty(h_wait) || ~ishandle(h_wait)
    return
end

msg = sprintf('Simulating hour %.0f',source_hour);
waitbar(i/max(n_hours,1),h_wait,msg);
drawnow limitrate
end

function localCloseWaitbar(h_wait)
if ~isempty(h_wait) && ishandle(h_wait)
    close(h_wait);
end
end

function ptc = localFinalizePtc(ptc)
ptc.eta_opt = ptc.r_mirror * ptc.tau_cover * ptc.alpha_abs * ...
    ptc.gamma_int * ptc.K_theta;
ptc.Ari = pi*ptc.Dri*ptc.L;
ptc.Aro = pi*ptc.Dro*ptc.L;
ptc.Aci = pi*ptc.Dci*ptc.L;
ptc.Aco = pi*ptc.Dco*ptc.L;
end

function opts = localFsolveOptions()
if exist('fsolve','file') ~= 2
    error('manualSolar:FsolveMissing', ...
        'This copied collector model requires fsolve.');
end

if exist('optimoptions','file') == 2
    opts = optimoptions('fsolve','Display','none', ...
        'FunctionTolerance',1e-10,'StepTolerance',1e-10);
else
    opts = optimset('Display','off','TolFun',1e-10,'TolX',1e-10);
end
end

function out = localSolveManualSolarHour(in,ptc,field,manual,model,opts)
out = struct();
out.T_water_in_K = in.T_water_in_K;
out.T_water_out_K = in.T_water_in_K;
out.mdot_water_kg_s = 0;
out.Q_useful_W = 0;
out.dP_water_Pa = 0;
out.status = 'SOLAR_OFF';

if in.DNI_Wm2 < manual.min_DNI_Wm2 || isnan(in.DNI_Wm2)
    return
end

try
    field_out = localSolveFieldSeriesParallel(in,ptc,field, ...
        model.Nusselt_multiplier,model.sigma,opts);

    out.T_water_out_K = field_out.T_water_out_K;
    out.mdot_water_kg_s = field_out.mdot_water_kg_s;
    out.Q_useful_W = max(0,field_out.Qu_total_W);
    out.dP_water_Pa = field_out.dP_water_Pa;
    if out.Q_useful_W > manual.min_useful_heat_W
        out.status = 'OK';
    else
        out.status = 'LOW_USEFUL_HEAT';
    end
catch ME
    out.status = ['ERROR: ' ME.identifier];
end
end

function field_out = localSolveFieldSeriesParallel(in,ptc,field,R,sigma,opts)
Tin_string_K = in.T_water_in_K;
Tin_now_K = Tin_string_K;
Qu_string_W = 0;
dP_string_Pa = 0;
Tout_last_K = Tin_now_K;
x0_prev = [];
last_module = struct('mdot_kg_s',0);

for k = 1:field.N_series
    module_in = struct();
    module_in.Gb = in.DNI_Wm2;
    module_in.Vwind = max(in.WindSpd_ms,0.1);
    module_in.Tam = in.T_amb_C + 273.15;
    module_in.Tin = Tin_now_K;
    module_in.V_Lmin = in.V_Lmin_1module;

    if isempty(x0_prev)
        x0_use = [];
    else
        x0_use = x0_prev;
        x0_use(1) = max(x0_use(1),module_in.Tin);
        x0_use(3) = max(x0_use(3),module_in.Tin + 0.5);
        x0_use(2) = min(max(x0_use(2),module_in.Tam),x0_use(1));
    end

    last_module = localSolveSingleModule(module_in,ptc,R,sigma,opts,x0_use);
    Tin_now_K = last_module.Tout_K;
    Tout_last_K = last_module.Tout_K;
    Qu_string_W = Qu_string_W + last_module.Qu_W;
    dP_string_Pa = dP_string_Pa + last_module.dP_abs_Pa;
    x0_prev = [last_module.Tr_K; last_module.Tc_K; last_module.Tout_K];
end

field_out = struct();
field_out.T_water_in_K = Tin_string_K;
field_out.T_water_out_K = Tout_last_K;
field_out.mdot_water_kg_s = field.N_parallel * last_module.mdot_kg_s;
field_out.Qu_total_W = field.N_parallel * Qu_string_W;
field_out.dP_water_Pa = dP_string_Pa;
field_out.Aa_total_m2 = ptc.Aa * field.N_series * field.N_parallel;
end

function out = localSolveSingleModule(in,ptc,R,sigma,opts,x0_in)
if nargin < 6 || isempty(x0_in)
    x0 = [in.Tin + 40; in.Tam + 20; in.Tin + 20];
else
    x0 = x0_in(:);
    x0(1) = max(x0(1),in.Tin);
    x0(3) = max(x0(3),in.Tin + 0.5);
    x0(2) = min(max(x0(2),in.Tam),x0(1));
end

f = @(x) localResidualsPtcWater(x,in.Gb,in.Vwind,in.Tam,in.Tin, ...
    in.V_Lmin,R,ptc,sigma);
[x,~,exitflag] = fsolve(f,x0,opts);
if exitflag <= 0
    x0_fallback = [in.Tin + 40; in.Tam + 20; in.Tin + 20];
    x = fsolve(f,x0_fallback,opts);
end

Tr = x(1);
Tc = x(2);
Tout = x(3);

Tfm = 0.5*(in.Tin + Tout);
[rho,cp,k,mu] = localWaterProps(Tfm);
V_m3s = in.V_Lmin*1e-3/60;
mdot = rho*V_m3s;
Re = 4*mdot/(pi*ptc.Dri*mu);
Pr = mu*cp/k;
Nu0 = 0.023*(Re^0.8)*(Pr^0.4);
Nu = R*Nu0;
h = Nu*k/ptc.Dri;
Qs = ptc.Aa*in.Gb;
Qabs = Qs*ptc.eta_opt;
Qu = mdot*cp*(Tout - in.Tin);
Aflow = pi*(ptc.Dri^2)/4;
u = mdot/(rho*Aflow);
fr = 1/((0.79*log(Re) - 1.64)^2);
dP = fr*(ptc.L/ptc.Dri)*(0.5*rho*u^2);

out = struct();
out.Tout_K = Tout;
out.Tr_K = Tr;
out.Tc_K = Tc;
out.mdot_kg_s = mdot;
out.Qu_W = Qu;
out.Qabs_W = Qabs;
out.Re = Re;
out.dP_abs_Pa = dP;
out.h_i_Wm2K = h;
end

function F = localResidualsPtcWater(x,Gb,Vwind,Tam,Tin,V_Lmin,R,ptc,sigma)
Tr = x(1);
Tc = x(2);
Tout = x(3);

Tfm = 0.5*(Tin + Tout);
[rho,cp,k,mu] = localWaterProps(Tfm);

V_m3s = V_Lmin*1e-3/60;
mdot = rho*V_m3s;
Re = 4*mdot/(pi*ptc.Dri*mu);
Pr = mu*cp/k;
Nu0 = 0.023*(Re^0.8)*(Pr^0.4);
Nu = R*Nu0;
h = Nu*k/ptc.Dri;

Qs = ptc.Aa*Gb;
Qabs = Qs*ptc.eta_opt;
Qu = mdot*cp*(Tout - Tin);

eps_r = 0.05599 + 1.039e-4*Tr + 2.249e-7*(Tr^2);
Tsky = 0.0553*(Tam^1.5);
hout = 4*(Vwind^0.58)*(ptc.Dco^(-0.42));

denom = (1/eps_r) + ((1 - ptc.eps_c)/ptc.eps_c)*(ptc.Aro/ptc.Aci);
QlossR2C = ptc.Aro*sigma*(Tr^4 - Tc^4)/denom;
QlossC2A = ptc.Aco*hout*(Tc - Tam) + ...
    ptc.Aco*sigma*ptc.eps_c*(Tc^4 - Tsky^4);
QuConv = h*ptc.Ari*(Tr - Tfm);

F = zeros(3,1);
F(1) = QlossR2C - QlossC2A;
F(2) = Qu - QuConv;
F(3) = Qabs - Qu - QlossR2C;
end

function [rho,cp,k,mu] = localWaterProps(TK)
TC = TK - 273.15;
data = [ ...
      0 4217 999.8 0.561 1.792
     10 4192 999.7 0.580 1.307
     20 4182 998.2 0.598 1.002
     30 4179 995.7 0.615 0.798
     40 4179 992.2 0.631 0.653
     50 4181 988.1 0.643 0.547
     60 4185 983.2 0.654 0.466
     70 4190 977.8 0.663 0.404
     80 4197 971.8 0.670 0.355
     90 4205 965.3 0.676 0.315
    100 4217 958.4 0.679 0.282
    110 4230 951.0 0.682 0.255
    120 4245 943.1 0.685 0.232
    130 4263 934.6 0.686 0.213
    140 4283 925.6 0.686 0.197
    150 4307 916.0 0.685 0.183
    160 4334 905.8 0.683 0.170
    170 4365 895.0 0.679 0.160
    180 4400 883.6 0.675 0.150
    190 4439 871.6 0.670 0.142
    200 4484 858.9 0.663 0.134
];

T = data(:,1);
rho = interp1(T,data(:,3),TC,'linear','extrap');
cp = interp1(T,data(:,2),TC,'linear','extrap');
k = interp1(T,data(:,4),TC,'linear','extrap');
mu = interp1(T,data(:,5),TC,'linear','extrap')*1e-3;
end

function localPrintSummary(results,manual,field,ptc)
is_ok = results.status == "OK";
fprintf('\nManual solar-field water analysis\n');
fprintf('Hour window       : %g to %g h\n',manual.start_hour,manual.end_hour);
fprintf('Collector field   : %d series x %d parallel\n',field.N_series,field.N_parallel);
fprintf('Aperture area     : %.1f m2\n',ptc.Aa*field.N_series*field.N_parallel);
fprintf('Inlet water temp  : %.2f degC\n',manual.T_water_in_C);
fprintf('Flow per module   : %.2f L/min\n',manual.V_Lmin_1module);
fprintf('Sunny solved hours: %d / %d\n',nnz(is_ok),height(results));

if any(is_ok)
    fprintf('Max outlet temp   : %.2f degC at hour %.0f\n', ...
        max(results.T_water_out_C(is_ok)), ...
        results.source_hour(find(results.T_water_out_C == max(results.T_water_out_C(is_ok)),1,'first')));
    fprintf('Mean outlet temp  : %.2f degC over OK hours\n', ...
        mean(results.T_water_out_C(is_ok),'omitnan'));
    fprintf('Mean useful heat  : %.2f kW over OK hours\n', ...
        mean(results.Q_useful_kW(is_ok),'omitnan'));
else
    fprintf('No hours exceeded the DNI/useful-heat thresholds.\n');
end
end

function localPlotOutletTemperature(results,manual,field)
figure('Name','Manual PTC water outlet temperature','Color','w');
plot(results.source_hour,results.T_water_out_C,'LineWidth',1.8);
hold on;
plot(results.source_hour,results.T_water_in_C,'--','LineWidth',1.1);
grid on;
box on;
xlabel('Year hour');
ylabel('Water temperature [degC]');
title(sprintf('Collector-group outlet water temperature, hours %g-%g', ...
    manual.start_hour,manual.end_hour));
legend({'Outlet','Inlet'},'Location','best');

is_ok = results.status == "OK";
if any(is_ok)
    mean_useful_heat_kW = mean(results.Q_useful_kW(is_ok),'omitnan');
    summary_text = sprintf(['Series collectors: %d\nParallel collectors: %d\n' ...
        'Mean useful heat: %.2f kW'], ...
        field.N_series,field.N_parallel,mean_useful_heat_kW);
else
    summary_text = sprintf(['Series collectors: %d\nParallel collectors: %d\n' ...
        'Mean useful heat: N/A'],field.N_series,field.N_parallel);
end

annotation('textbox',[0.64 0.70 0.25 0.16], ...
    'String',summary_text, ...
    'FitBoxToText','on', ...
    'BackgroundColor','w', ...
    'EdgeColor',[0.3 0.3 0.3], ...
    'Margin',8);
drawnow;
end
