function orcHydraulicResult = orc_hydraulic_feedback(systemInput,orcHotStream,orcColdStream,config)
% ORC_HYDRAULIC_FEEDBACK Iterate ORC cycle and HX pressure losses.
%
% The thermodynamic solver uses P_orcevap as turbine inlet pressure and
% P_orccond as pump inlet pressure. The HX design returns working-fluid
% pressure drops, which are fed back to the pump outlet and turbine outlet.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 4 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcHydraulicTimer = tic;                              % total timer [-]

% =========================================================================
% INITIAL PRESSURE-DROP GUESS
% =========================================================================
orc_dp_evap_wf = 0;                                  % evaporator wf dP [Pa]
orc_dp_cond_wf = 0;                                  % condenser wf dP [Pa]

orcIterLog = repmat(struct( ...
    'iter',NaN, ...
    'dp_orcevap_wf_in',NaN, ...
    'dp_orccond_wf_in',NaN, ...
    'dp_orcevap_wf_calc',NaN, ...
    'dp_orccond_wf_calc',NaN, ...
    'dp_orcevap_wf_next',NaN, ...
    'dp_orccond_wf_next',NaN, ...
    'relChange',NaN, ...
    'elapsed_s',NaN, ...
    'converged',false),config.orc_max_hydraulic_iter,1); % [-]

orcConverged = false;                                % convergence flag [-]
prevEvapNt = [];                                      % search hint [-]
prevEvapNpar = [];                                    % search hint [-]
prevCondNt = [];                                      % search hint [-]
prevCondNpar = [];                                    % search hint [-]

% =========================================================================
% HYDRAULIC FIXED-POINT LOOP
% =========================================================================
for orcIter = 1:config.orc_max_hydraulic_iter
    % ---------------------------------------------------------------------
    % Build hydraulic input for this iteration.
    % ---------------------------------------------------------------------
    orcHydraulic = struct();
    orcHydraulic.orc_dp_evap_wf = max(0,orc_dp_evap_wf); % [Pa]
    orcHydraulic.orc_dp_cond_wf = max(0,orc_dp_cond_wf); % [Pa]

    % ---------------------------------------------------------------------
    % Recalculate thermodynamic cycle with current dP.
    % ---------------------------------------------------------------------
    orcThermo = orc_thermo_design(systemInput,config,orcHydraulic);

    % ---------------------------------------------------------------------
    % Resize physical HX trains at the current cycle state.
    % ---------------------------------------------------------------------
    configIter = localApplySearchHints(config, ...
        prevEvapNt,prevEvapNpar,prevCondNt,prevCondNpar);

    iterTimer = tic;                                  % iteration timer [-]
    orcEvaporator = orc_evaporator_design(orcThermo,orcHotStream,configIter);
    orcCondenser = orc_condenser_design(orcThermo,orcColdStream,configIter);
    iterElapsed = toc(iterTimer);                     % [s]

    prevEvapNt = orcEvaporator.module.geometry.Nt;    % next hint [-]
    prevEvapNpar = orcEvaporator.N_parallel_installed; % next hint [-]
    prevCondNt = orcCondenser.module.geometry.Nt;     % next hint [-]
    prevCondNpar = orcCondenser.N_parallel_installed; % next hint [-]

    % ---------------------------------------------------------------------
    % Extract calculated pressure drops from the HX sizing layer.
    % ---------------------------------------------------------------------
    dp_evap_calc = max(0,orcEvaporator.total.dp_wf_train); % [Pa]
    dp_cond_calc = max(0,orcCondenser.total.dp_wf_train);  % [Pa]

    % ---------------------------------------------------------------------
    % Apply under-relaxation for stable fixed-point iteration.
    % ---------------------------------------------------------------------
    alpha = config.orc_hydraulic_relaxation;          % [-]
    dp_evap_next = (1-alpha)*orc_dp_evap_wf + alpha*dp_evap_calc; % [Pa]
    dp_cond_next = (1-alpha)*orc_dp_cond_wf + alpha*dp_cond_calc; % [Pa]

    rel_evap = abs(dp_evap_next-orc_dp_evap_wf)/max([abs(dp_evap_next),1]); % [-]
    rel_cond = abs(dp_cond_next-orc_dp_cond_wf)/max([abs(dp_cond_next),1]); % [-]
    relChange = max(rel_evap,rel_cond);              % [-]

    % ---------------------------------------------------------------------
    % Save iteration diagnostics.
    % ---------------------------------------------------------------------
    orcIterLog(orcIter).iter = orcIter;               % [-]
    orcIterLog(orcIter).dp_orcevap_wf_in = orc_dp_evap_wf; % [Pa]
    orcIterLog(orcIter).dp_orccond_wf_in = orc_dp_cond_wf; % [Pa]
    orcIterLog(orcIter).dp_orcevap_wf_calc = dp_evap_calc; % [Pa]
    orcIterLog(orcIter).dp_orccond_wf_calc = dp_cond_calc; % [Pa]
    orcIterLog(orcIter).dp_orcevap_wf_next = dp_evap_next; % [Pa]
    orcIterLog(orcIter).dp_orccond_wf_next = dp_cond_next; % [Pa]
    orcIterLog(orcIter).relChange = relChange;       % [-]
    orcIterLog(orcIter).elapsed_s = iterElapsed;       % [s]
    orcIterLog(orcIter).converged = relChange <= config.orc_tol_hydraulic_rel; % [-]

    if config.orc_hydraulic_printIterLog
        fprintf('ORC hydraulic iter %02d: dP_evap %.3f->%.3f kPa, dP_cond %.3f->%.3f kPa, rel %.3e, %.2f s\n', ...
            orcIter,orc_dp_evap_wf/1e3,dp_evap_calc/1e3, ...
            orc_dp_cond_wf/1e3,dp_cond_calc/1e3,relChange,iterElapsed);
    end

    % ---------------------------------------------------------------------
    % Accept convergence or continue.
    % ---------------------------------------------------------------------
    orc_dp_evap_wf = dp_evap_next;                   % [Pa]
    orc_dp_cond_wf = dp_cond_next;                   % [Pa]

    if relChange <= config.orc_tol_hydraulic_rel
        orcConverged = true;                         % [-]
        break
    end
end

% =========================================================================
% FINAL CONSISTENT PASS
% =========================================================================
orcHydraulic = struct();
orcHydraulic.orc_dp_evap_wf = max(0,orc_dp_evap_wf); % [Pa]
orcHydraulic.orc_dp_cond_wf = max(0,orc_dp_cond_wf); % [Pa]

orcThermo = orc_thermo_design(systemInput,config,orcHydraulic);
configFinal = localApplySearchHints(config, ...
    prevEvapNt,prevEvapNpar,prevCondNt,prevCondNpar);
finalTimer = tic;                                     % final pass timer [-]
orcEvaporator = orc_evaporator_design(orcThermo,orcHotStream,configFinal);
orcCondenser = orc_condenser_design(orcThermo,orcColdStream,configFinal);
orcFinalElapsed = toc(finalTimer);                    % [s]

% Final pressure-drop consistency check.
% The strict loop criterion remains orc_tol_hydraulic_rel; the final
% relaxed criterion avoids rejecting small sizing/rating oscillations caused
% by discrete Nt selection and the preliminary two-phase dP layer.
dp_evap_final_calc = max(0,orcEvaporator.total.dp_wf_train); % [Pa]
dp_cond_final_calc = max(0,orcCondenser.total.dp_wf_train);  % [Pa]
rel_evap_final = abs(dp_evap_final_calc-orc_dp_evap_wf)/max([abs(dp_evap_final_calc),1]); % [-]
rel_cond_final = abs(dp_cond_final_calc-orc_dp_cond_wf)/max([abs(dp_cond_final_calc),1]); % [-]
orcFinalRelChange = max(rel_evap_final,rel_cond_final);      % [-]
if ~orcConverged && orcFinalRelChange <= config.orc_hydraulic_finalRelTol
    orcConverged = true;                              % relaxed final criterion [-]
end

[orcDesignOK,orcFlags] = orc_check_feasibility( ...
    orcThermo,orcEvaporator,orcCondenser,config);

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcHydraulicResult = struct();
orcHydraulicResult.orc_thermo = orcThermo;            % final ORC state [-]
orcHydraulicResult.orc_evaporator = orcEvaporator;    % final evaporator [-]
orcHydraulicResult.orc_condenser = orcCondenser;      % final condenser [-]
orcHydraulicResult.orc_hydraulic = orcHydraulic;      % final dP input [-]
orcHydraulicResult.orc_iterLog = orcIterLog(1:orcIter); % iteration log [-]
orcHydraulicResult.orc_hydraulicConverged = orcConverged; % [-]
orcHydraulicResult.orc_designOK = orcDesignOK;        % [-]
orcHydraulicResult.orc_flags = orcFlags;              % [-]
orcHydraulicResult.orc_twoPhaseDpImplemented = ...
    logical(orcEvaporator.module.dp_orcevap_wf_2phImplemented) && ...
    logical(orcCondenser.module.dp_orccond_wf_2phImplemented); % [-]
orcHydraulicResult.orc_elapsed_s = toc(orcHydraulicTimer); % [s]
orcHydraulicResult.orc_finalPassElapsed_s = orcFinalElapsed; % [s]
orcHydraulicResult.orc_finalRelChange = orcFinalRelChange; % [-]
orcHydraulicResult.orc_dp_evap_wf_calc_final = dp_evap_final_calc; % [Pa]
orcHydraulicResult.orc_dp_cond_wf_calc_final = dp_cond_final_calc; % [Pa]
orcHydraulicResult.orc_nHydraulicIter = orcIter;       % [-]

end

% =========================================================================
% LOCAL: SEARCH HINTS
% =========================================================================
function configOut = localApplySearchHints(configIn,evapNt,evapNpar,condNt,condNpar)
% Add previous HX sizes as search hints for the next iteration.
configOut = configIn;
if ~isfield(configOut,'orc_hx_useSearchHints') || ~configOut.orc_hx_useSearchHints
    return
end
if ~isempty(evapNt)
    configOut.orc_evaporator_Nt_hint = evapNt;        % [-]
    configOut.orc_evaporator_Nparallel_hint = evapNpar; % [-]
end
if ~isempty(condNt)
    configOut.orc_condenser_Nt_hint = condNt;         % [-]
    configOut.orc_condenser_Nparallel_hint = condNpar; % [-]
end
end
