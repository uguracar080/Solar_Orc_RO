function orcCondenser = orc_condenser_design(orcThermo,orcColdStream,config)
% ORC_CONDENSER_DESIGN Size the ORC condenser STHE train.
%
% The physical condenser is one or more identical STHE modules in parallel.
% Each module is represented by one desuperheating zone and one condensation zone.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 3 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcDesignTimer = tic;                                 % component timer [-]

% =========================================================================
% INPUT CHECK
% =========================================================================
if nargin < 2 || isempty(orcColdStream)
    error('orc_condenser_design:MissingColdStream', ...
        'Provide orcColdStream with fluid, T_in, P_in and mdot.');
end
requiredFields = {'fluid','T_in','P_in','mdot'};
for iField = 1:numel(requiredFields)
    if ~isfield(orcColdStream,requiredFields{iField})
        error('orc_condenser_design:MissingColdStreamField', ...
            'Missing orcColdStream.%s',requiredFields{iField});
    end
end

% =========================================================================
% CONDENSER DUTY SPLIT
% =========================================================================
orcFluid = orcThermo.orc_fluid;                       % working fluid [-]
P_orccond = orcThermo.P_orccond;                      % condensation pressure [Pa]
mdot_orc = orcThermo.mdot_orc;                        % total ORC flow [kg/s]

h_orccond_g = orc_properties(config,'H','P',P_orccond,'Q',1,orcFluid); % [J/kg]
h_orccond_f = orc_properties(config,'H','P',P_orccond,'Q',0,orcFluid); % [J/kg]
T_orccond_sat = orc_properties(config,'T','P',P_orccond,'Q',0,orcFluid); % [K]

Q_orccond_dsh = mdot_orc*max(0,orcThermo.h_orcturb_out-h_orccond_g); % [W]
Q_orccond_2ph = mdot_orc*max(0,h_orccond_g-h_orccond_f);             % [W]
Q_orccond_total = Q_orccond_dsh + Q_orccond_2ph;                     % [W]

if Q_orccond_total <= 0
    error('orc_condenser_design:NonPositiveDuty', ...
        'Condenser duty must be positive.');
end

% =========================================================================
% PARALLEL SIZING INPUT
% =========================================================================
orcHxInput = struct();
orcHxInput.orc_hxType = 'condenser';                  % HX type [-]
orcHxInput.orcThermo = orcThermo;                     % ORC state struct [-]
orcHxInput.orcColdStream = orcColdStream;             % cold stream struct [-]
orcHxInput.Q_orccond_dsh = Q_orccond_dsh;             % [W]
orcHxInput.Q_orccond_2ph = Q_orccond_2ph;             % [W]
orcHxInput.Q_orccond_total = Q_orccond_total;         % [W]
orcHxInput.h_orccond_g = h_orccond_g;                 % [J/kg]
orcHxInput.h_orccond_f = h_orccond_f;                 % [J/kg]
orcHxInput.T_orccond_sat = T_orccond_sat;             % [K]

% =========================================================================
% SIZE PARALLEL STHE TRAIN
% =========================================================================
orcSizing = orc_sthe_parallel_sizing(orcHxInput,config);

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcCondenser = struct();
orcCondenser.orc_hxType = 'condenser';                % [-]
orcCondenser.orc_fluid = orcFluid;                    % [-]
orcCondenser.N_parallel_installed = orcSizing.N_parallel; % [-]
orcCondenser.N_parallel_active_design = orcSizing.N_parallel; % [-]
orcCondenser.module = orcSizing.module;               % one physical module [-]
orcCondenser.total = orcSizing.total;                 % train totals [-]
orcCondenser.Q_orccond_dsh = Q_orccond_dsh;           % [W]
orcCondenser.Q_orccond_2ph = Q_orccond_2ph;           % [W]
orcCondenser.Q_orccond_total = Q_orccond_total;       % [W]
orcCondenser.T_orccond_sat = T_orccond_sat;           % [K]
orcCondenser.orc_designOK = orcSizing.orc_sizingOK;   % [-]
orcCondenser.orc_designMessage = orcSizing.message;   % [-]
orcCondenser.orc_sizingElapsed_s = orcSizing.orc_elapsed_s; % [s]
orcCondenser.orc_nCandidatesEvaluated = orcSizing.orc_nCandidatesEvaluated; % [-]
orcCondenser.orc_componentElapsed_s = toc(orcDesignTimer); % [s]

end
