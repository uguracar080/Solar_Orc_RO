function orcCondRate = orc_condenser_rating(orcThermo,orcColdStream,orcCondenser,config)
% ORC_CONDENSER_RATING Rate the frozen ORC condenser at one timestep.
%
% The geometry is fixed from Stage-1. The function recalculates local HTC,
% required area, pressure drops and outlet cooling-water temperature.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 4 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % rating timer [-]

% =========================================================================
% GEOMETRY SAFETY
% =========================================================================
if config.orc_stage2_requireFrozenGeometry && ...
        (~isfield(orcCondenser,'module') || ...
         ~isfield(orcCondenser.module,'orc_geometryFrozen') || ...
         ~orcCondenser.module.orc_geometryFrozen)
    error('orc_condenser_rating:GeometryNotFrozen', ...
        'Stage-2 rating requires frozen condenser geometry.');
end

geom = orcCondenser.module.geometry;                 % frozen module geometry [-]
Npar = orcCondenser.N_parallel_installed;            % installed modules [-]
Nactive = Npar;                                      % v0.9 no staging [-]
Ageo_mod = pi*geom.do*geom.Nt*geom.Ltube;            % module area [m2]

% =========================================================================
% DUTY SPLIT
% =========================================================================
orcFluid = orcThermo.orc_fluid;                      % working fluid [-]
P_cond = orcThermo.P_orccond;                        % condensing pressure [Pa]
mdot_orc_mod = orcThermo.mdot_orc/Nactive;           % module ORC flow [kg/s]
mdot_cold_mod = orcColdStream.mdot/Nactive;          % module CW flow [kg/s]

h_g = orc_properties(config,'H','P',P_cond,'Q',1,orcFluid); % sat vap [J/kg]
h_f = orc_properties(config,'H','P',P_cond,'Q',0,orcFluid); % sat liq [J/kg]
T_sat = orc_properties(config,'T','P',P_cond,'Q',0,orcFluid); % [K]

Q_dsh = mdot_orc_mod*max(0,orcThermo.h_orcturb_out-h_g); % [W/module]
Q_2ph = mdot_orc_mod*max(0,h_g-h_f);                 % [W/module]
Q_total = Q_dsh + Q_2ph;                             % [W/module]

% =========================================================================
% COOLING-WATER PATH
% =========================================================================
h_cold_in = orc_stream_properties(config,orcColdStream,'H','T', ...
    orcColdStream.T_in,'P',orcColdStream.P_in);       % [J/kg]
h_cold_int = h_cold_in + Q_2ph/mdot_cold_mod;        % [J/kg]
h_cold_out = h_cold_int + Q_dsh/mdot_cold_mod;       % [J/kg]

T_cold_in = orcColdStream.T_in;                       % [K]
T_cold_int = orc_stream_properties(config,orcColdStream,'T','P', ...
    orcColdStream.P_in,'H',h_cold_int);               % [K]
T_cold_out = orc_stream_properties(config,orcColdStream,'T','P', ...
    orcColdStream.P_in,'H',h_cold_out);               % [K]
T_turb_out = orcThermo.T_orcturb_out;                % [K]

% =========================================================================
% APPROACH CHECK
% =========================================================================
dT_2ph_1 = T_sat - T_cold_int;                        % [K]
dT_2ph_2 = T_sat - T_cold_in;                         % [K]
if Q_dsh > 0
    dT_dsh_1 = T_turb_out - T_cold_out;               % [K]
    dT_dsh_2 = T_sat - T_cold_int;                    % [K]
else
    dT_dsh_1 = inf;                                   % inactive [K]
    dT_dsh_2 = inf;                                   % inactive [K]
end
minApproach = min([dT_2ph_1,dT_2ph_2,dT_dsh_1,dT_dsh_2]); % [K]
approachOK = minApproach > config.orc_hx_minApproach_K; % [-]

% =========================================================================
% TUBE-SIDE PROPERTIES
% =========================================================================
flow_cold_2ph = localExternalFlowAtH(config,orcColdStream,mdot_cold_mod, ...
    0.5*(h_cold_in+h_cold_int));                      % condensation zone [-]
flow_cold_dsh = localExternalFlowAtH(config,orcColdStream,mdot_cold_mod, ...
    0.5*(h_cold_int+h_cold_out));                     % dsh zone [-]

tube_2ph = orc_sthe_tube_singlephase(flow_cold_2ph,geom,NaN);
tube_dsh = orc_sthe_tube_singlephase(flow_cold_dsh,geom,NaN);

% =========================================================================
% DESUPERHEATING AREA
% =========================================================================
if Q_dsh > 0 && approachOK
    h_dsh_avg = 0.5*(orcThermo.h_orcturb_out + h_g);  % [J/kg]
    flow_wf_dsh = localWorkFluidFlowAtPH(config,orcFluid,mdot_orc_mod,P_cond,h_dsh_avg);
    shell_dsh = orc_sthe_shell_singlephase(flow_wf_dsh,geom,config);
    U_dsh = localOverallU(shell_dsh.h,tube_dsh.h);    % [W/m2/K]
    LMTD_dsh = localLmtd(dT_dsh_1,dT_dsh_2);          % [K]
    A_dsh = Q_dsh/(U_dsh*LMTD_dsh);                   % [m2]
else
    flow_wf_dsh = struct(); shell_dsh = struct();     % inactive [-]
    U_dsh = NaN; LMTD_dsh = NaN; A_dsh = 0;           % [-]
end

% =========================================================================
% CONDENSATION AREA
% =========================================================================
if Q_2ph > 0 && approachOK
    LMTD_2ph = localLmtd(dT_2ph_1,dT_2ph_2);          % [K]
    [A_2ph,condensation,U_2ph] = localCondensationAreaIteration( ...
        Q_2ph,LMTD_2ph,tube_2ph.h,P_cond,geom,orcFluid,config);
else
    LMTD_2ph = NaN; condensation = struct();          % inactive [-]
    U_2ph = NaN; A_2ph = 0;                           % [-]
end

% =========================================================================
% REQUIRED AREA AND PRESSURE DROP
% =========================================================================
A_req = A_dsh + A_2ph;                                % [m2/module]
areaRatio = A_req/max(Ageo_mod,eps);                  % [-]

f_dsh = A_dsh/max(A_req,eps);                         % zone fraction [-]
f_2ph = A_2ph/max(A_req,eps);                         % zone fraction [-]

tube_2ph_dp = orc_sthe_tube_singlephase(flow_cold_2ph,geom,geom.Ltube*f_2ph);
tube_dsh_dp = orc_sthe_tube_singlephase(flow_cold_dsh,geom,geom.Ltube*f_dsh);
dp_cold_mod = tube_2ph_dp.dp + tube_dsh_dp.dp;       % [Pa]

if Q_dsh > 0
    shell_dsh_dp = orc_sthe_shell_singlephase(flow_wf_dsh,geom,config);
    dp_wf_dsh = shell_dsh_dp.dp*f_dsh;                % [Pa]
else
    shell_dsh_dp = struct(); dp_wf_dsh = 0;           % [Pa]
end

flow_wf_cond_2ph = localTwoPhaseFlowAtSat(config,orcFluid,mdot_orc_mod, ...
    P_cond,1,0,f_2ph,'condensation');                 % [-]
cond_dp = orc_sthe_shell_twophase_dp(flow_wf_cond_2ph,geom,config);
dp_wf_2ph = cond_dp.dp;                               % [Pa]
dp_wf_mod = dp_wf_dsh + dp_wf_2ph;                   % [Pa]

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcCondRate = struct();
orcCondRate.orc_hxType = 'condenser';                 % [-]
orcCondRate.N_parallel_installed = Npar;              % [-]
orcCondRate.N_parallel_active = Nactive;              % [-]
orcCondRate.A_geo_module = Ageo_mod;                  % [m2]
orcCondRate.A_req_module = A_req;                     % [m2]
orcCondRate.A_ratio = areaRatio;                      % [-]
orcCondRate.A_tol_rel = config.orc_stage2_areaTol_rel; % [-]
orcCondRate.Q_orccond_module = Q_total;               % [W]
orcCondRate.Q_orccond_total = Q_total*Nactive;        % [W]
orcCondRate.T_orccw_in = T_cold_in;                   % [K]
orcCondRate.T_orccw_int = T_cold_int;                 % [K]
orcCondRate.T_orccw_out = T_cold_out;                 % [K]
orcCondRate.dp_orccond_wf = dp_wf_mod;                % branch dP [Pa]
orcCondRate.dp_orccw = dp_cold_mod;                   % branch dP [Pa]
orcCondRate.deltaT_pinch = minApproach;               % [K]
orcCondRate.orc_areaOK = areaRatio <= 1 + config.orc_stage2_areaTol_rel; % [-]
orcCondRate.orc_approachOK = approachOK;              % [-]
orcCondRate.orc_feasible = orcCondRate.orc_areaOK && approachOK; % [-]
orcCondRate.orc_elapsed_s = toc(orcTimer);            % [s]

orcCondRate.zones.dsh = struct('Q',Q_dsh,'A',A_dsh,'U',U_dsh, ...
    'LMTD',LMTD_dsh,'tube',tube_dsh,'shell',shell_dsh); % [-]
orcCondRate.zones.cond = struct('Q',Q_2ph,'A',A_2ph,'U',U_2ph, ...
    'LMTD',LMTD_2ph,'tube',tube_2ph,'condensation',condensation,'dp_twophase',cond_dp); % [-]

end

% =========================================================================
% LOCAL HELPERS
% =========================================================================
function flow = localWorkFluidFlowAtPH(config,orcFluid,mdot,P,h)
flow = struct();
flow.mdot = mdot;                                     % [kg/s]
flow.rho = orc_properties(config,'D','P',P,'H',h,orcFluid); % [kg/m3]
flow.mu = orc_properties(config,'V','P',P,'H',h,orcFluid);  % [Pa s]
flow.k = orc_properties(config,'L','P',P,'H',h,orcFluid);   % [W/m/K]
flow.cp = orc_properties(config,'C','P',P,'H',h,orcFluid);  % [J/kg/K]
end

function flow = localExternalFlowAtH(config,orcStream,mdot,h)
T = orc_stream_properties(config,orcStream,'T','P',orcStream.P_in,'H',h); % [K]
flow = struct();
flow.mdot = mdot;                                     % [kg/s]
flow.T = T;                                           % [K]
flow.h = h;                                           % [J/kg]
flow.rho = orc_stream_properties(config,orcStream,'D','T',T,'P',orcStream.P_in); % [kg/m3]
flow.mu = orc_stream_properties(config,orcStream,'V','T',T,'P',orcStream.P_in);  % [Pa s]
flow.k = orc_stream_properties(config,orcStream,'L','T',T,'P',orcStream.P_in);   % [W/m/K]
flow.cp = orc_stream_properties(config,orcStream,'C','T',T,'P',orcStream.P_in);  % [J/kg/K]
end

function U = localOverallU(hShell,hTube)
U = 1/(1/max(hShell,eps) + 1/max(hTube,eps));         % [W/m2/K]
end

function lmtd = localLmtd(dT1,dT2)
if dT1 <= 0 || dT2 <= 0
    error('orc_condenser_rating:InvalidLMTD','Temperature approaches must be positive.');
end
if abs(dT1-dT2) <= 1e-9*max([dT1,dT2,1])
    lmtd = 0.5*(dT1+dT2);                             % [K]
else
    lmtd = (dT1-dT2)/log(dT1/dT2);                    % [K]
end
end

function [A,condensation,U] = localCondensationAreaIteration(Q,lmtd,hTube,P,geom,orcFluid,config)
T_sat = orc_properties(config,'T','P',P,'Q',0,orcFluid);       % [K]
h_l = orc_properties(config,'H','P',P,'Q',0,orcFluid);         % [J/kg]
h_v = orc_properties(config,'H','P',P,'Q',1,orcFluid);         % [J/kg]
condInput = struct();
condInput.rho_l = orc_properties(config,'D','P',P,'Q',0,orcFluid); % [kg/m3]
condInput.rho_v = orc_properties(config,'D','P',P,'Q',1,orcFluid); % [kg/m3]
condInput.mu_l = orc_properties(config,'V','P',P,'Q',0,orcFluid);  % [Pa s]
condInput.k_l = orc_properties(config,'L','P',P,'Q',0,orcFluid);   % [W/m/K]
condInput.h_fg = h_v - h_l;                           % [J/kg]
condInput.T_sat = T_sat;                              % [K]
A = max(Q/(400*lmtd),1e-6);                           % initial area [m2]
T_wall = T_sat - 5;                                   % initial wall temp [K]
for iter = 1:config.orc_max_htc_iter
    condInput.T_wall = T_wall;                        % [K]
    condensation = orc_sthe_condensation(condInput,geom,config);
    U = localOverallU(condensation.h,hTube);          % [W/m2/K]
    Anew = Q/(U*lmtd);                                % [m2]
    q_flux = Q/Anew;                                  % [W/m2]
    T_wall_new = T_sat - q_flux/max(condensation.h,eps); % [K]
    if abs(Anew-A)/max(Anew,eps) < config.orc_tol_htc_rel
        A = Anew; return
    end
    A = 0.5*A + 0.5*Anew;                             % damping [m2]
    T_wall = 0.5*T_wall + 0.5*T_wall_new;             % damping [K]
end
A = Anew;                                             % last value [m2]
end

function flow = localTwoPhaseFlowAtSat(config,orcFluid,mdot,P,xIn,xOut,areaFraction,mode)
flow = struct();
flow.mdot = mdot;                                     % [kg/s]
flow.P = P;                                           % [Pa]
flow.rho_l = orc_properties(config,'D','P',P,'Q',0,orcFluid); % [kg/m3]
flow.rho_v = orc_properties(config,'D','P',P,'Q',1,orcFluid); % [kg/m3]
flow.mu_l = orc_properties(config,'V','P',P,'Q',0,orcFluid);  % [Pa s]
flow.mu_v = orc_properties(config,'V','P',P,'Q',1,orcFluid);  % [Pa s]
flow.k_l = orc_properties(config,'L','P',P,'Q',0,orcFluid);   % [W/m/K]
flow.k_v = orc_properties(config,'L','P',P,'Q',1,orcFluid);   % [W/m/K]
flow.cp_l = localSafeSatCp(config,orcFluid,P,0);      % [J/kg/K]
flow.cp_v = localSafeSatCp(config,orcFluid,P,1);      % [J/kg/K]
flow.x_in = xIn;                                      % [-]
flow.x_out = xOut;                                    % [-]
flow.areaFraction = areaFraction;                     % [-]
flow.mode = mode;                                     % [-]
end

function cp = localSafeSatCp(config,orcFluid,P,Q)
try
    cp = orc_properties(config,'C','P',P,'Q',Q,orcFluid); % [J/kg/K]
catch
    cp = 1000;                                       % fallback [J/kg/K]
end
if ~isfinite(cp) || cp <= 0
    cp = 1000;                                       % fallback [J/kg/K]
end
end
