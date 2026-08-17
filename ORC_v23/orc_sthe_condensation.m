function orcCond = orc_sthe_condensation(orcCondInput,orcGeometry,config)
% ORC_STHE_CONDENSATION Shell-side film-condensation HTC.
%
% Baseline model:
%   Nusselt smooth horizontal tube + Kern bundle-row correction.
%
% Required orcCondInput fields:
%   rho_l    saturated-liquid density [kg/m3]
%   rho_v    saturated-vapor density [kg/m3]
%   mu_l     saturated-liquid viscosity [Pa s]
%   k_l      saturated-liquid conductivity [W/m/K]
%   h_fg     latent heat [J/kg]
%   T_sat    saturation temperature [K]
%   T_wall   tube-wall temperature [K]

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 3 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

% =========================================================================
% INPUT CHECK
% =========================================================================
requiredFields = {'rho_l','rho_v','mu_l','k_l','h_fg','T_sat','T_wall'};
for iField = 1:numel(requiredFields)
    if ~isfield(orcCondInput,requiredFields{iField})
        error('orc_sthe_condensation:MissingInput', ...
            'Missing orcCondInput.%s',requiredFields{iField});
    end
end

orcDeltaT = orcCondInput.T_sat - orcCondInput.T_wall; % film temperature difference [K]
if orcDeltaT <= 0
    error('orc_sthe_condensation:WallTemperature', ...
        'Condensation requires T_wall < T_sat.');
end

% =========================================================================
% CORRELATION SELECTION
% =========================================================================
orcCorrelation = lower(string(config.orc_cond_condensationCorrelation));

switch orcCorrelation
    case "nusseltkern"
        orcG = 9.80665;                               % gravity [m/s2]

        orcHsingle = 0.728 * ...
            (orcCondInput.rho_l*(orcCondInput.rho_l-orcCondInput.rho_v)* ...
             orcG*orcCondInput.h_fg*orcCondInput.k_l^3 / ...
            (orcCondInput.mu_l*orcDeltaT*orcGeometry.do))^0.25; % [W/m2/K]

        orcNrow = max(1,ceil(orcGeometry.Dctl/orcGeometry.Xl)); % tube rows [-]
        orcBundleFactor = orcNrow^(-1/6);             % Kern correction [-]
        orcH = orcHsingle*orcBundleFactor;            % bundle HTC [W/m2/K]

    otherwise
        error('orc_sthe_condensation:CorrelationNotImplemented', ...
            'Condensation correlation %s is not implemented in ORC v0.7.', ...
            char(orcCorrelation));
end

% =========================================================================
% OUTPUT CHECK
% =========================================================================
if ~isfinite(orcH) || orcH <= 0
    error('orc_sthe_condensation:InvalidHTC', ...
        'Calculated condensation HTC is non-positive or non-finite.');
end

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcCond = struct();
orcCond.correlation = char(config.orc_cond_condensationCorrelation);
orcCond.T_sat = orcCondInput.T_sat;                   % [K]
orcCond.T_wall = orcCondInput.T_wall;                 % [K]
orcCond.deltaT_film = orcDeltaT;                      % [K]
orcCond.Nrow = orcNrow;                               % [-]
orcCond.bundleFactor = orcBundleFactor;               % [-]
orcCond.h_single = orcHsingle;                        % [W/m2/K]
orcCond.h = orcH;                                     % [W/m2/K]

end
