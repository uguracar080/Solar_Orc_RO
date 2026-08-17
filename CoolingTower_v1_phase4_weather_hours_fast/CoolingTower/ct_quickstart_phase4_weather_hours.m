%% CT_QUICKSTART_PHASE4_WEATHER_HOURS
% Phase-4 weather-hour smoke test using the sibling Weather folder.
%
% Expected project layout:
%   Project/
%     Weather/
%       read_epw_weather.m
%       HAPropsSI.m
%       TUR_IC_Mersin.173400_TMYx.2009-2023.epw
%       TUR_IC_Mersin.173400_TMYx.2009-2023_weather_cache.mat  (created/used by read_epw_weather)
%     CoolingTower/
%       ct_quickstart_phase4_weather_hours.m
%
% This script does not copy weather data into CoolingTower. It finds the
% shared project Weather folder, calls read_epw_weather(epwFile) once, and
% then passes only hourly CTAmbient structures to the CT model.
%
% WHERE TO CHANGE THE WEATHER FILE NAME:
%   Edit CTWeatherEPWFileName below.

clearvars -except ProjectConfig WeatherData
clc

CTTimerTotal = tic;

%% ------------------------------------------------------------------------
% USER-EDITABLE WEATHER FILE NAME
% -------------------------------------------------------------------------
% Write the EPW file name here. The file must be inside the sibling Weather
% folder. The cache file is NOT written here; read_epw_weather automatically
% looks for the matching *_weather_cache.mat in the same Weather folder.
CTWeatherEPWFileName = 'TUR_IC_Mersin.173400_TMYx.2009-2023.epw';

%% ------------------------------------------------------------------------
% Locate project folders from this script location
% -------------------------------------------------------------------------
CTTimerInit = tic;
CTThisDir = fileparts(mfilename('fullpath'));
CTProjectRoot = fileparts(CTThisDir);
CTWeatherDir = fullfile(CTProjectRoot,'Weather');

addpath(CTThisDir);
addpath(CTWeatherDir);
CTTiming.initialization_s = toc(CTTimerInit);

fprintf('\nCooling Tower v1 - Phase 4 weather-hour quickstart\n');
fprintf('Weather folder: %s\n',CTWeatherDir);
fprintf('Weather EPW   : %s\n',CTWeatherEPWFileName);

CTWeatherEPWFile = fullfile(CTWeatherDir,CTWeatherEPWFileName);

if ~isfile(CTWeatherEPWFile)
    error(['EPW file not found:\n  %s\n\n' ...
           'Put the EPW file in the Weather folder or edit CTWeatherEPWFileName at the top of this script.'], ...
           CTWeatherEPWFile);
end

% read_epw_weather handles the cache by itself:
%   1) if *_weather_cache.mat exists and matches this EPW file name, it loads it;
%   2) otherwise it reads the EPW and creates the cache.
CTTimerWeather = tic;
WeatherData = read_epw_weather(CTWeatherEPWFile);
CTTiming.weather_load_s = toc(CTTimerWeather);
fprintf('Rows loaded   : %d\n',height(WeatherData));

%% ------------------------------------------------------------------------
% CT model setup
% -------------------------------------------------------------------------
CTTimerSetup = tic;
CTConfig = ct_default_config();
CTConfig.water_consumption.drift_fraction = 2e-5;
CTConfig.water_consumption.cycles_of_concentration = 5;

CTDesign = ct_rate_design_point(struct(),CTConfig);
CTTiming.model_setup_s = toc(CTTimerSetup);

%% ------------------------------------------------------------------------
% Select representative hours automatically from WeatherData
% -------------------------------------------------------------------------
CTTimerSelect = tic;
CTWeatherCases = ct_select_weather_test_hours(WeatherData,CTDesign);
CTTiming.weather_selection_s = toc(CTTimerSelect);

fprintf('\nSelected representative weather hours:\n');
disp(CTWeatherCases(:,{'Label','WeatherRow','Month','Day','Hour','T_db_C','T_wb_C','WB_depression_C','RH_pct','P_atm_kPa'}));

%% ------------------------------------------------------------------------
% Run fixed tower at selected hours
% -------------------------------------------------------------------------
CTTimerLoop = tic;

nCases = height(CTWeatherCases);
Label = strings(nCases,1);
WeatherRow = nan(nCases,1);
Month = nan(nCases,1);
Day = nan(nCases,1);
Hour = nan(nCases,1);
Tdb = nan(nCases,1);
Twb = nan(nCases,1);
RH = nan(nCases,1);

Full_TwOut_C = nan(nCases,1);
Full_Q_MW = nan(nCases,1);
Full_Approach_C = nan(nCases,1);
Full_Evap_m3h = nan(nCases,1);
Full_Makeup_m3h = nan(nCases,1);
Full_Status = strings(nCases,1);

Target_TwOut_C = nan(nCases,1);
Target_FanRatio = nan(nCases,1);
Target_Wfan_kW = nan(nCases,1);
Target_Q_MW = nan(nCases,1);
Target_Evap_m3h = nan(nCases,1);
Target_Makeup_m3h = nan(nCases,1);
Target_Status = strings(nCases,1);

CTWeatherResults = repmat(struct(),nCases,1);
CTCaseTiming = table('Size',[nCases 4], ...
    'VariableTypes',{'string','double','double','double'}, ...
    'VariableNames',{'Label','FullFan_s','TargetSolve_s','TotalCase_s'});

for k = 1:nCases
    CTTimerCase = tic;
    irow = CTWeatherCases.WeatherRow(k);

    CTAmbient = struct();
    CTAmbient.T_db_C = WeatherData.T_amb_C(irow);
    CTAmbient.T_wb_C = WeatherData.T_wb_C(irow);
    CTAmbient.RH_pct = WeatherData.RH_pct(irow);
    CTAmbient.P_atm_Pa = WeatherData.Patm_Pa(irow);

    CTInputFull = struct();
    CTInputFull.T_w_in_C = CTDesign.T_w_in_rated_C;
    CTInputFull.mdot_water = CTDesign.mdot_water_rated;
    CTInputFull.fan_ratio = 1.0;

    CTTimerFullFan = tic;
    CTOutputFull = ct_offdesign_merkel(CTInputFull,CTAmbient,CTDesign,CTConfig);
    CTCaseTiming.FullFan_s(k) = toc(CTTimerFullFan);

    CTInputTarget = CTInputFull;
    CTInputTarget.T_w_out_target_C = CTDesign.T_w_out_rated_C;

    CTTimerTarget = tic;
    CTOutputTarget = ct_solve_fan_for_target(CTInputTarget,CTAmbient,CTDesign,CTConfig);
    CTCaseTiming.TargetSolve_s(k) = toc(CTTimerTarget);

    Label(k) = CTWeatherCases.Label(k);
    WeatherRow(k) = irow;
    Month(k) = CTWeatherCases.Month(k);
    Day(k) = CTWeatherCases.Day(k);
    Hour(k) = CTWeatherCases.Hour(k);
    Tdb(k) = CTAmbient.T_db_C;
    Twb(k) = CTAmbient.T_wb_C;
    RH(k) = CTAmbient.RH_pct;

    Full_TwOut_C(k) = CTOutputFull.T_w_out_C;
    Full_Q_MW(k) = CTOutputFull.Q_rejected_W/1e6;
    Full_Approach_C(k) = CTOutputFull.approach_C;
    Full_Evap_m3h(k) = CTOutputFull.water_consumption.V_evap_m3_h;
    Full_Makeup_m3h(k) = CTOutputFull.water_consumption.V_makeup_m3_h;
    Full_Status(k) = string(CTOutputFull.status);

    Target_TwOut_C(k) = CTOutputTarget.T_w_out_C;
    Target_FanRatio(k) = CTOutputTarget.fan_ratio;
    Target_Wfan_kW(k) = CTOutputTarget.W_fan_W/1000;
    Target_Q_MW(k) = CTOutputTarget.Q_rejected_W/1e6;
    Target_Evap_m3h(k) = CTOutputTarget.water_consumption.V_evap_m3_h;
    Target_Makeup_m3h(k) = CTOutputTarget.water_consumption.V_makeup_m3_h;
    Target_Status(k) = string(CTOutputTarget.status);

    CTWeatherResults(k).label = Label(k);
    CTWeatherResults(k).row = irow;
    CTWeatherResults(k).ambient = CTAmbient;
    CTWeatherResults(k).full_fan = CTOutputFull;
    CTWeatherResults(k).target = CTOutputTarget;

    CTCaseTiming.Label(k) = Label(k);
    CTCaseTiming.TotalCase_s(k) = toc(CTTimerCase);
end

CTTiming.ct_selected_hour_loop_s = toc(CTTimerLoop);

CTWeatherSummary = table(Label,WeatherRow,Month,Day,Hour,Tdb,Twb,RH, ...
    Full_TwOut_C,Full_Q_MW,Full_Approach_C,Full_Evap_m3h,Full_Makeup_m3h,Full_Status, ...
    Target_TwOut_C,Target_FanRatio,Target_Wfan_kW,Target_Q_MW,Target_Evap_m3h,Target_Makeup_m3h,Target_Status);

fprintf('\nCooling tower results for selected weather hours:\n');
disp(CTWeatherSummary);

fprintf('\nPer-case timing:\n');
disp(CTCaseTiming);

CTTiming.total_s = toc(CTTimerTotal);
CTTiming.n_cases = nCases;
CTTiming.seconds_per_case = CTTiming.ct_selected_hour_loop_s / max(nCases,1);
CTTiming.cases_per_second = max(nCases,1) / max(CTTiming.ct_selected_hour_loop_s,eps);

fprintf('\nTiming:\n');
fprintf('  Initialization          : %.3f s\n',CTTiming.initialization_s);
fprintf('  Weather load/cache      : %.3f s\n',CTTiming.weather_load_s);
fprintf('  CT model setup          : %.3f s\n',CTTiming.model_setup_s);
fprintf('  Weather-hour selection  : %.3f s\n',CTTiming.weather_selection_s);
fprintf('  CT selected-hour loop   : %.3f s\n',CTTiming.ct_selected_hour_loop_s);
fprintf('  Seconds per case        : %.6f s/case\n',CTTiming.seconds_per_case);
fprintf('  Cases per second        : %.2f case/s\n',CTTiming.cases_per_second);
fprintf('  Total elapsed time      : %.3f s\n',CTTiming.total_s);

fprintf('\nNotes:\n');
fprintf('  * Full-fan columns show fixed tower performance at fan_ratio = 1.\n');
fprintf('  * Target columns try to reach T_w_out_target = %.2f C with minimum fan.\n',CTDesign.T_w_out_rated_C);
fprintf('  * AIRFLOW_LIMIT_TARGET_NOT_MET means the fixed tower cannot reach the target at that weather hour.\n');
fprintf('  * WeatherData stays in the shared Weather layer; CT receives only hourly CTAmbient values.\n');
fprintf('  * CTTiming and CTCaseTiming remain in the workspace for runtime checks.\n');

fprintf('\nPhase 4 complete. Next milestone: ORC/preheater/CT coupling interface.\n');
