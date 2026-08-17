function out = preheater_sthe_core_v1(action,varargin)
%PREHEATER_STHE_CORE_V1 Local STHE single-phase core copied from ORC_v23.
%
% This keeps the seawater preheater independent from ORC runtime functions
% while preserving the same single-phase geometry, tube-side, and shell-side
% correlation structure used by the ORC STHE model.

switch lower(string(action))
    case "default_config"
        if nargin >= 2
            out = localDefaultConfig(varargin{1});
        else
            out = localDefaultConfig(struct());
        end
    case "geometry"
        out = localGeometry(varargin{:});
    case "tube_singlephase"
        out = localTubeSinglephase(varargin{:});
    case "shell_singlephase"
        out = localShellSinglephase(varargin{:});
    otherwise
        error('preheater_sthe_core_v1:UnknownAction','Unknown action: %s',action);
end
end

function config = localDefaultConfig(config)
if nargin < 1 || isempty(config)
    config = struct();
end
config = localSetDefault(config,'orc_hx_shellPasses',1);
config = localSetDefault(config,'orc_hx_layoutAngle_deg',60);
config = localSetDefault(config,'orc_hx_baffleCutRatio',0.35);
config = localSetDefault(config,'orc_hx_baffleSpacingTarget',0.30);
config = localSetDefault(config,'orc_hx_maxShellDiameter',2.00);
config = localSetDefault(config,'orc_hx_minShellDiameter',0.30);
config = localSetDefault(config,'orc_hx_maxTubeLength',8.00);
config = localSetDefault(config,'orc_hx_minTubeLength',0.50);
config = localSetDefault(config,'orc_hx_designAreaMargin',5e-3);
config = localSetDefault(config,'orc_hx_useSealingStrips',true);
config = localSetDefault(config,'orc_hx_equalBaffleSpacing',true);
config = localSetDefault(config,'orc_hx_useJrCorrection',false);
config = localSetDefault(config,'orc_cond_tube_do',0.02540);
config = localSetDefault(config,'orc_cond_tube_wall',0.00200);
config = localSetDefault(config,'orc_cond_tube_pitch',0.03175);
config = localSetDefault(config,'orc_cond_tubePassCandidates',1);
config = localSetDefault(config,'orc_evap_tube_do',0.01905);
config = localSetDefault(config,'orc_evap_tube_wall',0.00200);
config = localSetDefault(config,'orc_evap_tube_pitch',0.02540);
config = localSetDefault(config,'orc_evap_tubePassCandidates',1);
end

function G = localGeometry(hxType,Nt,Ltube,config)
config = localDefaultConfig(config);
if nargin < 3
    Ltube = [];
end
hxType = lower(string(hxType));
switch hxType
    case "evaporator"
        do = config.orc_evap_tube_do;
        wall = config.orc_evap_tube_wall;
        pitch = config.orc_evap_tube_pitch;
        tubePasses = config.orc_evap_tubePassCandidates;
    case "condenser"
        do = config.orc_cond_tube_do;
        wall = config.orc_cond_tube_wall;
        pitch = config.orc_cond_tube_pitch;
        tubePasses = config.orc_cond_tubePassCandidates;
    otherwise
        error('preheater_sthe_core_v1:UnknownHxType','hxType must be evaporator or condenser.');
end
if numel(tubePasses) ~= 1 || tubePasses ~= 1
    error('preheater_sthe_core_v1:TubePassNotImplemented','Only one tube pass is implemented.');
end
if config.orc_hx_shellPasses ~= 1
    error('preheater_sthe_core_v1:ShellPassNotImplemented','Only one shell pass is implemented.');
end
if config.orc_hx_layoutAngle_deg ~= 60
    error('preheater_sthe_core_v1:LayoutNotImplemented','Only 60 deg layout is implemented.');
end

validateattributes(Nt,{'numeric'},{'scalar','integer','positive'});
di = do - 2*wall;
if di <= 0
    error('preheater_sthe_core_v1:InvalidTubeWall','Tube wall gives non-positive ID.');
end
if pitch <= do
    error('preheater_sthe_core_v1:InvalidPitch','Tube pitch must exceed tube OD.');
end

Xt = sqrt(3)*pitch;
Xl = 0.5*pitch;
Ct = sqrt(3)/2;
Xd = hypot(Xt,Xl);
XtStar = Xt/do;
XlStar = Xl/do;
XdStar = Xd/do;

Dctl = pitch*sqrt(4*Ct*Nt/pi);
Dshell = (Dctl + do + 0.0265)/0.983;
deltaBB = 0.017*Dshell + 0.0265;
Dotl = Dshell - deltaBB;

lc = config.orc_hx_baffleCutRatio*Dshell;
argB = min(max(1 - 2*lc/Dshell,-1),1);
thetaB = 2*acos(argB);
argCtl = min(max((Dshell - 2*lc)/Dctl,-1),1);
thetaCtl = 2*acos(argCtl);

LbTarget = config.orc_hx_baffleSpacingTarget;
if isempty(Ltube) || ~isfinite(Ltube) || Ltube <= 0
    LtubeUsed = NaN;
    Nb = NaN;
    Lb = LbTarget;
else
    LtubeUsed = Ltube;
    Nb = max(1,round(Ltube/LbTarget)-1);
    Lb = Ltube/(Nb+1);
end

AfrW = Dshell^2/4*(thetaB/2 - (1 - 2*lc/Dshell)*sin(thetaB/2));
Fw = thetaCtl/(2*pi) - sin(thetaCtl)/(2*pi);
AfrT = pi/4*do^2*Fw*Nt;
AoW = AfrW - AfrT;
if AoW <= 0
    error('preheater_sthe_core_v1:NegativeWindowArea','Non-positive window flow area.');
end
DhW = 4*AoW/(pi*do*Fw*Nt + Dshell*thetaB/2);
NrCW = 0.8/Xl*(lc - 0.5*(Dshell-Dctl));

Fc = 1 - 2*Fw;
NrCC = (Dshell - 2*lc)/Xl;
AoCr = (Dshell - Dotl + 2*Dctl/Xt*(pitch-do))*Lb;
if AoCr <= 0
    error('preheater_sthe_core_v1:NegativeCrossflowArea','Non-positive crossflow area.');
end

Fbp = (Dshell-Dotl)*Lb/AoCr;
deltaTB = 0.4e-3;
deltaSB = 3.1e-3 + 0.004*Dshell;
AoTB = pi/4*((do+deltaTB)^2-do^2)*Nt*(1-Fw);
AoSB = pi*Dshell*deltaSB/2*(1-thetaB/(2*pi));

Acell = Ct*pitch^2;
AfreeCell = Acell - pi*do^2/4;
DhShell = 4*AfreeCell/(pi*do);
AtubeFlow = Nt*pi*di^2/4;

if isfinite(LtubeUsed)
    Aoutside = pi*do*Nt*LtubeUsed;
    Ainside = pi*di*Nt*LtubeUsed;
else
    Aoutside = NaN;
    Ainside = NaN;
end

pitchRatio = pitch/do;
diameterRatio = do/Dshell;
geometryOK = Dshell >= config.orc_hx_minShellDiameter && ...
    Dshell <= config.orc_hx_maxShellDiameter && ...
    pitchRatio >= 1.15 && pitchRatio <= 2.5 && ...
    diameterRatio <= 0.1 && Lb >= 0.30 && Lb <= 5.0;

G = struct();
G.orc_hxType = char(hxType);
G.orc_NshellPass = 1;
G.orc_NtubePass = 1;
G.orc_layoutAngle_deg = 60;
G.Nt = Nt;
G.Ltube = LtubeUsed;
G.do = do;
G.di = di;
G.wall = wall;
G.pt = pitch;
G.pitchRatio = pitchRatio;
G.Xt = Xt;
G.Xl = Xl;
G.Xd = Xd;
G.Ct = Ct;
G.XtStar = XtStar;
G.XlStar = XlStar;
G.XdStar = XdStar;
G.Dctl = Dctl;
G.Dotl = Dotl;
G.Dshell = Dshell;
G.deltaBB = deltaBB;
G.do_over_Dshell = diameterRatio;
G.lc = lc;
G.baffleCutRatio = config.orc_hx_baffleCutRatio;
G.thetaB = thetaB;
G.thetaCtl = thetaCtl;
G.Nb = Nb;
G.Lb = Lb;
G.AfrW = AfrW;
G.Fw = Fw;
G.AfrT = AfrT;
G.AoW = AoW;
G.DhW = DhW;
G.NrCW = NrCW;
G.Fc = Fc;
G.NrCC = NrCC;
G.AoCr = AoCr;
G.Fbp = Fbp;
G.AoTB = AoTB;
G.AoSB = AoSB;
G.deltaTB = deltaTB;
G.deltaSB = deltaSB;
G.DhShell = DhShell;
G.AtubeFlow = AtubeFlow;
G.Aoutside = Aoutside;
G.Ainside = Ainside;
G.orc_geometryOK = geometryOK;
end

function tube = localTubeSinglephase(flow,geom,L)
required = {'mdot','rho','mu','k','cp'};
localRequireFields(flow,required,'tube flow');
if nargin < 3 || isempty(L)
    L = NaN;
end
NtPerPass = geom.Nt/geom.orc_NtubePass;
areaFlow = NtPerPass*pi*geom.di^2/4;
velocity = flow.mdot/(flow.rho*areaFlow);
Re = flow.rho*velocity*geom.di/flow.mu;
Pr = flow.cp*flow.mu/flow.k;
if Re <= 0 || Pr <= 0
    error('preheater_sthe_core_v1:InvalidTubeDimensionless','Tube Re and Pr must be positive.');
end
if Re < 2300
    Nu = 3.66;
    fFanning = 16/Re;
    regime = 'laminar';
else
    if Re < 2e4
        fFanning = 0.079*Re^(-1/4);
    else
        fFanning = 0.046*Re^(-1/5);
    end
    Nu = (0.5*fFanning*(Re-1000)*Pr)/(1 + 12.7*sqrt(0.5*fFanning)*(Pr^(2/3)-1));
    regime = 'turbulent';
end
if ~isfinite(Nu) || Nu <= 0
    error('preheater_sthe_core_v1:InvalidTubeNusselt','Tube Nusselt is invalid.');
end
h = Nu*flow.k/geom.di;
fDarcy = 4*fFanning;
if isfinite(L) && L > 0
    dp = fDarcy*(L/geom.di)*flow.rho*velocity^2/2;
else
    dp = NaN;
end
tube = struct('Re',Re,'Pr',Pr,'Nu',Nu,'h',h,'velocity',velocity, ...
    'areaFlow',areaFlow,'f_Fanning',fFanning,'f_Darcy',fDarcy,'dp',dp, ...
    'regime',regime);
end

function shell = localShellSinglephase(flow,geom,config)
config = localDefaultConfig(config);
required = {'mdot','rho','mu','k','cp'};
localRequireFields(flow,required,'shell flow');

XtStar = geom.XtStar;
XlStar = geom.XlStar;
XdStar = geom.XdStar;
Dh = geom.DhShell;
threshold = 0.5*sqrt(2*XtStar^2 + 1);
uInf = flow.mdot/(flow.rho*geom.AoCr);
if XlStar >= threshold
    uMean = uInf*XtStar/(XtStar-1);
else
    uMean = uInf*XtStar/(2*(XdStar-1));
end
ReD = flow.rho*uMean*geom.do/flow.mu;
Pr = flow.cp*flow.mu/flow.k;
if ReD <= 0 || Pr <= 0
    error('preheater_sthe_core_v1:InvalidShellDimensionless','Shell Re and Pr must be positive.');
end

Nr = geom.NrCC;
if Nr >= 5 && Nr <= 10
    if XlStar >= threshold
        phiTN = 1/(2*XtStar^2)*(1/Nr-1/10);
    else
        phiTN = 2*((XdStar-1)/(XtStar*(XtStar-1)))^2*(1/Nr-1/10);
    end
else
    phiTN = 0;
end

commonDen = 4*XtStar*XlStar/pi - 1;
if commonDen <= 0
    error('preheater_sthe_core_v1:InvalidTubeBank','Non-positive Hagen denominator.');
end
geomNum = (sqrt(XlStar)-0.6)^2 + 0.75;
if XlStar >= threshold
    HgLam = 140*ReD*geomNum/(XtStar^1.6*commonDen);
else
    HgLam = 140*ReD*geomNum/(XdStar^1.6*commonDen);
end
HgTurbCoeff = (1.25 + 0.6/(XtStar-0.85)^1.08) + ...
    0.2*(XlStar/XtStar-1)^3 - 0.005*(XtStar/XlStar-1)^3;
HgTurb = HgTurbCoeff*ReD^1.75 + phiTN*ReD^2;
if ReD > 250000
    HgTurb = HgTurb*(1 + (ReD-250000)/325000);
end
blend = 1 - exp(1 - (ReD+200)/1000);
Hg = HgLam + HgTurb*blend;
if ~isfinite(Hg) || Hg <= 0
    error('preheater_sthe_core_v1:InvalidHagen','Invalid shell Hagen number.');
end

if XlStar >= 1
    Lq = 0.92*Hg*Pr*((4*XtStar/pi-1)/XdStar);
else
    Lq = 0.92*Hg*Pr*((4*XtStar*XlStar/pi-1)/(XlStar*XdStar));
end
if ~isfinite(Lq) || Lq <= 0
    error('preheater_sthe_core_v1:InvalidLeveque','Invalid shell Leveque number.');
end

hIdeal = flow.k/Dh*0.404*Lq^(1/3);
Jc = 0.55 + 0.72*geom.Fc;
leakSum = geom.AoSB + geom.AoTB;
rs = geom.AoSB/leakSum;
rlm = leakSum/geom.AoCr;
Jl = 0.44*(1-rs) + (1-0.44*(1-rs))*exp(-2.2*rlm);
if config.orc_hx_useSealingStrips
    Jb = 1;
else
    error('preheater_sthe_core_v1:JbNotImplemented','Bundle-bypass correction not implemented.');
end
if config.orc_hx_equalBaffleSpacing
    Js = 1;
else
    error('preheater_sthe_core_v1:JsNotImplemented','Unequal baffle spacing not implemented.');
end
if config.orc_hx_useJrCorrection
    error('preheater_sthe_core_v1:JrNotImplemented','Jr correction disabled in baseline.');
else
    Jr = 1;
end
h = hIdeal*Jc*Jl*Jb*Js*Jr;

dpBIdeal = flow.mu^2*geom.NrCC/(flow.rho*geom.do^2)*Hg;
Gw = flow.mdot/sqrt(geom.AoCr*geom.AoW);
if ReD > 100
    dpWIdeal = (2+0.6*geom.NrCW)*Gw^2/(2*flow.rho);
else
    dpWIdeal = 26*Gw*flow.mu/flow.rho*(geom.NrCW/(geom.pt-geom.do) + ...
        geom.Lb/geom.DhW^2) + Gw^2/(2*flow.rho);
end
pExp = -0.15*(1+rs) + 0.8;
fl = exp(-1.33*(1+rs)*rlm^pExp);
if config.orc_hx_useSealingStrips
    fb = 1;
else
    error('preheater_sthe_core_v1:FbNotImplemented','Bundle-bypass dP correction not implemented.');
end
if config.orc_hx_equalBaffleSpacing
    fs = 1;
else
    error('preheater_sthe_core_v1:FsNotImplemented','Unequal baffle spacing dP correction not implemented.');
end
if isfinite(geom.Nb)
    dp = ((geom.Nb-1)*dpBIdeal*fb + geom.Nb*dpWIdeal)*fl + ...
        2*dpBIdeal*(1+geom.NrCW/geom.NrCC)*fb*fs;
else
    dp = NaN;
end

shell = struct();
shell.u_inf = uInf;
shell.u_mean = uMean;
shell.Re_d = ReD;
shell.Pr = Pr;
shell.phi_tn = phiTN;
shell.Hg_lam = HgLam;
shell.Hg_turb = HgTurb;
shell.Hg = Hg;
shell.Lq = Lq;
shell.h_ideal = hIdeal;
shell.Jc = Jc;
shell.Jl = Jl;
shell.Jb = Jb;
shell.Js = Js;
shell.Jr = Jr;
shell.h = h;
shell.rs = rs;
shell.rlm = rlm;
shell.fl = fl;
shell.fb = fb;
shell.fs = fs;
shell.Gw = Gw;
shell.dp_b_ideal = dpBIdeal;
shell.dp_w_ideal = dpWIdeal;
shell.dp = dp;
end

function localRequireFields(S,fields,label)
for i = 1:numel(fields)
    if ~isfield(S,fields{i})
        error('preheater_sthe_core_v1:MissingInput','Missing %s.%s',label,fields{i});
    end
end
end

function S = localSetDefault(S,fieldName,defaultValue)
if ~isfield(S,fieldName) || isempty(S.(fieldName))
    S.(fieldName) = defaultValue;
end
end
