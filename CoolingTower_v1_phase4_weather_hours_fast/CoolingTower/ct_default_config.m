function CTConfig = ct_default_config()
% CT_DEFAULT_CONFIG  Project-wide cooling-tower configuration structure.
%
% Naming convention:
%   CTConfig  : cooling-tower configuration / modelling choices
%   CTInput   : cooling-tower solver inputs
%   CTOutput  : cooling-tower solver outputs
%   CTDesign  : fixed/rated cooling-tower design data
%   CTAmbient : ambient-air boundary condition
%   CTAir     : psychrometric state returned by ct_psychrometrics
%
% Field names themselves are not redundantly prefixed with CT because the
% owning structure already identifies the component. Example:
%   CTInput.Me_available
%   CTOutput.Me_required
% rather than data.Me_available or CTInput.CT_Me_available.

CTConfig = struct();
CTConfig.component = 'CT';

% -------------------------------------------------------------------------
% Model choices
% -------------------------------------------------------------------------
CTConfig.model.runtime   = 'merkel_classic';
CTConfig.model.reference = 'cdawc';

% -------------------------------------------------------------------------
% Psychrometrics
% -------------------------------------------------------------------------
% Runtime cooling-tower calculations use fast built-in psychrometric
% correlations. CoolProp remains in read_epw_weather.m for one-time
% weather preprocessing/wet-bulb cache generation. Avoid using 'auto' in
% annual CT loops because repeated Python/CoolProp calls are too slow.
CTConfig.psychrometrics.backend = 'correlation';

% -------------------------------------------------------------------------
% Water properties
% -------------------------------------------------------------------------
CTConfig.water.property_backend = 'fluidgrid';
CTConfig.water.gridFile = 'thermoDB_Water_V5.mat';
CTConfig.water.P_Pa = 2e5;
CTConfig.water.cp_JkgK = 4180;
CTConfig.water.rho_kgm3 = 997;

% -------------------------------------------------------------------------
% Numerics
% -------------------------------------------------------------------------
CTConfig.numerics.merkel_n_intervals = 100;
CTConfig.numerics.min_approach_C = 0.05;
CTConfig.numerics.min_enthalpy_potential_Jkgda = 10;
CTConfig.numerics.min_fan_ratio_for_solve = 1e-4;
CTConfig.numerics.target_temperature_tolerance_C = 1e-4;

% -------------------------------------------------------------------------
% Default rating point used by examples / quickstarts
% -------------------------------------------------------------------------
% These are not hidden universal constants. They only define a convenient
% example tower based on the old model regression case.
CTConfig.rating.Q_rated_W = 2217000*2;
CTConfig.rating.T_db_rated_C = 35.0;
CTConfig.rating.T_wb_rated_C = 24.0;
CTConfig.rating.P_atm_rated_Pa = 101325;
CTConfig.rating.approach_rated_C = 4.0;
CTConfig.rating.range_rated_C = 5.0;
CTConfig.rating.L_over_G_rated = 1.0;

% -------------------------------------------------------------------------
% Transfer characteristic correlation
% -------------------------------------------------------------------------
% Phase 2 implements a normalized Kloppers-Kroger trickle-fill style
% correlation as reported in Lemouari et al. (2009). Since Me = KaV/L, the
% water-flow exponent for Me is (0.43177 - 1).
CTConfig.transfer.correlation = 'kloppers_trickle_normalized';
CTConfig.transfer.Ka_water_exponent = 0.43177;
CTConfig.transfer.Ka_air_exponent   = 0.641400;
CTConfig.transfer.Ka_Twin_exponent  = 0.178670;
CTConfig.transfer.Me_water_exponent = CTConfig.transfer.Ka_water_exponent - 1.0;
CTConfig.transfer.Me_air_exponent   = CTConfig.transfer.Ka_air_exponent;
CTConfig.transfer.Me_Twin_exponent  = CTConfig.transfer.Ka_Twin_exponent;
CTConfig.transfer.temperature_ratio_basis = 'Celsius';

% -------------------------------------------------------------------------
% Fan model
% -------------------------------------------------------------------------
CTConfig.fan.model = 'affinity_cubic';
CTConfig.fan.fan_ratio_min = 0.0;
CTConfig.fan.fan_ratio_max = 1.0;
CTConfig.fan.hp_per_refrigeration_ton = 0.015;

% -------------------------------------------------------------------------
% Water-consumption model
% -------------------------------------------------------------------------
% Evaporation is calculated from the dry-air humidity balance. Drift and
% cycles of concentration are project-level/user inputs and should be
% documented when used in final simulations.
CTConfig.water_consumption.enabled = true;
CTConfig.water_consumption.drift_fraction = 0;
CTConfig.water_consumption.cycles_of_concentration = NaN;
CTConfig.water_consumption.drift_basis = 'circulating_water_mass_flow';

% Air outlet state used by the fast Merkel runtime model.
CTConfig.air_outlet.model = 'saturated_exit';
end
