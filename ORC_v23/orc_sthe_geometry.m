function orcGeometry = orc_sthe_geometry(orcHxType,orcNt,orcLtube,config)
% ORC_STHE_GEOMETRY Build one physical TEMA-E STHE module geometry.
%
% Current implementation:
%   - one shell pass
%   - one tube pass
%   - 60 deg staggered tube layout
%   - single-segmental baffles
%
% Walraven et al. (2014), Appendix A, is used for shell geometry.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 4 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

if nargin < 3
    orcLtube = [];
end

orcHxType = lower(string(orcHxType));

% =========================================================================
% TUBE FAMILY
% =========================================================================
switch orcHxType
    case "evaporator"
        orcDo = config.orc_evap_tube_do;              % outside diameter [m]
        orcWall = config.orc_evap_tube_wall;          % wall thickness [m]
        orcPitch = config.orc_evap_tube_pitch;        % tube pitch [m]
        orcTubePasses = config.orc_evap_tubePassCandidates;

    case "condenser"
        orcDo = config.orc_cond_tube_do;              % outside diameter [m]
        orcWall = config.orc_cond_tube_wall;          % wall thickness [m]
        orcPitch = config.orc_cond_tube_pitch;        % tube pitch [m]
        orcTubePasses = config.orc_cond_tubePassCandidates;

    otherwise
        error('orc_sthe_geometry:UnknownHxType', ...
            'orcHxType must be evaporator or condenser.');
end

if numel(orcTubePasses) ~= 1 || orcTubePasses ~= 1
    error('orc_sthe_geometry:TubePassNotImplemented', ...
        ['ORC v0.7 uses the source-closed one-tube-pass geometry. ', ...
         'Parallel physical modules are supported separately.']);
end

if config.orc_hx_shellPasses ~= 1
    error('orc_sthe_geometry:ShellPassNotImplemented', ...
        'ORC v0.7 supports one TEMA-E shell pass.');
end

if config.orc_hx_layoutAngle_deg ~= 60
    error('orc_sthe_geometry:LayoutNotImplemented', ...
        'ORC v0.7 geometry kernel is implemented for 60 deg layout.');
end

% =========================================================================
% BASIC INPUT CHECKS
% =========================================================================
validateattributes(orcNt,{'numeric'},{'scalar','integer','positive'});

orcDi = orcDo - 2*orcWall;                           % inside diameter [m]
if orcDi <= 0
    error('orc_sthe_geometry:InvalidTubeWall', ...
        'Tube wall thickness produces a non-positive inside diameter.');
end
if orcPitch <= orcDo
    error('orc_sthe_geometry:InvalidPitch', ...
        'Tube pitch must exceed tube outside diameter.');
end

% =========================================================================
% 60-DEG STAGGERED TUBE BANK
% =========================================================================
orcXt = sqrt(3)*orcPitch;                            % transverse pitch [m]
orcXl = 0.5*orcPitch;                               % longitudinal pitch [m]
orcCt = sqrt(3)/2;                                  % tube-count constant [-]
orcXd = hypot(orcXt,orcXl);                         % diagonal pitch [m]

orcXtStar = orcXt/orcDo;                            % [-]
orcXlStar = orcXl/orcDo;                            % [-]
orcXdStar = orcXd/orcDo;                            % [-]

% =========================================================================
% TUBE BUNDLE AND SHELL DIAMETER
% =========================================================================
% Walraven Eq. A.5 inverted for one tube pass.
orcDctl = orcPitch*sqrt(4*orcCt*orcNt/pi);          % tube-center circle [m]

% Walraven Eqs. A.1-A.2 with delta_bb = 0.017 Ds + 0.0265 m.
orcDs = (orcDctl + orcDo + 0.0265)/0.983;           % shell diameter [m]
orcDeltaBB = 0.017*orcDs + 0.0265;                  % bundle bypass clearance [m]
orcDotl = orcDs - orcDeltaBB;                       % outermost tube diameter [m]

% =========================================================================
% BAFFLE CUT AND ANGLES
% =========================================================================
orcLc = config.orc_hx_baffleCutRatio*orcDs;         % baffle cut length [m]

orcArgB = 1 - 2*orcLc/orcDs;
orcArgB = min(max(orcArgB,-1),1);
orcThetaB = 2*acos(orcArgB);                        % shell baffle angle [rad]

orcArgCtl = (orcDs - 2*orcLc)/orcDctl;
orcArgCtl = min(max(orcArgCtl,-1),1);
orcThetaCtl = 2*acos(orcArgCtl);                    % tube-center angle [rad]

% =========================================================================
% BAFFLE SPACING
% =========================================================================
orcLbTarget = config.orc_hx_baffleSpacingTarget;    % target spacing [m]

if isempty(orcLtube) || ~isfinite(orcLtube) || orcLtube <= 0
    orcLtubeUsed = NaN;                             % tube length not fixed [m]
    orcNb = NaN;                                    % baffle count [-]
    orcLb = orcLbTarget;                            % provisional spacing [m]
else
    orcLtubeUsed = orcLtube;                        % tube length [m]
    orcNb = max(1,round(orcLtube/orcLbTarget)-1);   % baffle count [-]
    orcLb = orcLtube/(orcNb+1);                    % equal baffle spacing [m]
end

% =========================================================================
% WINDOW GEOMETRY
% =========================================================================
% Walraven Eqs. A.6-A.11.
orcAfrW = orcDs^2/4 * ...
    (orcThetaB/2 - (1 - 2*orcLc/orcDs)*sin(orcThetaB/2)); % gross window area [m2]

orcFw = orcThetaCtl/(2*pi) - sin(orcThetaCtl)/(2*pi);     % tube fraction/window [-]
orcAfrT = pi/4*orcDo^2*orcFw*orcNt;                       % tube area/window [m2]
orcAoW = orcAfrW - orcAfrT;                               % net window flow area [m2]

if orcAoW <= 0
    error('orc_sthe_geometry:NegativeWindowArea', ...
        'The selected tube count produces a non-positive window flow area.');
end

orcDhW = 4*orcAoW/(pi*orcDo*orcFw*orcNt + orcDs*orcThetaB/2); % window Dh [m]
orcNrCW = 0.8/orcXl*(orcLc - 0.5*(orcDs-orcDctl));             % rows/window [-]

% =========================================================================
% CROSSFLOW GEOMETRY
% =========================================================================
% Walraven Eqs. A.12-A.15. Current 60-deg families use low pitch.
orcFc = 1 - 2*orcFw;                                      % crossflow tube fraction [-]
orcNrCC = (orcDs - 2*orcLc)/orcXl;                        % rows/crossflow [-]

orcAoCr = (orcDs - orcDotl + ...
    2*orcDctl/orcXt*(orcPitch-orcDo))*orcLb;              % crossflow area [m2]

if orcAoCr <= 0
    error('orc_sthe_geometry:NegativeCrossflowArea', ...
        'The selected geometry produces a non-positive crossflow area.');
end

% =========================================================================
% BYPASS AND LEAKAGE AREAS
% =========================================================================
% Walraven Eqs. A.16-A.18.
orcFbp = (orcDs-orcDotl)*orcLb/orcAoCr;                  % bundle bypass ratio [-]
orcDeltaTB = 0.4e-3;                                     % tube-baffle clearance [m]
orcDeltaSB = 3.1e-3 + 0.004*orcDs;                       % shell-baffle clearance [m]

orcAoTB = pi/4*((orcDo+orcDeltaTB)^2-orcDo^2)* ...
    orcNt*(1-orcFw);                                     % tube-baffle leakage [m2]

orcAoSB = pi*orcDs*orcDeltaSB/2* ...
    (1-orcThetaB/(2*pi));                                % shell-baffle leakage [m2]

% =========================================================================
% DERIVED TUBE-BANK HYDRAULIC DIAMETER
% =========================================================================
% Unit-cell free area / wetted perimeter for the staggered bank.
orcAcell = orcCt*orcPitch^2;                             % repeating cell area [m2]
orcAfreeCell = orcAcell - pi*orcDo^2/4;                 % free cell area [m2]
orcDhShell = 4*orcAfreeCell/(pi*orcDo);                  % shell-bank Dh [m]

% =========================================================================
% TUBE-SIDE FLOW AREA
% =========================================================================
orcAtubeFlow = orcNt*pi*orcDi^2/4;                      % one-pass flow area [m2]

% =========================================================================
% HEAT-TRANSFER AREA
% =========================================================================
if isfinite(orcLtubeUsed)
    orcAreaOutside = pi*orcDo*orcNt*orcLtubeUsed;       % outside tube area [m2]
    orcAreaInside = pi*orcDi*orcNt*orcLtubeUsed;        % inside tube area [m2]
else
    orcAreaOutside = NaN;                               % [m2]
    orcAreaInside = NaN;                                % [m2]
end

% =========================================================================
% GEOMETRIC FEASIBILITY
% =========================================================================
orcPitchRatio = orcPitch/orcDo;                         % relative pitch [-]
orcDiameterRatio = orcDo/orcDs;                         % tube/shell ratio [-]

orcGeometryOK = ...
    orcDs >= config.orc_hx_minShellDiameter && ...
    orcDs <= config.orc_hx_maxShellDiameter && ...
    orcPitchRatio >= 1.15 && orcPitchRatio <= 2.5 && ...
    orcDiameterRatio <= 0.1 && ...
    orcLb >= 0.30 && orcLb <= 5.0;

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcGeometry = struct();

orcGeometry.orc_hxType = char(orcHxType);
orcGeometry.orc_NshellPass = 1;                        % [-]
orcGeometry.orc_NtubePass = 1;                         % [-]
orcGeometry.orc_layoutAngle_deg = 60;                  % [deg]

orcGeometry.Nt = orcNt;                                % tube count [-]
orcGeometry.Ltube = orcLtubeUsed;                      % tube length [m]
orcGeometry.do = orcDo;                                % tube OD [m]
orcGeometry.di = orcDi;                                % tube ID [m]
orcGeometry.wall = orcWall;                            % wall thickness [m]
orcGeometry.pt = orcPitch;                             % tube pitch [m]
orcGeometry.pitchRatio = orcPitchRatio;                % [-]

orcGeometry.Xt = orcXt;                                % transverse pitch [m]
orcGeometry.Xl = orcXl;                                % longitudinal pitch [m]
orcGeometry.Xd = orcXd;                                % diagonal pitch [m]
orcGeometry.Ct = orcCt;                                % tube-count constant [-]
orcGeometry.XtStar = orcXtStar;                        % [-]
orcGeometry.XlStar = orcXlStar;                        % [-]
orcGeometry.XdStar = orcXdStar;                        % [-]

orcGeometry.Dctl = orcDctl;                            % [m]
orcGeometry.Dotl = orcDotl;                            % [m]
orcGeometry.Dshell = orcDs;                            % [m]
orcGeometry.deltaBB = orcDeltaBB;                      % [m]
orcGeometry.do_over_Dshell = orcDiameterRatio;         % [-]

orcGeometry.lc = orcLc;                                % baffle cut [m]
orcGeometry.baffleCutRatio = config.orc_hx_baffleCutRatio; % [-]
orcGeometry.thetaB = orcThetaB;                        % [rad]
orcGeometry.thetaCtl = orcThetaCtl;                    % [rad]
orcGeometry.Nb = orcNb;                                % baffle count [-]
orcGeometry.Lb = orcLb;                                % baffle spacing [m]

orcGeometry.AfrW = orcAfrW;                            % gross window area [m2]
orcGeometry.Fw = orcFw;                                % [-]
orcGeometry.AfrT = orcAfrT;                            % [m2]
orcGeometry.AoW = orcAoW;                              % window flow area [m2]
orcGeometry.DhW = orcDhW;                              % window hydraulic diameter [m]
orcGeometry.NrCW = orcNrCW;                            % effective rows/window [-]

orcGeometry.Fc = orcFc;                                % [-]
orcGeometry.NrCC = orcNrCC;                            % effective rows/crossflow [-]
orcGeometry.AoCr = orcAoCr;                            % crossflow area [m2]
orcGeometry.Fbp = orcFbp;                              % bundle bypass area ratio [-]
orcGeometry.AoTB = orcAoTB;                            % tube-baffle leakage [m2]
orcGeometry.AoSB = orcAoSB;                            % shell-baffle leakage [m2]
orcGeometry.deltaTB = orcDeltaTB;                      % [m]
orcGeometry.deltaSB = orcDeltaSB;                      % [m]
orcGeometry.DhShell = orcDhShell;                      % derived tube-bank Dh [m]

orcGeometry.AtubeFlow = orcAtubeFlow;                  % tube flow area [m2]
orcGeometry.Aoutside = orcAreaOutside;                 % heat-transfer area [m2]
orcGeometry.Ainside = orcAreaInside;                   % heat-transfer area [m2]
orcGeometry.orc_geometryOK = orcGeometryOK;             % feasibility flag [-]

end
