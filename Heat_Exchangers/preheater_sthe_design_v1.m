function PHDesign = preheater_sthe_design_v1(PHInput,PHConfig)
%PREHEATER_STHE_DESIGN_V1 Size fixed-geometry single-phase STHE preheater.
%
% The geometry, tube/shell correlations, and pressure-drop kernels are a
% local preheater copy of the ORC_v23 single-phase STHE core. V1 uses
% seawater on the tube side and condenser-loop water on the shell side.

if nargin < 1 || isempty(PHInput)
    PHInput = struct();
end
if nargin < 2 || isempty(PHConfig)
    PHConfig = struct();
end
PHConfig = localDefaults(PHConfig);
orcConfig = preheater_sthe_core_v1('default_config',PHConfig.orc_config);

PHDesign = localBlankDesign();
PHDesign.config = PHConfig;

ThIn = localGet(PHInput,'T_hot_in_C',NaN);
TcIn = localGet(PHInput,'T_cold_in_C',NaN);
TcOutRequested = min(localGet(PHInput,'T_cold_out_target_C',PHConfig.T_cold_out_design_C), ...
    PHConfig.T_cold_out_max_C);
mdotHot = localGet(PHInput,'mdot_hot_kg_s',NaN);
mdotCold = localGet(PHInput,'mdot_cold_kg_s',NaN);

PHDesign.T_hot_in_design_C = ThIn;
PHDesign.T_cold_in_design_C = TcIn;
PHDesign.T_cold_out_requested_C = TcOutRequested;
PHDesign.mdot_hot_design_kg_s = mdotHot;
PHDesign.mdot_cold_design_kg_s = mdotCold;

if any(~isfinite([ThIn,TcIn,TcOutRequested,mdotHot,mdotCold])) || mdotHot <= 0 || mdotCold <= 0
    PHDesign.status = 'INVALID_INPUT';
    return
end

TcOutTarget = min(TcOutRequested,ThIn - PHConfig.dT_min_K);
PHDesign.T_cold_out_design_C = TcOutTarget;
PHDesign.target_limited_by_approach = TcOutTarget < TcOutRequested - 1e-9;

if TcOutTarget <= TcIn
    PHDesign.status = 'NO_COLD_HEATING_REQUIRED';
    PHDesign.feasible = true;
    PHDesign.Q_design_W = 0;
    PHDesign.A_design_m2 = 0;
    PHDesign.UA_design_WK = 0;
    return
end

hotProps = localSideProps(PHConfig,'hot',ThIn);
coldProps = localSideProps(PHConfig,'cold',0.5*(TcIn + TcOutTarget));
Qtotal = mdotCold*coldProps.cp_JkgK*(TcOutTarget - TcIn);
dT1 = ThIn - TcOutTarget;
ThOut = ThIn - Qtotal/(mdotHot*hotProps.cp_JkgK);
for iter = 1:3
    hotProps = localSideProps(PHConfig,'hot',0.5*(ThIn + ThOut));
    ThOut = ThIn - Qtotal/(mdotHot*hotProps.cp_JkgK);
end
dT2 = ThOut - TcIn;
if min([dT1,dT2]) < PHConfig.dT_min_K
    PHDesign.status = 'MIN_APPROACH_VIOLATED';
    PHDesign.Q_design_W = Qtotal;
    PHDesign.T_hot_out_design_C = ThOut;
    PHDesign.dT_min_actual_K = min([dT1,dT2]);
    return
end
lmtd = localLmtd(dT1,dT2);

best = [];
NparMin = max(1,round(PHConfig.N_parallel_min));
NparMax = max(NparMin,round(PHConfig.N_parallel_max));
search = localBlankSearchSummary(NparMin,NparMax,numel(PHConfig.Nt_list),PHConfig);
for Npar = NparMin:NparMax
    for Nt = PHConfig.Nt_list
        search.candidates_evaluated_total = search.candidates_evaluated_total + 1;
        cand = localEvaluateCandidate(Npar,Nt,Qtotal,lmtd,ThIn,ThOut,TcIn,TcOutTarget, ...
            mdotHot,mdotCold,PHConfig,orcConfig);
        if cand.thermal_geometric_ok
            search.candidates_thermal_geometric_feasible = search.candidates_thermal_geometric_feasible + 1;
        end
        if cand.dp_rejected
            search.candidates_dp_rejected = search.candidates_dp_rejected + 1;
            if ~cand.dp_hot_ok
                search.candidates_dp_hot_rejected = search.candidates_dp_hot_rejected + 1;
            end
            if ~cand.dp_cold_ok
                search.candidates_dp_cold_rejected = search.candidates_dp_cold_rejected + 1;
            end
        end
        if cand.ok
            search.candidates_feasible_after_dp = search.candidates_feasible_after_dp + 1;
            if isempty(best) || cand.score < best.score
                best = cand;
            end
        end
    end
end
PHDesign.search = search;

if isempty(best)
    PHDesign.status = 'NO_FEASIBLE_STHE_GEOMETRY';
    return
end

PHDesign.feasible = true;
if PHDesign.target_limited_by_approach
    PHDesign.status = 'TARGET_APPROACH_LIMITED';
else
    PHDesign.status = 'OK';
end
PHDesign.Q_design_W = Qtotal;
PHDesign.T_hot_out_design_C = ThOut;
PHDesign.dT1_design_K = dT1;
PHDesign.dT2_design_K = dT2;
PHDesign.dT_min_actual_K = min([dT1,dT2]);
PHDesign.LMTD_design_K = lmtd;
PHDesign.U_design_Wm2K = best.U_Wm2K;
PHDesign.UA_design_WK = best.UA_WK;
PHDesign.A_design_m2 = best.A_total_m2;
PHDesign.A_required_m2 = best.A_required_total_m2;
PHDesign.N_parallel = best.N_parallel;
PHDesign.Nt = best.geometry.Nt;
PHDesign.Ltube_m = best.geometry.Ltube;
PHDesign.Dshell_m = best.geometry.Dshell;
PHDesign.geometry = best.geometry;
PHDesign.dp_hot_Pa = best.dp_hot_Pa;
PHDesign.dp_cold_Pa = best.dp_cold_Pa;
PHDesign.dp_hot_design_Pa = best.dp_hot_Pa;
PHDesign.dp_cold_design_Pa = best.dp_cold_Pa;
PHDesign.dp_hot_max_Pa = best.dp_hot_max_Pa;
PHDesign.dp_cold_max_Pa = best.dp_cold_max_Pa;
PHDesign.hot_velocity_design_m_s = best.hot_velocity_m_s;
PHDesign.cold_velocity_design_m_s = best.cold_velocity_m_s;
PHDesign.candidate_score = best.score;
PHDesign.candidate_score_basis = 'minimum_total_area_after_thermal_geometric_velocity_and_dp_constraints';
PHDesign.selected_reason = sprintf('Lowest total area among %d pressure-drop-feasible candidates over N_parallel=%d..%d.', ...
    PHDesign.search.candidates_feasible_after_dp,PHDesign.search.N_parallel_min,PHDesign.search.N_parallel_max);
PHDesign.shell = best.shell;
PHDesign.tube = best.tube;
PHDesign.method = 'local_copy_of_ORC_v23_STHE_singlephase_geometry_and_correlations';
end

function cand = localEvaluateCandidate(Npar,Nt,Qtotal,lmtd,ThIn,ThOut,TcIn,TcOut,mdotHot,mdotCold,PHConfig,orcConfig)
cand = localBlankCandidate(Npar,Nt,PHConfig);
try
    geom0 = preheater_sthe_core_v1('geometry',PHConfig.geometry_family,Nt,NaN,orcConfig);
    if ~geom0.orc_geometryOK
        cand.reject_reason = 'INITIAL_GEOMETRY_LIMIT';
        return
    end

    hotT = 0.5*(ThIn + ThOut);
    coldT = 0.5*(TcIn + TcOut);
    hotFlow = localFlowStruct(mdotHot/Npar,hotT,localSideProps(PHConfig,'hot',hotT));
    coldFlow = localFlowStruct(mdotCold/Npar,coldT,localSideProps(PHConfig,'cold',coldT));

    shell0 = preheater_sthe_core_v1('shell_singlephase',hotFlow,geom0,orcConfig);
    tube0 = preheater_sthe_core_v1('tube_singlephase',coldFlow,geom0,NaN);
    U = localOverallU(shell0.h,tube0.h);
    Areq = (Qtotal/Npar)/(U*lmtd);
    LtubeReq = Areq/(pi*geom0.do*Nt);
    Ltube = LtubeReq*(1+orcConfig.orc_hx_designAreaMargin);

    if Ltube < orcConfig.orc_hx_minTubeLength || Ltube > orcConfig.orc_hx_maxTubeLength
        cand.reject_reason = 'TUBE_LENGTH_LIMIT';
        return
    end

    geom = preheater_sthe_core_v1('geometry',PHConfig.geometry_family,Nt,Ltube,orcConfig);
    if ~geom.orc_geometryOK
        cand.reject_reason = 'FINAL_GEOMETRY_LIMIT';
        return
    end

    shell = preheater_sthe_core_v1('shell_singlephase',hotFlow,geom,orcConfig);
    tube = preheater_sthe_core_v1('tube_singlephase',coldFlow,geom,Ltube);
    AgeoMod = pi*geom.do*geom.Nt*geom.Ltube;

    cand.thermal_geometric_ok = true;
    cand.N_parallel = Npar;
    cand.geometry = geom;
    cand.U_Wm2K = localOverallU(shell.h,tube.h);
    cand.UA_WK = cand.U_Wm2K*Npar*AgeoMod;
    cand.A_total_m2 = Npar*AgeoMod;
    cand.A_required_total_m2 = Npar*Areq;
    cand.dp_hot_Pa = shell.dp;
    cand.dp_cold_Pa = tube.dp;
    cand.hot_velocity_m_s = shell.u_mean;
    cand.cold_velocity_m_s = tube.velocity;
    cand.dp_hot_ok = isfinite(shell.dp) && shell.dp <= cand.dp_hot_max_Pa;
    cand.dp_cold_ok = isfinite(tube.dp) && tube.dp <= cand.dp_cold_max_Pa;
    if ~(cand.dp_hot_ok && cand.dp_cold_ok)
        cand.dp_rejected = true;
        cand.reject_reason = 'PRESSURE_DROP_LIMIT';
        return
    end
    cand.ok = true;
    cand.score = Npar*AgeoMod;
    cand.reject_reason = '';
    cand.shell = shell;
    cand.tube = tube;
catch ME
    cand.ok = false;
    cand.reject_reason = ME.identifier;
end
end

function cand = localBlankCandidate(Npar,Nt,PHConfig)
[dpHotMax,dpColdMax] = localPressureDropLimits(PHConfig);
cand = struct();
cand.ok = false;
cand.score = inf;
cand.N_parallel = Npar;
cand.Nt = Nt;
cand.thermal_geometric_ok = false;
cand.dp_rejected = false;
cand.dp_hot_ok = false;
cand.dp_cold_ok = false;
cand.dp_hot_max_Pa = dpHotMax;
cand.dp_cold_max_Pa = dpColdMax;
cand.dp_hot_Pa = NaN;
cand.dp_cold_Pa = NaN;
cand.hot_velocity_m_s = NaN;
cand.cold_velocity_m_s = NaN;
cand.reject_reason = 'NOT_EVALUATED';
end

function search = localBlankSearchSummary(NparMin,NparMax,nNt,PHConfig)
[dpHotMax,dpColdMax] = localPressureDropLimits(PHConfig);
search = struct();
search.N_parallel_min = NparMin;
search.N_parallel_max = NparMax;
search.N_parallel_tested = NparMax - NparMin + 1;
search.Nt_values_per_parallel = nNt;
search.candidates_evaluated_total = 0;
search.candidates_thermal_geometric_feasible = 0;
search.candidates_dp_rejected = 0;
search.candidates_dp_hot_rejected = 0;
search.candidates_dp_cold_rejected = 0;
search.candidates_feasible_after_dp = 0;
search.dp_hot_max_Pa = dpHotMax;
search.dp_cold_max_Pa = dpColdMax;
end

function [dpHotMax,dpColdMax] = localPressureDropLimits(PHConfig)
design = localGet(PHConfig,'design',struct());
dpHotMax = localGet(design,'dp_hot_max_Pa',localGet(PHConfig,'dp_hot_max_Pa',25e3));
dpColdMax = localGet(design,'dp_cold_max_Pa',localGet(PHConfig,'dp_cold_max_Pa',25e3));
dpHotMax = max(dpHotMax,0);
dpColdMax = max(dpColdMax,0);
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

function props = localSideProps(PHConfig,sideName,T_C)
side = PHConfig.(sideName);
fluid = localGet(side,'fluid','');
useGrid = localGet(side,'useFluidGrid',false);
if useGrid && localIsWater(fluid)
    props = preheater_water_properties_v1(T_C,PHConfig);
else
    props = side;
end
end

function cfg = localDefaults(cfg)
cfg = localSetDefault(cfg,'dT_min_K',3.0);
cfg = localSetDefault(cfg,'T_cold_out_design_C',25.0);
cfg = localSetDefault(cfg,'T_cold_out_max_C',45.0);
cfg = localSetDefault(cfg,'geometry_family','condenser');
cfg = localSetDefault(cfg,'N_parallel_min',1);
cfg = localSetDefault(cfg,'N_parallel_max',20);
cfg = localSetDefault(cfg,'Nt_list',20:20:1200);
if ~isfield(cfg,'design') || isempty(cfg.design)
    cfg.design = struct();
end
% Conservative STHE branch limits. Keeping preheater dP near ordinary pump
% design values prevents compact, high-velocity geometries from winning.
cfg.design = localSetDefault(cfg.design,'dp_hot_max_Pa',25e3);
cfg.design = localSetDefault(cfg.design,'dp_cold_max_Pa',25e3);
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
cfg.hot = localSetDefault(cfg.hot,'fluid','Water');
cfg.hot = localSetDefault(cfg.hot,'useFluidGrid',true);
cfg.hot = localSetDefault(cfg.hot,'gridFile','thermoDB_Water_V5.mat');
cfg.hot = localSetDefault(cfg.hot,'P_Pa',2e5);
if ~isfield(cfg,'cold') || isempty(cfg.cold)
    cfg.cold = struct();
end
cfg.cold = localSetDefault(cfg.cold,'cp_JkgK',3990);
cfg.cold = localSetDefault(cfg.cold,'rho_kgm3',1025);
cfg.cold = localSetDefault(cfg.cold,'mu_Pas',1.05e-3);
cfg.cold = localSetDefault(cfg.cold,'k_WmK',0.60);
cfg.cold = localSetDefault(cfg.cold,'fluid','Seawater');
cfg.cold = localSetDefault(cfg.cold,'useFluidGrid',false);
end

function D = localBlankDesign()
D = struct();
D.component = 'Preheater_STHE_v1';
D.feasible = false;
D.status = 'UNINITIALIZED';
D.Q_design_W = NaN;
D.A_design_m2 = NaN;
D.A_required_m2 = NaN;
D.UA_design_WK = NaN;
D.U_design_Wm2K = NaN;
D.T_hot_in_design_C = NaN;
D.T_hot_out_design_C = NaN;
D.T_cold_in_design_C = NaN;
D.T_cold_out_design_C = NaN;
D.T_cold_out_requested_C = NaN;
D.target_limited_by_approach = false;
D.mdot_hot_design_kg_s = NaN;
D.mdot_cold_design_kg_s = NaN;
D.LMTD_design_K = NaN;
D.dT1_design_K = NaN;
D.dT2_design_K = NaN;
D.dT_min_actual_K = NaN;
D.N_parallel = NaN;
D.Nt = NaN;
D.Ltube_m = NaN;
D.Dshell_m = NaN;
D.dp_hot_Pa = NaN;
D.dp_cold_Pa = NaN;
D.dp_hot_design_Pa = NaN;
D.dp_cold_design_Pa = NaN;
D.dp_hot_max_Pa = NaN;
D.dp_cold_max_Pa = NaN;
D.hot_velocity_design_m_s = NaN;
D.cold_velocity_design_m_s = NaN;
D.pump_power_hot_design_W = NaN;
D.pump_power_cold_design_W = NaN;
D.candidate_score = NaN;
D.candidate_score_basis = '';
D.selected_reason = '';
D.search = struct();
D.method = '';
end

function U = localOverallU(hShell,hTube)
U = 1/(1/max(hShell,eps) + 1/max(hTube,eps));
end

function L = localLmtd(DT1,DT2)
if DT1 <= 0 || DT2 <= 0
    error('preheater_sthe_design_v1:InvalidApproach','Terminal approaches must be positive.');
end
if abs(DT1 - DT2) < 1e-9
    L = 0.5*(DT1 + DT2);
else
    L = (DT1 - DT2)/log(DT1/DT2);
end
end

function value = localGet(S,fieldName,defaultValue)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end

function tf = localIsWater(fluid)
clean = lower(regexprep(char(string(fluid)),'[^a-zA-Z0-9]',''));
tf = any(strcmp(clean,{'water','h2o'}));
end

function S = localSetDefault(S,fieldName,defaultValue)
if ~isfield(S,fieldName) || isempty(S.(fieldName))
    S.(fieldName) = defaultValue;
end
end
