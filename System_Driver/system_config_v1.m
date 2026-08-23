function cfg = system_config_v1(ProjectRoot)
%SYSTEM_CONFIG_V1 Manual single-configuration inputs for the first system run.

if nargin < 1 || isempty(ProjectRoot)
    ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
end

cfg = struct();
cfg.version = 'system_v1';
cfg.project_root = ProjectRoot;

cfg.paths.weather_epw = fullfile(ProjectRoot,'Weather','TUR_IC_Mersin.173400_TMYx.2009-2023.epw');
cfg.paths.weather_cache = fullfile(ProjectRoot,'Weather','TUR_IC_Mersin.173400_TMYx.2009-2023_weather_cache.mat');
cfg.paths.seawater_csv = fullfile(ProjectRoot,'Hourly_profiles_seawater','seawater_profile.csv');
cfg.paths.ro_model = fullfile(ProjectRoot,'RO_MATLAB_Model_v1_8_0_FINAL_DATASET','RO_ANN_models_v1_9_1.mat');

cfg.sim.startHour = 0;
cfg.sim.endHour = 24;
cfg.sim.timeStep_min = 60;
cfg.sim.dt_s = cfg.sim.timeStep_min*60;
cfg.sim.nHours = [];

cfg.solar = struct();
cfg.solar.T_HTF_in_K = 380.0;
cfg.solar.V_Lmin_1module = 56.8;
cfg.solar.V_Lmin_1module_reference = 56.8;
cfg.solar.min_DNI_Wm2 = 50;
cfg.solar.min_useful_heat_W = 100;
cfg.solar.min_deltaT_gain_K = 5.0;
cfg.solar.field.N_series = 5;
cfg.solar.field.N_parallel = 20;
cfg.solar.flow_control.enabled = true;
cfg.solar.flow_control.factor_list = 0.50:0.25:2.00;
cfg.solar.flow_control.selection_mode = 'max_heat_below_limit';
cfg.solar.flow_control.search_mode = 'adaptive_local_then_full';
cfg.solar.flow_control.local_neighbor_steps = 1;
cfg.solar.flow_control.full_search_dni_abs_change_Wm2 = 150.0;
cfg.solar.flow_control.full_search_dni_rel_change = 0.35;
cfg.solar.flow_control.full_search_Tin_change_K = 8.0;
cfg.solar.flow_control.full_search_temp_margin_C = 8.0;
cfg.solar.flow_control.T_out_target_C = 390.0;
cfg.solar.flow_control.T_out_min_C = 160.0;
cfg.solar.flow_control.T_out_max_C = 400.0;
cfg.solar.shutdown_when_no_useful_heat = true;
cfg.solar.pump.enabled = true;
cfg.solar.pump.eta_hydraulic = 0.75;
cfg.solar.pump.eta_motor = 0.95;

cfg.orc = struct();
cfg.orc.working_fluid = 'R1233zd(E)';
cfg.orc.eta_turb = 0.85;
cfg.orc.eta_pump = 0.80;
cfg.orc.W_net_design_W = 250e3;
cfg.orc.P_evap_design_Pa = 10.7e5;
cfg.orc.P_cond_design_Pa = 2.0e5;
cfg.orc.hot_stream_fluid = 'Syltherm800';
cfg.orc.hot_stream_pressure_Pa = 10e5;
cfg.orc.hot_stream_design_T_in_K = 160 + 273.15;
cfg.orc.hot_stream_design_T_return_K = 115 + 273.15;
cfg.orc.hot_stream_design_mdot_kg_s = 30.0;
cfg.orc.cold_stream_fluid = 'Water';
cfg.orc.cold_stream_pressure_Pa = 2e5;
cfg.orc.cw_target_in_C = 27.0;
cfg.orc.mdot_cw_design_kg_s = 100.0;
cfg.orc.operating_mode = 'dispatch';

% Adapter note:
% Use 'Syltherm800' for the real solar-loop HTF in the ORC evaporator hot side.
% If this is set to 'Water', the coupled solver falls back to a water-equivalent
% solar heat adapter for comparison runs.
cfg.orc.solar_adapter_return_T_K = 115 + 273.15;
cfg.orc.solar_adapter_min_deltaT_K = 2.0;

cfg.preheater = struct();
cfg.preheater.T_RO_in_rise_C = 5.0;
cfg.preheater.T_RO_in_design_C = NaN;
cfg.preheater.T_RO_in_min_C = 20.0;
cfg.preheater.T_RO_in_max_C = 45.0;
cfg.preheater.dT_min_K = 3.0;
cfg.preheater.control_mode = 'available_deltaT';
cfg.preheater.deltaT_ON_K = 3.0;
cfg.preheater.deltaT_OFF_K = 2.0;
cfg.preheater.enforce_cond_out_above_feed = false;
cfg.preheater.cond_out_min_deltaT_to_feed_K = 3.0;
cfg.preheater.U_design_Wm2K = 900;
cfg.preheater.cp_hot_JkgK = 4180;
cfg.preheater.cp_cold_JkgK = 3990;
cfg.preheater.hot_rho_kgm3 = 997;
cfg.preheater.hot_mu_Pas = 8.9e-4;
cfg.preheater.hot_k_WmK = 0.60;
cfg.preheater.cold_rho_kgm3 = 1025;
cfg.preheater.cold_mu_Pas = 1.05e-3;
cfg.preheater.cold_k_WmK = 0.60;
cfg.preheater.geometry_family = 'condenser';
cfg.preheater.N_parallel_max = 20;
cfg.preheater.Nt_min = 20;
cfg.preheater.Nt_max = 1200;
cfg.preheater.Nt_step = 20;

cfg.ct = struct();
cfg.ct.T_cw_target_C = cfg.orc.cw_target_in_C;
cfg.ct.Q_rated_fraction_of_design_condenser = 1.00;
cfg.ct.drift_fraction = 2e-5;
cfg.ct.cycles_of_concentration = 5;

cfg.storage = struct();
cfg.storage.enabled = true;
cfg.storage.type = 'water_tank_v1';
cfg.storage.volume_m3 = 100.0;
cfg.storage.T_initial_C = 30.0;
cfg.storage.T_min_C = 25.0;
cfg.storage.T_max_C = 95.0;
cfg.storage.rho_kgm3 = 997.0;
cfg.storage.cp_JkgK = 4180.0;
cfg.storage.solar_return_sink_enabled = true;

cfg.ui = struct();
cfg.ui.use_waitbar = true;
cfg.ui.orc_stage2_progressMode = 'waitbar';

cfg.coupling = struct();
cfg.coupling.max_iter = 12;
cfg.coupling.tol_solar_K = 1.00;
cfg.coupling.tol_cw_K = 0.25;
cfg.coupling.relax = 1.00;

cfg.ro = struct();
cfg.ro.N_train_total = 1;
cfg.ro.Qf_train_m3h = 55.0;
cfg.ro.R_target = 0.48;
cfg.ro.rho_seawater_kgm3 = 1025;
cfg.ro.model_file = cfg.paths.ro_model;

cfg.outputs.results_root = fullfile(ProjectRoot,'Results');
cfg.outputs.use_timestamped_results = true;
cfg.outputs.run_label = '';
cfg.outputs.hourly_csv = fullfile(cfg.outputs.results_root,'single_config_v1_hourly.csv');
cfg.outputs.summary_csv = fullfile(cfg.outputs.results_root,'single_config_v1_summary.csv');
cfg.outputs.summary_mat = fullfile(cfg.outputs.results_root,'single_config_v1_summary.mat');
cfg.outputs.report_txt = fullfile(cfg.outputs.results_root,'single_config_v1_report.txt');
cfg.outputs.generate_figures = true;
cfg.outputs.figures_root = fullfile(ProjectRoot,'Figures');
end
