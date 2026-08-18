%% CT_MANUAL_THERMAL_ANALYSIS
% Standalone manual cooling-tower analysis.
%
% This script does not call the system driver, ORC, preheater, storage, RO,
% or solar field. It reads only the selected hourly ambient-air conditions
% from the sibling Weather folder, then solves the cooling-tower model with
% the manually entered water-side inputs below. No result or figure file is
% saved.

clear all
clc

%% Manual inputs
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
weather_dir = fullfile(project_root,'Weather');
addpath(script_dir);
addpath(weather_dir);

manual = struct();
manual.show_waitbar = true;
manual.open_figure = true;

% Use one of:
%   'fixed_fan'     : run ct_offdesign_merkel at manual.fan_ratio
%   'target_outlet' : solve the minimum fan ratio for manual.T_w_out_target_C
manual.solve_mode = 'fixed_fan';

% Hour window. The same manual boundary conditions below are applied at the
% beginning of every hour in this window on the water side. Ambient air is
% read from the matching weather-file row for each hour.
manual.start_hour = 1;
manual.end_hour = 8760;
manual.use_zero_based_hours = false;    % false: hour 1 is the first weather row

manual.weather_epw_file = fullfile(weather_dir, ...
    'TUR_IC_Mersin.173400_TMYx.2009-2023.epw');

% Water-side operating inputs. Every input may be either scalar or a vector
% with the same length as the selected hour window.
manual.T_w_in_C = 33.0;               % Hot water entering tower [degC]
manual.mdot_water = 212.15;           % Circulating water mass flow [kg/s]
manual.fan_ratio = 1.0;               % Used by solve_mode = 'fixed_fan'
manual.T_w_out_target_C = 28.0;       % Used by solve_mode = 'target_outlet'

% Water-consumption assumptions for the standalone test.
manual.drift_fraction = 2e-5;
manual.cycles_of_concentration = 5;

% Rated tower basis. Leave fields empty to use ct_default_config defaults.
rating = struct();
% rating.Q_rated_W = 4.434e6;
% rating.T_db_rated_C = 35.0;
% rating.T_wb_rated_C = 24.0;
% rating.approach_rated_C = 4.0;
% rating.range_rated_C = 5.0;
% rating.mdot_water_rated = 212.15;
% rating.L_over_G_rated = 1.0;

%% Model setup
CTTimerTotal = tic;
WeatherData = localLoadWeather(manual.weather_epw_file);

CTConfig = ct_default_config();
CTConfig.water_consumption.drift_fraction = manual.drift_fraction;
CTConfig.water_consumption.cycles_of_concentration = manual.cycles_of_concentration;

CTDesign = ct_rate_design_point(rating,CTConfig);

%% Expand manual inputs
source_hour = (manual.start_hour:manual.end_hour).';
n_hours = numel(source_hour);
weather_row = localHourToWeatherRow(source_hour,manual.use_zero_based_hours,height(WeatherData));

T_db_C = WeatherData.T_amb_C(weather_row);
RH_pct = WeatherData.RH_pct(weather_row);
P_atm_Pa = WeatherData.Patm_Pa(weather_row);
if ismember('T_wb_C',WeatherData.Properties.VariableNames)
    T_wb_C = WeatherData.T_wb_C(weather_row);
else
    T_wb_C = nan(n_hours,1);
end

T_w_in_C = localExpandManualInput(manual.T_w_in_C,n_hours,'manual.T_w_in_C');
mdot_water = localExpandManualInput(manual.mdot_water,n_hours,'manual.mdot_water');
fan_ratio_input = localExpandManualInput(manual.fan_ratio,n_hours,'manual.fan_ratio');
T_w_out_target_C = localExpandManualInput(manual.T_w_out_target_C,n_hours,'manual.T_w_out_target_C');

%% Run manual hours
T_w_out_C = nan(n_hours,1);
Q_rejected_MW = nan(n_hours,1);
range_C = nan(n_hours,1);
approach_C = nan(n_hours,1);
fan_ratio = nan(n_hours,1);
W_fan_kW = nan(n_hours,1);
T_air_out_C = nan(n_hours,1);
omega_air_in = nan(n_hours,1);
omega_air_out = nan(n_hours,1);
mdot_evap_kg_s = nan(n_hours,1);
mdot_makeup_kg_s = nan(n_hours,1);
V_evap_m3_h = nan(n_hours,1);
V_makeup_m3_h = nan(n_hours,1);
Status = strings(n_hours,1);
WaterStatus = strings(n_hours,1);

CTManualResults = repmat(struct(),n_hours,1);

h_wait = localOpenWaitbar(manual);
waitbar_cleanup = onCleanup(@() localCloseWaitbar(h_wait));

for i = 1:n_hours
    localUpdateWaitbar(h_wait,i,n_hours,source_hour(i));

    CTAmbient = struct();
    CTAmbient.T_db_C = T_db_C(i);
    CTAmbient.P_atm_Pa = P_atm_Pa(i);
    if isfinite(T_wb_C(i))
        CTAmbient.T_wb_C = T_wb_C(i);
    else
        CTAmbient.RH_pct = RH_pct(i);
    end

    CTInput = struct();
    CTInput.T_w_in_C = T_w_in_C(i);
    CTInput.mdot_water = mdot_water(i);

    try
        if strcmpi(manual.solve_mode,'target_outlet')
            CTInput.T_w_out_target_C = T_w_out_target_C(i);
            CTOutput = ct_solve_fan_for_target(CTInput,CTAmbient,CTDesign,CTConfig);
        elseif strcmpi(manual.solve_mode,'fixed_fan')
            CTInput.fan_ratio = fan_ratio_input(i);
            CTOutput = ct_offdesign_merkel(CTInput,CTAmbient,CTDesign,CTConfig);
        else
            error('ctManual:UnknownSolveMode', ...
                'manual.solve_mode must be fixed_fan or target_outlet.');
        end

        T_w_out_C(i) = CTOutput.T_w_out_C;
        Q_rejected_MW(i) = CTOutput.Q_rejected_W/1e6;
        range_C(i) = CTOutput.range_C;
        approach_C(i) = CTOutput.approach_C;
        fan_ratio(i) = CTOutput.fan_ratio;
        W_fan_kW(i) = CTOutput.W_fan_W/1000;
        T_air_out_C(i) = CTOutput.T_air_out_C;
        omega_air_in(i) = CTOutput.omega_air_in;
        omega_air_out(i) = CTOutput.omega_air_out;
        mdot_evap_kg_s(i) = CTOutput.mdot_evap_kg_s;
        mdot_makeup_kg_s(i) = CTOutput.mdot_makeup_kg_s;
        V_evap_m3_h(i) = CTOutput.water_consumption.V_evap_m3_h;
        V_makeup_m3_h(i) = CTOutput.V_makeup_m3_h;
        Status(i) = string(CTOutput.status);
        WaterStatus(i) = string(CTOutput.water_consumption.status);

        CTManualResults(i).source_hour = source_hour(i);
        CTManualResults(i).ambient = CTAmbient;
        CTManualResults(i).input = CTInput;
        CTManualResults(i).output = CTOutput;
    catch ME
        Status(i) = "ERROR: " + string(ME.identifier);
        WaterStatus(i) = "NOT_SOLVED";
        CTManualResults(i).source_hour = source_hour(i);
        CTManualResults(i).ambient = CTAmbient;
        CTManualResults(i).input = CTInput;
        CTManualResults(i).error = ME;
    end
end

CTTiming = struct();
CTTiming.total_s = toc(CTTimerTotal);
CTTiming.n_hours = n_hours;
CTTiming.seconds_per_hour = CTTiming.total_s/max(n_hours,1);

CTManualSummary = table(source_hour,weather_row,T_db_C,RH_pct,T_wb_C,P_atm_Pa, ...
    T_w_in_C,mdot_water,fan_ratio_input,T_w_out_target_C, ...
    T_w_out_C,Q_rejected_MW,range_C,approach_C,fan_ratio,W_fan_kW, ...
    T_air_out_C,omega_air_in,omega_air_out,mdot_evap_kg_s,mdot_makeup_kg_s, ...
    V_evap_m3_h,V_makeup_m3_h,Status,WaterStatus);

localPrintSummary(CTManualSummary,manual,CTDesign,CTTiming);
localCloseWaitbar(h_wait);
clear waitbar_cleanup

if manual.open_figure
    localPlotManualResults(CTManualSummary,manual);
end

%% Local functions
function WeatherData = localLoadWeather(epw_file)
if ~isfile(epw_file)
    error('ctManual:WeatherMissing', ...
        'Weather EPW file was not found: %s',epw_file);
end

if exist('read_epw_weather','file') ~= 2
    error('ctManual:WeatherReaderMissing', ...
        'read_epw_weather.m was not found on the MATLAB path.');
end

WeatherData = read_epw_weather(epw_file);

required = {'T_amb_C','RH_pct','Patm_Pa'};
for k = 1:numel(required)
    if ~ismember(required{k},WeatherData.Properties.VariableNames)
        error('ctManual:WeatherColumnMissing', ...
            'Weather data is missing column %s.',required{k});
    end
end
end

function weather_row = localHourToWeatherRow(source_hour,use_zero_based,n_available)
if any(abs(source_hour - round(source_hour)) > 1e-9)
    error('ctManual:NonIntegerHour', ...
        'This standalone script expects integer hour inputs.');
end

if use_zero_based
    weather_row = round(source_hour) + 1;
else
    weather_row = round(source_hour);
end

if any(weather_row < 1) || any(weather_row > n_available)
    error('ctManual:HourWindowOutOfRange', ...
        ['Requested hour window is outside the available weather rows 1 to %d. ' ...
        'Use manual.use_zero_based_hours = false for 1:8760, or true for 0:8759.'], ...
        n_available);
end
end

function x = localExpandManualInput(x,n,name)
if isscalar(x)
    x = repmat(double(x),n,1);
else
    x = double(x(:));
end

if numel(x) ~= n
    error('ctManual:InputLengthMismatch', ...
        '%s must be scalar or have %d elements.',name,n);
end
end

function h_wait = localOpenWaitbar(manual)
h_wait = [];
if ~isfield(manual,'show_waitbar') || ~manual.show_waitbar || ~usejava('desktop')
    return
end

try
    h_wait = waitbar(0,'Starting manual cooling-tower analysis...', ...
        'Name','Manual cooling-tower analysis');
catch
    h_wait = [];
end
end

function localUpdateWaitbar(h_wait,i,n_hours,source_hour)
if isempty(h_wait) || ~ishandle(h_wait)
    return
end

msg = sprintf('Solving cooling-tower hour %.0f',source_hour);
waitbar(i/max(n_hours,1),h_wait,msg);
drawnow limitrate
end

function localCloseWaitbar(h_wait)
if ~isempty(h_wait) && ishandle(h_wait)
    close(h_wait);
end
end

function localPrintSummary(results,manual,CTDesign,CTTiming)
is_ok = results.Status == "OK" | results.Status == "TARGET_MET" | ...
    results.Status == "MIN_FAN_TARGET_MET" | results.Status == "APPROACH_LIMIT";

fprintf('\nManual cooling-tower analysis\n');
fprintf('Solve mode        : %s\n',manual.solve_mode);
fprintf('Hour count        : %d\n',height(results));
fprintf('Rated hot/cold    : %.2f / %.2f degC\n', ...
    CTDesign.T_w_in_rated_C,CTDesign.T_w_out_rated_C);
fprintf('Rated water flow  : %.3f kg/s\n',CTDesign.mdot_water_rated);
fprintf('Solved OK hours   : %d / %d\n',nnz(is_ok),height(results));

if any(is_ok)
    fprintf('Mean outlet temp  : %.3f degC over OK hours\n', ...
        mean(results.T_w_out_C(is_ok),'omitnan'));
    fprintf('Mean heat rejected: %.3f MW over OK hours\n', ...
        mean(results.Q_rejected_MW(is_ok),'omitnan'));
    fprintf('Mean fan power    : %.3f kW over OK hours\n', ...
        mean(results.W_fan_kW(is_ok),'omitnan'));
    fprintf('Mean makeup water : %.3f m3/h over OK hours\n', ...
        mean(results.V_makeup_m3_h(is_ok),'omitnan'));
else
    fprintf('No manually entered hours solved with an OK/target-met status.\n');
end

fprintf('Elapsed time      : %.3f s  (%.6f s/hour)\n', ...
    CTTiming.total_s,CTTiming.seconds_per_hour);
fprintf('\nWorkspace outputs : CTManualSummary, CTManualResults, CTConfig, CTDesign, CTTiming\n');
end

function localPlotManualResults(results,manual)
figure('Name','Manual cooling-tower analysis','Color','w');

tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(results.source_hour,results.T_w_in_C,'--','LineWidth',1.1);
hold on;
plot(results.source_hour,results.T_w_out_C,'LineWidth',1.8);
if strcmpi(manual.solve_mode,'target_outlet')
    plot(results.source_hour,results.T_w_out_target_C,':','LineWidth',1.4);
    legend({'Hot water in','Cold water out','Target'},'Location','best');
else
    legend({'Hot water in','Cold water out'},'Location','best');
end
grid on;
box on;
ylabel('Water temp [degC]');
title('Cooling-tower manual hourly test');

nexttile;
plot(results.source_hour,results.Q_rejected_MW,'LineWidth',1.8);
hold on;
plot(results.source_hour,results.W_fan_kW/1000,'LineWidth',1.4);
grid on;
box on;
ylabel('MW');
legend({'Heat rejected','Fan power'},'Location','best');

nexttile;
plot(results.source_hour,results.T_db_C,'LineWidth',1.5);
hold on;
plot(results.source_hour,results.T_wb_C,'LineWidth',1.8);
grid on;
box on;
xlabel('Manual hour');
ylabel('Air temp [degC]');
legend({'Dry bulb','Wet bulb'},'Location','best');

drawnow;
end
