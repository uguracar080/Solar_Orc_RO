function PHOut = preheater_sthe_rating_v1(PHInput,PHDesign,PHConfig)
%PREHEATER_STHE_RATING_V1 Rate fixed-geometry STHE preheater.

if nargin < 1 || isempty(PHInput)
    PHInput = struct();
end
if nargin < 2 || isempty(PHDesign)
    PHDesign = struct();
end
if nargin < 3 || isempty(PHConfig)
    if isfield(PHDesign,'config')
        PHConfig = PHDesign.config;
    else
        PHConfig = struct();
    end
end
PHConfig = localDefaults(PHConfig);
orcConfig = preheater_sthe_core_v1('default_config',PHConfig.orc_config);

PHOut = localBlankOutput();

ThIn = localGet(PHInput,'T_hot_in_C',NaN);
TcIn = localGet(PHInput,'T_cold_in_C',NaN);
mdotHot = localGet(PHInput,'mdot_hot_kg_s',NaN);
mdotCold = localGet(PHInput,'mdot_cold_kg_s',NaN);
QAvailable = localGet(PHInput,'Q_available_W',Inf);
TcOutTarget = localGet(PHInput,'T_cold_out_target_C',TcIn + PHConfig.T_cold_rise_target_C);
TcOutTarget = min(TcOutTarget,PHConfig.T_cold_out_max_C);

PHOut.T_hot_in_C = ThIn;
PHOut.T_sw_in_C = TcIn;
PHOut.mdot_hot_kg_s = mdotHot;
PHOut.mdot_sw_kg_s = mdotCold;
PHOut.T_RO_target_C = TcOutTarget;

if any(~isfinite([ThIn,TcIn,mdotHot,mdotCold])) || mdotHot <= 0 || mdotCold <= 0
    PHOut.status = 'INVALID_INPUT';
    return
end

if ~isfield(PHDesign,'geometry') || isempty(PHDesign.geometry) || ...
        ~isfield(PHDesign,'N_parallel') || ~isfinite(PHDesign.N_parallel) || ...
        PHDesign.N_parallel <= 0 || ~isfield(PHDesign,'A_design_m2') || PHDesign.A_design_m2 <= 0
    PHOut.T_hot_out_C = ThIn;
    PHOut.T_cw_out_C = ThIn;
    PHOut.T_sw_out_C = TcIn;
    PHOut.T_RO_in_C = TcIn;
    PHOut.Q_recovered_W = 0;
    PHOut.feasible = true;
    PHOut.status = 'NO_FIXED_GEOMETRY';
    return
end

if ThIn <= TcIn + PHConfig.dT_min_K
    PHOut.T_hot_out_C = ThIn;
    PHOut.T_cw_out_C = ThIn;
    PHOut.T_sw_out_C = TcIn;
    PHOut.T_RO_in_C = TcIn;
    PHOut.Q_recovered_W = 0;
    PHOut.feasible = true;
    PHOut.status = 'NO_THERMAL_DRIVING_FORCE';
    return
end

Npar = max(1,round(PHDesign.N_parallel));
geom = PHDesign.geometry;

hotFlow = localFlowStruct(mdotHot/Npar,ThIn,PHConfig.hot);
coldFlow = localFlowStruct(mdotCold/Npar,TcIn,PHConfig.cold);
shell = preheater_sthe_core_v1('shell_singlephase',hotFlow,geom,orcConfig);
tube = preheater_sthe_core_v1('tube_singlephase',coldFlow,geom,geom.Ltube);
U = localOverallU(shell.h,tube.h);
A = PHDesign.A_design_m2;
UA = U*A;

C_hot = mdotHot*PHConfig.hot.cp_JkgK;
C_cold = mdotCold*PHConfig.cold.cp_JkgK;
Cmin = min(C_hot,C_cold);
Cmax = max(C_hot,C_cold);
Cr = Cmin/Cmax;
NTU = UA/Cmin;

if abs(Cr - 1) < 1e-8
    epsHx = NTU/(1 + NTU);
else
    epsHx = (1 - exp(-NTU*(1 - Cr))) / (1 - Cr*exp(-NTU*(1 - Cr)));
end
epsHx = min(max(epsHx,0),1);

Qntu = epsHx*Cmin*(ThIn - TcIn);
Qupper = min(Qntu,QAvailable);
Qupper = min(Qupper,C_cold*max(0,TcOutTarget - TcIn));
Qupper = max(0,Qupper);

Q = localApproachLimitedHeat(Qupper,ThIn,TcIn,C_hot,C_cold,PHConfig.dT_min_K);
ThOut = ThIn - Q/C_hot;
TcOut = TcIn + Q/C_cold;

PHOut.Q_recovered_W = Q;
PHOut.T_hot_out_C = ThOut;
PHOut.T_cw_out_C = ThOut;
PHOut.T_sw_out_C = TcOut;
PHOut.T_RO_in_C = TcOut;
PHOut.effectiveness = epsHx;
PHOut.NTU = NTU;
PHOut.U_runtime_Wm2K = U;
PHOut.UA_runtime_WK = UA;
PHOut.A_ratio = A/max(PHDesign.A_design_m2,eps);
PHOut.dp_hot_Pa = shell.dp;
PHOut.dp_cold_Pa = tube.dp;
PHOut.shell = shell;
PHOut.tube = tube;
PHOut.feasible = true;
if Q > 0
    PHOut.status = 'OK';
else
    PHOut.status = 'NO_HEAT_RECOVERED';
end
end

function Q = localApproachLimitedHeat(Qupper,ThIn,TcIn,C_hot,C_cold,dTmin)
if Qupper <= 0
    Q = 0;
    return
end
isOK = @(q) ((ThIn - (TcIn + q/C_cold)) >= dTmin) && ...
            (((ThIn - q/C_hot) - TcIn) >= dTmin);
if isOK(Qupper)
    Q = Qupper;
    return
end
lo = 0;
hi = Qupper;
for i = 1:60
    mid = 0.5*(lo + hi);
    if isOK(mid)
        lo = mid;
    else
        hi = mid;
    end
end
Q = lo;
end

function flow = localFlowStruct(mdot,T_C,props)
flow = struct();
flow.mdot = mdot;
flow.rho = props.rho_kgm3;
flow.mu = props.mu_Pas;
flow.k = props.k_WmK;
flow.cp = props.cp_JkgK;
flow.T_C = T_C;
end

function cfg = localDefaults(cfg)
cfg = localSetDefault(cfg,'dT_min_K',3.0);
cfg = localSetDefault(cfg,'T_cold_rise_target_C',5.0);
cfg = localSetDefault(cfg,'T_cold_out_max_C',45.0);
if ~isfield(cfg,'orc_config') || isempty(cfg.orc_config)
    cfg.orc_config = struct();
end
if ~isfield(cfg,'hot') || isempty(cfg.hot)
    cfg.hot = struct();
end
cfg.hot = localSetDefault(cfg.hot,'cp_JkgK',4180);
cfg.hot = localSetDefault(cfg.hot,'rho_kgm3',997);
cfg.hot = localSetDefault(cfg.hot,'mu_Pas',8.9e-4);
cfg.hot = localSetDefault(cfg.hot,'k_WmK',0.60);
if ~isfield(cfg,'cold') || isempty(cfg.cold)
    cfg.cold = struct();
end
cfg.cold = localSetDefault(cfg.cold,'cp_JkgK',3990);
cfg.cold = localSetDefault(cfg.cold,'rho_kgm3',1025);
cfg.cold = localSetDefault(cfg.cold,'mu_Pas',1.05e-3);
cfg.cold = localSetDefault(cfg.cold,'k_WmK',0.60);
end

function out = localBlankOutput()
out = struct();
out.component = 'Preheater_STHE_v1';
out.T_hot_in_C = NaN;
out.T_hot_out_C = NaN;
out.T_cw_out_C = NaN;
out.T_sw_in_C = NaN;
out.T_sw_out_C = NaN;
out.T_RO_in_C = NaN;
out.T_RO_target_C = NaN;
out.mdot_hot_kg_s = NaN;
out.mdot_sw_kg_s = NaN;
out.Q_recovered_W = NaN;
out.effectiveness = NaN;
out.NTU = NaN;
out.U_runtime_Wm2K = NaN;
out.UA_runtime_WK = NaN;
out.A_ratio = NaN;
out.dp_hot_Pa = NaN;
out.dp_cold_Pa = NaN;
out.feasible = false;
out.status = 'UNINITIALIZED';
end

function U = localOverallU(hShell,hTube)
U = 1/(1/max(hShell,eps) + 1/max(hTube,eps));
end

function value = localGet(S,fieldName,defaultValue)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end

function S = localSetDefault(S,fieldName,defaultValue)
if ~isfield(S,fieldName) || isempty(S.(fieldName))
    S.(fieldName) = defaultValue;
end
end
