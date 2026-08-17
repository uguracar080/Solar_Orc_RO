function orcEvapRate = orc_evaporator_rating(orcThermo,orcHotStream,orcEvaporator,config)
% ORC_EVAPORATOR_RATING Rate the frozen ORC evaporator at one timestep.
%
% The geometry is fixed from Stage-1. The function recalculates local HTC,
% required area, pressure drops and outlet hot-stream temperature.

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
        (~isfield(orcEvaporator,'module') || ...
         ~isfield(orcEvaporator.module,'orc_geometryFrozen') || ...
         ~orcEvaporator.module.orc_geometryFrozen)
    error('orc_evaporator_rating:GeometryNotFrozen', ...
        'Stage-2 rating requires frozen evaporator geometry.');
end

geom = orcEvaporator.module.geometry;                % frozen module geometry [-]
Npar = orcEvaporator.N_parallel_installed;           % installed modules [-]
Nactive = Npar;                                      % v0.9 no staging [-]
Ageo_mod = pi*geom.do*geom.Nt*geom.Ltube;            % module area [m2]

% =========================================================================
% DUTY SPLIT
% =========================================================================
orcFluid = orcThermo.orc_fluid;                      % working fluid [-]
P_evap = orcThermo.P_orcevap;                        % evaporation pressure [Pa]
mdot_orc_mod = orcThermo.mdot_orc/Nactive;           % module ORC flow [kg/s]
mdot_hot_mod = orcHotStream.mdot/Nactive;            % module hot flow [kg/s]

h_f = orc_properties(config,'H','P',P_evap,'Q',0,orcFluid); % sat liq [J/kg]
h_g = orc_properties(config,'H','P',P_evap,'Q',1,orcFluid); % sat vap [J/kg]
T_sat = orc_properties(config,'T','P',P_evap,'Q',0,orcFluid); % [K]

Q_pre = mdot_orc_mod*max(0,h_f-orcThermo.h_orcpump_out); % [W/module]
Q_boil = mdot_orc_mod*max(0,h_g-h_f);                % [W/module]
Q_total = Q_pre + Q_boil;                            % [W/module]

% =========================================================================
% HOT-STREAM PATH
% =========================================================================
h_hot_in = orc_stream_properties(config,orcHotStream,'H','T', ...
    orcHotStream.T_in,'P',orcHotStream.P_in);         % [J/kg]
h_hot_after_boil = h_hot_in - Q_boil/mdot_hot_mod;   % [J/kg]
h_hot_out = h_hot_after_boil - Q_pre/mdot_hot_mod;   % [J/kg]

T_hot_in = orcHotStream.T_in;                         % [K]
T_hot_int = orc_stream_properties(config,orcHotStream,'T','P', ...
    orcHotStream.P_in,'H',h_hot_after_boil);          % [K]
T_hot_out = orc_stream_properties(config,orcHotStream,'T','P', ...
    orcHotStream.P_in,'H',h_hot_out);                 % [K]
T_wf_in = orcThermo.T_orcpump_out;                   % [K]

% =========================================================================
% APPROACH CHECK
% =========================================================================
dT_boil_1 = T_hot_in - T_sat;                         % [K]
dT_boil_2 = T_hot_int - T_sat;                        % [K]
dT_pre_1 = T_hot_int - T_sat;                         % [K]
dT_pre_2 = T_hot_out - T_wf_in;                       % [K]
minApproach = min([dT_boil_1,dT_boil_2,dT_pre_1,dT_pre_2]); % [K]
approachOK = minApproach > config.orc_hx_minApproach_K; % [-]

% =========================================================================
% TUBE-SIDE PROPERTIES
% =========================================================================
flow_hot_boil = localExternalFlowAtH(config,orcHotStream,mdot_hot_mod, ...
    0.5*(h_hot_in+h_hot_after_boil));                 % boiling zone [-]
flow_hot_pre = localExternalFlowAtH(config,orcHotStream,mdot_hot_mod, ...
    0.5*(h_hot_after_boil+h_hot_out));                % preheat zone [-]

tube_boil = orc_sthe_tube_singlephase(flow_hot_boil,geom,NaN);
tube_pre = orc_sthe_tube_singlephase(flow_hot_pre,geom,NaN);

% =========================================================================
% PREHEATING AREA
% =========================================================================
if Q_pre > 0 && approachOK
    h_pre_avg = 0.5*(orcThermo.h_orcpump_out + h_f);  % [J/kg]
    flow_wf_pre = localWorkFluidFlowAtPH(config,orcFluid,mdot_orc_mod,P_evap,h_pre_avg);
    shell_pre = orc_sthe_shell_singlephase(flow_wf_pre,geom,config);
    U_pre = localOverallU(shell_pre.h,tube_pre.h);    % [W/m2/K]
    LMTD_pre = localLmtd(dT_pre_1,dT_pre_2);          % [K]
    A_pre = Q_pre/(U_pre*LMTD_pre);                   % [m2]
else
    flow_wf_pre = struct(); shell_pre = struct();     % inactive [-]
    U_pre = NaN; LMTD_pre = NaN; A_pre = 0;           % [-]
end

% =========================================================================
% BOILING AREA
% =========================================================================
if Q_boil > 0 && approachOK
    LMTD_boil = localLmtd(dT_boil_1,dT_boil_2);       % [K]
    [A_boil,boiling,U_boil] = localBoilingAreaIteration( ...
        Q_boil,LMTD_boil,tube_boil.h,P_evap,orcThermo.P_orc_crit,geom,config);
else
    LMTD_boil = NaN; boiling = struct();              % inactive [-]
    U_boil = NaN; A_boil = 0;                         % [-]
end

% =========================================================================
% REQUIRED AREA AND PRESSURE DROP
% =========================================================================
A_req = A_pre + A_boil;                               % [m2/module]
areaRatio = A_req/max(Ageo_mod,eps);                  % [-]

f_pre = A_pre/max(A_req,eps);                         % zone length fraction [-]
f_boil = A_boil/max(A_req,eps);                       % zone length fraction [-]

tube_pre_dp = orc_sthe_tube_singlephase(flow_hot_pre,geom,geom.Ltube*f_pre);
tube_boil_dp = orc_sthe_tube_singlephase(flow_hot_boil,geom,geom.Ltube*f_boil);
dp_hot_mod = tube_pre_dp.dp + tube_boil_dp.dp;        % [Pa]

if Q_pre > 0
    shell_pre_dp = orc_sthe_shell_singlephase(flow_wf_pre,geom,config);
    dp_wf_pre = shell_pre_dp.dp*f_pre;                % [Pa]
else
    shell_pre_dp = struct(); dp_wf_pre = 0;           % [Pa]
end

flow_wf_boil_2ph = localTwoPhaseFlowAtSat(config,orcFluid,mdot_orc_mod, ...
    P_evap,0,1,f_boil,'evaporation');                 % [-]
boil_dp = orc_sthe_shell_twophase_dp(flow_wf_boil_2ph,geom,config);
dp_wf_boil = boil_dp.dp;                              % [Pa]
dp_wf_mod = dp_wf_pre + dp_wf_boil;                  % [Pa]

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcEvapRate = struct();
orcEvapRate.orc_hxType = 'evaporator';                % [-]
orcEvapRate.N_parallel_installed = Npar;              % [-]
orcEvapRate.N_parallel_active = Nactive;              % [-]
orcEvapRate.A_geo_module = Ageo_mod;                  % [m2]
orcEvapRate.A_req_module = A_req;                     % [m2]
orcEvapRate.A_ratio = areaRatio;                      % [-]
orcEvapRate.A_tol_rel = config.orc_stage2_areaTol_rel; % [-]
orcEvapRate.Q_orcevap_module = Q_total;               % [W]
orcEvapRate.Q_orcevap_total = Q_total*Nactive;        % [W]
orcEvapRate.T_orchtf_in = T_hot_in;                   % [K]
orcEvapRate.T_orchtf_int = T_hot_int;                 % [K]
orcEvapRate.T_orchtf_out = T_hot_out;                 % [K]
orcEvapRate.dp_orcevap_wf = dp_wf_mod;                % branch dP [Pa]
orcEvapRate.dp_orchtf = dp_hot_mod;                   % branch dP [Pa]
orcEvapRate.deltaT_pinch = minApproach;               % [K]
orcEvapRate.orc_areaOK = areaRatio <= 1 + config.orc_stage2_areaTol_rel; % [-]
orcEvapRate.orc_approachOK = approachOK;              % [-]
orcEvapRate.orc_feasible = orcEvapRate.orc_areaOK && approachOK; % [-]
orcEvapRate.orc_elapsed_s = toc(orcTimer);            % [s]

orcEvapRate.zones.pre = struct('Q',Q_pre,'A',A_pre,'U',U_pre, ...
    'LMTD',LMTD_pre,'tube',tube_pre,'shell',shell_pre); % [-]
orcEvapRate.zones.boil = struct('Q',Q_boil,'A',A_boil,'U',U_boil, ...
    'LMTD',LMTD_boil,'tube',tube_boil,'boiling',boiling,'dp_twophase',boil_dp); % [-]

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
    error('orc_evaporator_rating:InvalidLMTD','Temperature approaches must be positive.');
end
if abs(dT1-dT2) <= 1e-9*max([dT1,dT2,1])
    lmtd = 0.5*(dT1+dT2);                             % [K]
else
    lmtd = (dT1-dT2)/log(dT1/dT2);                    % [K]
end
end

function [A,boiling,U] = localBoilingAreaIteration(Q,lmtd,hTube,P,Pcrit,geom,config)
A = max(Q/(300*lmtd),1e-6);                           % initial area [m2]
for iter = 1:config.orc_max_htc_iter
    q_flux = Q/A;                                     % [W/m2]
    boilInput = struct('q_flux',q_flux,'P',P,'Pcrit',Pcrit);
    boiling = orc_sthe_boiling(boilInput,geom,config);
    U = localOverallU(boiling.h,hTube);               % [W/m2/K]
    Anew = Q/(U*lmtd);                                % [m2]
    if abs(Anew-A)/max(Anew,eps) < config.orc_tol_htc_rel
        A = Anew; return
    end
    A = 0.5*A + 0.5*Anew;                             % damping [m2]
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
