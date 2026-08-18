function orcAnnual = orc_stage2_annual_dispatch(orcDesign,orcAnnualInput,config)
% ORC_STAGE2_ANNUAL_DISPATCH Run annual/period fixed-geometry dispatch.
%
% Wrapper around orc_stage2_annual_offdesign with dispatch enabled.  The
% heat-exchanger geometry remains frozen; each timestep chooses a feasible
% ORC operating point using orc_offdesign_dispatch.  Warm-starting is handled
% inside orc_stage2_annual_offdesign when enabled in config.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 3 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

if nargin < 2 || isempty(orcAnnualInput)
    orcAnnualInput = struct();                       % default single-step input [-]
end

% =========================================================================
% DEFAULT OPERATING COMMAND
% =========================================================================
orcAnnualInput.orc_useDispatch = true;               % force dispatch mode [-]
if ~isfield(orcAnnualInput,'orcOperatingInput') || isempty(orcAnnualInput.orcOperatingInput)
    op = struct();                                   % design maximum command [-]
    op.orc_P_evap = orcDesign.orc_thermo.P_orcevap;  % [Pa]
    op.orc_P_cond = orcDesign.orc_thermo.P_orccond;  % [Pa]
    op.orc_mdot = orcDesign.orc_thermo.mdot_orc;     % [kg/s]
    orcAnnualInput.orcOperatingInput = op;           % [-]
end

% =========================================================================
% RUN ANNUAL/PERIOD SIMULATION
% =========================================================================
orcAnnual = orc_stage2_annual_offdesign(orcDesign,orcAnnualInput,config); % [-]
orcAnnual.orc_stage2Mode = 'annual-dispatch';        % [-]

end
