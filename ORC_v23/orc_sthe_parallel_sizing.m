function orcSizing = orc_sthe_parallel_sizing(orcHxInput,config)
% ORC_STHE_PARALLEL_SIZING Size one or more identical STHE modules.
%
% The outer system supplies a total ORC duty and total flow rates. This file
% tests N_parallel = 1,2,... and sizes one identical module for each case.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 2 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

% =========================================================================
% INPUT CHECK
% =========================================================================
if ~isfield(orcHxInput,'orc_hxType')
    error('orc_sthe_parallel_sizing:MissingHxType', ...
        'orcHxInput.orc_hxType is required.');
end
orcHxType = lower(string(orcHxInput.orc_hxType));

% =========================================================================
% SEARCH OVER PARALLEL MODULE COUNT
% =========================================================================
orcTimer = tic;                                      % sizing timer [-]
orcBest = [];
orcCandidateLog = struct([]);
orcLogIndex = 0;
orcEvalCount = 0;                                    % tested candidates [-]

orcNparallelList = localBuildParallelList(orcHxType,config); % [-]

for iPar = 1:numel(orcNparallelList)
    orcNparallel = orcNparallelList(iPar);           % [-]

    % ---------------------------------------------------------------------
    % Build and evaluate Nt list for this parallel count.
    % ---------------------------------------------------------------------
    [orcNtList,orcSearchInfo] = localBuildNtList(orcHxType,orcNparallel,config); % [-]
    orcBestThisParallel = [];

    for iNt = 1:numel(orcNtList)
        orcNt = orcNtList(iNt);                      % [-]
        [orcCandidate,orcMessage] = localEvaluateCandidate( ...
            orcHxInput,orcHxType,orcNparallel,orcNt,config);
        orcEvalCount = orcEvalCount + 1;             % [-]

        if config.orc_hx_storeCandidateLogFull
            orcLogIndex = orcLogIndex + 1;
            orcCandidateLog(orcLogIndex).N_parallel = orcNparallel; %#ok<AGROW>
            orcCandidateLog(orcLogIndex).Nt = orcNt; %#ok<AGROW>
            orcCandidateLog(orcLogIndex).ok = orcCandidate.ok; %#ok<AGROW>
            orcCandidateLog(orcLogIndex).message = orcMessage; %#ok<AGROW>
        end

        if orcCandidate.ok
            if isempty(orcBestThisParallel) || ...
                    localCandidateIsBetter(orcCandidate,orcBestThisParallel)
                orcBestThisParallel = orcCandidate;
            end
        end
    end

    % ---------------------------------------------------------------------
    % Coarse-to-fine refinement around the best coarse candidate.
    % ---------------------------------------------------------------------
    if isempty(orcSearchInfo.hintUsed) || ~orcSearchInfo.hintUsed
        if strcmpi(config.orc_hx_Nt_searchMode,'coarseFine') && ...
                ~isempty(orcBestThisParallel)
            orcNtFine = localFineNtList( ...
                orcBestThisParallel.module.geometry.Nt,config); % [-]
            orcNtFine = setdiff(orcNtFine,orcNtList,'stable');  % new only [-]

            for iNt = 1:numel(orcNtFine)
                orcNt = orcNtFine(iNt);              % [-]
                [orcCandidate,orcMessage] = localEvaluateCandidate( ...
                    orcHxInput,orcHxType,orcNparallel,orcNt,config);
                orcEvalCount = orcEvalCount + 1;     % [-]

                if config.orc_hx_storeCandidateLogFull
                    orcLogIndex = orcLogIndex + 1;
                    orcCandidateLog(orcLogIndex).N_parallel = orcNparallel; %#ok<AGROW>
                    orcCandidateLog(orcLogIndex).Nt = orcNt; %#ok<AGROW>
                    orcCandidateLog(orcLogIndex).ok = orcCandidate.ok; %#ok<AGROW>
                    orcCandidateLog(orcLogIndex).message = orcMessage; %#ok<AGROW>
                end

                if orcCandidate.ok
                    if isempty(orcBestThisParallel) || ...
                            localCandidateIsBetter(orcCandidate,orcBestThisParallel)
                        orcBestThisParallel = orcCandidate;
                    end
                end
            end
        end
    end

    % ---------------------------------------------------------------------
    % Accept first feasible parallel count.
    % ---------------------------------------------------------------------
    if ~isempty(orcBestThisParallel)
        orcBest = orcBestThisParallel;
        break
    end
end

orcElapsed = toc(orcTimer);                           % [s]
if ~config.orc_hx_storeCandidateLogFull
    orcCandidateLog = struct();
    orcCandidateLog.nEvaluated = orcEvalCount;        % [-]
    orcCandidateLog.searchMode = config.orc_hx_Nt_searchMode; % [-]
end

% =========================================================================
% OUTPUT
% =========================================================================
if isempty(orcBest)
    error('orc_sthe_parallel_sizing:NoFeasibleDesign', ...
        'No feasible %s STHE design was found.',char(orcHxType));
end

orcSizing = struct();
orcSizing.orc_hxType = char(orcHxType);               % [-]
orcSizing.N_parallel = orcBest.N_parallel;            % [-]
orcSizing.module = orcBest.module;                    % one module [-]
orcSizing.total = orcBest.total;                      % all modules [-]
orcSizing.orc_sizingOK = true;                        % [-]
orcSizing.message = orcBest.message;                  % [-]
orcSizing.candidateLog = orcCandidateLog;             % diagnostics [-]
orcSizing.orc_elapsed_s = orcElapsed;                  % sizing time [s]
orcSizing.orc_nCandidatesEvaluated = orcEvalCount;     % tested candidates [-]

end

% =========================================================================
% LOCAL: BUILD PARALLEL LIST
% =========================================================================
function NparList = localBuildParallelList(orcHxType,config)
% Build candidate parallel-module counts.
NparMax = config.orc_hx_maxParallelUnits;             % [-]
NparList = 1:NparMax;                                 % default [-]

if ~config.orc_hx_useSearchHints
    return
end

hintField = sprintf('orc_%s_Nparallel_hint',char(orcHxType)); % [-]
if isfield(config,hintField) && ~isempty(config.(hintField))
    hp = round(config.(hintField));                   % [-]
    if hp >= 1 && hp <= NparMax
        % Keep ascending order so the solver still prefers the lowest
        % feasible number of installed parallel modules.  The hint only
        % narrows the local neighbourhood; it must not make Npar=2 tested
        % before Npar=1, otherwise hydraulic iterations can jump to a
        % different architecture than the broad reference search.
        lo = max(1,hp-1);                             % [-]
        hi = min(NparMax,hp+1);                       % [-]
        NparList = lo:hi;                             % ascending [-]
    end
end
end

% =========================================================================
% LOCAL: BUILD NT LIST
% =========================================================================
function [NtList,info] = localBuildNtList(orcHxType,Nparallel,config)
% Build tube-count candidates for coarse/hint search.
info = struct();
info.hintUsed = false;                                % [-]
info.Nparallel = Nparallel;                           % [-]

NtMin = config.orc_hx_Nt_min;                         % [-]
NtMax = config.orc_hx_Nt_max;                         % [-]

if config.orc_hx_useSearchHints
    hintField = sprintf('orc_%s_Nt_hint',char(orcHxType)); % [-]
    parField = sprintf('orc_%s_Nparallel_hint',char(orcHxType)); % [-]
    if isfield(config,hintField) && ~isempty(config.(hintField))
        useHint = true;                               % [-]
        if isfield(config,parField) && ~isempty(config.(parField))
            useHint = round(config.(parField)) == Nparallel; % [-]
        end
        if useHint
            hNt = round(config.(hintField));          % [-]
            NtList = localWindowNtList(hNt,config.orc_hx_hintHalfWindow, ...
                config.orc_hx_Nt_step_fine,NtMin,NtMax); % [-]
            info.hintUsed = true;                     % [-]
            return
        end
    end
end

if strcmpi(config.orc_hx_Nt_searchMode,'coarseFine')
    NtList = NtMin:config.orc_hx_Nt_step_coarse:NtMax; % coarse [-]
else
    NtList = NtMin:config.orc_hx_Nt_step:NtMax;       % legacy [-]
end
NtList = unique(round(NtList));                       % [-]
end

% =========================================================================
% LOCAL: FINE NT LIST
% =========================================================================
function NtList = localFineNtList(NtCenter,config)
% Build fine tube-count candidates around a coarse winner.
NtList = localWindowNtList(NtCenter,config.orc_hx_Nt_fineHalfWindow, ...
    config.orc_hx_Nt_step_fine,config.orc_hx_Nt_min,config.orc_hx_Nt_max); % [-]
end

% =========================================================================
% LOCAL: WINDOW NT LIST
% =========================================================================
function NtList = localWindowNtList(NtCenter,halfWindow,step,NtMin,NtMax)
% Build bounded tube-count candidates around one center.
lo = max(NtMin,round(NtCenter-halfWindow));           % [-]
hi = min(NtMax,round(NtCenter+halfWindow));           % [-]
NtList = lo:step:hi;                                  % [-]
NtList = unique(round(NtList));                       % [-]
end

% =========================================================================
% LOCAL: EVALUATE ONE CANDIDATE
% =========================================================================
function [orcCandidate,orcMessage] = localEvaluateCandidate(orcHxInput,orcHxType,orcNparallel,orcNt,config)
% Evaluate one parallel-count/tube-count candidate.
try
    switch orcHxType
        case "evaporator"
            orcCandidate = localSizeEvaporatorModule( ...
                orcHxInput,orcNparallel,orcNt,config);
        case "condenser"
            orcCandidate = localSizeCondenserModule( ...
                orcHxInput,orcNparallel,orcNt,config);
        otherwise
            error('orc_sthe_parallel_sizing:UnknownHxType', ...
                'Unknown orc_hxType: %s',char(orcHxType));
    end
    orcMessage = orcCandidate.message;                % [-]
catch orcME
    orcCandidate = localFailedCandidate( ...
        orcHxType,orcNparallel,orcNt,orcME.message);
    orcMessage = orcME.message;                       % [-]
end
end

% =========================================================================
% LOCAL: EVAPORATOR MODULE SIZING
% =========================================================================
function orcCandidate = localSizeEvaporatorModule(orcHxInput,orcNparallel,orcNt,config)
% Size one evaporator module at fixed N_parallel and Nt.

orcThermo = orcHxInput.orcThermo;
orcHotStream = orcHxInput.orcHotStream;
orcFluid = orcThermo.orc_fluid;

% -------------------------------------------------------------------------
% Module duty and flow split.
% -------------------------------------------------------------------------
mdot_orc_mod = orcThermo.mdot_orc/orcNparallel;       % [kg/s]
mdot_hot_mod = orcHotStream.mdot/orcNparallel;        % [kg/s]

Q_pre = orcHxInput.Q_orcevap_pre/orcNparallel;        % [W]
Q_boil = orcHxInput.Q_orcevap_boil/orcNparallel;      % [W]
Q_total = Q_pre + Q_boil;                             % [W]

if Q_total <= 0 || mdot_orc_mod <= 0 || mdot_hot_mod <= 0
    error('localSizeEvaporatorModule:InvalidSplit', ...
        'Module duty and mass flows must be positive.');
end

% -------------------------------------------------------------------------
% Provisional geometry with target baffle spacing.
% -------------------------------------------------------------------------
geom0 = orc_sthe_geometry('evaporator',orcNt,NaN,config);
if ~geom0.orc_geometryOK
    error('localSizeEvaporatorModule:GeometryNotOK', ...
        'Provisional geometry is outside the accepted domain.');
end

% -------------------------------------------------------------------------
% Hot-side enthalpy path.
% -------------------------------------------------------------------------
h_hot_in = orc_stream_properties(config,orcHotStream,'H','T', ...
    orcHotStream.T_in,'P',orcHotStream.P_in);         % [J/kg]
h_hot_after_boil = h_hot_in - Q_boil/mdot_hot_mod;   % [J/kg]
h_hot_out = h_hot_after_boil - Q_pre/mdot_hot_mod;   % [J/kg]

T_hot_in = orcHotStream.T_in;                         % [K]
T_hot_int = orc_stream_properties(config,orcHotStream,'T','P', ...
    orcHotStream.P_in,'H',h_hot_after_boil);          % [K]
T_hot_out = orc_stream_properties(config,orcHotStream,'T','P', ...
    orcHotStream.P_in,'H',h_hot_out);                 % [K]

% -------------------------------------------------------------------------
% Working-fluid state path.
% -------------------------------------------------------------------------
P_evap = orcThermo.P_orcevap;                         % [Pa]
T_sat = orcHxInput.T_orcevap_sat;                     % [K]
T_wf_in = orcThermo.T_orcpump_out;                    % [K]

% -------------------------------------------------------------------------
% Positive approach checks.
% -------------------------------------------------------------------------
dT_boil_1 = T_hot_in - T_sat;                         % [K]
dT_boil_2 = T_hot_int - T_sat;                        % [K]
dT_pre_1 = T_hot_int - T_sat;                         % [K]
dT_pre_2 = T_hot_out - T_wf_in;                       % [K]

if min([dT_boil_1,dT_boil_2,dT_pre_1,dT_pre_2]) <= config.orc_hx_minApproach_K
    error('localSizeEvaporatorModule:ApproachViolation', ...
        'Evaporator has non-positive or too-small temperature approach.');
end

% -------------------------------------------------------------------------
% Tube-side hot-stream properties.
% -------------------------------------------------------------------------
flow_hot_boil = localExternalFlowAtH(config,orcHotStream,mdot_hot_mod, ...
    0.5*(h_hot_in+h_hot_after_boil));                 % boiling zone [-]
flow_hot_pre = localExternalFlowAtH(config,orcHotStream,mdot_hot_mod, ...
    0.5*(h_hot_after_boil+h_hot_out));                % preheat zone [-]

tube_boil = orc_sthe_tube_singlephase(flow_hot_boil,geom0,NaN);
tube_pre = orc_sthe_tube_singlephase(flow_hot_pre,geom0,NaN);

% -------------------------------------------------------------------------
% Shell-side preheater properties.
% -------------------------------------------------------------------------
h_pre_avg = 0.5*(orcThermo.h_orcpump_out + orcHxInput.h_orcevap_f); % [J/kg]
flow_wf_pre = localWorkFluidFlowAtPH(config,orcFluid,mdot_orc_mod,P_evap,h_pre_avg);
shell_pre = orc_sthe_shell_singlephase(flow_wf_pre,geom0,config);

% -------------------------------------------------------------------------
% Preheater area.
% -------------------------------------------------------------------------
U_pre = localOverallU(shell_pre.h,tube_pre.h);        % [W/m2/K]
lmtd_pre = localLmtd(dT_pre_1,dT_pre_2);              % [K]
A_pre = Q_pre/(U_pre*lmtd_pre);                       % [m2]

% -------------------------------------------------------------------------
% Boiling area with heat-flux iteration.
% -------------------------------------------------------------------------
lmtd_boil = localLmtd(dT_boil_1,dT_boil_2);           % [K]
[A_boil,boiling,U_boil] = localBoilingAreaIteration( ...
    Q_boil,lmtd_boil,tube_boil.h,P_evap,orcThermo.P_orc_crit,geom0,config);

% -------------------------------------------------------------------------
% Required module length.
% -------------------------------------------------------------------------
A_req = A_pre + A_boil;                               % [m2]
Ltube_req = A_req/(pi*geom0.do*orcNt);               % required length [m]
Ltube = Ltube_req*(1+config.orc_hx_designAreaMargin); % design margin [m]

geom = orc_sthe_geometry('evaporator',orcNt,Ltube,config);
localCheckFinalGeometry(geom,Ltube,config);

% -------------------------------------------------------------------------
% Recalculate pressure drops with frozen module length.
% -------------------------------------------------------------------------
tube_boil_dp = orc_sthe_tube_singlephase(flow_hot_boil,geom,Ltube*A_boil/A_req);
tube_pre_dp = orc_sthe_tube_singlephase(flow_hot_pre,geom,Ltube*A_pre/A_req);
shell_pre_dp = orc_sthe_shell_singlephase(flow_wf_pre,geom,config);

% Two-phase shell-side pressure drop.
dp_hot = tube_boil_dp.dp + tube_pre_dp.dp;            % [Pa]
dp_wf_pre = shell_pre_dp.dp*A_pre/max(A_req,eps);     % [Pa]

flow_wf_boil_2ph = localTwoPhaseFlowAtSat(config,orcFluid,mdot_orc_mod, ...
    P_evap,0,1,A_boil/max(A_req,eps),'evaporation'); % [-]
boil_dp = orc_sthe_shell_twophase_dp(flow_wf_boil_2ph,geom,config);
dp_wf_boil = boil_dp.dp;                              % [Pa]
dp_wf = dp_wf_pre + dp_wf_boil;                       % [Pa]

% -------------------------------------------------------------------------
% Candidate output.
% -------------------------------------------------------------------------
orcCandidate = localPackCandidate('evaporator',orcNparallel,geom,A_req,Ltube, ...
    Q_total,dp_wf,dp_hot,min([dT_boil_1,dT_boil_2,dT_pre_1,dT_pre_2]),config);

orcCandidate.module.zones.pre.Q = Q_pre;              % [W]
orcCandidate.module.zones.pre.A = A_pre;              % [m2]
orcCandidate.module.zones.pre.U = U_pre;              % [W/m2/K]
orcCandidate.module.zones.pre.LMTD = lmtd_pre;        % [K]
orcCandidate.module.zones.pre.shell = shell_pre;      % [-]
orcCandidate.module.zones.pre.tube = tube_pre;        % [-]

orcCandidate.module.zones.boil.Q = Q_boil;            % [W]
orcCandidate.module.zones.boil.A = A_boil;            % [m2]
orcCandidate.module.zones.boil.U = U_boil;            % [W/m2/K]
orcCandidate.module.zones.boil.LMTD = lmtd_boil;      % [K]
orcCandidate.module.zones.boil.boiling = boiling;     % [-]
orcCandidate.module.zones.boil.tube = tube_boil;      % [-]

orcCandidate.module.T_orchtf_in = T_hot_in;           % [K]
orcCandidate.module.T_orchtf_int = T_hot_int;         % [K]
orcCandidate.module.T_orchtf_out = T_hot_out;         % [K]
orcCandidate.module.mdot_orc_module = mdot_orc_mod;   % [kg/s]
orcCandidate.module.mdot_hot_module = mdot_hot_mod;   % [kg/s]
orcCandidate.module.zones.boil.dp_twophase = boil_dp;     % [-]
orcCandidate.module.dp_orcevap_wf_2phImplemented = true;  % [-]

end

% =========================================================================
% LOCAL: CONDENSER MODULE SIZING
% =========================================================================
function orcCandidate = localSizeCondenserModule(orcHxInput,orcNparallel,orcNt,config)
% Size one condenser module at fixed N_parallel and Nt.

orcThermo = orcHxInput.orcThermo;
orcColdStream = orcHxInput.orcColdStream;
orcFluid = orcThermo.orc_fluid;

% -------------------------------------------------------------------------
% Module duty and flow split.
% -------------------------------------------------------------------------
mdot_orc_mod = orcThermo.mdot_orc/orcNparallel;       % [kg/s]
mdot_cold_mod = orcColdStream.mdot/orcNparallel;      % [kg/s]

Q_dsh = orcHxInput.Q_orccond_dsh/orcNparallel;        % [W]
Q_2ph = orcHxInput.Q_orccond_2ph/orcNparallel;        % [W]
Q_total = Q_dsh + Q_2ph;                              % [W]

if Q_total <= 0 || mdot_orc_mod <= 0 || mdot_cold_mod <= 0
    error('localSizeCondenserModule:InvalidSplit', ...
        'Module duty and mass flows must be positive.');
end

% -------------------------------------------------------------------------
% Provisional geometry with target baffle spacing.
% -------------------------------------------------------------------------
geom0 = orc_sthe_geometry('condenser',orcNt,NaN,config);
if ~geom0.orc_geometryOK
    error('localSizeCondenserModule:GeometryNotOK', ...
        'Provisional geometry is outside the accepted domain.');
end

% -------------------------------------------------------------------------
% Cooling-water enthalpy path.
% -------------------------------------------------------------------------
h_cold_in = orc_stream_properties(config,orcColdStream,'H','T', ...
    orcColdStream.T_in,'P',orcColdStream.P_in);       % [J/kg]
h_cold_int = h_cold_in + Q_2ph/mdot_cold_mod;        % [J/kg]
h_cold_out = h_cold_int + Q_dsh/mdot_cold_mod;       % [J/kg]

T_cold_in = orcColdStream.T_in;                       % [K]
T_cold_int = orc_stream_properties(config,orcColdStream,'T','P', ...
    orcColdStream.P_in,'H',h_cold_int);               % [K]
T_cold_out = orc_stream_properties(config,orcColdStream,'T','P', ...
    orcColdStream.P_in,'H',h_cold_out);               % [K]

% -------------------------------------------------------------------------
% Working-fluid temperatures.
% -------------------------------------------------------------------------
P_cond = orcThermo.P_orccond;                         % [Pa]
T_sat = orcHxInput.T_orccond_sat;                     % [K]
T_turb_out = orcThermo.T_orcturb_out;                 % [K]

% -------------------------------------------------------------------------
% Positive approach checks.
% -------------------------------------------------------------------------
dT_2ph_1 = T_sat - T_cold_int;                        % [K]
dT_2ph_2 = T_sat - T_cold_in;                         % [K]

if Q_dsh > 0
    dT_dsh_1 = T_turb_out - T_cold_out;               % [K]
    dT_dsh_2 = T_sat - T_cold_int;                    % [K]
else
    dT_dsh_1 = inf;                                   % inactive zone [K]
    dT_dsh_2 = inf;                                   % inactive zone [K]
end

if min([dT_2ph_1,dT_2ph_2,dT_dsh_1,dT_dsh_2]) <= config.orc_hx_minApproach_K
    error('localSizeCondenserModule:ApproachViolation', ...
        'Condenser has non-positive or too-small temperature approach.');
end

% -------------------------------------------------------------------------
% Tube-side cooling-water properties.
% -------------------------------------------------------------------------
flow_cold_2ph = localExternalFlowAtH(config,orcColdStream,mdot_cold_mod, ...
    0.5*(h_cold_in+h_cold_int));                      % condensation zone [-]
flow_cold_dsh = localExternalFlowAtH(config,orcColdStream,mdot_cold_mod, ...
    0.5*(h_cold_int+h_cold_out));                     % dsh zone [-]

tube_2ph = orc_sthe_tube_singlephase(flow_cold_2ph,geom0,NaN);
tube_dsh = orc_sthe_tube_singlephase(flow_cold_dsh,geom0,NaN);

% -------------------------------------------------------------------------
% Desuperheating shell-side properties and area.
% -------------------------------------------------------------------------
if Q_dsh > 0
    h_dsh_avg = 0.5*(orcThermo.h_orcturb_out + orcHxInput.h_orccond_g); % [J/kg]
    flow_wf_dsh = localWorkFluidFlowAtPH(config,orcFluid,mdot_orc_mod, ...
        P_cond,h_dsh_avg);                            % [-]
    shell_dsh = orc_sthe_shell_singlephase(flow_wf_dsh,geom0,config);

    U_dsh = localOverallU(shell_dsh.h,tube_dsh.h);    % [W/m2/K]
    lmtd_dsh = localLmtd(dT_dsh_1,dT_dsh_2);          % [K]
    A_dsh = Q_dsh/(U_dsh*lmtd_dsh);                   % [m2]
else
    shell_dsh = struct();                             % inactive [-]
    U_dsh = NaN;                                      % [W/m2/K]
    lmtd_dsh = NaN;                                   % [K]
    A_dsh = 0;                                        % [m2]
end

% -------------------------------------------------------------------------
% Condensation area with wall-temperature iteration.
% -------------------------------------------------------------------------
lmtd_2ph = localLmtd(dT_2ph_1,dT_2ph_2);              % [K]
[A_2ph,condensation,U_2ph] = localCondensationAreaIteration( ...
    Q_2ph,lmtd_2ph,tube_2ph.h,P_cond,geom0,orcFluid,config);

% -------------------------------------------------------------------------
% Required module length.
% -------------------------------------------------------------------------
A_req = A_dsh + A_2ph;                                % [m2]
Ltube_req = A_req/(pi*geom0.do*orcNt);               % required length [m]
Ltube = Ltube_req*(1+config.orc_hx_designAreaMargin); % design margin [m]

geom = orc_sthe_geometry('condenser',orcNt,Ltube,config);
localCheckFinalGeometry(geom,Ltube,config);

% -------------------------------------------------------------------------
% Recalculate pressure drops with frozen module length.
% -------------------------------------------------------------------------
tube_2ph_dp = orc_sthe_tube_singlephase(flow_cold_2ph,geom,Ltube*A_2ph/A_req);
if Q_dsh > 0
    tube_dsh_dp = orc_sthe_tube_singlephase(flow_cold_dsh,geom,Ltube*A_dsh/A_req);
    dp_cold_dsh = tube_dsh_dp.dp;                     % [Pa]
else
    tube_dsh_dp = tube_dsh;                            % inactive [-]
    dp_cold_dsh = 0;                                   % [Pa]
end

dp_cold = tube_2ph_dp.dp + dp_cold_dsh;               % [Pa]
if Q_dsh > 0
    shell_dsh_dp = orc_sthe_shell_singlephase(flow_wf_dsh,geom,config);
    dp_wf_dsh = shell_dsh_dp.dp*A_dsh/max(A_req,eps); % [Pa]
else
    dp_wf_dsh = 0;                                    % [Pa]
end

% Two-phase shell-side pressure drop.
flow_wf_cond_2ph = localTwoPhaseFlowAtSat(config,orcFluid,mdot_orc_mod, ...
    P_cond,1,0,A_2ph/max(A_req,eps),'condensation'); % [-]
cond_dp = orc_sthe_shell_twophase_dp(flow_wf_cond_2ph,geom,config);
dp_wf_2ph = cond_dp.dp;                               % [Pa]
dp_wf = dp_wf_dsh + dp_wf_2ph;                       % [Pa]

% -------------------------------------------------------------------------
% Candidate output.
% -------------------------------------------------------------------------
orcCandidate = localPackCandidate('condenser',orcNparallel,geom,A_req,Ltube, ...
    Q_total,dp_wf,dp_cold,min([dT_2ph_1,dT_2ph_2,dT_dsh_1,dT_dsh_2]),config);

orcCandidate.module.zones.dsh.Q = Q_dsh;              % [W]
orcCandidate.module.zones.dsh.A = A_dsh;              % [m2]
orcCandidate.module.zones.dsh.U = U_dsh;              % [W/m2/K]
orcCandidate.module.zones.dsh.LMTD = lmtd_dsh;        % [K]
orcCandidate.module.zones.dsh.shell = shell_dsh;      % [-]
orcCandidate.module.zones.dsh.tube = tube_dsh;        % [-]

orcCandidate.module.zones.cond.Q = Q_2ph;             % [W]
orcCandidate.module.zones.cond.A = A_2ph;             % [m2]
orcCandidate.module.zones.cond.U = U_2ph;             % [W/m2/K]
orcCandidate.module.zones.cond.LMTD = lmtd_2ph;       % [K]
orcCandidate.module.zones.cond.condensation = condensation; % [-]
orcCandidate.module.zones.cond.tube = tube_2ph;       % [-]

orcCandidate.module.T_orccw_in = T_cold_in;           % [K]
orcCandidate.module.T_orccw_int = T_cold_int;         % [K]
orcCandidate.module.T_orccw_out = T_cold_out;         % [K]
orcCandidate.module.mdot_orc_module = mdot_orc_mod;   % [kg/s]
orcCandidate.module.mdot_cold_module = mdot_cold_mod; % [kg/s]
orcCandidate.module.zones.cond.dp_twophase = cond_dp;      % [-]
orcCandidate.module.dp_orccond_wf_2phImplemented = true;  % [-]

end


% =========================================================================
% LOCAL: TWO-PHASE SATURATION FLOW
% =========================================================================
function flow = localTwoPhaseFlowAtSat(config,orcFluid,mdot,P,xIn,xOut,areaFraction,mode)
% Build saturated two-phase flow properties for shell-side dP.
flow = struct();
flow.mdot = mdot;                                      % [kg/s]
flow.P = P;                                            % [Pa]
flow.rho_l = orc_properties(config,'D','P',P,'Q',0,orcFluid); % [kg/m3]
flow.rho_v = orc_properties(config,'D','P',P,'Q',1,orcFluid); % [kg/m3]
flow.mu_l = orc_properties(config,'V','P',P,'Q',0,orcFluid);  % [Pa s]
flow.mu_v = orc_properties(config,'V','P',P,'Q',1,orcFluid);  % [Pa s]
flow.k_l = orc_properties(config,'L','P',P,'Q',0,orcFluid);   % [W/m/K]
flow.k_v = orc_properties(config,'L','P',P,'Q',1,orcFluid);   % [W/m/K]
flow.cp_l = localSafeSatCp(config,orcFluid,P,0);              % [J/kg/K]
flow.cp_v = localSafeSatCp(config,orcFluid,P,1);              % [J/kg/K]
flow.x_in = xIn;                                      % [-]
flow.x_out = xOut;                                    % [-]
flow.areaFraction = areaFraction;                     % [-]
flow.mode = mode;                                     % [-]
end


% =========================================================================
% LOCAL: SAFE SATURATED CP
% =========================================================================
function cp = localSafeSatCp(config,orcFluid,P,Q)
% Return saturated cp; use harmless dP-only fallback if unavailable.
try
    cp = orc_properties(config,'C','P',P,'Q',Q,orcFluid); % [J/kg/K]
catch
    cp = 1000;                                           % dP-only fallback [J/kg/K]
end
if ~isfinite(cp) || cp <= 0
    cp = 1000;                                           % dP-only fallback [J/kg/K]
end
end

% =========================================================================
% LOCAL: WORKING-FLUID FLOW FROM P,H
% =========================================================================
function flow = localWorkFluidFlowAtPH(config,orcFluid,mdot,P,h)
% Build a flow-property struct from working-fluid P,H.
flow = struct();
flow.mdot = mdot;                                     % [kg/s]
flow.rho = orc_properties(config,'D','P',P,'H',h,orcFluid); % [kg/m3]
flow.mu = orc_properties(config,'V','P',P,'H',h,orcFluid);  % [Pa s]
flow.k = orc_properties(config,'L','P',P,'H',h,orcFluid);   % [W/m/K]
flow.cp = orc_properties(config,'C','P',P,'H',h,orcFluid);  % [J/kg/K]
end

% =========================================================================
% LOCAL: EXTERNAL FLOW FROM P,H
% =========================================================================
function flow = localExternalFlowAtH(config,orcStream,mdot,h)
% Build a flow-property struct from external-stream P,H.
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

% =========================================================================
% LOCAL: OVERALL U
% =========================================================================
function U = localOverallU(hShell,hTube)
% Calculate baseline overall HTC without wall or fouling. [W/m2/K]
U = 1/(1/max(hShell,eps) + 1/max(hTube,eps));
end

% =========================================================================
% LOCAL: LMTD
% =========================================================================
function lmtd = localLmtd(dT1,dT2)
% Counter-current log-mean temperature difference. [K]
if dT1 <= 0 || dT2 <= 0
    error('localLmtd:InvalidApproach', ...
        'Both terminal temperature differences must be positive.');
end
if abs(dT1-dT2) <= 1e-9*max([dT1,dT2,1])
    lmtd = 0.5*(dT1+dT2);                             % equal-limit [K]
else
    lmtd = (dT1-dT2)/log(dT1/dT2);                    % [K]
end
end

% =========================================================================
% LOCAL: BOILING AREA ITERATION
% =========================================================================
function [A,boiling,U] = localBoilingAreaIteration(Q,lmtd,hTube,P,Pcrit,geom,config)
% Iterate area because Palen-Mostinski depends on heat flux.
if Q <= 0
    A = 0; boiling = struct(); U = NaN; return
end
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

% =========================================================================
% LOCAL: CONDENSATION AREA ITERATION
% =========================================================================
function [A,condensation,U] = localCondensationAreaIteration(Q,lmtd,hTube,P,geom,orcFluid,config)
% Iterate area and wall temperature for film condensation.
if Q <= 0
    A = 0; condensation = struct(); U = NaN; return
end

T_sat = orc_properties(config,'T','P',P,'Q',0,orcFluid);       % [K]
h_l = orc_properties(config,'H','P',P,'Q',0,orcFluid);         % [J/kg]
h_v = orc_properties(config,'H','P',P,'Q',1,orcFluid);         % [J/kg]
condInput = struct();
condInput.rho_l = orc_properties(config,'D','P',P,'Q',0,orcFluid); % [kg/m3]
condInput.rho_v = orc_properties(config,'D','P',P,'Q',1,orcFluid); % [kg/m3]
condInput.mu_l = orc_properties(config,'V','P',P,'Q',0,orcFluid);  % [Pa s]
condInput.k_l = orc_properties(config,'L','P',P,'Q',0,orcFluid);   % [W/m/K]
condInput.h_fg = h_v - h_l;                              % [J/kg]
condInput.T_sat = T_sat;                                 % [K]

A = max(Q/(400*lmtd),1e-6);                              % initial area [m2]
T_wall = T_sat - 5;                                      % initial wall temp [K]
for iter = 1:config.orc_max_htc_iter
    condInput.T_wall = T_wall;                           % [K]
    condensation = orc_sthe_condensation(condInput,geom,config);
    U = localOverallU(condensation.h,hTube);             % [W/m2/K]
    Anew = Q/(U*lmtd);                                   % [m2]
    q_flux = Q/Anew;                                     % [W/m2]
    T_wall_new = T_sat - q_flux/max(condensation.h,eps); % [K]
    if abs(Anew-A)/max(Anew,eps) < config.orc_tol_htc_rel
        A = Anew; return
    end
    A = 0.5*A + 0.5*Anew;                                % damping [m2]
    T_wall = 0.5*T_wall + 0.5*T_wall_new;                 % damping [K]
end
A = Anew;                                                % last value [m2]
end

% =========================================================================
% LOCAL: FINAL GEOMETRY CHECK
% =========================================================================
function localCheckFinalGeometry(geom,Ltube,config)
% Enforce geometry-domain limits.
if ~geom.orc_geometryOK
    error('localCheckFinalGeometry:GeometryNotOK', ...
        'Final geometry is outside the accepted domain.');
end
if Ltube < config.orc_hx_minTubeLength || Ltube > config.orc_hx_maxTubeLength
    error('localCheckFinalGeometry:TubeLengthLimit', ...
        'Required tube length is outside the accepted range.');
end
end

% =========================================================================
% LOCAL: PACK SUCCESSFUL CANDIDATE
% =========================================================================
function orcCandidate = localPackCandidate(orcHxType,Npar,geom,Areq,Ltube,Q,dpWf,dpSec,pinch,config)
% Collect one successful candidate.
orcCandidate = struct();
orcCandidate.ok = true;                               % [-]
orcCandidate.message = 'OK';                          % [-]
orcCandidate.orc_hxType = char(orcHxType);            % [-]
orcCandidate.N_parallel = Npar;                       % [-]
Ageo = pi*geom.do*geom.Nt*geom.Ltube;                  % geometric area [m2]
orcCandidate.score = Npar*Ageo;                       % total area score [m2]
orcCandidate.secondaryScore = abs(dpWf)+abs(dpSec);   % pressure score [Pa]

orcCandidate.module = struct();
orcCandidate.module.geometry = geom;                  % [-]
orcCandidate.module.A_module = Ageo;                  % geometric area [m2]
orcCandidate.module.A_req_module = Areq;              % required area [m2]
orcCandidate.module.areaMargin = Ageo/max(Areq,eps)-1; % area margin [-]
orcCandidate.module.Ltube = Ltube;                    % [m]
orcCandidate.module.Q_module = Q;                     % [W]
orcCandidate.module.dp_wf_module = dpWf;              % [Pa]
orcCandidate.module.dp_secondary_module = dpSec;      % [Pa]
orcCandidate.module.deltaT_pinch = pinch;             % [K]
orcCandidate.module.orc_geometryFrozen = true;        % [-]

orcCandidate.total = struct();
orcCandidate.total.A_total = Npar*Ageo;               % [m2]
orcCandidate.total.A_req_total = Npar*Areq;         % [m2]
orcCandidate.total.Q_total = Npar*Q;                  % [W]
orcCandidate.total.dp_wf_train = dpWf;                % parallel branch drop [Pa]
orcCandidate.total.dp_secondary_train = dpSec;        % parallel branch drop [Pa]
orcCandidate.total.N_parallel = Npar;                 % [-]
orcCandidate.total.orc_hx_maxTubeLength = config.orc_hx_maxTubeLength; % [m]
end

% =========================================================================
% LOCAL: FAILED CANDIDATE
% =========================================================================
function orcCandidate = localFailedCandidate(orcHxType,Npar,Nt,msg)
% Collect one failed candidate without throwing upward.
orcCandidate = struct();
orcCandidate.ok = false;                              % [-]
orcCandidate.message = msg;                           % [-]
orcCandidate.orc_hxType = char(orcHxType);            % [-]
orcCandidate.N_parallel = Npar;                       % [-]
orcCandidate.Nt = Nt;                                 % [-]
orcCandidate.score = inf;                             % [m2]
orcCandidate.secondaryScore = inf;                    % [Pa]
end

% =========================================================================
% LOCAL: CANDIDATE COMPARISON
% =========================================================================
function tf = localCandidateIsBetter(a,b)
% Prefer smaller total area, then lower pressure score.
areaTol = 1e-6*max([abs(a.score),abs(b.score),1]);
if a.score < b.score - areaTol
    tf = true;
elseif abs(a.score-b.score) <= areaTol && a.secondaryScore < b.secondaryScore
    tf = true;
else
    tf = false;
end
end
