function orcStep = orc_offdesign_rating(orcDesign,orcHotStream,orcColdStream,orcOperatingInput,config)
% ORC_OFFDESIGN_RATING Rate one fixed-geometry ORC operating point.
%
% The function never resizes the evaporator or condenser. If an extreme
% operating point is outside the numerical/property domain, it can return a
% guarded infeasible step instead of stopping the annual simulation.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 5 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % step timer [-]

if nargin < 4 || isempty(orcOperatingInput)
    orcOperatingInput = struct();                    % defaults below [-]
end

% =========================================================================
% FROZEN-GEOMETRY CHECK
% =========================================================================
if config.orc_stage2_requireFrozenGeometry && ...
        (~isfield(orcDesign,'orc_geometryFrozen') || ~orcDesign.orc_geometryFrozen)
    error('orc_offdesign_rating:GeometryNotFrozen', ...
        'Run orc_stage1_sizing before off-design rating.');
end

% =========================================================================
% PROTECTED RATING BLOCK
% =========================================================================
try
    orcStep = localRatePoint( ...
        orcDesign,orcHotStream,orcColdStream,orcOperatingInput,config,orcTimer);
catch ME
    if config.orc_stage2_returnInfeasibleOnError
        orcStep = localBuildGuardedStep( ...
            orcDesign,orcHotStream,orcColdStream,orcOperatingInput,config,orcTimer,ME);
    else
        rethrow(ME)
    end
end

end

% =========================================================================
% LOCAL MAIN RATING ROUTINE
% =========================================================================
function orcStep = localRatePoint(orcDesign,orcHotStream,orcColdStream,orcOperatingInput,config,orcTimer)
% Execute fixed-geometry hydraulic iteration for a valid operating point.

% -------------------------------------------------------------------------
% Operating inputs.
% -------------------------------------------------------------------------
P_orcevap = localGetField(orcOperatingInput,'orc_P_evap', ...
    orcDesign.orc_thermo.P_orcevap);                 % [Pa]
P_orccond = localGetField(orcOperatingInput,'orc_P_cond', ...
    orcDesign.orc_thermo.P_orccond);                 % [Pa]

systemInput = struct();                              % thermo input [-]
systemInput.orc_P_evap_des = P_orcevap;              % [Pa]
systemInput.orc_P_cond_des = P_orccond;              % [Pa]

if isfield(orcOperatingInput,'orc_mdot') && orcOperatingInput.orc_mdot > 0
    systemInput.orc_mdot_des = orcOperatingInput.orc_mdot; % [kg/s]
elseif isfield(orcOperatingInput,'orc_W_nom') && orcOperatingInput.orc_W_nom > 0
    systemInput.orc_W_nom = orcOperatingInput.orc_W_nom;   % [W]
else
    systemInput.orc_mdot_des = orcDesign.orc_thermo.mdot_orc; % [kg/s]
end

% -------------------------------------------------------------------------
% Initial pressure-loss estimates.
% -------------------------------------------------------------------------
hyd = struct();                                      % dP estimate [-]
hyd.orc_dp_evap_wf = localGetField(orcOperatingInput,'orc_dp_evap_wf', ...
    orcDesign.orc_thermo.dp_orcevap_wf);             % [Pa]
hyd.orc_dp_cond_wf = localGetField(orcOperatingInput,'orc_dp_cond_wf', ...
    orcDesign.orc_thermo.dp_orccond_wf);             % [Pa]

orcIterLog = struct([]);                             % iteration log [-]
conv = false;                                        % convergence flag [-]
finalRel = inf;                                      % final residual [-]

% -------------------------------------------------------------------------
% Fixed-geometry hydraulic iteration.
% -------------------------------------------------------------------------
for iter = 1:config.orc_max_hydraulic_iter
    orcThermo = orc_thermo_design(systemInput,config,hyd); % cycle state [-]

    orcEvapRate = orc_evaporator_rating( ...
        orcThermo,orcHotStream,orcDesign.orc_evaporator,config); % [-]
    orcCondRate = orc_condenser_rating( ...
        orcThermo,orcColdStream,orcDesign.orc_condenser,config); % [-]

    dpEvapCalc = orcEvapRate.dp_orcevap_wf;          % [Pa]
    dpCondCalc = orcCondRate.dp_orccond_wf;          % [Pa]

    relEvap = abs(dpEvapCalc-hyd.orc_dp_evap_wf)/max(abs(dpEvapCalc),1); % [-]
    relCond = abs(dpCondCalc-hyd.orc_dp_cond_wf)/max(abs(dpCondCalc),1); % [-]
    finalRel = max(relEvap,relCond);                 % [-]

    orcIterLog(iter).iter = iter;                    %#ok<AGROW>
    orcIterLog(iter).dp_evap_in = hyd.orc_dp_evap_wf; %#ok<AGROW>
    orcIterLog(iter).dp_cond_in = hyd.orc_dp_cond_wf; %#ok<AGROW>
    orcIterLog(iter).dp_evap_calc = dpEvapCalc;      %#ok<AGROW>
    orcIterLog(iter).dp_cond_calc = dpCondCalc;      %#ok<AGROW>
    orcIterLog(iter).rel = finalRel;                 %#ok<AGROW>

    if finalRel < config.orc_tol_hydraulic_rel
        conv = true;                                 % converged [-]
        break
    end

    r = config.orc_hydraulic_relaxation;             % relaxation [-]
    hyd.orc_dp_evap_wf = (1-r)*hyd.orc_dp_evap_wf + r*dpEvapCalc; % [Pa]
    hyd.orc_dp_cond_wf = (1-r)*hyd.orc_dp_cond_wf + r*dpCondCalc; % [Pa]
end

% -------------------------------------------------------------------------
% Output struct.
% -------------------------------------------------------------------------
orcStep = struct();
orcStep.orc_modelVersion = config.orc_modelVersion;  % [-]
orcStep.orc_thermo = orcThermo;                      % [-]
orcStep.orc_evaporator_rate = orcEvapRate;           % [-]
orcStep.orc_condenser_rate = orcCondRate;            % [-]
orcStep.orc_hotStream = orcHotStream;                % [-]
orcStep.orc_coldStream = orcColdStream;              % [-]
orcStep.orc_operatingInput = orcOperatingInput;      % [-]
orcStep.orc_hydraulicIterLog = orcIterLog;           % [-]
orcStep.orc_hydraulicConverged = conv;               % [-]
orcStep.orc_hydraulicFinalRel = finalRel;            % [-]
orcStep.orc_hydraulicNiter = iter;                   % [-]
orcStep.orc_errorCaught = false;                     % no protected error [-]
orcStep.orc_errorMessage = '';                       % [-]
orcStep.orc_status = 'rated';                        % status text [-]
orcStep.orc_feasible = conv && orcEvapRate.orc_feasible && ...
    orcCondRate.orc_feasible && orcThermo.orc_energyBalanceOK; % [-]
orcStep.orc_elapsed_s = toc(orcTimer);               % [s]
end

% =========================================================================
% GUARDED INFEASIBLE OUTPUT
% =========================================================================
function orcStep = localBuildGuardedStep(orcDesign,orcHotStream,orcColdStream,orcOperatingInput,config,orcTimer,ME)
% Build a non-crashing off-design output for infeasible extreme cases.

P_orcevap = localGetField(orcOperatingInput,'orc_P_evap', ...
    orcDesign.orc_thermo.P_orcevap);                 % [Pa]
P_orccond = localGetField(orcOperatingInput,'orc_P_cond', ...
    orcDesign.orc_thermo.P_orccond);                 % [Pa]
mdot_orc = localGetField(orcOperatingInput,'orc_mdot', ...
    orcDesign.orc_thermo.mdot_orc);                  % [kg/s]

orcThermo = struct();                                % minimal thermo [-]
orcThermo.orc_fluid = localGetField(orcDesign.orc_thermo,'orc_fluid',config.orc_fluid); % [-]
orcThermo.P_orcevap = P_orcevap;                     % [Pa]
orcThermo.P_orccond = P_orccond;                     % [Pa]
orcThermo.mdot_orc = mdot_orc;                       % [kg/s]
orcThermo.W_orcturb = 0;                             % [W]
orcThermo.W_orcpump = 0;                             % [W]
orcThermo.W_orcnet = 0;                              % [W]
orcThermo.Q_orcevap = 0;                             % [W]
orcThermo.Q_orccond = 0;                             % [W]
orcThermo.eta_orc_th = NaN;                          % [-]
orcThermo.orc_energyBalanceOK = false;               % [-]

orcEvapRate = localBlankHxRate('evaporator',orcHotStream.T_in); % [-]
orcCondRate = localBlankHxRate('condenser',orcColdStream.T_in); % [-]

orcStep = struct();
orcStep.orc_modelVersion = config.orc_modelVersion;  % [-]
orcStep.orc_thermo = orcThermo;                      % [-]
orcStep.orc_evaporator_rate = orcEvapRate;           % [-]
orcStep.orc_condenser_rate = orcCondRate;            % [-]
orcStep.orc_hotStream = orcHotStream;                % [-]
orcStep.orc_coldStream = orcColdStream;              % [-]
orcStep.orc_operatingInput = orcOperatingInput;      % [-]
orcStep.orc_hydraulicIterLog = struct([]);           % [-]
orcStep.orc_hydraulicConverged = false;              % [-]
orcStep.orc_hydraulicFinalRel = NaN;                 % [-]
orcStep.orc_hydraulicNiter = 0;                      % [-]
orcStep.orc_errorCaught = true;                      % guarded error [-]
orcStep.orc_errorMessage = ME.message;               % diagnostic [-]
orcStep.orc_status = 'guarded-infeasible';           % status text [-]
orcStep.orc_feasible = false;                        % infeasible [-]
orcStep.orc_elapsed_s = toc(orcTimer);               % [s]
end

function hx = localBlankHxRate(hxType,T_in)
% Create a minimal HX-rate struct for guarded infeasible cases.
hx = struct();                                       % [-]
hx.orc_hxType = hxType;                              % [-]
hx.N_parallel_installed = NaN;                       % [-]
hx.N_parallel_active = NaN;                          % [-]
hx.A_geo_module = NaN;                               % [m2]
hx.A_req_module = NaN;                               % [m2]
hx.A_ratio = NaN;                                    % [-]
hx.A_tol_rel = NaN;                                  % [-]
hx.T_orchtf_in = T_in;                               % [K]
hx.T_orchtf_out = NaN;                               % [K]
hx.T_orccw_in = T_in;                                % [K]
hx.T_orccw_out = NaN;                                % [K]
hx.dp_orcevap_wf = NaN;                              % [Pa]
hx.dp_orccond_wf = NaN;                              % [Pa]
hx.dp_orchtf = NaN;                                  % [Pa]
hx.dp_orccw = NaN;                                   % [Pa]
hx.deltaT_pinch = NaN;                               % [K]
hx.orc_areaOK = false;                               % [-]
hx.orc_approachOK = false;                           % [-]
hx.orc_feasible = false;                             % [-]
hx.orc_elapsed_s = 0;                                % [s]
hx.zones = struct();                                 % [-]
end

% =========================================================================
% LOCAL HELPER
% =========================================================================
function value = localGetField(s,fieldName,defaultValue)
if isfield(s,fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);                           % user value [-]
else
    value = defaultValue;                            % default [-]
end
end
