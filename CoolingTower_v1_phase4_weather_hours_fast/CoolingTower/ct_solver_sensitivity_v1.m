function Summary = ct_solver_sensitivity_v1(ProjectRoot,startHour,nHours,fastIntervals,fastTolC)
%CT_SOLVER_SENSITIVITY_V1 Compare CT Merkel/fan-solve numerics.

if nargin < 1 || isempty(ProjectRoot)
    ProjectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
if nargin < 2 || isempty(startHour)
    startHour = [];
end
if nargin < 3 || isempty(nHours)
    nHours = [];
end
if nargin < 4 || isempty(fastIntervals)
    fastIntervals = 50;
end
if nargin < 5 || isempty(fastTolC)
    fastTolC = 1e-4;
end

system_paths_v1(ProjectRoot);
cfg = system_config_v1(ProjectRoot);
WeatherData = localLoadWeather(cfg);
if nargin >= 2 && ~isempty(startHour) && nargin >= 3 && ~isempty(nHours)
    idx = (startHour + 1):(startHour + nHours);
    if max(idx) > height(WeatherData)
        error('ct_solver_sensitivity_v1:WindowOutOfRange', ...
            'Requested hours exceed available weather rows.');
    end
    WeatherCases = WeatherData(idx,:);
    WeatherCases.Label = "window";
else
    WeatherCases = localSelectRepresentativeWeather(WeatherData);
end

strictCfg = localBuildCTConfig(cfg,100,cfg.ct.target_temperature_tolerance_C,1e-4);
fastCfg = localBuildCTConfig(cfg,fastIntervals,cfg.ct.target_temperature_tolerance_C,fastTolC);
CTDesign = ct_rate_design_point(struct(),strictCfg);

Ttarget = cfg.ct.T_cw_target_C;
TinListC = (28:34).';
mdotWater = cfg.orc.mdot_cw_design_kg_s;

strict = localRunCase(WeatherCases,strictCfg,CTDesign,TinListC,Ttarget,mdotWater);
fast = localRunCase(WeatherCases,fastCfg,CTDesign,TinListC,Ttarget,mdotWater);

dT = fast.T_w_out_C - strict.T_w_out_C;
dFan = fast.fan_ratio - strict.fan_ratio;
dW = fast.W_fan_W - strict.W_fan_W;
dQ = fast.Q_rejected_W - strict.Q_rejected_W;
relQ = abs(dQ)./max(abs(strict.Q_rejected_W),eps);
fastTargetError = fast.T_w_out_C - Ttarget;
fastTargetContradiction = fast.status == "TARGET_MET" & fastTargetError > fastCfg.numerics.target_temperature_tolerance_C;

Summary = struct();
Summary.startHour = startHour;
Summary.nHours = nHours;
Summary.n_weather_cases = height(WeatherCases);
Summary.T_w_in_values_C = TinListC;
Summary.n_test_points = numel(fast.T_w_out_C);
Summary.T_w_out_target_C = Ttarget;
Summary.strict_intervals = 100;
Summary.fast_intervals = fastIntervals;
Summary.strict_target_tol_C = strictCfg.numerics.target_temperature_tolerance_C;
Summary.strict_inverse_tol_C = strictCfg.numerics.inverse_temperature_tolerance_C;
Summary.fast_target_tol_C = fastCfg.numerics.target_temperature_tolerance_C;
Summary.fast_inverse_tol_C = fastCfg.numerics.inverse_temperature_tolerance_C;
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
Summary.max_rel_Q_rejected = max(relQ,[],'omitnan');
Summary.status_mismatch_count = sum(strict.status ~= fast.status);
Summary.target_met_mismatch_count = sum(strict.target_met ~= fast.target_met);
Summary.fast_TARGET_MET_contradiction_count = sum(fastTargetContradiction);
Summary.fast_TARGET_MET_max_positive_error_C = max(fastTargetError(fast.status == "TARGET_MET"),[],'omitnan');
Summary.weather_cases = WeatherCases;
Summary.strict = strict;
Summary.fast = fast;

fprintf('\nCT solver sensitivity\n');
fprintf('  Weather cases           : %d\n',height(WeatherCases));
fprintf('  T_in sweep              : %s C\n',mat2str(TinListC.'));
fprintf('  Target/mdot             : %.3f C / %.3f kg/s\n',Ttarget,mdotWater);
fprintf('  Strict intervals/tol    : %d / target %.4g C / inverse %.4g C\n', ...
    100,strictCfg.numerics.target_temperature_tolerance_C,strictCfg.numerics.inverse_temperature_tolerance_C);
fprintf('  Fast intervals/tol      : %d / target %.4g C / inverse %.4g C\n', ...
    fastIntervals,fastCfg.numerics.target_temperature_tolerance_C,fastCfg.numerics.inverse_temperature_tolerance_C);
fprintf('  Runtime strict/fast     : %.3f s / %.3f s (speedup %.2fx)\n', ...
    Summary.strict_runtime_s,Summary.fast_runtime_s,Summary.speedup);
fprintf('  Max |dT_w_out|          : %.6g C\n',Summary.max_abs_T_w_out_C);
fprintf('  Mean |dT_w_out|         : %.6g C\n',Summary.mean_abs_T_w_out_C);
fprintf('  Max |dfan_ratio|        : %.6g\n',Summary.max_abs_fan_ratio);
fprintf('  Max |dW_fan|            : %.6g W\n',Summary.max_abs_W_fan_W);
fprintf('  Max |dQ_rejected|       : %.6g W\n',Summary.max_abs_Q_rejected_W);
fprintf('  Max rel |dQ_rejected|   : %.6g\n',Summary.max_rel_Q_rejected);
fprintf('  Status mismatch         : %d\n',Summary.status_mismatch_count);
fprintf('  target.met mismatch     : %d\n',Summary.target_met_mismatch_count);
fprintf('  TARGET_MET contradictions: %d\n',Summary.fast_TARGET_MET_contradiction_count);
end

function CTConfig = localBuildCTConfig(cfg,nIntervals,targetTolC,inverseTolC)
CTConfig = ct_default_config();
CTConfig.numerics.merkel_n_intervals = nIntervals;
CTConfig.numerics.target_temperature_tolerance_C = targetTolC;
CTConfig.numerics.inverse_temperature_tolerance_C = inverseTolC;
CTConfig.numerics.fan_ratio_tolerance = 1e-4;
CTConfig.water_consumption.drift_fraction = cfg.ct.drift_fraction;
CTConfig.water_consumption.cycles_of_concentration = cfg.ct.cycles_of_concentration;
end

function Result = localRunCase(WeatherData,CTConfig,CTDesign,TinListC,Ttarget,mdotWater)
nWeather = height(WeatherData);
nTin = numel(TinListC);
n = nWeather*nTin;
Result.weather_case = strings(n,1);
Result.weather_row = nan(n,1);
Result.T_db_C = nan(n,1);
Result.T_wb_C = nan(n,1);
Result.T_w_in_C = nan(n,1);
Result.T_w_out_C = nan(n,1);
Result.fan_ratio = nan(n,1);
Result.W_fan_W = nan(n,1);
Result.Q_rejected_W = nan(n,1);
Result.target_met = false(n,1);
Result.solved = false(n,1);
Result.status = strings(n,1);

timer = tic;
ir = 0;
for iw = 1:nWeather
for itn = 1:nTin
    ir = ir + 1;
    CTAmbient = struct();
    CTAmbient.T_db_C = WeatherData.T_amb_C(iw);
    CTAmbient.T_wb_C = WeatherData.T_wb_C(iw);
    CTAmbient.RH_pct = WeatherData.RH_pct(iw);
    CTAmbient.P_atm_Pa = WeatherData.Patm_Pa(iw);
    CTAir = ct_psychrometrics(CTAmbient,CTConfig);

    CTInput = struct();
    CTInput.T_w_in_C = TinListC(itn);
    CTInput.T_w_out_target_C = Ttarget;
    CTInput.mdot_water = mdotWater;
    CTInput.air_in = CTAir;

    out = ct_solve_fan_for_target(CTInput,CTAmbient,CTDesign,CTConfig);
    Result.weather_case(ir) = string(localGetTableValue(WeatherData,'Label',iw,"case"));
    Result.weather_row(ir) = localGetTableValue(WeatherData,'WeatherRow',iw,iw);
    Result.T_db_C(ir) = CTAmbient.T_db_C;
    Result.T_wb_C(ir) = CTAmbient.T_wb_C;
    Result.T_w_in_C(ir) = TinListC(itn);
    Result.T_w_out_C(ir) = out.T_w_out_C;
    Result.fan_ratio(ir) = out.fan_ratio;
    Result.W_fan_W(ir) = out.W_fan_W;
    Result.Q_rejected_W(ir) = out.Q_rejected_W;
    Result.target_met(ir) = isfield(out,'target') && isfield(out.target,'met') && logical(out.target.met);
    Result.solved(ir) = true;
    Result.status(ir) = string(out.status);
end
end
Result.runtime_s = toc(timer);
end

function WeatherCases = localSelectRepresentativeWeather(WeatherData)
valid = find(isfinite(WeatherData.T_amb_C) & isfinite(WeatherData.T_wb_C) & ...
    isfinite(WeatherData.RH_pct) & isfinite(WeatherData.Patm_Pa));
if isempty(valid)
    error('ct_solver_sensitivity_v1:NoValidWeather','No valid weather rows found.');
end
Twb = WeatherData.T_wb_C(valid);
Tdb = WeatherData.T_amb_C(valid);
idxLow = valid(localNearest(Twb,prctile(Twb,10)));
idxMid = valid(localNearest(Twb,prctile(Twb,50)));
idxHigh = valid(localNearest(Twb,prctile(Twb,90)));
summer = valid;
if any(strcmp(WeatherData.Properties.VariableNames,'Month'))
    m = WeatherData.Month(valid);
    summer = valid(m >= 6 & m <= 9);
end
if isempty(summer)
    summer = valid;
end
[~,is] = max(WeatherData.T_amb_C(summer));
idxSummer = summer(is);
idx = unique([idxLow;idxMid;idxHigh;idxSummer],'stable');
WeatherCases = WeatherData(idx,:);
labels = ["low_wet_bulb";"mid_wet_bulb";"high_wet_bulb";"hot_summer"];
labels = labels(1:numel(idx));
WeatherCases.Label = labels;
WeatherCases.WeatherRow = idx(:);
end

function idx = localNearest(x,target)
[~,idx] = min(abs(x - target));
end

function value = localGetTableValue(T,varName,row,defaultValue)
if any(strcmp(T.Properties.VariableNames,varName))
    value = T.(varName)(row);
else
    value = defaultValue;
end
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
