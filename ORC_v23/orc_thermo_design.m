function orcThermo = orc_thermo_design(systemInput,config,orcHydraulic)
% ORC_THERMO_DESIGN Solve the nominal simple subcritical ORC cycle.
%
% Required systemInput fields:
%   systemInput.orc_P_evap_des   evaporator outlet pressure [Pa]
%   systemInput.orc_P_cond_des   condenser outlet pressure [Pa]
%
% One sizing specification is required:
%   systemInput.orc_W_nom        requested net ORC power [W]
% or
%   systemInput.orc_mdot_des     working-fluid mass flow [kg/s]
%
% Optional hydraulic fields:
%   orcHydraulic.orc_dp_evap_wf  working-fluid evaporator pressure drop [Pa]
%   orcHydraulic.orc_dp_cond_wf  working-fluid condenser pressure drop [Pa]

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 2 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcFluid = config.orc_fluid;

if nargin < 3 || isempty(orcHydraulic)
    orcHydraulic = struct();
end

if ~isfield(orcHydraulic,'orc_dp_evap_wf')
    orcHydraulic.orc_dp_evap_wf = 0;                 % evaporator pressure drop [Pa]
end
if ~isfield(orcHydraulic,'orc_dp_cond_wf')
    orcHydraulic.orc_dp_cond_wf = 0;                 % condenser pressure drop [Pa]
end

% =========================================================================
% REQUIRED DESIGN INPUTS
% =========================================================================
requiredFields = {'orc_P_evap_des','orc_P_cond_des'};
for iField = 1:numel(requiredFields)
    if ~isfield(systemInput,requiredFields{iField})
        error('orc_thermo_design:MissingInput', ...
            'Missing systemInput.%s',requiredFields{iField});
    end
end

orcP_evap = systemInput.orc_P_evap_des;              % evaporator outlet pressure [Pa]
orcP_cond = systemInput.orc_P_cond_des;              % condenser outlet pressure [Pa]
orcDP_evap = orcHydraulic.orc_dp_evap_wf;            % evaporator pressure drop [Pa]
orcDP_cond = orcHydraulic.orc_dp_cond_wf;             % condenser pressure drop [Pa]

orcP_pumpOut = orcP_evap + orcDP_evap;               % pump discharge pressure [Pa]
orcP_turbOut = orcP_cond + orcDP_cond;                % turbine exhaust pressure [Pa]

% =========================================================================
% PRESSURE FEASIBILITY
% =========================================================================
orcP_crit = orc_properties(config,'PCRIT',orcFluid); % critical pressure [Pa]

if ~(orcP_cond > 0 && orcP_evap > orcP_cond)
    error('orc_thermo_design:PressureOrder', ...
        'Require 0 < P_orccond < P_orcevap.');
end
if orcP_evap >= orcP_crit
    error('orc_thermo_design:SupercriticalInput', ...
        'The current ORC v0.1 design solver is subcritical.');
end
if orcP_turbOut >= orcP_evap
    error('orc_thermo_design:InvalidExpansion', ...
        'Turbine outlet pressure must be below turbine inlet pressure.');
end

% =========================================================================
% STATE: CONDENSER OUTLET / PUMP INLET
% =========================================================================
if ~strcmpi(config.orc_condOutletMode,'sat_liquid')
    error('orc_thermo_design:CondOutletMode', ...
        'ORC v0.1 supports saturated-liquid condenser outlet only.');
end

h_orcpump_in = orc_properties(config,'H','P',orcP_cond,'Q',0,orcFluid); % [J/kg]
s_orcpump_in = orc_properties(config,'S','P',orcP_cond,'Q',0,orcFluid); % [J/kg/K]
T_orcpump_in = orc_properties(config,'T','P',orcP_cond,'Q',0,orcFluid); % [K]
rho_orcpump_in = orc_properties(config,'D','P',orcP_cond,'Q',0,orcFluid); % [kg/m3]

% =========================================================================
% STATE: PUMP OUTLET
% =========================================================================
h_orcpump_out_s = orc_properties(config,'H','P',orcP_pumpOut, ...
    'S',s_orcpump_in,orcFluid);                       % isentropic enthalpy [J/kg]

h_orcpump_out = h_orcpump_in + ...
    (h_orcpump_out_s - h_orcpump_in)/config.orc_eta_pump; % actual enthalpy [J/kg]

orcStatePumpOut = stateFromPH(config,orcFluid,orcP_pumpOut,h_orcpump_out);

% =========================================================================
% STATE: EVAPORATOR OUTLET / TURBINE INLET
% =========================================================================
if ~strcmpi(config.orc_turbineInletMode,'sat_vapor')
    error('orc_thermo_design:TurbineInletMode', ...
        'ORC v0.1 supports saturated-vapor turbine inlet only.');
end

h_orcturb_in = orc_properties(config,'H','P',orcP_evap,'Q',1,orcFluid); % [J/kg]
s_orcturb_in = orc_properties(config,'S','P',orcP_evap,'Q',1,orcFluid); % [J/kg/K]
T_orcturb_in = orc_properties(config,'T','P',orcP_evap,'Q',1,orcFluid); % [K]
rho_orcturb_in = orc_properties(config,'D','P',orcP_evap,'Q',1,orcFluid); % [kg/m3]

% =========================================================================
% STATE: TURBINE OUTLET
% =========================================================================
h_orcturb_out_s = orc_properties(config,'H','P',orcP_turbOut, ...
    'S',s_orcturb_in,orcFluid);                       % isentropic enthalpy [J/kg]

h_orcturb_out = h_orcturb_in - config.orc_eta_turb* ...
    (h_orcturb_in - h_orcturb_out_s);                 % actual enthalpy [J/kg]

orcStateTurbOut = stateFromPH(config,orcFluid,orcP_turbOut,h_orcturb_out);

% =========================================================================
% SPECIFIC CYCLE PERFORMANCE
% =========================================================================
w_orcturb = h_orcturb_in - h_orcturb_out;            % turbine work [J/kg]
w_orcpump = h_orcpump_out - h_orcpump_in;            % pump work [J/kg]
w_orcnet = w_orcturb - w_orcpump;                    % net ORC work [J/kg]
q_orcevap = h_orcturb_in - h_orcpump_out;             % evaporator heat input [J/kg]
q_orccond = h_orcturb_out - h_orcpump_in;             % condenser heat rejection [J/kg]

if w_orcnet <= 0 || q_orcevap <= 0
    error('orc_thermo_design:NonPositiveCycle', ...
        'The selected pressures do not produce a positive ORC cycle.');
end

% =========================================================================
% DESIGN MASS FLOW
% =========================================================================
hasMdot = isfield(systemInput,'orc_mdot_des') && ...
    isfinite(systemInput.orc_mdot_des) && systemInput.orc_mdot_des > 0;
hasPower = isfield(systemInput,'orc_W_nom') && ...
    isfinite(systemInput.orc_W_nom) && systemInput.orc_W_nom > 0;

if hasMdot
    mdot_orc = systemInput.orc_mdot_des;              % working-fluid flow [kg/s]
elseif hasPower
    mdot_orc = systemInput.orc_W_nom/w_orcnet;        % working-fluid flow [kg/s]
else
    error('orc_thermo_design:MissingSizeSpecification', ...
        'Provide systemInput.orc_W_nom or systemInput.orc_mdot_des.');
end

% =========================================================================
% TOTAL CYCLE PERFORMANCE
% =========================================================================
W_orcturb = mdot_orc*w_orcturb;                       % turbine power [W]
W_orcpump = mdot_orc*w_orcpump;                       % pump power [W]
W_orcnet = W_orcturb - W_orcpump;                     % net ORC power [W]
Q_orcevap = mdot_orc*q_orcevap;                       % evaporator duty [W]
Q_orccond = mdot_orc*q_orccond;                       % condenser duty [W]
eta_orc_th = W_orcnet/Q_orcevap;                      % thermal efficiency [-]

orcEnergyResidual = Q_orcevap - W_orcnet - Q_orccond; % first-law residual [W]
orcEnergyResidualRel = abs(orcEnergyResidual)/max(abs(Q_orcevap),eps); % [-]

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcThermo = struct();

orcThermo.orc_fluid = orcFluid;
orcThermo.P_orc_crit = orcP_crit;                     % critical pressure [Pa]
orcThermo.P_orcevap = orcP_evap;                      % turbine inlet pressure [Pa]
orcThermo.P_orccond = orcP_cond;                      % pump inlet pressure [Pa]
orcThermo.P_orcpump_out = orcP_pumpOut;               % pump discharge pressure [Pa]
orcThermo.P_orcturb_out = orcP_turbOut;               % turbine exhaust pressure [Pa]
orcThermo.dp_orcevap_wf = orcDP_evap;                 % evaporator pressure drop [Pa]
orcThermo.dp_orccond_wf = orcDP_cond;                 % condenser pressure drop [Pa]

orcThermo.h_orcpump_in = h_orcpump_in;                % [J/kg]
orcThermo.s_orcpump_in = s_orcpump_in;                % [J/kg/K]
orcThermo.T_orcpump_in = T_orcpump_in;                % [K]
orcThermo.rho_orcpump_in = rho_orcpump_in;            % [kg/m3]

orcThermo.h_orcpump_out_s = h_orcpump_out_s;          % [J/kg]
orcThermo.h_orcpump_out = h_orcpump_out;              % [J/kg]
orcThermo.T_orcpump_out = orcStatePumpOut.T;          % [K]
orcThermo.s_orcpump_out = orcStatePumpOut.s;          % [J/kg/K]
orcThermo.rho_orcpump_out = orcStatePumpOut.rho;      % [kg/m3]

orcThermo.h_orcturb_in = h_orcturb_in;                % [J/kg]
orcThermo.s_orcturb_in = s_orcturb_in;                % [J/kg/K]
orcThermo.T_orcturb_in = T_orcturb_in;                % [K]
orcThermo.rho_orcturb_in = rho_orcturb_in;            % [kg/m3]

orcThermo.h_orcturb_out_s = h_orcturb_out_s;          % [J/kg]
orcThermo.h_orcturb_out = h_orcturb_out;              % [J/kg]
orcThermo.T_orcturb_out = orcStateTurbOut.T;          % [K]
orcThermo.s_orcturb_out = orcStateTurbOut.s;          % [J/kg/K]
orcThermo.rho_orcturb_out = orcStateTurbOut.rho;      % [kg/m3]
orcThermo.x_orcturb_out = orcStateTurbOut.x;          % quality if two-phase [-]

orcThermo.mdot_orc = mdot_orc;                        % [kg/s]
orcThermo.W_orcturb = W_orcturb;                      % [W]
orcThermo.W_orcpump = W_orcpump;                      % [W]
orcThermo.W_orcnet = W_orcnet;                        % [W]
orcThermo.Q_orcevap = Q_orcevap;                      % [W]
orcThermo.Q_orccond = Q_orccond;                      % [W]
orcThermo.eta_orc_th = eta_orc_th;                    % [-]

orcThermo.orc_energyResidual = orcEnergyResidual;     % [W]
orcThermo.orc_energyResidualRel = orcEnergyResidualRel; % [-]
orcThermo.orc_energyBalanceOK = ...
    orcEnergyResidualRel <= config.orc_tol_energy_rel;

if hasPower
    orcThermo.W_orc_nom_requested = systemInput.orc_W_nom; % [W]
    orcThermo.W_orc_nom_error = W_orcnet - systemInput.orc_W_nom; % [W]
else
    orcThermo.W_orc_nom_requested = NaN;              % [W]
    orcThermo.W_orc_nom_error = NaN;                  % [W]
end

end

% =========================================================================
% LOCAL STATE HELPER
% =========================================================================
function orcState = stateFromPH(config,orcFluid,orcPressure,orcEnthalpy)
% Build a state from pressure and enthalpy.
orcState = struct();
orcState.P = orcPressure;                             % [Pa]
orcState.h = orcEnthalpy;                             % [J/kg]
orcState.T = orc_properties(config,'T','P',orcPressure,'H',orcEnthalpy,orcFluid); % [K]
orcState.s = orc_properties(config,'S','P',orcPressure,'H',orcEnthalpy,orcFluid); % [J/kg/K]
orcState.rho = orc_properties(config,'D','P',orcPressure,'H',orcEnthalpy,orcFluid); % [kg/m3]

% CoolProp returns an out-of-range quality for single-phase states.
try
    orcQuality = orc_properties(config,'Q','P',orcPressure,'H',orcEnthalpy,orcFluid);
    if orcQuality >= 0 && orcQuality <= 1
        orcState.x = orcQuality;                      % [-]
    else
        orcState.x = NaN;                             % single-phase state [-]
    end
catch
    orcState.x = NaN;                                 % single-phase state [-]
end
end
