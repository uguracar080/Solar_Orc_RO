% RUN_SINGLE_CONFIGURATION_V1
% Script entry point for the first integrated Solar-ORC-RO configuration.
%
% Edit the block below, then press Run in MATLAB.

ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
system_paths_v1(ProjectRoot);
cfg = system_config_v1(ProjectRoot);

% Simulation window uses 0-based source hours and a half-open interval.
% Examples: 0 to 8760 runs the full year; 5500 to 5548 runs 48 hours.
cfg.sim.startHour = 0;
cfg.sim.endHour = 48;
cfg.sim.timeStep_min = 60;

% Solar field design/operation variables.
cfg.solar.field.N_series = 20;
cfg.solar.field.N_parallel = 10;
cfg.solar.T_HTF_in_K = 380.0;
cfg.solar.V_Lmin_1module = 56.8;
cfg.solar.V_Lmin_1module_reference = 56.8;
cfg.solar.min_DNI_Wm2 = 50;
cfg.solar.flow_control.enabled = true;
cfg.solar.flow_control.factor_list = 0.50:0.25:2.00;
cfg.solar.flow_control.selection_mode = 'max_heat_below_limit';
cfg.solar.flow_control.T_out_target_C = 390.0;
cfg.solar.flow_control.T_out_min_C = 160.0;
cfg.solar.flow_control.T_out_max_C = 400.0;
cfg.solar.pump.enabled = true;
cfg.solar.pump.eta_hydraulic = 0.75;
cfg.solar.pump.eta_motor = 0.95;

% ORC design variables and fixed assumptions exposed for optimizer wiring.
cfg.orc.working_fluid = 'R1233zd(E)';
cfg.orc.eta_turb = 0.85;
cfg.orc.eta_pump = 0.80;
cfg.orc.W_net_design_W = 250e3;
cfg.orc.P_evap_design_Pa = 10.7e5;
cfg.orc.P_cond_design_Pa = 1.2e5;
cfg.orc.hot_stream_design_T_in_K = 150 + 273.15; %160
cfg.orc.hot_stream_design_T_return_K = 130 + 273.15; %115
cfg.orc.hot_stream_fluid = 'Syltherm800';
cfg.orc.hot_stream_design_mdot_kg_s = 30.0;
cfg.orc.cw_target_in_C = 15.0;
cfg.orc.mdot_cw_design_kg_s = 100.0;

% Heat rejection and RO variables.
cfg.ro.N_train_total = 1;
cfg.preheater.T_RO_in_rise_C = 5.0;
cfg.preheater.N_parallel_max = 20;
cfg.preheater.Nt_min = 20;
cfg.preheater.Nt_max = 1200;
cfg.preheater.Nt_step = 20;
cfg.ct.Q_rated_fraction_of_design_condenser = 0.30;

% Temporary thermal storage placeholder for excess solar heat.
% This is a water-tank bookkeeping model; PCM charge/discharge logic is not active yet.
cfg.storage.enabled = true;
cfg.storage.type = 'water_tank_v1';
cfg.storage.volume_m3 = 100.0;
cfg.storage.T_initial_C = 30.0;
cfg.storage.T_min_C = 25.0;
cfg.storage.T_max_C = 95.0;
cfg.storage.solar_return_sink_enabled = true;

Results = run_single_configuration_core_v1(cfg);
