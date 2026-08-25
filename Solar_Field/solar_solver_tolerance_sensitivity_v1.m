function Summary = solar_solver_tolerance_sensitivity_v1(ProjectRoot,startHour,nHours,looseTol)
%SOLAR_SOLVER_TOLERANCE_SENSITIVITY_V1 Compare PTC fsolve tolerances.
%
% The test intentionally evaluates the full flow-factor list at each hour so
% the nonlinear solver tolerance is isolated from adaptive search decisions.

if nargin < 1 || isempty(ProjectRoot)
    ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
end
if nargin < 2 || isempty(startHour)
    startHour = 770;
end
if nargin < 3 || isempty(nHours)
    nHours = 48;
end
if nargin < 4 || isempty(looseTol)
    looseTol = 1e-6;
end

system_paths_v1(ProjectRoot);
cfg = system_config_v1(ProjectRoot);
cfg.solar.field.N_series = 20;
cfg.solar.field.N_parallel = 10;
cfg.solar.flow_control.factor_list = 0.50:0.25:2.00;

WeatherData = localLoadWeather(cfg);
idx = (startHour + 1):(startHour + nHours);
if max(idx) > height(WeatherData)
    error('solar_solver_tolerance_sensitivity_v1:WindowOutOfRange', ...
        'Requested hours exceed available weather rows.');
end
WeatherWindow = WeatherData(idx,:);

strictCfg = cfg.solar;
strictCfg.solver.FunctionTolerance = 1e-10;
strictCfg.solver.StepTolerance = 1e-10;
looseCfg = cfg.solar;
looseCfg.solver.FunctionTolerance = looseTol;
looseCfg.solver.StepTolerance = looseTol;

strict = localRunCase(WeatherWindow,strictCfg);
loose = localRunCase(WeatherWindow,looseCfg);

dt_h = cfg.sim.timeStep_min/60;
onMask = strict.DNI_Wm2 >= cfg.solar.min_DNI_Wm2 | loose.DNI_Wm2 >= cfg.solar.min_DNI_Wm2;
dTout_K = loose.Tout_K - strict.Tout_K;
dQ_W = loose.Q_useful_W - strict.Q_useful_W;
dP_Pa = loose.dP_Pa - strict.dP_Pa;
dFactor = loose.flow_factor - strict.flow_factor;

Summary = struct();
Summary.startHour = startHour;
Summary.nHours = nHours;
Summary.N_series = cfg.solar.field.N_series;
Summary.N_parallel = cfg.solar.field.N_parallel;
Summary.factor_list = cfg.solar.flow_control.factor_list;
Summary.strict_tol = 1e-10;
Summary.loose_tol = looseTol;
Summary.strict_runtime_s = strict.runtime_s;
Summary.loose_runtime_s = loose.runtime_s;
Summary.speedup = strict.runtime_s/max(loose.runtime_s,eps);
Summary.candidates_per_case = strict.candidates;
Summary.daylight_hours = sum(onMask);
Summary.max_abs_Tout_K = max(abs(dTout_K(onMask)),[],'omitnan');
Summary.mean_abs_Tout_K = mean(abs(dTout_K(onMask)),'omitnan');
Summary.max_abs_Q_W = max(abs(dQ_W(onMask)),[],'omitnan');
Summary.mean_abs_Q_W = mean(abs(dQ_W(onMask)),'omitnan');
Summary.max_abs_dP_Pa = max(abs(dP_Pa(onMask)),[],'omitnan');
Summary.mean_abs_dP_Pa = mean(abs(dP_Pa(onMask)),'omitnan');
Summary.selected_factor_changes = sum(abs(dFactor(onMask)) > 1e-12,'omitnan');
Summary.strict_E_useful_kWh = sum(strict.Q_useful_W,'omitnan')*dt_h/1000;
Summary.loose_E_useful_kWh = sum(loose.Q_useful_W,'omitnan')*dt_h/1000;
Summary.delta_E_useful_kWh = Summary.loose_E_useful_kWh - Summary.strict_E_useful_kWh;
Summary.delta_E_useful_rel = Summary.delta_E_useful_kWh/max(abs(Summary.strict_E_useful_kWh),eps);
Summary.projected_annual_delta_E_kWh = Summary.delta_E_useful_kWh*8760/nHours;

fprintf('\nSolar solver tolerance sensitivity\n');
fprintf('  Window                  : hour %d to %d (%d h)\n', ...
    startHour,startHour+nHours,nHours);
fprintf('  Field                   : Ns=%d, Np=%d, candidates/hour=%d\n', ...
    Summary.N_series,Summary.N_parallel,numel(Summary.factor_list));
fprintf('  Runtime strict/loose    : %.3f s / %.3f s (speedup %.2fx)\n', ...
    Summary.strict_runtime_s,Summary.loose_runtime_s,Summary.speedup);
fprintf('  Daylight hours          : %d\n',Summary.daylight_hours);
fprintf('  Max |dTout|             : %.6g K\n',Summary.max_abs_Tout_K);
fprintf('  Mean |dTout|            : %.6g K\n',Summary.mean_abs_Tout_K);
fprintf('  Max |dQ useful|         : %.6g W\n',Summary.max_abs_Q_W);
fprintf('  Mean |dQ useful|        : %.6g W\n',Summary.mean_abs_Q_W);
fprintf('  Max |ddP|               : %.6g Pa\n',Summary.max_abs_dP_Pa);
fprintf('  Selected factor changes : %d\n',Summary.selected_factor_changes);
fprintf('  48h useful energy delta : %.6g kWh (rel %.6g)\n', ...
    Summary.delta_E_useful_kWh,Summary.delta_E_useful_rel);
fprintf('  Annual-projected delta  : %.6g kWh\n',Summary.projected_annual_delta_E_kWh);
end

function WeatherData = localLoadWeather(cfg)
if exist(cfg.paths.weather_cache,'file') == 2
    S = load(cfg.paths.weather_cache);
    if isfield(S,'WeatherData')
        WeatherData = S.WeatherData;
    elseif isfield(S,'weather')
        WeatherData = S.weather;
    else
        error('solar_solver_tolerance_sensitivity_v1:WeatherCacheSchema', ...
            'Weather cache does not contain WeatherData or weather.');
    end
else
    WeatherData = read_epw_weather(cfg.paths.weather_epw);
end
end

function Result = localRunCase(WeatherData,SolarConfig)
factors = unique([SolarConfig.flow_control.factor_list(:); 1.0]);
factors = factors(isfinite(factors) & factors > 0);
Vref = SolarConfig.V_Lmin_1module_reference;
nHours = height(WeatherData);

Result.DNI_Wm2 = WeatherData.DNI_Whm2;
Result.Tout_K = nan(nHours,1);
Result.Q_useful_W = zeros(nHours,1);
Result.dP_Pa = zeros(nHours,1);
Result.flow_factor = nan(nHours,1);
Result.candidates = nHours*numel(factors);

timer = tic;
for it = 1:nHours
    SolarInput = struct();
    SolarInput.DNI_Wm2 = WeatherData.DNI_Whm2(it);
    SolarInput.T_amb_C = WeatherData.T_amb_C(it);
    SolarInput.WindSpd_ms = WeatherData.WindSpd_ms(it);
    SolarInput.T_HTF_in_K = SolarConfig.T_HTF_in_K;

    best = localBlankCandidate();
    for j = 1:numel(factors)
        trialInput = SolarInput;
        trialInput.V_Lmin_1module = Vref*factors(j);
        out = solar_field_ptc_v1(trialInput,SolarConfig);
        cand = localCandidateFromOutput(out,factors(j),SolarConfig);
        if localCandidateBetter(cand,best,SolarConfig)
            best = cand;
        end
    end

    Result.Tout_K(it) = best.Tout_K;
    Result.Q_useful_W(it) = best.Q_useful_W;
    Result.dP_Pa(it) = best.dP_Pa;
    Result.flow_factor(it) = best.factor;
end
Result.runtime_s = toc(timer);
end

function cand = localCandidateFromOutput(out,factor,SolarConfig)
TinK = localGet(out,'T_HTF_in_K',SolarConfig.T_HTF_in_K);
ToutK = localGet(out,'T_HTF_out_K',TinK);
ToutC = ToutK - 273.15;
deltaT_K = ToutK - TinK;
fc = SolarConfig.flow_control;
cand = struct();
cand.factor = factor;
cand.Tout_K = ToutK;
cand.Tout_C = ToutC;
cand.Q_useful_W = localGet(out,'Q_useful_W',0);
cand.dP_Pa = localGet(out,'dP_HTF_Pa',0);
cand.feasible = localGet(out,'feasible',false) && ...
    isfinite(deltaT_K) && deltaT_K >= SolarConfig.min_deltaT_gain_K && ...
    isfinite(ToutC) && ToutC <= fc.T_out_max_C;
end

function best = localBlankCandidate()
best = struct('factor',NaN,'Tout_K',NaN,'Tout_C',NaN, ...
    'Q_useful_W',-Inf,'dP_Pa',NaN,'feasible',false);
end

function tf = localCandidateBetter(cand,best,SolarConfig)
tf = false;
if cand.feasible && ~best.feasible
    tf = true;
    return
elseif ~cand.feasible && best.feasible
    return
end

mode = lower(string(SolarConfig.flow_control.selection_mode));
switch mode
    case "max_heat_below_limit"
        if cand.Q_useful_W > best.Q_useful_W
            tf = true;
        end
    otherwise
        targetC = localGet(SolarConfig.flow_control,'T_out_target_C',390);
        if abs(cand.Tout_C - targetC) < abs(best.Tout_C - targetC)
            tf = true;
        end
end
end

function value = localGet(S,fieldName,defaultValue)
if isstruct(S) && isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end
