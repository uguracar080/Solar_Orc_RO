function [orcK,orcKInfo] = orc_r1233zde_thermal_conductivity(config,orcT,orcRho)
% ORC_R1233ZDE_THERMAL_CONDUCTIVITY NIST R1233zd(E) conductivity.
%
% Implements the dilute-gas plus residual background correlation of Perkins,
% Huber and Assael for trans-R1233zd(E). The critical enhancement term is
% disabled by default for ORC v0.7 because the present ORC calculations avoid
% the near-critical region and because the full term needs EOS derivatives and
% viscosity handling. The function is isolated so the full term can be added
% later without changing the ORC heat-exchanger code.
%
% Inputs:
%   orcT     temperature [K]
%   orcRho   density [kg/m3]
%
% Output:
%   orcK     thermal conductivity [W/m/K]

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 1 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

% =========================================================================
% INPUT CHECK
% =========================================================================
validateattributes(orcT,{'numeric'},{'real','finite','positive'});
validateattributes(orcRho,{'numeric'},{'real','finite','nonnegative'});

if ~isequal(size(orcT),size(orcRho)) && ~isscalar(orcT) && ~isscalar(orcRho)
    error('orc_r1233zde_thermal_conductivity:SizeMismatch', ...
        'orcT and orcRho must have compatible sizes.');
end

% =========================================================================
% CONSTANTS FROM NIST CORRELATION
% =========================================================================
orcTc = 439.6;                                      % critical temperature [K]
orcRhoc = 480.239;                                 % critical density [kg/m3]

orcA = [-0.140033e-1, ...
         0.378160e-1, ...
        -0.245832e-2];                             % dilute-gas coefficients [W/m/K]

orcB = [ 0.862816e-2,  0.914709e-3; ...
        -0.208988e-1, -0.407914e-2; ...
         0.511968e-1,  0.845668e-2; ...
        -0.349076e-1, -0.108985e-1; ...
         0.975727e-2,  0.538262e-2; ...
        -0.926484e-3, -0.806009e-3];               % residual coefficients [W/m/K]

% =========================================================================
% REDUCED VARIABLES
% =========================================================================
orcTr = orcT./orcTc;                                % reduced temperature [-]
orcRhor = orcRho./orcRhoc;                          % reduced density [-]

% =========================================================================
% DILUTE-GAS CONTRIBUTION, EQ. 5
% =========================================================================
orcK0 = orcA(1) + orcA(2).*orcTr + orcA(3).*orcTr.^2; % [W/m/K]

% =========================================================================
% RESIDUAL CONTRIBUTION, EQ. 6
% =========================================================================
orcKr = zeros(size(orcK0));                         % residual term [W/m/K]
for orcI = 1:6
    orcKr = orcKr + ...
        (orcB(orcI,1) + orcB(orcI,2).*orcTr).*orcRhor.^orcI;
end

% =========================================================================
% CRITICAL ENHANCEMENT PLACEHOLDER
% =========================================================================
orcKc = zeros(size(orcK0));                         % critical term [W/m/K]
if isfield(config,'orc_r1233zde_k_includeCritical') && ...
        config.orc_r1233zde_k_includeCritical
    error('orc_r1233zde_thermal_conductivity:CriticalNotImplemented', ...
        ['Critical enhancement is reserved for a later version. Set ', ...
         'config.orc_r1233zde_k_includeCritical = false for ORC v0.7.']);
end

% =========================================================================
% TOTAL CONDUCTIVITY
% =========================================================================
orcK = orcK0 + orcKr + orcKc;                       % [W/m/K]

% =========================================================================
% RANGE / OUTPUT CHECK
% =========================================================================
orcRangeOK = orcT >= 195.15 & orcT <= 550.0 & orcRho >= 0; % source EOS range [-]

if any(~isfinite(orcK(:))) || any(orcK(:) <= 0)
    error('orc_r1233zde_thermal_conductivity:InvalidConductivity', ...
        'Calculated thermal conductivity is non-positive or non-finite.');
end

% =========================================================================
% OPTIONAL DIAGNOSTICS
% =========================================================================
if nargout > 1
    orcKInfo = struct();
    orcKInfo.model = 'NIST_background_Eq5_Eq6';      % correlation ID [-]
    orcKInfo.includeCritical = false;                % critical enhancement [-]
    orcKInfo.T = orcT;                               % [K]
    orcKInfo.rho = orcRho;                           % [kg/m3]
    orcKInfo.Tcrit = orcTc;                          % [K]
    orcKInfo.rhocrit = orcRhoc;                      % [kg/m3]
    orcKInfo.k0 = orcK0;                             % [W/m/K]
    orcKInfo.kr = orcKr;                             % [W/m/K]
    orcKInfo.kc = orcKc;                             % [W/m/K]
    orcKInfo.rangeOK = orcRangeOK;                   % [-]
end

end
