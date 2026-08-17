function orcShell = orc_sthe_shell_singlephase(orcFlow,orcGeometry,config)
% ORC_STHE_SHELL_SINGLEPHASE Bell-Delaware shell-side single-phase model.
%
% orcFlow fields:
%   mdot   mass flow [kg/s]
%   rho    density [kg/m3]
%   mu     dynamic viscosity [Pa s]
%   k      thermal conductivity [W/m/K]
%   cp     specific heat [J/kg/K]
%
% Walraven et al. (2014), Eqs. (1)-(3), Appendix B.1.1 are used.

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
requiredFields = {'mdot','rho','mu','k','cp'};
for iField = 1:numel(requiredFields)
    if ~isfield(orcFlow,requiredFields{iField})
        error('orc_sthe_shell_singlephase:MissingInput', ...
            'Missing orcFlow.%s',requiredFields{iField});
    end
end

% =========================================================================
% DIMENSIONLESS GEOMETRY
% =========================================================================
orcXtStar = orcGeometry.XtStar;                       % [-]
orcXlStar = orcGeometry.XlStar;                       % [-]
orcXdStar = orcGeometry.XdStar;                       % [-]
orcDh = orcGeometry.DhShell;                          % shell-bank Dh [m]

orcThreshold = 0.5*sqrt(2*orcXtStar^2 + 1);           % geometry threshold [-]

% =========================================================================
% FREE-STREAM AND MEAN VELOCITY
% =========================================================================
orcUinf = orcFlow.mdot/(orcFlow.rho*orcGeometry.AoCr); % free-stream velocity [m/s]

if orcXlStar >= orcThreshold
    orcUm = orcUinf*orcXtStar/(orcXtStar-1);          % Walraven Eq. B.15 [m/s]
else
    orcUm = orcUinf*orcXtStar/(2*(orcXdStar-1));      % Walraven Eq. B.15 [m/s]
end

orcRed = orcFlow.rho*orcUm*orcGeometry.do/orcFlow.mu; % Walraven Eq. B.8 [-]
orcPr = orcFlow.cp*orcFlow.mu/orcFlow.k;              % Prandtl [-]

if orcRed <= 0 || orcPr <= 0
    error('orc_sthe_shell_singlephase:InvalidDimensionless', ...
        'Shell-side Reynolds and Prandtl numbers must be positive.');
end

% =========================================================================
% INLET/OUTLET TUBE-BANK CORRECTION
% =========================================================================
orcNr = orcGeometry.NrCC;                             % rows crossed [-]

if orcNr >= 5 && orcNr <= 10
    if orcXlStar >= orcThreshold
        orcPhiTN = 1/(2*orcXtStar^2)*(1/orcNr-1/10); % Walraven Eq. B.7 [-]
    else
        orcPhiTN = 2*((orcXdStar-1)/(orcXtStar*(orcXtStar-1)))^2 * ...
            (1/orcNr-1/10);                           % Walraven Eq. B.7 [-]
    end
else
    orcPhiTN = 0;                                     % Walraven Eq. B.7 [-]
end

% =========================================================================
% HAGEN NUMBER - LAMINAR PART
% =========================================================================
orcCommonDen = 4*orcXtStar*orcXlStar/pi - 1;          % tube-bank free-area term [-]
if orcCommonDen <= 0
    error('orc_sthe_shell_singlephase:InvalidTubeBank', ...
        'Tube-bank geometry gives a non-positive Hagen denominator.');
end

orcGeomNum = (sqrt(orcXlStar)-0.6)^2 + 0.75;          % Walraven Eq. B.12 [-]

if orcXlStar >= orcThreshold
    orcHgLam = 140*orcRed*orcGeomNum / ...
        (orcXtStar^1.6*orcCommonDen);                  % Walraven Eq. B.12 [-]
else
    orcHgLam = 140*orcRed*orcGeomNum / ...
        (orcXdStar^1.6*orcCommonDen);                  % Walraven Eq. B.12 [-]
end

% =========================================================================
% HAGEN NUMBER - TURBULENT PART
% =========================================================================
orcHgTurbCoeff = ...
    (1.25 + 0.6/(orcXtStar-0.85)^1.08) + ...
    0.2*(orcXlStar/orcXtStar-1)^3 - ...
    0.005*(orcXtStar/orcXlStar-1)^3;                  % Walraven Eq. B.13 [-]

orcHgTurb = orcHgTurbCoeff*orcRed^1.75 + ...
    orcPhiTN*orcRed^2;                                % Walraven Eq. B.13 [-]

if orcRed > 250000
    orcHgTurb = orcHgTurb*(1 + (orcRed-250000)/325000); % Eq. B.14 [-]
end

% =========================================================================
% TOTAL HAGEN NUMBER
% =========================================================================
orcBlend = 1 - exp(1 - (orcRed+200)/1000);            % Walraven Eq. B.11 [-]
orcHg = orcHgLam + orcHgTurb*orcBlend;                % Hagen number [-]

if ~isfinite(orcHg) || orcHg <= 0
    error('orc_sthe_shell_singlephase:InvalidHagen', ...
        'Calculated Hagen number is non-positive or non-finite.');
end

% =========================================================================
% LEVEQUE NUMBER AND IDEAL HTC
% =========================================================================
if orcXlStar >= 1
    orcLq = 0.92*orcHg*orcPr * ...
        ((4*orcXtStar/pi-1)/orcXdStar);               % Walraven Eq. B.10 [-]
else
    orcLq = 0.92*orcHg*orcPr * ...
        ((4*orcXtStar*orcXlStar/pi-1)/(orcXlStar*orcXdStar)); % Eq. B.10 [-]
end

if ~isfinite(orcLq) || orcLq <= 0
    error('orc_sthe_shell_singlephase:InvalidLeveque', ...
        'Calculated Leveque number is non-positive or non-finite.');
end

orcHideal = orcFlow.k/orcDh*0.404*orcLq^(1/3);        % Walraven Eq. B.9 [W/m2/K]

% =========================================================================
% BELL-DELAWARE HTC CORRECTIONS
% =========================================================================
orcJc = 0.55 + 0.72*orcGeometry.Fc;                   % baffle-cut correction [-]

orcLeakSum = orcGeometry.AoSB + orcGeometry.AoTB;     % total leakage area [m2]
orcRs = orcGeometry.AoSB/orcLeakSum;                  % shell leakage fraction [-]
orcRlm = orcLeakSum/orcGeometry.AoCr;                 % leakage/crossflow ratio [-]

orcJl = 0.44*(1-orcRs) + ...
    (1-0.44*(1-orcRs))*exp(-2.2*orcRlm);              % leakage correction [-]

if config.orc_hx_useSealingStrips
    orcJb = 1;                                        % Walraven assumption [-]
else
    error('orc_sthe_shell_singlephase:JbNotImplemented', ...
        'Bundle-bypass correction without sealing strips is not implemented.');
end

if config.orc_hx_equalBaffleSpacing
    orcJs = 1;                                        % Walraven assumption [-]
else
    error('orc_sthe_shell_singlephase:JsNotImplemented', ...
        'Unequal-baffle-spacing HTC correction is not implemented.');
end

if config.orc_hx_useJrCorrection
    error('orc_sthe_shell_singlephase:JrNotImplemented', ...
        'Adverse-gradient correction is disabled in the baseline model.');
else
    orcJr = 1;                                        % Walraven assumption [-]
end

orcH = orcHideal*orcJc*orcJl*orcJb*orcJs*orcJr;       % Bell-Delaware HTC [W/m2/K]

% =========================================================================
% IDEAL CROSSFLOW PRESSURE DROP
% =========================================================================
orcDPbIdeal = orcFlow.mu^2*orcGeometry.NrCC / ...
    (orcFlow.rho*orcGeometry.do^2)*orcHg;              % Walraven Eq. B.16 [Pa]

% =========================================================================
% IDEAL WINDOW PRESSURE DROP
% =========================================================================
orcGw = orcFlow.mdot/sqrt(orcGeometry.AoCr*orcGeometry.AoW); % Eq. B.18 [kg/m2/s]

if orcRed > 100
    orcDPwIdeal = (2+0.6*orcGeometry.NrCW)* ...
        orcGw^2/(2*orcFlow.rho);                       % Walraven Eq. B.17 [Pa]
else
    orcDPwIdeal = 26*orcGw*orcFlow.mu/orcFlow.rho * ...
        (orcGeometry.NrCW/(orcGeometry.pt-orcGeometry.do) + ...
         orcGeometry.Lb/orcGeometry.DhW^2) + ...
         orcGw^2/(2*orcFlow.rho);                      % Walraven Eq. B.17 [Pa]
end

% =========================================================================
% BELL-DELAWARE PRESSURE-DROP CORRECTIONS
% =========================================================================
orcPexp = -0.15*(1+orcRs) + 0.8;                      % Bell-Delaware exponent [-]
orcFl = exp(-1.33*(1+orcRs)*orcRlm^orcPexp);          % leakage correction [-]

if config.orc_hx_useSealingStrips
    orcFb = 1;                                        % Walraven assumption [-]
else
    error('orc_sthe_shell_singlephase:FbNotImplemented', ...
        'Bundle-bypass pressure correction is not implemented.');
end

if config.orc_hx_equalBaffleSpacing
    orcFs = 1;                                        % Walraven assumption [-]
else
    error('orc_sthe_shell_singlephase:FsNotImplemented', ...
        'Unequal-baffle-spacing pressure correction is not implemented.');
end

if isfinite(orcGeometry.Nb)
    orcDP = ((orcGeometry.Nb-1)*orcDPbIdeal*orcFb + ...
        orcGeometry.Nb*orcDPwIdeal)*orcFl + ...
        2*orcDPbIdeal*(1+orcGeometry.NrCW/orcGeometry.NrCC)*orcFb*orcFs; % [Pa]
else
    orcDP = NaN;                                      % length not fixed [Pa]
end

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcShell = struct();

orcShell.u_inf = orcUinf;                             % [m/s]
orcShell.u_mean = orcUm;                              % [m/s]
orcShell.Re_d = orcRed;                               % [-]
orcShell.Pr = orcPr;                                  % [-]
orcShell.phi_tn = orcPhiTN;                           % [-]
orcShell.Hg_lam = orcHgLam;                           % [-]
orcShell.Hg_turb = orcHgTurb;                         % [-]
orcShell.Hg = orcHg;                                  % [-]
orcShell.Lq = orcLq;                                  % [-]
orcShell.h_ideal = orcHideal;                         % [W/m2/K]

orcShell.Jc = orcJc;                                  % [-]
orcShell.Jl = orcJl;                                  % [-]
orcShell.Jb = orcJb;                                  % [-]
orcShell.Js = orcJs;                                  % [-]
orcShell.Jr = orcJr;                                  % [-]
orcShell.h = orcH;                                    % [W/m2/K]

orcShell.rs = orcRs;                                  % [-]
orcShell.rlm = orcRlm;                                % [-]
orcShell.fl = orcFl;                                  % [-]
orcShell.fb = orcFb;                                  % [-]
orcShell.fs = orcFs;                                  % [-]
orcShell.Gw = orcGw;                                  % [kg/m2/s]
orcShell.dp_b_ideal = orcDPbIdeal;                    % [Pa]
orcShell.dp_w_ideal = orcDPwIdeal;                    % [Pa]
orcShell.dp = orcDP;                                  % [Pa]

end
