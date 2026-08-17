function orcDP = orc_sthe_pressure_drop(orcSide,orcPhaseMode,orcFlow,orcGeometry,orcLength,config)
% ORC_STHE_PRESSURE_DROP Unified STHE pressure-drop interface.
%
% Implemented in ORC v0.6:
%   tube  + singlephase
%   shell + singlephase
%   shell + evaporation/condensation, preliminary homogeneous model

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 6 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

if nargin < 5
    orcLength = NaN;
end

orcSide = lower(string(orcSide));
orcPhaseMode = lower(string(orcPhaseMode));

% =========================================================================
% PRESSURE-DROP MODEL
% =========================================================================
if orcSide == "tube" && orcPhaseMode == "singlephase"
    orcTube = orc_sthe_tube_singlephase(orcFlow,orcGeometry,orcLength);

    orcDP = struct();
    orcDP.dp = orcTube.dp;                            % [Pa]
    orcDP.model = 'tube_singlephase';
    orcDP.details = orcTube;
    return
end

if orcSide == "shell" && orcPhaseMode == "singlephase"
    orcShell = orc_sthe_shell_singlephase(orcFlow,orcGeometry,config);

    orcDP = struct();
    orcDP.dp = orcShell.dp;                           % [Pa]
    orcDP.model = 'bell_delaware_singlephase';
    orcDP.details = orcShell;
    return
end

% =========================================================================
% SHELL-SIDE TWO-PHASE PRESSURE DROP
% =========================================================================
if orcSide == "shell" && any(orcPhaseMode == ["evaporation","condensation"])
    orcFlow.mode = char(orcPhaseMode);                 % phase-change mode [-]
    orcTwoPhase = orc_sthe_shell_twophase_dp(orcFlow,orcGeometry,config);

    orcDP = struct();
    orcDP.dp = orcTwoPhase.dp;                         % [Pa]
    orcDP.model = 'shell_twophase_homogeneous';
    orcDP.details = orcTwoPhase;
    return
end

error('orc_sthe_pressure_drop:UnsupportedMode', ...
    'Unsupported ORC STHE pressure-drop mode.');

end
