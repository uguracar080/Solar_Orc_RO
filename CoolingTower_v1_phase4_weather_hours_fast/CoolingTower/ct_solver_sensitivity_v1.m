function Summary = ct_solver_sensitivity_v1(ProjectRoot,startHour,nHours,fastIntervals,fastTolC)
%CT_SOLVER_SENSITIVITY_V1 Compare CT Merkel/fan-solve numerics.

if nargin < 1 || isempty(ProjectRoot)
    ProjectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
if nargin < 2 || isempty(startHour)
    startHour = 770;
end
if nargin < 3 || isempty(nHours)
    nHours = 48;
end
if nargin < 4 || isempty(fastIntervals)
    fastIntervals = 50;
end
if nargin < 5 || isempty(fastTolC)
    fastTolC = 0.02;
end

system_paths_v1(ProjectRoot);
cfg = system_config_v1(ProjectRoot);
WeatherData = localLoadWeather(cfg);
idx = (startHour + 1):(startHour + nHours);
if max(idx) > height(WeatherData)
    error('ct_solver_sensitivity_v1:WindowOutOfRange', ...
        'Requested hours exceed available weather rows.');
end
WeatherWindow = WeatherData(idx,:);

strictCfg = localBuildCTConfig(cfg,100,1e-4);
fastCfg = localBuildCTConfig(cfg,fastIntervals,fastTolC);
CTDesign = ct_rate_design_point(struct(),strictCfg);

Ttarget = cfg.ct.T_cw_target_C;
TinC = Ttarget + strictCfg.rating.range_rated_C;
mdotWater = cfg.orc.mdot_cw_design_kg_s;

strict = localRunCase(WeatherWindow,strictCfg,CTDesign,TinC,Ttarget,mdotWater);
fast = localRunCase(WeatherWindow,fastCfg,CTDesign,TinC,Ttarget,mdotWater);

dT = fast.T_w_out_C - strict.T_w_out_C;
dFan = fast.fan_ratio - strict.fan_ratio;
dW = fast.W_fan_W - strict.W_fan_W;
dQ = fast.Q_rejected_W - strict.Q_rejected_W;

Summary = struct();
Summary.startHour = startHour;
Summary.nHours = nHours;
Summary.T_w_in_C = TinC;
Summary.T_w_out_target_C = Ttarget;
Summary.strict_intervals = 100;
Summary.fast_intervals = fastIntervals;
Summary.strict_target_tol_C = 1e-4;
Summary.fast_target_tol_C = fastTolC;
Summary.strict_runtime_s = strict.runtime_s;
Summary.fast_runtime_s = fast.runtime_s;
Summary.speedup = strict.runtime_s/max(fast.runtime_s,eps);
Summary.solved_hours = sum(strict.solved | fast.solved);
Summary.max_abs_T_w_out_C = max(abs(dT),[],'omitnan');
Summary.mean_abs_T_w_out_C = mean(abs(dT),'omitnan');
Summary.max_abs_fan_ratio = max(abs(dFan),[],'omitnan');
Summary.mean_abs_fan_ratio = mean(abs(dFan),'omitnan');
Summary.max_abs_W_fan_W = max(abs(dW),[],'omitnan');
Summary.mean_abs_W_fan_W = mean(abs(dW),'omitnan');
Summary.max_abs_Q_rejected_W = max(abs(dQ),[],'omitnan');
Summary.mean_abs_Q_rejected_W = mean(abs(dQ),'omitnan');
Summary.status_changes = sum(strict.status ~= fast.status);

fprintf('\nCT solver sensitivity\n');
fprintf('  Window                  : hour %d to %d (%d h)\n', ...
    startHour,startHour+nHours,nHours);
fprintf('  Input                   : T_in=%.3f C, target=%.3f C, mdot=%.3f kg/s\n', ...
    TinC,Ttarget,mdotWater);
fprintf('  Strict intervals/tol    : %d / %.4g C\n',100,1e-4);
fprintf('  Fast intervals/tol      : %d / %.4g C\n',fastIntervals,fastTolC);
fprintf('  Runtime strict/fast     : %.3f s / %.3f s (speedup %.2fx)\n', ...
    Summary.strict_runtime_s,Summary.fast_runtime_s,Summary.speedup);
fprintf('  Max |dT_w_out|          : %.6g C\n',Summary.max_abs_T_w_out_C);
fprintf('  Mean |dT_w_out|         : %.6g C\n',Summary.mean_abs_T_w_out_C);
fprintf('  Max |dfan_ratio|        : %.6g\n',Summary.max_abs_fan_ratio);
fprintf('  Max |dW_fan|            : %.6g W\n',Summary.max_abs_W_fan_W);
fprintf('  Max |dQ_rejected|       : %.6g W\n',Summary.max_abs_Q_rejected_W);
fprintf('  Status changes          : %d\n',Summary.status_changes);
end

function CTConfig = localBuildCTConfig(cfg,nIntervals,tolC)
CTConfig = ct_default_config();
CTConfig.numerics.merkel_n_intervals = nIntervals;
CTConfig.numerics.target_temperature_tolerance_C = tolC;
CTConfig.numerics.inverse_temperature_tolerance_C = tolC;
CTConfig.numerics.fan_ratio_tolerance = 1e-4;
CTConfig.water_consumption.drift_fraction = cfg.ct.drift_fraction;
CTConfig.water_consumption.cycles_of_concentration = cfg.ct.cycles_of_concentration;
end

function Result = localRunCase(WeatherData,CTConfig,CTDesign,TinC,Ttarget,mdotWater)
nHours = height(WeatherData);
Result.T_w_out_C = nan(nHours,1);
Result.fan_ratio = nan(nHours,1);
Result.W_fan_W = nan(nHours,1);
Result.Q_rejected_W = nan(nHours,1);
Result.solved = false(nHours,1);
Result.status = strings(nHours,1);

timer = tic;
for it = 1:nHours
    CTAmbient = struct();
    CTAmbient.T_db_C = WeatherData.T_amb_C(it);
    CTAmbient.T_wb_C = WeatherData.T_wb_C(it);
    CTAmbient.RH_pct = WeatherData.RH_pct(it);
    CTAmbient.P_atm_Pa = WeatherData.Patm_Pa(it);
    CTAir = ct_psychrometrics(CTAmbient,CTConfig);

    CTInput = struct();
    CTInput.T_w_in_C = TinC;
    CTInput.T_w_out_target_C = Ttarget;
    CTInput.mdot_water = mdotWater;
    CTInput.air_in = CTAir;

    out = ct_solve_fan_for_target(CTInput,CTAmbient,CTDesign,CTConfig);
    Result.T_w_out_C(it) = out.T_w_out_C;
    Result.fan_ratio(it) = out.fan_ratio;
    Result.W_fan_W(it) = out.W_fan_W;
    Result.Q_rejected_W(it) = out.Q_rejected_W;
    Result.solved(it) = true;
    Result.status(it) = string(out.status);
end
Result.runtime_s = toc(timer);
end

function WeatherData = localLoadWeather(cfg)
if exist(cfg.paths.weather_cache,'file') == 2
    S = load(cfg.paths.weather_cache);
    if isfield(S,'WeatherData')
        WeatherData = S.WeatherData;
    elseif isfield(S,'weather')
        WeatherData = S.weather;
    else
        error('ct_solver_sensitivity_v1:WeatherCacheSchema', ...
            'Weather cache does not contain WeatherData or weather.');
    end
else
    WeatherData = read_epw_weather(cfg.paths.weather_epw);
end
end
