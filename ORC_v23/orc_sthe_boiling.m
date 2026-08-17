function orcBoiling = orc_sthe_boiling(orcBoilInput,orcGeometry,config)
% ORC_STHE_BOILING Shell-side boiling heat-transfer coefficient.
%
% Baseline model:
%   Palen-Mostinski correlation reported by Calise et al. (2018).
%
% Required orcBoilInput fields:
%   q_flux   local heat flux [W/m2]
%   P        saturation pressure [Pa]
%   Pcrit    critical pressure [Pa]

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
requiredFields = {'q_flux','P','Pcrit'};
for iField = 1:numel(requiredFields)
    if ~isfield(orcBoilInput,requiredFields{iField})
        error('orc_sthe_boiling:MissingInput', ...
            'Missing orcBoilInput.%s',requiredFields{iField});
    end
end

orcQflux = orcBoilInput.q_flux;                       % heat flux [W/m2]
orcP = orcBoilInput.P;                                % saturation pressure [Pa]
orcPcrit = orcBoilInput.Pcrit;                        % critical pressure [Pa]

if orcQflux <= 0 || orcP <= 0 || orcPcrit <= 0 || orcP >= orcPcrit
    error('orc_sthe_boiling:InvalidInput', ...
        'Require q_flux > 0 and 0 < P < Pcrit.');
end

% =========================================================================
% CORRELATION SELECTION
% =========================================================================
orcCorrelation = lower(string(config.orc_evap_boilingCorrelation));

switch orcCorrelation
    case "palenmostinski"
        % Calise et al. (2018), Eqs. 25-27.
        orcPr = orcP/orcPcrit;                        % reduced pressure [-]
        orcPcritBar = orcPcrit/1e5;                  % Mostinski pressure unit [bar]

        orcFp = 1.8*orcPr^0.17 + ...
            4*orcPr^1.2 + 10*orcPr^10;               % pressure factor [-]

        orcHnb = 0.00417*orcQflux^0.7* ...
            orcPcritBar*orcFp;                        % nucleate boiling HTC [W/m2/K]

        orcFb = 1.5;                                  % bundle boiling factor [-]
        orcFc = 1.0;                                  % pure-fluid factor [-]
        orcHnatural = 250;                            % natural convection HTC [W/m2/K]

        orcH = orcHnb*orcFb*orcFc + orcHnatural;      % total boiling HTC [W/m2/K]

    otherwise
        error('orc_sthe_boiling:CorrelationNotImplemented', ...
            'Boiling correlation %s is not implemented in ORC v0.7.', ...
            char(orcCorrelation));
end

% =========================================================================
% OUTPUT CHECK
% =========================================================================
if ~isfinite(orcH) || orcH <= 0
    error('orc_sthe_boiling:InvalidHTC', ...
        'Calculated boiling HTC is non-positive or non-finite.');
end

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcBoiling = struct();
orcBoiling.correlation = char(config.orc_evap_boilingCorrelation);
orcBoiling.q_flux = orcQflux;                         % [W/m2]
orcBoiling.p_reduced = orcPr;                         % [-]
orcBoiling.Fp = orcFp;                                % [-]
orcBoiling.Fb = orcFb;                                % [-]
orcBoiling.Fc = orcFc;                                % [-]
orcBoiling.h_nb = orcHnb;                             % [W/m2/K]
orcBoiling.h_natural = orcHnatural;                   % [W/m2/K]
orcBoiling.h = orcH;                                  % [W/m2/K]

% Geometry is accepted for a common correlation interface.
orcBoiling.Nt = orcGeometry.Nt;                       % tube count [-]

end
