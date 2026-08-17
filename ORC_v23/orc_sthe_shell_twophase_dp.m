function orcTwoPhaseDP = orc_sthe_shell_twophase_dp(orc2phFlow,orcGeometry,config)
% ORC_STHE_SHELL_TWOPHASE_DP Preliminary shell-side two-phase dP model.
%
%
% NOTE: This is a preliminary homogeneous-equilibrium pressure-drop
% layer used to activate cycle-HX hydraulic coupling. It is not yet
% the final publication-grade Walraven two-phase shell-side dP model.
% The model uses a homogeneous-equilibrium mixture in the existing
% Bell-Delaware shell-side pressure-drop kernel. The zone is split into
% quality segments and the full-geometry dP is length-scaled by areaFraction.
%
% Required orc2phFlow fields:
%   mdot          working-fluid mass flow in one module [kg/s]
%   rho_l         saturated liquid density [kg/m3]
%   rho_v         saturated vapor density [kg/m3]
%   mu_l          saturated liquid viscosity [Pa s]
%   mu_v          saturated vapor viscosity [Pa s]
%   k_l           saturated liquid conductivity [W/m/K]
%   k_v           saturated vapor conductivity [W/m/K]
%   cp_l          saturated liquid heat capacity [J/kg/K]
%   cp_v          saturated vapor heat capacity [J/kg/K]
%   x_in          inlet vapor quality [-]
%   x_out         outlet vapor quality [-]
%   areaFraction  fraction of total tube length/area used by this zone [-]
%   mode          'evaporation' or 'condensation' [-]

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 3 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

% =========================================================================
% INPUT CHECK
% =========================================================================
requiredFields = {'mdot','rho_l','rho_v','mu_l','mu_v','k_l','k_v', ...
    'cp_l','cp_v','x_in','x_out','areaFraction','mode'};
for iField = 1:numel(requiredFields)
    if ~isfield(orc2phFlow,requiredFields{iField})
        error('orc_sthe_shell_twophase_dp:MissingInput', ...
            'Missing orc2phFlow.%s',requiredFields{iField});
    end
end

if orc2phFlow.mdot <= 0 || orc2phFlow.areaFraction <= 0
    error('orc_sthe_shell_twophase_dp:InvalidFlow', ...
        'Two-phase mass flow and area fraction must be positive.');
end

% =========================================================================
% QUALITY GRID
% =========================================================================
Nseg = max(1,round(config.orc_hx_twophaseDpSegments)); % [-]
xMin = config.orc_hx_twophaseDpMinQuality;            % [-]
xMax = 1 - xMin;                                      % [-]

xEdges = linspace(orc2phFlow.x_in,orc2phFlow.x_out,Nseg+1); % [-]

dpSeg = zeros(Nseg,1);                                 % [Pa]
xMidLog = zeros(Nseg,1);                               % [-]
rhoLog = zeros(Nseg,1);                                % [kg/m3]
muLog = zeros(Nseg,1);                                 % [Pa s]

% =========================================================================
% HOMOGENEOUS SEGMENT SUM
% =========================================================================
for iSeg = 1:Nseg
    xMid = 0.5*(xEdges(iSeg)+xEdges(iSeg+1));          % segment quality [-]
    xMid = min(max(xMid,xMin),xMax);                   % clamp endpoints [-]

    rhoH = 1/((1-xMid)/orc2phFlow.rho_l + xMid/orc2phFlow.rho_v); % [kg/m3]
    muH = 1/((1-xMid)/orc2phFlow.mu_l + xMid/orc2phFlow.mu_v);    % [Pa s]
    kH = (1-xMid)*orc2phFlow.k_l + xMid*orc2phFlow.k_v;           % [W/m/K]
    cpH = (1-xMid)*orc2phFlow.cp_l + xMid*orc2phFlow.cp_v;        % [J/kg/K]

    if ~isfinite(kH) || kH <= 0
        kH = 0.05;                                  % dP-only fallback [W/m/K]
    end
    if ~isfinite(cpH) || cpH <= 0
        cpH = 1000;                                  % dP-only fallback [J/kg/K]
    end

    mixFlow = struct();
    mixFlow.mdot = orc2phFlow.mdot;                    % [kg/s]
    mixFlow.rho = rhoH;                                % [kg/m3]
    mixFlow.mu = muH;                                  % [Pa s]
    mixFlow.k = kH;                                    % [W/m/K]
    mixFlow.cp = cpH;                                  % [J/kg/K]

    shellMix = orc_sthe_shell_singlephase(mixFlow,orcGeometry,config);
    dpSeg(iSeg) = shellMix.dp*orc2phFlow.areaFraction/Nseg; % [Pa]

    xMidLog(iSeg) = xMid;                              % [-]
    rhoLog(iSeg) = rhoH;                               % [kg/m3]
    muLog(iSeg) = muH;                                 % [Pa s]
end

dpFriction = sum(dpSeg);                               % [Pa]

% =========================================================================
% OPTIONAL ACCELERATION TERM
% =========================================================================
dpAccel = 0;                                           % [Pa]
if config.orc_hx_twophaseDpIncludeAccel
    G = orc2phFlow.mdot/max(orcGeometry.AoCr,eps);     % mass flux [kg/m2/s]
    betaIn = localMomentumFactor(orc2phFlow.x_in,orc2phFlow,xMin,xMax);  % [m3/kg]
    betaOut = localMomentumFactor(orc2phFlow.x_out,orc2phFlow,xMin,xMax); % [m3/kg]
    dpRaw = G^2*(betaOut-betaIn);                      % signed term [Pa]

    if strcmpi(orc2phFlow.mode,'evaporation')
        dpAccel = max(0,dpRaw);                        % pressure loss [Pa]
    else
        dpAccel = max(0,-dpRaw);                       % conservative loss [Pa]
    end
end

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcTwoPhaseDP = struct();
orcTwoPhaseDP.model = char(config.orc_hx_twophaseDpModel); % [-]
orcTwoPhaseDP.mode = char(orc2phFlow.mode);           % [-]
orcTwoPhaseDP.dp = dpFriction + dpAccel;              % [Pa]
orcTwoPhaseDP.dp_friction = dpFriction;               % [Pa]
orcTwoPhaseDP.dp_acceleration = dpAccel;              % [Pa]
orcTwoPhaseDP.Nseg = Nseg;                            % [-]
orcTwoPhaseDP.x_mid = xMidLog;                        % [-]
orcTwoPhaseDP.rho_h = rhoLog;                         % [kg/m3]
orcTwoPhaseDP.mu_h = muLog;                           % [Pa s]
orcTwoPhaseDP.dp_segment = dpSeg;                     % [Pa]
orcTwoPhaseDP.areaFraction = orc2phFlow.areaFraction; % [-]
orcTwoPhaseDP.isPreliminary = true;                   % [-]

end

% =========================================================================
% LOCAL: HOMOGENEOUS MOMENTUM FACTOR
% =========================================================================
function beta = localMomentumFactor(x,flow,xMin,xMax)
% Homogeneous momentum factor for optional acceleration term. [m3/kg]
x = min(max(x,xMin),xMax);                             % [-]
alpha = (x/flow.rho_v)/((x/flow.rho_v)+((1-x)/flow.rho_l)); % void fraction [-]
alpha = min(max(alpha,xMin),xMax);                     % clamp [-]
beta = (1-x)^2/(flow.rho_l*(1-alpha)) + x^2/(flow.rho_v*alpha); % [m3/kg]
end
