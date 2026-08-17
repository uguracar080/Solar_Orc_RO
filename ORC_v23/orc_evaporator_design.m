function orcEvaporator = orc_evaporator_design(orcThermo,orcHotStream,config)
% ORC_EVAPORATOR_DESIGN Size the ORC evaporator STHE train.
%
% The physical evaporator is one or more identical STHE modules in parallel.
% Each module is represented by one preheating zone and one boiling zone.

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
if nargin < 2 || isempty(orcHotStream)
    error('orc_evaporator_design:MissingHotStream', ...
        'Provide orcHotStream with fluid, T_in, P_in and mdot.');
end
requiredFields = {'fluid','T_in','P_in','mdot'};
for iField = 1:numel(requiredFields)
    if ~isfield(orcHotStream,requiredFields{iField})
        error('orc_evaporator_design:MissingHotStreamField', ...
            'Missing orcHotStream.%s',requiredFields{iField});
    end
end

% =========================================================================
% EVAPORATOR DUTY SPLIT
% =========================================================================
orcFluid = orcThermo.orc_fluid;                       % working fluid [-]
P_orcevap = orcThermo.P_orcevap;                      % evaporation pressure [Pa]
mdot_orc = orcThermo.mdot_orc;                        % total ORC flow [kg/s]

h_orcevap_f = orc_properties(config,'H','P',P_orcevap,'Q',0,orcFluid); % [J/kg]
h_orcevap_g = orc_properties(config,'H','P',P_orcevap,'Q',1,orcFluid); % [J/kg]
T_orcevap_sat = orc_properties(config,'T','P',P_orcevap,'Q',0,orcFluid); % [K]

Q_orcevap_pre = mdot_orc*max(0,h_orcevap_f-orcThermo.h_orcpump_out); % [W]
Q_orcevap_boil = mdot_orc*max(0,h_orcevap_g-h_orcevap_f);            % [W]
Q_orcevap_total = Q_orcevap_pre + Q_orcevap_boil;                    % [W]

if Q_orcevap_total <= 0
    error('orc_evaporator_design:NonPositiveDuty', ...
        'Evaporator duty must be positive.');
end

% =========================================================================
% PARALLEL SIZING INPUT
% =========================================================================
orcHxInput = struct();
orcHxInput.orc_hxType = 'evaporator';                 % HX type [-]
orcHxInput.orcThermo = orcThermo;                     % ORC state struct [-]
orcHxInput.orcHotStream = orcHotStream;               % hot stream struct [-]
orcHxInput.Q_orcevap_pre = Q_orcevap_pre;             % [W]
orcHxInput.Q_orcevap_boil = Q_orcevap_boil;           % [W]
orcHxInput.Q_orcevap_total = Q_orcevap_total;         % [W]
orcHxInput.h_orcevap_f = h_orcevap_f;                 % [J/kg]
orcHxInput.h_orcevap_g = h_orcevap_g;                 % [J/kg]
orcHxInput.T_orcevap_sat = T_orcevap_sat;             % [K]

% =========================================================================
% SIZE PARALLEL STHE TRAIN
% =========================================================================
orcSizing = orc_sthe_parallel_sizing(orcHxInput,config);

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcEvaporator = struct();
orcEvaporator.orc_hxType = 'evaporator';              % [-]
orcEvaporator.orc_fluid = orcFluid;                   % [-]
orcEvaporator.N_parallel_installed = orcSizing.N_parallel; % [-]
orcEvaporator.N_parallel_active_design = orcSizing.N_parallel; % [-]
orcEvaporator.module = orcSizing.module;              % one physical module [-]
orcEvaporator.total = orcSizing.total;                % train totals [-]
orcEvaporator.Q_orcevap_pre = Q_orcevap_pre;          % [W]
orcEvaporator.Q_orcevap_boil = Q_orcevap_boil;        % [W]
orcEvaporator.Q_orcevap_total = Q_orcevap_total;      % [W]
orcEvaporator.T_orcevap_sat = T_orcevap_sat;          % [K]
orcEvaporator.orc_designOK = orcSizing.orc_sizingOK;  % [-]
orcEvaporator.orc_designMessage = orcSizing.message;  % [-]
orcEvaporator.orc_sizingElapsed_s = orcSizing.orc_elapsed_s; % [s]
orcEvaporator.orc_nCandidatesEvaluated = orcSizing.orc_nCandidatesEvaluated; % [-]
orcEvaporator.orc_componentElapsed_s = toc(orcDesignTimer); % [s]

end
