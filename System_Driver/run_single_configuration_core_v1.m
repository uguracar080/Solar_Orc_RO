function Results = run_single_configuration_core_v1(cfg)
%RUN_SINGLE_CONFIGURATION_CORE_V1 Run the first fixed-configuration system chain.
%
% Usage:
%   Results = run_single_configuration_core_v1;
%   cfg = system_config_v1; cfg.sim.startHour = 0; cfg.sim.endHour = 8760;
%   Results = run_single_configuration_core_v1(cfg);

if nargin < 1 || isempty(cfg)
    ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
    system_paths_v1(ProjectRoot);
    cfg = system_config_v1(ProjectRoot);
else
    if isfield(cfg,'project_root')
        ProjectRoot = cfg.project_root;
    else
        ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
    end
    system_paths_v1(ProjectRoot);
end

timerTotal = tic;

cfg = localFinalizeSimulationConfig(cfg);
WeatherAll = localLoadWeather(cfg);
SeawaterAll = readtable(cfg.paths.seawater_csv);
[WeatherData,SeawaterData,sourceHour] = localPrepareInputWindow(cfg,WeatherAll,SeawaterAll);
nHours = numel(sourceHour);

fprintf('\nSystem V1 single-configuration run\n');
fprintf('Source window   : %.3f to %.3f h\n',cfg.sim.startHour,cfg.sim.endHour);
fprintf('Time step       : %.3f min\n',cfg.sim.timeStep_min);
fprintf('Steps simulated : %d\n',nHours);

[orcDesign,orcConfig,orcTemplates] = localDesignOrc(cfg);
[PHDesign,CTDesign,CTConfig] = localDesignHeatRejectionTrain(cfg,SeawaterData,orcDesign);

[Hourly,SolarHourly,orcAnnual] = system_hourly_coupled_solver_v1(cfg,WeatherData,SeawaterData, ...
    orcDesign,PHDesign,CTDesign,CTConfig,orcConfig,orcTemplates,nHours,sourceHour);
Summary = localSummarize(Hourly,cfg,toc(timerTotal));

if ~isfolder(fileparts(cfg.outputs.hourly_csv))
    mkdir(fileparts(cfg.outputs.hourly_csv));
end
writetable(Hourly,cfg.outputs.hourly_csv);
writetable(Summary,cfg.outputs.summary_csv);

Results = struct();
Results.cfg = cfg;
Results.Hourly = Hourly;
Results.Summary = Summary;
Results.PHDesign = PHDesign;
Results.CTDesign = CTDesign;
Results.orcDesign = orcDesign;
Results.orcAnnual = orcAnnual;
Results.elapsed_s = toc(timerTotal);

if localGetNestedStruct(cfg,'outputs','generate_figures',false)
    FigureResults = generate_all_figures_v1(Results,cfg.outputs.figures_root);
    cfg.outputs.figures_dir = FigureResults.output_dir;
    Results.cfg = cfg;
    Results.FigureResults = FigureResults;
else
    FigureResults = struct('output_dir','','files',strings(0,1));
    cfg.outputs.figures_dir = '';
    Results.cfg = cfg;
    Results.FigureResults = FigureResults;
end

ReportFile = write_simulation_report_v1(cfg,Summary,Hourly,PHDesign,CTDesign,orcDesign,orcAnnual,cfg.outputs.report_txt);
Results.report_txt = ReportFile;
save(cfg.outputs.summary_mat,'cfg','Summary','Hourly','PHDesign','CTDesign','orcDesign','orcAnnual','FigureResults','ReportFile');

fprintf('\nSystem V1 complete.\n');
fprintf('Hourly output : %s\n',cfg.outputs.hourly_csv);
fprintf('Summary output: %s\n',cfg.outputs.summary_csv);
fprintf('MAT output    : %s\n',cfg.outputs.summary_mat);
fprintf('Report output : %s\n',ReportFile);
if ~isempty(FigureResults.output_dir)
    fprintf('Figures dir   : %s\n',FigureResults.output_dir);
end
end

function cfg = localFinalizeSimulationConfig(cfg)
if ~isfield(cfg,'sim') || isempty(cfg.sim)
    cfg.sim = struct();
end
cfg.sim.timeStep_min = localGetStruct(cfg.sim,'timeStep_min',localGetStruct(cfg.sim,'dt_s',3600)/60);
cfg.sim.timeStep_min = max(cfg.sim.timeStep_min,eps);
cfg.sim.dt_s = cfg.sim.timeStep_min*60;

cfg.sim.startHour = localGetStruct(cfg.sim,'startHour',0);
if isfield(cfg.sim,'endHour') && ~isempty(cfg.sim.endHour)
    cfg.sim.endHour = cfg.sim.endHour;
elseif isfield(cfg.sim,'nHours') && ~isempty(cfg.sim.nHours)
    cfg.sim.endHour = cfg.sim.startHour + cfg.sim.nHours;
else
    cfg.sim.endHour = cfg.sim.startHour + 24;
end
if cfg.sim.endHour <= cfg.sim.startHour
    error('run_single_configuration_core_v1:InvalidWindow', ...
        'cfg.sim.endHour must be greater than cfg.sim.startHour.');
end
cfg.sim.nHours = ceil((cfg.sim.endHour - cfg.sim.startHour)/(cfg.sim.timeStep_min/60));
end

function [WeatherData,SeawaterData,sourceHour] = localPrepareInputWindow(cfg,WeatherAll,SeawaterAll)
dt_h = cfg.sim.timeStep_min/60;
sourceHour = (cfg.sim.startHour:dt_h:(cfg.sim.endHour - 0.5*dt_h)).';
nAvailable = min(height(WeatherAll),height(SeawaterAll));
if isempty(sourceHour) || sourceHour(1) < 0 || sourceHour(end) > nAvailable - 1 + 1e-9
    error('run_single_configuration_core_v1:WindowOutOfRange', ...
        'Requested source window %.3f to %.3f h is outside available input range 0 to %d h.', ...
        cfg.sim.startHour,cfg.sim.endHour,nAvailable);
end

WeatherData = localInterpolateHourlyTable(WeatherAll,sourceHour);
SeawaterData = localInterpolateHourlyTable(SeawaterAll,sourceHour);
end

function Tout = localInterpolateHourlyTable(Tin,sourceHour)
x = (0:height(Tin)-1).';
Tout = Tin(ones(numel(sourceHour),1),:);
for iv = 1:numel(Tin.Properties.VariableNames)
    name = Tin.Properties.VariableNames{iv};
    values = Tin.(name);
    if isnumeric(values) || islogical(values)
        Tout.(name) = interp1(x,double(values),sourceHour,'linear');
    else
        idx = min(max(round(sourceHour) + 1,1),height(Tin));
        Tout.(name) = values(idx);
    end
end
end

function value = localGetStruct(S,fieldName,defaultValue)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end

function h = localOpenWaitbar(cfg,titleText)
h = [];
if isfield(cfg,'ui') && isfield(cfg.ui,'use_waitbar') && cfg.ui.use_waitbar && usejava('desktop')
    try
        h = waitbar(0,titleText,'Name','System V1 progress');
    catch
        h = [];
    end
end
end

function localUpdateWaitbar(h,it,n,msg)
if isempty(h) || ~ishandle(h)
    return
end
waitbar(max(0,min(1,it/max(n,1))),h,msg);
drawnow limitrate
end

function localCloseWaitbar(h)
if ~isempty(h) && ishandle(h)
    close(h);
end
end

function WeatherData = localLoadWeather(cfg)
if isfile(cfg.paths.weather_epw)
    WeatherData = read_epw_weather(cfg.paths.weather_epw);
elseif isfile(cfg.paths.weather_cache)
    S = load(cfg.paths.weather_cache);
    if isfield(S,'weather')
        WeatherData = S.weather;
    elseif isfield(S,'WeatherData')
        WeatherData = S.WeatherData;
    else
        error('run_single_configuration_v1:WeatherCacheMissingTable', ...
            'Weather cache exists, but no weather/WeatherData variable was found.');
    end
else
    error('run_single_configuration_v1:WeatherMissing', ...
        'Neither EPW nor weather cache was found.');
end
end

function [orcDesign,orcConfig,orcTemplates] = localDesignOrc(cfg)
orcConfig = struct();
orcConfig.orc_fluid = cfg.orc.working_fluid;
orcConfig.orc_eta_turb = cfg.orc.eta_turb;
orcConfig.orc_eta_pump = cfg.orc.eta_pump;
orcConfig.orc_stage2_operatingMode = cfg.orc.operating_mode;
orcConfig.orc_stage2_progressMode = localGetNestedStruct(cfg,'ui','orc_stage2_progressMode','none');
orcConfig.orc_stage2_printSummary = false;
orcConfig.orc_dispatch_printSummary = false;
orcConfig.orc_property_cache_resetAtQuickstart = false;
orcConfig.sim_dt_s = cfg.sim.dt_s;
orcConfig = orc_default_config(orcConfig);

systemInput = struct();
systemInput.orc_W_nom = cfg.orc.W_net_design_W;
systemInput.orc_P_evap_des = cfg.orc.P_evap_design_Pa;
systemInput.orc_P_cond_des = cfg.orc.P_cond_design_Pa;

orcHotDesign = struct();
orcHotDesign.fluid = cfg.orc.hot_stream_fluid;
orcHotDesign.T_in = cfg.orc.hot_stream_design_T_in_K;
orcHotDesign.P_in = cfg.orc.hot_stream_pressure_Pa;
orcHotDesign.mdot = cfg.orc.hot_stream_design_mdot_kg_s;

orcColdDesign = struct();
orcColdDesign.fluid = cfg.orc.cold_stream_fluid;
orcColdDesign.T_in = cfg.orc.cw_target_in_C + 273.15;
orcColdDesign.P_in = cfg.orc.cold_stream_pressure_Pa;
orcColdDesign.mdot = cfg.orc.mdot_cw_design_kg_s;

orcDesign = orc_stage1_sizing(systemInput,orcHotDesign,orcColdDesign,orcConfig);

op = struct();
op.orc_P_evap = orcDesign.orc_thermo.P_orcevap;
op.orc_P_cond = orcDesign.orc_thermo.P_orccond;
op.orc_mdot = orcDesign.orc_thermo.mdot_orc;

orcTemplates = struct();
orcTemplates.orcHotDesign = orcHotDesign;
orcTemplates.orcColdDesign = orcColdDesign;
orcTemplates.op = op;
end

function [orcDesign,orcAnnual] = localRunOrcAnnual(cfg,SolarHourly,nHours)
orcConfig = struct();
orcConfig.orc_fluid = cfg.orc.working_fluid;
orcConfig.orc_eta_turb = cfg.orc.eta_turb;
orcConfig.orc_eta_pump = cfg.orc.eta_pump;
orcConfig.orc_stage2_operatingMode = cfg.orc.operating_mode;
orcConfig.orc_stage2_progressMode = localGetNestedStruct(cfg,'ui','orc_stage2_progressMode','none');
orcConfig.orc_stage2_printSummary = true;
orcConfig.orc_dispatch_printSummary = false;
orcConfig.orc_property_cache_resetAtQuickstart = false;
orcConfig.sim_dt_s = cfg.sim.dt_s;
orcConfig = orc_default_config(orcConfig);

systemInput = struct();
systemInput.orc_W_nom = cfg.orc.W_net_design_W;
systemInput.orc_P_evap_des = cfg.orc.P_evap_design_Pa;
systemInput.orc_P_cond_des = cfg.orc.P_cond_design_Pa;

orcHotDesign = struct();
orcHotDesign.fluid = cfg.orc.hot_stream_fluid;
orcHotDesign.T_in = cfg.orc.hot_stream_design_T_in_K;
orcHotDesign.P_in = cfg.orc.hot_stream_pressure_Pa;
orcHotDesign.mdot = cfg.orc.hot_stream_design_mdot_kg_s;

orcColdDesign = struct();
orcColdDesign.fluid = cfg.orc.cold_stream_fluid;
orcColdDesign.T_in = cfg.orc.cw_target_in_C + 273.15;
orcColdDesign.P_in = cfg.orc.cold_stream_pressure_Pa;
orcColdDesign.mdot = cfg.orc.mdot_cw_design_kg_s;

orcDesign = orc_stage1_sizing(systemInput,orcHotDesign,orcColdDesign,orcConfig);

hotStreams = repmat(orcHotDesign,nHours,1);
coldStreams = repmat(orcColdDesign,nHours,1);
for it = 1:nHours
    hotStreams(it) = localSolarToOrcHotStreamLegacy(SolarHourly(it),cfg,orcHotDesign);
end

op = struct();
op.orc_P_evap = orcDesign.orc_thermo.P_orcevap;
op.orc_P_cond = orcDesign.orc_thermo.P_orccond;
op.orc_mdot = orcDesign.orc_thermo.mdot_orc;

orcAnnualInput = struct();
orcAnnualInput.orcHotStream = hotStreams;
orcAnnualInput.orcColdStream = coldStreams;
orcAnnualInput.orcOperatingInput = op;
orcAnnualInput.orc_dt_s = cfg.sim.dt_s;
orcAnnualInput.orc_useDispatch = strcmpi(cfg.orc.operating_mode,'dispatch');

orcAnnual = orc_stage2_annual_offdesign(orcDesign,orcAnnualInput,orcConfig);
end

function hot = localSolarToOrcHotStreamLegacy(SolarOut,cfg,hotTemplate)
hot = hotTemplate;
if ~isfield(SolarOut,'feasible') || ~SolarOut.feasible || SolarOut.Q_useful_W <= 0
    hot.T_in = cfg.orc.solar_adapter_return_T_K + cfg.orc.solar_adapter_min_deltaT_K;
    hot.mdot = 1e-6;
    return
end

if localIsSyltherm800(hot.fluid)
    hot.T_in = SolarOut.T_HTF_out_K;
    hot.mdot = max(SolarOut.mdot_HTF_kg_s,1e-6);
    return
end

T_in = max(SolarOut.T_HTF_out_K,cfg.orc.solar_adapter_return_T_K + cfg.orc.solar_adapter_min_deltaT_K);
cpEq = 4180;
deltaT = max(T_in - cfg.orc.solar_adapter_return_T_K,cfg.orc.solar_adapter_min_deltaT_K);
mdotEq = SolarOut.Q_useful_W/(cpEq*deltaT);

hot.T_in = T_in;
hot.mdot = max(mdotEq,1e-6);
end

function tf = localIsSyltherm800(fluid)
name = regexprep(lower(char(string(fluid))),'[^a-z0-9]','');
tf = any(strcmp(name,{'syltherm800','syltherm'}));
end

function [PHDesign,CTDesign,CTConfig] = localDesignHeatRejectionTrain(cfg,SeawaterData,orcDesign)
TswDesign = SeawaterData.SeaWater_Temperature_C(1);
mdotSw = cfg.ro.N_train_total * cfg.ro.Qf_train_m3h * cfg.ro.rho_seawater_kgm3 / 3600;
Qcond = orcDesign.orc_thermo.Q_orccond;
TcwInC = cfg.orc.cw_target_in_C;
TcwHotC = TcwInC + Qcond/(cfg.orc.mdot_cw_design_kg_s*cfg.preheater.cp_hot_JkgK);

PHConfig = struct();
PHConfig.cp_hot_JkgK = cfg.preheater.cp_hot_JkgK;
PHConfig.cp_cold_JkgK = cfg.preheater.cp_cold_JkgK;
PHConfig.dT_min_K = cfg.preheater.dT_min_K;
PHConfig.T_cold_rise_target_C = cfg.preheater.T_RO_in_rise_C;
PHConfig.T_cold_out_design_C = min(TswDesign + cfg.preheater.T_RO_in_rise_C,cfg.preheater.T_RO_in_max_C);
PHConfig.T_cold_out_max_C = cfg.preheater.T_RO_in_max_C;
PHConfig.geometry_family = cfg.preheater.geometry_family;
PHConfig.N_parallel_max = cfg.preheater.N_parallel_max;
PHConfig.Nt_list = localGetStruct(cfg.preheater,'Nt_min',20): ...
    localGetStruct(cfg.preheater,'Nt_step',20):localGetStruct(cfg.preheater,'Nt_max',1200);
PHConfig.hot.cp_JkgK = cfg.preheater.cp_hot_JkgK;
PHConfig.hot.rho_kgm3 = cfg.preheater.hot_rho_kgm3;
PHConfig.hot.mu_Pas = cfg.preheater.hot_mu_Pas;
PHConfig.hot.k_WmK = cfg.preheater.hot_k_WmK;
PHConfig.cold.cp_JkgK = cfg.preheater.cp_cold_JkgK;
PHConfig.cold.rho_kgm3 = cfg.preheater.cold_rho_kgm3;
PHConfig.cold.mu_Pas = cfg.preheater.cold_mu_Pas;
PHConfig.cold.k_WmK = cfg.preheater.cold_k_WmK;
PHConfig.orc_config.orc_hx_Nt_min = localGetStruct(cfg.preheater,'Nt_min',20);
PHConfig.orc_config.orc_hx_Nt_max = localGetStruct(cfg.preheater,'Nt_max',1200);
PHConfig.orc_config.orc_hx_minTubeLength = localGetStruct(cfg.preheater,'minTubeLength_m',0.50);
PHConfig.orc_config.orc_hx_maxTubeLength = localGetStruct(cfg.preheater,'maxTubeLength_m',8.00);

PHInput = struct();
PHInput.T_hot_in_C = TcwHotC;
PHInput.T_cold_in_C = TswDesign;
PHInput.T_cold_out_target_C = PHConfig.T_cold_out_design_C;
PHInput.mdot_hot_kg_s = cfg.orc.mdot_cw_design_kg_s;
PHInput.mdot_cold_kg_s = mdotSw;
PHDesign = preheater_sthe_design_v1(PHInput,PHConfig);

CTConfig = ct_default_config();
CTConfig.water_consumption.drift_fraction = cfg.ct.drift_fraction;
CTConfig.water_consumption.cycles_of_concentration = cfg.ct.cycles_of_concentration;

CTRatingInput = struct();
CTRatingInput.Q_rated_W = cfg.ct.Q_rated_fraction_of_design_condenser * Qcond;
CTRatingInput.T_w_in_C = TcwHotC;
CTRatingInput.T_w_out_C = cfg.ct.T_cw_target_C;
CTRatingInput.mdot_water = cfg.orc.mdot_cw_design_kg_s;
CTDesign = ct_rate_design_point(CTRatingInput,CTConfig);
end

function Summary = localSummarize(Hourly,cfg,elapsed_s)
dt_h = cfg.sim.dt_s/3600;
Summary = table();
Summary.n_hours = height(Hourly);
Summary.elapsed_s = elapsed_s;
Summary.ORC_operating_hours = sum(Hourly.ORC_feasible)*dt_h;
Summary.RO_operating_hours = sum(Hourly.RO_feasible)*dt_h;
Summary.E_ORC_net_kWh = sum(Hourly.W_ORC_net_W,'omitnan')*dt_h/1000;
Summary.E_solar_pump_kWh = sum(Hourly.W_solar_pump_W,'omitnan')*dt_h/1000;
Summary.E_RO_kWh = sum(Hourly.W_RO_total_W,'omitnan')*dt_h/1000;
Summary.E_CT_fan_kWh = sum(Hourly.W_CT_fan_W,'omitnan')*dt_h/1000;
Summary.E_aux_total_kWh = Summary.E_solar_pump_kWh + Summary.E_CT_fan_kWh;
Summary.E_available_for_RO_kWh = sum(Hourly.W_available_for_RO_W,'omitnan')*dt_h/1000;
Summary.RO_product_water_m3 = sum(Hourly.Qp_total_m3h,'omitnan')*dt_h;
Summary.CT_makeup_water_m3 = sum(Hourly.CT_makeup_m3h,'omitnan')*dt_h;
Summary.Net_product_water_m3 = Summary.RO_product_water_m3 - Summary.CT_makeup_water_m3;
Summary.RO_train_total = max(Hourly.N_train_total);
Summary.RO_train_running_max = max(Hourly.N_train_running);
Summary.RO_train_running_mean_when_on = mean(Hourly.N_train_running(Hourly.N_train_running > 0),'omitnan');
Summary.Preheater_heat_kWh = sum(Hourly.Q_preheater_W,'omitnan')*dt_h/1000;
Summary.CT_heat_rejected_kWh = sum(Hourly.Q_CT_rejected_W,'omitnan')*dt_h/1000;
Summary.Solar_useful_heat_kWh = sum(Hourly.Q_solar_useful_W,'omitnan')*dt_h/1000;
Summary.Solar_excess_heat_kWh = sum(Hourly.Q_solar_excess_W,'omitnan')*dt_h/1000;
Summary.Solar_return_sink_heat_kWh = sum(Hourly.Q_solar_return_sink_W,'omitnan')*dt_h/1000;
Summary.Storage_charge_heat_kWh = sum(Hourly.Q_storage_charge_W,'omitnan')*dt_h/1000;
Summary.Solar_curtailed_heat_kWh = sum(Hourly.Q_solar_curtailed_W,'omitnan')*dt_h/1000;
Summary.Storage_final_SOC = Hourly.storage_SOC(end);
Summary.Storage_final_T_C = Hourly.storage_T_C(end);
Summary.Solar_flow_factor_mean = mean(Hourly.solar_flow_factor,'omitnan');
Summary.Solar_flow_factor_min = min(Hourly.solar_flow_factor);
Summary.Solar_flow_factor_max = max(Hourly.solar_flow_factor);
Summary.RO_domain_fail_hours = sum(Hourly.system_status == "RO_DOMAIN_FAIL")*dt_h;
Summary.RO_infeasible_hours = sum(Hourly.system_status == "RO_INFEASIBLE")*dt_h;
Summary.Power_deficit_hours = sum(Hourly.system_status == "POWER_DEFICIT")*dt_h;
Summary.CT_target_not_met_hours = sum(Hourly.system_status == "CT_TARGET_NOT_MET")*dt_h;
Summary.CT_limited_operating_hours = sum(Hourly.system_status == "OK_CT_LIMITED")*dt_h;
Summary.Coupling_not_converged_hours = sum(~Hourly.coupling_converged)*dt_h;
end

function value = localGetNestedStruct(S,sectionName,fieldName,defaultValue)
if isfield(S,sectionName) && isstruct(S.(sectionName)) && ...
        isfield(S.(sectionName),fieldName) && ~isempty(S.(sectionName).(fieldName))
    value = S.(sectionName).(fieldName);
else
    value = defaultValue;
end
end
