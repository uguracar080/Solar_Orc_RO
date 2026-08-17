function orcTube = orc_sthe_tube_singlephase(orcFlow,orcGeometry,orcLength)
% ORC_STHE_TUBE_SINGLEPHASE Single-phase tube-side HTC and pressure drop.
%
% orcFlow fields:
%   mdot   mass flow [kg/s]
%   rho    density [kg/m3]
%   mu     dynamic viscosity [Pa s]
%   k      thermal conductivity [W/m/K]
%   cp     specific heat [J/kg/K]
%
% Calise et al. (2014/2018) Eqs. for laminar/turbulent Nu are used.

% =========================================================================
% INPUT CHECK
% =========================================================================
requiredFields = {'mdot','rho','mu','k','cp'};
for iField = 1:numel(requiredFields)
    if ~isfield(orcFlow,requiredFields{iField})
        error('orc_sthe_tube_singlephase:MissingInput', ...
            'Missing orcFlow.%s',requiredFields{iField});
    end
end

if nargin < 3 || isempty(orcLength)
    orcLength = NaN;                                   % segment length [m]
end

% =========================================================================
% FLOW AREA AND VELOCITY
% =========================================================================
orcNtPerPass = orcGeometry.Nt/orcGeometry.orc_NtubePass; % tubes/pass [-]
orcAreaFlow = orcNtPerPass*pi*orcGeometry.di^2/4;       % flow area/pass [m2]
orcVelocity = orcFlow.mdot/(orcFlow.rho*orcAreaFlow);   % mean velocity [m/s]

orcRe = orcFlow.rho*orcVelocity*orcGeometry.di/orcFlow.mu; % Reynolds [-]
orcPr = orcFlow.cp*orcFlow.mu/orcFlow.k;                % Prandtl [-]

if orcRe <= 0 || orcPr <= 0
    error('orc_sthe_tube_singlephase:InvalidDimensionless', ...
        'Reynolds and Prandtl numbers must be positive.');
end

% =========================================================================
% NUSSELT NUMBER
% =========================================================================
if orcRe < 2300
    orcNu = 3.66;                                      % fully developed laminar [-]
    orcFanning = 16/orcRe;                            % smooth-tube Fanning factor [-]
    orcRegime = 'laminar';
else
    if orcRe < 2e4
        orcFanning = 0.079*orcRe^(-1/4);              % Fanning factor [-]
    else
        orcFanning = 0.046*orcRe^(-1/5);              % Fanning factor [-]
    end

    orcNu = (0.5*orcFanning*(orcRe-1000)*orcPr) / ...
        (1 + 12.7*sqrt(0.5*orcFanning)*(orcPr^(2/3)-1)); % [-]
    orcRegime = 'turbulent';
end

if ~isfinite(orcNu) || orcNu <= 0
    error('orc_sthe_tube_singlephase:InvalidNusselt', ...
        'Tube-side Nusselt number is non-positive or non-finite.');
end

% =========================================================================
% HEAT-TRANSFER COEFFICIENT
% =========================================================================
orcH = orcNu*orcFlow.k/orcGeometry.di;                 % HTC [W/m2/K]

% =========================================================================
% FRICTIONAL PRESSURE DROP
% =========================================================================
orcDarcy = 4*orcFanning;                               % Darcy friction factor [-]

if isfinite(orcLength) && orcLength > 0
    orcDP = orcDarcy*(orcLength/orcGeometry.di)* ...
        orcFlow.rho*orcVelocity^2/2;                   % frictional drop [Pa]
else
    orcDP = NaN;                                       % [Pa]
end

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcTube = struct();
orcTube.Re = orcRe;                                    % [-]
orcTube.Pr = orcPr;                                    % [-]
orcTube.Nu = orcNu;                                    % [-]
orcTube.h = orcH;                                      % [W/m2/K]
orcTube.velocity = orcVelocity;                        % [m/s]
orcTube.areaFlow = orcAreaFlow;                        % [m2]
orcTube.f_Fanning = orcFanning;                        % [-]
orcTube.f_Darcy = orcDarcy;                            % [-]
orcTube.dp = orcDP;                                    % [Pa]
orcTube.regime = orcRegime;

end
