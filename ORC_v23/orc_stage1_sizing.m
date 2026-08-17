function orcDesign = orc_stage1_sizing(systemInput,orcHotStream,orcColdStream,config)
% ORC_STAGE1_SIZING Complete ORC nominal sizing with fixed HX geometry.
%
% Stage 1 calculates the nominal thermodynamic ORC state and sizes the
% evaporator/condenser STHE trains. The returned geometry is frozen for
% Stage-2 annual off-design rating.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 4 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcStage1Timer = tic;                                 % stage timer [-]

% =========================================================================
% STAGE-1 SOLUTION
% =========================================================================
if config.orc_stage1_useHydraulicFeedback
    % ---------------------------------------------------------------------
    % Iterative cycle-HX pressure-loss coupling.
    % ---------------------------------------------------------------------
    orcHydraulicResult = orc_hydraulic_feedback( ...
        systemInput,orcHotStream,orcColdStream,config);

    orcThermo = orcHydraulicResult.orc_thermo;        % [-]
    orcEvaporator = orcHydraulicResult.orc_evaporator; % [-]
    orcCondenser = orcHydraulicResult.orc_condenser;  % [-]
    orcHydraulic = orcHydraulicResult.orc_hydraulic;  % [-]
    orcIterLog = orcHydraulicResult.orc_iterLog;      % [-]
    orcHydraulicConverged = orcHydraulicResult.orc_hydraulicConverged; % [-]
    orcHydraulicElapsed_s = orcHydraulicResult.orc_elapsed_s; % [s]
    orcTwoPhaseDpImplemented = orcHydraulicResult.orc_twoPhaseDpImplemented; % [-]
    orcHydraulicFinalRel = orcHydraulicResult.orc_finalRelChange; % [-]
    orcHydraulicNiter = orcHydraulicResult.orc_nHydraulicIter; % [-]
    orcDpEvapCalcFinal = orcHydraulicResult.orc_dp_evap_wf_calc_final; % [Pa]
    orcDpCondCalcFinal = orcHydraulicResult.orc_dp_cond_wf_calc_final; % [Pa]
else
    % ---------------------------------------------------------------------
    % One-pass thermal sizing without hydraulic feedback.
    % ---------------------------------------------------------------------
    orcHydraulic = struct();
    orcHydraulic.orc_dp_evap_wf = 0;                  % [Pa]
    orcHydraulic.orc_dp_cond_wf = 0;                  % [Pa]

    orcThermo = orc_thermo_design(systemInput,config,orcHydraulic);
    orcEvaporator = orc_evaporator_design(orcThermo,orcHotStream,config);
    orcCondenser = orc_condenser_design(orcThermo,orcColdStream,config);

    orcIterLog = struct([]);                          % [-]
    orcHydraulicConverged = true;                     % one-pass mode [-]
    orcHydraulicElapsed_s = NaN;                       % [s]
    orcTwoPhaseDpImplemented = ...
        logical(orcEvaporator.module.dp_orcevap_wf_2phImplemented) && ...
        logical(orcCondenser.module.dp_orccond_wf_2phImplemented); % [-]
    orcHydraulicFinalRel = 0;                         % [-]
    orcHydraulicNiter = 0;                            % [-]
    orcDpEvapCalcFinal = orcEvaporator.total.dp_wf_train; % [Pa]
    orcDpCondCalcFinal = orcCondenser.total.dp_wf_train;  % [Pa]
end

% =========================================================================
% DESIGN FEASIBILITY
% =========================================================================
[orcDesignOK,orcFlags] = orc_check_feasibility( ...
    orcThermo,orcEvaporator,orcCondenser,config);

% =========================================================================
% TIMING
% =========================================================================
orcStage1Elapsed_s = toc(orcStage1Timer);             % [s]

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcDesign = struct();
orcDesign.orc_modelVersion = config.orc_modelVersion; % [-]
orcDesign.orc_thermo = orcThermo;                     % thermodynamic state [-]
orcDesign.orc_evaporator = orcEvaporator;             % frozen evaporator [-]
orcDesign.orc_condenser = orcCondenser;               % frozen condenser [-]
orcDesign.orc_hydraulic = orcHydraulic;               % converged dP input [-]
orcDesign.orc_hydraulicIterLog = orcIterLog;          % dP iteration log [-]
orcDesign.orc_hydraulicConverged = orcHydraulicConverged; % [-]
orcDesign.orc_twoPhaseDpImplemented = orcTwoPhaseDpImplemented; % [-]
orcDesign.orc_geometryFrozen = true;                  % Stage-2 safety flag [-]
orcDesign.orc_designOK = orcDesignOK;                 % [-]
orcDesign.orc_flags = orcFlags;                       % diagnostics [-]
orcDesign.orc_hotStream_design = orcHotStream;        % design hot stream [-]
orcDesign.orc_coldStream_design = orcColdStream;      % design cold stream [-]
orcDesign.orc_stage1Elapsed_s = orcStage1Elapsed_s;   % [s]
orcDesign.orc_hydraulicElapsed_s = orcHydraulicElapsed_s; % [s]

orcRuntime = struct();                                % timing output [-]
orcRuntime.orc_stage1Elapsed_s = orcStage1Elapsed_s;  % [s]
orcRuntime.orc_hydraulicElapsed_s = orcHydraulicElapsed_s; % [s]
orcRuntime.orc_evaporatorSizingElapsed_s = orcEvaporator.orc_componentElapsed_s; % [s]
orcRuntime.orc_condenserSizingElapsed_s = orcCondenser.orc_componentElapsed_s; % [s]
orcRuntime.orc_evaporatorCandidates = orcEvaporator.orc_nCandidatesEvaluated; % [-]
orcRuntime.orc_condenserCandidates = orcCondenser.orc_nCandidatesEvaluated; % [-]
orcDesign.orc_runtime = orcRuntime;                   % solver timing [-]
orcDesign.orc_hydraulicFinalRel = orcHydraulicFinalRel; % [-]
orcDesign.orc_hydraulicNiter = orcHydraulicNiter;    % [-]
orcDesign.orc_dp_evap_wf_calc_final = orcDpEvapCalcFinal; % [Pa]
orcDesign.orc_dp_cond_wf_calc_final = orcDpCondCalcFinal; % [Pa]

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
fprintf('\n============================================================\n');
fprintf('ORC STAGE-1 SIZING SUMMARY - V%s\n',config.orc_modelVersion);
fprintf('============================================================\n');
fprintf('W_orcnet          : %10.2f kW\n',orcThermo.W_orcnet/1e3);
fprintf('mdot_orc          : %10.4f kg/s\n',orcThermo.mdot_orc);
fprintf('Q_orcevap         : %10.2f kW\n',orcThermo.Q_orcevap/1e3);
fprintf('Q_orccond         : %10.2f kW\n',orcThermo.Q_orccond/1e3);
fprintf('Evap modules      : %10d\n',orcEvaporator.N_parallel_installed);
fprintf('Evap Nt x Ltube   : %10d x %.3f m\n', ...
    orcEvaporator.module.geometry.Nt,orcEvaporator.module.geometry.Ltube);
fprintf('Evap Dshell       : %10.4f m\n',orcEvaporator.module.geometry.Dshell);
fprintf('Evap A margin     : %10.4f %%\n',100*orcEvaporator.module.areaMargin);
fprintf('Evap dP wf        : %10.3f kPa\n',orcThermo.dp_orcevap_wf/1e3);
fprintf('Evap dP hot       : %10.3f kPa\n',orcEvaporator.total.dp_secondary_train/1e3);
fprintf('Evap candidates   : %10d\n',orcEvaporator.orc_nCandidatesEvaluated);
fprintf('Cond modules      : %10d\n',orcCondenser.N_parallel_installed);
fprintf('Cond Nt x Ltube   : %10d x %.3f m\n', ...
    orcCondenser.module.geometry.Nt,orcCondenser.module.geometry.Ltube);
fprintf('Cond Dshell       : %10.4f m\n',orcCondenser.module.geometry.Dshell);
fprintf('Cond A margin     : %10.4f %%\n',100*orcCondenser.module.areaMargin);
fprintf('Cond dP wf        : %10.3f kPa\n',orcThermo.dp_orccond_wf/1e3);
fprintf('Cond dP cold      : %10.3f kPa\n',orcCondenser.total.dp_secondary_train/1e3);
fprintf('Cond candidates   : %10d\n',orcCondenser.orc_nCandidatesEvaluated);
fprintf('Hydraulic conv.   : %10d\n',orcHydraulicConverged);
fprintf('Hydraulic iter    : %10d\n',orcHydraulicNiter);
fprintf('Hydraulic rel     : %10.3e\n',orcHydraulicFinalRel);
fprintf('Hydraulic rel tol : %10.3e\n',config.orc_hydraulic_finalRelTol);
fprintf('Evap dP calc      : %10.3f kPa\n',orcDpEvapCalcFinal/1e3);
fprintf('Cond dP calc      : %10.3f kPa\n',orcDpCondCalcFinal/1e3);
fprintf('Two-phase dP      : %10d\n',orcTwoPhaseDpImplemented);
fprintf('Design feasible   : %10d\n',orcDesignOK);
fprintf('Stage-1 time      : %10.2f s\n',orcStage1Elapsed_s);
if ~isnan(orcHydraulicElapsed_s)
    fprintf('Hydraulic time    : %10.2f s\n',orcHydraulicElapsed_s);
end
fprintf('============================================================\n');

end
