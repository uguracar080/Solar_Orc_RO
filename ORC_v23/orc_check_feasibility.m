function [orcOK,orcFlags] = orc_check_feasibility(orcThermo,orcEvaporator,orcCondenser,config)
% ORC_CHECK_FEASIBILITY Central feasibility flags for the ORC design.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 4 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

% =========================================================================
% FLAGS
% =========================================================================
orcFlags = struct();
orcFlags.pressureOrder = orcThermo.P_orcevap > orcThermo.P_orccond; % [-]
orcFlags.subcritical = orcThermo.P_orcevap < orcThermo.P_orc_crit;  % [-]
orcFlags.netPowerPositive = orcThermo.W_orcnet > 0;                 % [-]
orcFlags.energyBalance = logical(orcThermo.orc_energyBalanceOK);    % [-]
orcFlags.evapDesign = logical(orcEvaporator.orc_designOK);          % [-]
orcFlags.condDesign = logical(orcCondenser.orc_designOK);           % [-]
orcFlags.evapPinch = orcEvaporator.module.deltaT_pinch > config.orc_hx_minApproach_K; % [-]
orcFlags.condPinch = orcCondenser.module.deltaT_pinch > config.orc_hx_minApproach_K;  % [-]
orcFlags.evapGeometry = logical(orcEvaporator.module.geometry.orc_geometryOK); % [-]
orcFlags.condGeometry = logical(orcCondenser.module.geometry.orc_geometryOK);  % [-]

% =========================================================================
% OVERALL RESULT
% =========================================================================
orcOK = all(structfun(@(x) logical(x),orcFlags));      % [-]

end
