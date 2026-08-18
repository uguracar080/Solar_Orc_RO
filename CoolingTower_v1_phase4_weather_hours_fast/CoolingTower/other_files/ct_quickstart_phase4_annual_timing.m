%% CT_QUICKSTART_PHASE4_ANNUAL_TIMING
% Optional Phase-4 annual timing smoke test using all WeatherData rows.
%
% This script measures the cost of running the CT target-fan controller over
% the full weather file. It is intentionally separate from the selected-hour
% quickstart because it may take longer.
%
% WHERE TO CHANGE THE WEATHER FILE NAME:
%   Edit CTWeatherEPWFileName below.

clearvars -except ProjectConfig WeatherData
clc

CTTimerTotal = tic;

%% User-editable weather file name
CTWeatherEPWFileName = 'TUR_IC_Mersin.173400_TMYx.2009-2023.epw';

%% Locate project folders
CTTimerInit = tic;
CTThisDir = fileparts(mfilename('fullpath'));
CTProjectRoot = fileparts(CTThisDir);
CTWeatherDir = fullfile(CTProjectRoot,'Weather');
addpath(CTThisDir);
addpath(CTWeatherDir);
CTTiming.initialization_s = toc(CTTimerInit);

fprintf('\nCooling Tower v1 - Phase 4 annual timing quickstart\n');
fprintf('Weather folder: %s\n',CTWeatherDir);
fprintf('Weather EPW   : %s\n',CTWeatherEPWFileName);

CTWeatherEPWFile = fullfile(CTWeatherDir,CTWeatherEPWFileName);
if ~isfile(CTWeatherEPWFile)
    error(['EPW file not found:\n  %s\n\n' ...
           'Put the EPW file in the Weather folder or edit CTWeatherEPWFileName at the top of this script.'], ...
           CTWeatherEPWFile);
end

%% Load weather
CTTimerWeather = tic;
WeatherData = read_epw_weather(CTWeatherEPWFile);
CTTiming.weather_load_s = toc(CTTimerWeather);
N = height(WeatherData);
fprintf('Rows loaded   : %d\n',N);

%% Build CT design
CTTimerSetup = tic;
CTConfig = ct_default_config();
CTConfig.water_consumption.drift_fraction = 2e-5;
CTConfig.water_consumption.cycles_of_concentration = 5;
CTDesign = ct_rate_design_point(struct(),CTConfig);
CTTiming.model_setup_s = toc(CTTimerSetup);

%% Preallocate annual arrays
T_w_out_C = nan(N,1);
fan_ratio = nan(N,1);
W_fan_kW = nan(N,1);
Q_rejected_MW = nan(N,1);
V_evap_m3_h = nan(N,1);
V_makeup_m3_h = nan(N,1);
status = strings(N,1);

%% Annual target-fan loop
CTTimerAnnual = tic;
for t = 1:N
    CTAmbient = struct();
    CTAmbient.T_db_C = WeatherData.T_amb_C(t);
    CTAmbient.T_wb_C = WeatherData.T_wb_C(t);
    CTAmbient.RH_pct = WeatherData.RH_pct(t);
    CTAmbient.P_atm_Pa = WeatherData.Patm_Pa(t);

    CTInput = struct();
    CTInput.T_w_in_C = CTDesign.T_w_in_rated_C;
    CTInput.mdot_water = CTDesign.mdot_water_rated;
    CTInput.fan_ratio = 1.0;
    CTInput.T_w_out_target_C = CTDesign.T_w_out_rated_C;

    CTOutput = ct_solve_fan_for_target(CTInput,CTAmbient,CTDesign,CTConfig);

    T_w_out_C(t) = CTOutput.T_w_out_C;
    fan_ratio(t) = CTOutput.fan_ratio;
    W_fan_kW(t) = CTOutput.W_fan_W/1000;
    Q_rejected_MW(t) = CTOutput.Q_rejected_W/1e6;
    V_evap_m3_h(t) = CTOutput.water_consumption.V_evap_m3_h;
    V_makeup_m3_h(t) = CTOutput.water_consumption.V_makeup_m3_h;
    status(t) = string(CTOutput.status);
end
CTTiming.annual_loop_s = toc(CTTimerAnnual);

%% Summary
CTAnnualSummary = table(T_w_out_C,fan_ratio,W_fan_kW,Q_rejected_MW,V_evap_m3_h,V_makeup_m3_h,status);

CTTiming.total_s = toc(CTTimerTotal);
CTTiming.n_hours = N;
CTTiming.seconds_per_hour = CTTiming.annual_loop_s / max(N,1);
CTTiming.hours_per_second = max(N,1) / max(CTTiming.annual_loop_s,eps);

fprintf('\nAnnual CT timing summary:\n');
fprintf('  Simulated hours         : %d\n',CTTiming.n_hours);
fprintf('  Annual CT loop          : %.3f s\n',CTTiming.annual_loop_s);
fprintf('  Seconds per hour        : %.6f s/hour\n',CTTiming.seconds_per_hour);
fprintf('  Simulated hours/second  : %.1f h/s\n',CTTiming.hours_per_second);
fprintf('  Total elapsed time      : %.3f s\n',CTTiming.total_s);

fprintf('\nAnnual CT result summary:\n');
fprintf('  Mean fan ratio          : %.4f\n',mean(fan_ratio,'omitnan'));
fprintf('  Mean fan power          : %.3f kW\n',mean(W_fan_kW,'omitnan'));
fprintf('  Annual fan energy       : %.3f MWh\n',sum(W_fan_kW,'omitnan')/1000);
fprintf('  Annual evap water       : %.1f m3/year\n',sum(V_evap_m3_h,'omitnan'));
fprintf('  Annual makeup water     : %.1f m3/year\n',sum(V_makeup_m3_h,'omitnan'));
fprintf('  Target-not-met hours    : %d\n',sum(status=="AIRFLOW_LIMIT_TARGET_NOT_MET"));

fprintf('\nCTAnnualSummary and CTTiming remain in the workspace.\n');
fprintf('Phase 4 annual timing complete.\n');
