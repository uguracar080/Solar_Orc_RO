function orcValidation = orc_validate_kaska(config)
% ORC_VALIDATE_KASKA Validate the thermodynamic core with Kaşka Case 1.
%
% Reference:
% O. Kaska, Energy Conversion and Management 77 (2014) 108-117.
% Case 1 uses R245fa at 10.8 bar evaporation and 2.1 bar condensation.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 1 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

orcConfigKaska = config;
orcConfigKaska.orc_fluid = 'R245fa';                 % validation working fluid [-]

% These two values preserve the supplied legacy MATLAB validation setup.
% They are model settings, not values claimed from the Kaşka state table.
orcConfigKaska.orc_eta_turb = 0.775;                 % turbine isentropic efficiency [-]
orcConfigKaska.orc_eta_pump = 0.70;                  % pump isentropic efficiency [-]

% =========================================================================
% CASE-1 INPUT
% =========================================================================
systemInput = struct();
systemInput.orc_P_evap_des = 10.8e5;                 % evaporator pressure [Pa]
systemInput.orc_P_cond_des = 2.1e5;                  % condenser pressure [Pa]
systemInput.orc_mdot_des = 11.06;                    % R245fa mass flow [kg/s]

orcHydraulic = struct();
orcHydraulic.orc_dp_evap_wf = 0;                     % Kaşka neglects HX pressure drop [Pa]
orcHydraulic.orc_dp_cond_wf = 0;                     % Kaşka neglects HX pressure drop [Pa]

% =========================================================================
% MODEL SOLUTION
% =========================================================================
orcModel = orc_thermo_design(systemInput,orcConfigKaska,orcHydraulic);

% =========================================================================
% PUBLISHED CASE-1 REFERENCE VALUES
% =========================================================================
orcReference = struct();
orcReference.mdot_orc = 11.06;                       % [kg/s]
orcReference.T_orcturb_in = 92.9 + 273.15;           % [K]
orcReference.T_orcturb_out = 51.3 + 273.15;          % [K]
orcReference.T_orcpump_in = 34.9 + 273.15;           % [K]
orcReference.T_orcpump_out = 35.4 + 273.15;          % [K]

orcReference.h_orcturb_in = 469.9e3;                 % [J/kg]
orcReference.h_orcturb_out = 446.2e3;                % [J/kg]
orcReference.h_orcpump_in = 245.6e3;                 % [J/kg]
orcReference.h_orcpump_out = 246.4e3;                % [J/kg]

orcReference.W_orcturb = 262.2e3;                    % [W]
orcReference.W_orcpump = 10.4e3;                     % [W]
orcReference.W_orcnet = 251.8e3;                     % [W]
orcReference.Q_orcevap = 2479e3;                     % [W]
orcReference.Q_orccond = 2217e3;                     % [W]
orcReference.eta_orc_th = 0.102;                     % [-]

% =========================================================================
% RELATIVE ERRORS
% =========================================================================
orcError = struct();
orcError.h_orcturb_in_pct = relErrorPct(orcModel.h_orcturb_in,orcReference.h_orcturb_in);
orcError.h_orcturb_out_pct = relErrorPct(orcModel.h_orcturb_out,orcReference.h_orcturb_out);
orcError.h_orcpump_in_pct = relErrorPct(orcModel.h_orcpump_in,orcReference.h_orcpump_in);
orcError.h_orcpump_out_pct = relErrorPct(orcModel.h_orcpump_out,orcReference.h_orcpump_out);

orcError.W_orcturb_pct = relErrorPct(orcModel.W_orcturb,orcReference.W_orcturb);
orcError.W_orcpump_pct = relErrorPct(orcModel.W_orcpump,orcReference.W_orcpump);
orcError.W_orcnet_pct = relErrorPct(orcModel.W_orcnet,orcReference.W_orcnet);
orcError.Q_orcevap_pct = relErrorPct(orcModel.Q_orcevap,orcReference.Q_orcevap);
orcError.Q_orccond_pct = relErrorPct(orcModel.Q_orccond,orcReference.Q_orccond);
orcError.eta_orc_th_pct = relErrorPct(orcModel.eta_orc_th,orcReference.eta_orc_th);

% =========================================================================
% OUTPUT
% =========================================================================
orcValidation = struct();
orcValidation.orc_model = orcModel;
orcValidation.orc_reference = orcReference;
orcValidation.orc_error_pct = orcError;

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
fprintf('\n============================================================\n');
fprintf('ORC THERMODYNAMIC VALIDATION - KASKA CASE 1\n');
fprintf('============================================================\n');
fprintf('W_turb : model = %8.2f kW | ref = %8.2f kW | err = %6.3f %%\n', ...
    orcModel.W_orcturb/1e3,orcReference.W_orcturb/1e3,orcError.W_orcturb_pct);
fprintf('W_pump : model = %8.2f kW | ref = %8.2f kW | err = %6.3f %%\n', ...
    orcModel.W_orcpump/1e3,orcReference.W_orcpump/1e3,orcError.W_orcpump_pct);
fprintf('W_net  : model = %8.2f kW | ref = %8.2f kW | err = %6.3f %%\n', ...
    orcModel.W_orcnet/1e3,orcReference.W_orcnet/1e3,orcError.W_orcnet_pct);
fprintf('Q_evap : model = %8.2f kW | ref = %8.2f kW | err = %6.3f %%\n', ...
    orcModel.Q_orcevap/1e3,orcReference.Q_orcevap/1e3,orcError.Q_orcevap_pct);
fprintf('Q_cond : model = %8.2f kW | ref = %8.2f kW | err = %6.3f %%\n', ...
    orcModel.Q_orccond/1e3,orcReference.Q_orccond/1e3,orcError.Q_orccond_pct);
fprintf('eta_th : model = %8.4f    | ref = %8.4f    | err = %6.3f %%\n', ...
    orcModel.eta_orc_th,orcReference.eta_orc_th,orcError.eta_orc_th_pct);
fprintf('============================================================\n\n');

end

% =========================================================================
% LOCAL HELPER
% =========================================================================
function orcErrorPct = relErrorPct(orcModelValue,orcReferenceValue)
% Relative absolute error [%].
orcErrorPct = 100*abs(orcModelValue-orcReferenceValue)/abs(orcReferenceValue);
end
