function Results = repair_RO_truth_local_branches(final_mat_file, audit_file)
% repair_RO_truth_local_branches
% R2023b-compatible targeted repair for confirmed local-branch truth points.
% It DOES NOT overwrite the original truth dataset. For each suspicious DOE_ID,
% the code minimizes RO power on the full N=150 recovery-equality manifold by
% a global P1 scan followed by successive local grid refinement. P2 is solved
% from the target-recovery root at every P1. The corrected table is saved as
% RO_ANN_final_truth_dataset_corrected.mat/.csv for ANN retraining.

%% INPUT FILES
if nargin < 1 || strlength(string(final_mat_file)) == 0
    final_mat_file = 'RO_ANN_final_truth_dataset.mat';
end
if nargin < 2 || strlength(string(audit_file)) == 0
    audit_file = 'RO_ANN_truth_branch_audit_summary.csv';
end
if ~isfile(final_mat_file)
    error('Final truth MAT bulunamadi: %s', final_mat_file);
end
if ~isfile(audit_file)
    error('Branch audit summary bulunamadi: %s', audit_file);
end

%% LOAD DATA
S = load(final_mat_file, 'Dataset', 'DOE', 'cfg');
if ~isfield(S, 'Dataset') || ~isfield(S, 'DOE')
    error('MAT dosyasinda Dataset ve DOE tablolarinin ikisi de bulunmalidir.');
end
Dataset = S.Dataset;
DOE = S.DOE;
cfg = ro_ann_config(); % Current validated physics/FASTPX configuration.
Audit = readtable(audit_file, 'TextType', 'string');

if ~ismember('SuspiciousLocalBranch', Audit.Properties.VariableNames)
    error('Audit dosyasinda SuspiciousLocalBranch kolonu bulunamadi.');
end
ids = Audit.DOE_ID(logical(Audit.SuspiciousLocalBranch));
ids = unique(ids(:), 'stable');
if isempty(ids)
    error('Audit summary icinde repair gerektiren suspicious DOE_ID bulunamadi.');
end

%% REPAIR SEARCH SETTINGS
n_coarse = 61;          % Full P1-domain grid.
n_refine = 21;          % Points per local refinement level.
n_levels = 4;           % Each level reduces P1 spacing approximately 10x.
min_improvement_kW = 0.05; % Do not replace a row for numerical-noise improvements.

%% PARALLEL POOL
try
    p = gcp('nocreate');
    if isempty(p)
        p = parpool('Processes'); %#ok<NASGU>
    end
catch
    % parfor will execute according to the available MATLAB configuration.
end

fprintf('\n============================================================\n');
fprintf('RO TRUTH LOCAL-BRANCH TARGETED REPAIR\n');
fprintf('============================================================\n');
fprintf('Suspicious DOE points : %d\n', numel(ids));
fprintf('Global coarse grid     : %d P1 points\n', n_coarse);
fprintf('Local refinement       : %d points x %d levels\n', n_refine, n_levels);
fprintf('Truth discretization   : N=%d\n', cfg.hybrid.final_N_segments);
fprintf('Original dataset is NOT overwritten.\n\n');

RepairRows = cell(numel(ids),1);
AllScans = table();

for ii = 1:numel(ids)
    tpoint = tic;
    id = ids(ii);
    idx = find(Dataset.DOE_ID == id, 1, 'first');
    if isempty(idx)
        warning('DOE_ID %d Dataset icinde bulunamadi; atlaniyor.', id);
        continue;
    end

    Qf = Dataset.Qf_train_m3h(idx);
    Tin = Dataset.T_RO_in_C(idx);
    Cf = Dataset.Cf_kg_m3(idx);
    Rt = Dataset.R_target(idx);
    oldW = Dataset.W_RO_train_kW(idx);
    oldP1 = Dataset.P1_opt_gauge_MPa(idx);
    oldP2 = Dataset.P2_opt_gauge_MPa(idx);
    oldCp = Dataset.Cp_mg_L(idx);

    mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years);
    pi_feed_MPa = ro_osmotic_pressure_du2014(Tin, Cf, mem);
    P1_lb = max(cfg.hybrid.P1_lb_MPa, pi_feed_MPa + cfg.hybrid.P1_osmotic_margin_MPa);
    P1_lb = min(P1_lb, cfg.hybrid.P1_ub_MPa);
    P1_ub = cfg.hybrid.P1_ub_MPa;

    fprintf('DOE_ID %d | Qf=%.5f | T=%.4f | Cf=%.5f | R=%.6f\n', id, Qf, Tin, Cf, Rt);
    fprintf('Original : P1=%.6f | P2=%.6f | W=%.6f kW | Cp=%.3f mg/L\n', oldP1, oldP2, oldW, oldCp);

    % Global grid. Include the original P1 explicitly.
    P1_grid = unique([linspace(P1_lb, P1_ub, n_coarse), oldP1]);
    Scan = scan_p1_grid(P1_grid, id, "coarse", Qf, Tin, Cf, Rt, cfg);
    feasible = Scan.TargetMet & Scan.PhysicalFeasible & isfinite(Scan.W_kW);
    if ~any(feasible)
        warning('DOE_ID %d icin global gridde feasible recovery-manifold noktasi bulunamadi.', id);
        RepairRows{ii} = make_summary(id,Qf,Tin,Cf,Rt,oldP1,oldP2,oldW,oldCp,NaN,NaN,NaN,NaN,0,NaN,toc(tpoint),false);
        AllScans = [AllScans; Scan]; %#ok<AGROW>
        continue;
    end

    [bestP1, bestP2, bestW, bestCp] = best_from_scan(Scan);
    coarse_step = (P1_ub - P1_lb) / (n_coarse - 1);
    half_width = coarse_step;

    % Successive local refinement. A 21-point grid over +/-half_width gives
    % ~10x smaller spacing at each level while retaining boundary robustness.
    for lev = 1:n_levels
        lo = max(P1_lb, bestP1 - half_width);
        hi = min(P1_ub, bestP1 + half_width);
        P1_local = unique([linspace(lo, hi, n_refine), bestP1]);
        Slev = scan_p1_grid(P1_local, id, "refine" + string(lev), Qf, Tin, Cf, Rt, cfg);
        Scan = [Scan; Slev]; %#ok<AGROW>
        [bestP1, bestP2, bestW, bestCp] = best_from_scan(Scan);
        half_width = half_width / 10.0;
    end

    % Re-evaluate the selected optimum once more to capture every physical field.
    rr = ro_find_P2_for_recovery(Qf, Tin, Cf, Rt, bestP1, cfg, cfg.hybrid.final_N_segments, bestP2);
    if ~(rr.target_met && ~isempty(rr.ev) && rr.ev.success && rr.ev.physical_feasible)
        error('DOE_ID %d final repair optimum yeniden degerlendirmede valid olmadi.', id);
    end
    ev = rr.ev;
    bestP2 = rr.P2_gauge_MPa;
    bestW = ev.W_RO_kW;
    bestCp = ev.Cp_mg_L;
    improve = oldW - bestW;
    improvePct = 100.0 * improve / oldW;
    replace = improve > min_improvement_kW;

    if replace
        Dataset = apply_repaired_ev(Dataset, idx, ev, bestP1, bestP2, Rt, cfg, height(Scan), rr.n_evaluations, toc(tpoint));
    end

    fprintf('Repaired : P1=%.6f | P2=%.6f | W=%.6f kW | Cp=%.3f mg/L\n', bestP1, bestP2, bestW, bestCp);
    fprintf('Gain     : %.6f kW (%.3f %%) | row replaced=%d\n\n', improve, improvePct, replace);

    Scan.SelectedBest = abs(Scan.P1_MPa-bestP1) < 1e-10 & abs(Scan.W_kW-bestW) < 1e-7;
    AllScans = [AllScans; Scan]; %#ok<AGROW>
    RepairRows{ii} = make_summary(id,Qf,Tin,Cf,Rt,oldP1,oldP2,oldW,oldCp,bestP1,bestP2,bestW,bestCp,improve,improvePct,toc(tpoint),replace);
end

%% SAVE CORRECTED DATASET WITHOUT OVERWRITING ORIGINAL
RepairRows = RepairRows(~cellfun(@isempty, RepairRows));
Results = vertcat(RepairRows{:});

corrected_csv = 'RO_ANN_final_truth_dataset_corrected.csv';
corrected_mat = 'RO_ANN_final_truth_dataset_corrected.mat';
summary_csv = 'RO_ANN_truth_branch_repair_summary.csv';
scan_csv = 'RO_ANN_truth_branch_repair_scan.csv';

writetable(Dataset, corrected_csv);
writetable(Results, summary_csv);
writetable(AllScans, scan_csv);
save(corrected_mat, 'Dataset', 'DOE', 'cfg', '-v7.3');

fprintf('============================================================\n');
fprintf('REPAIR SUMMARY\n');
fprintf('============================================================\n');
disp(Results);
fprintf('Rows replaced : %d / %d\n', sum(Results.Replaced), height(Results));
fprintf('Corrected MAT : %s\n', corrected_mat);
fprintf('Corrected CSV : %s\n', corrected_csv);
fprintf('Repair summary: %s\n', summary_csv);
fprintf('Repair scan   : %s\n', scan_csv);
fprintf('Original truth files remain unchanged.\n');
fprintf('============================================================\n');
end

function S = scan_p1_grid(P1_grid, DOE_ID, level, Qf, Tin, Cf, Rt, cfg)
n = numel(P1_grid);
P2 = NaN(n,1); W = NaN(n,1); Cp = NaN(n,1); Rec = NaN(n,1); Rerr = NaN(n,1);
Physical = false(n,1); TargetMet = false(n,1); Success = false(n,1);
EvalCount = zeros(n,1); Runtime = NaN(n,1); Failure = strings(n,1);
parfor k = 1:n
    tk = tic;
    rr = ro_find_P2_for_recovery(Qf, Tin, Cf, Rt, P1_grid(k), cfg, cfg.hybrid.final_N_segments, NaN);
    Runtime(k) = toc(tk);
    EvalCount(k) = rr.n_evaluations;
    Failure(k) = string(rr.failure_reason);
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success
        ev = rr.ev;
        P2(k) = rr.P2_gauge_MPa;
        W(k) = ev.W_RO_kW;
        Cp(k) = ev.Cp_mg_L;
        Rec(k) = ev.Recovery;
        Rerr(k) = ev.Recovery - Rt;
        Physical(k) = ev.physical_feasible;
        TargetMet(k) = abs(Rerr(k)) <= cfg.optim.recovery_accept_tolerance;
        Success(k) = true;
    end
end
S = table(repmat(DOE_ID,n,1), repmat(string(level),n,1), P1_grid(:), P2, W, Cp, Rec, Rerr, ...
    TargetMet, Physical, Success, EvalCount, Runtime, Failure, ...
    'VariableNames', {'DOE_ID','ScanLevel','P1_MPa','P2_MPa','W_kW','Cp_mg_L','Recovery','RecoveryError', ...
    'TargetMet','PhysicalFeasible','Success','RootEvalCount','Runtime_s','FailureReason'});
end

function [P1,P2,W,Cp] = best_from_scan(S)
mask = S.TargetMet & S.PhysicalFeasible & isfinite(S.W_kW);
if ~any(mask)
    P1=NaN; P2=NaN; W=NaN; Cp=NaN; return;
end
idx = find(mask);
[W,jj] = min(S.W_kW(idx));
j = idx(jj);
P1 = S.P1_MPa(j); P2 = S.P2_MPa(j); Cp = S.Cp_mg_L(j);
end

function D = apply_repaired_ev(D, i, ev, P1, P2, Rt, cfg, nScanRows, nFinalRootEval, runtime_s)
D.Qp_train_m3h(i) = ev.Qp_train_m3h;
D.Recovery_actual(i) = ev.Recovery;
D.Recovery_error(i) = ev.Recovery - Rt;
D.Cp_mg_L(i) = ev.Cp_mg_L;
D.W_RO_train_kW(i) = ev.W_RO_kW;
D.SEC_kWh_m3(i) = ev.SEC_kWh_m3;
D.P1_opt_gauge_MPa(i) = P1;
D.P2_opt_gauge_MPa(i) = P2;
D.Javg_LMH(i) = ev.Javg_LMH;
D.Jfirst_stage1_LMH(i) = ev.Jfirst_stage1_LMH;
D.Jfirst_stage2_LMH(i) = ev.Jfirst_stage2_LMH;
D.Jmax_local_stage1_LMH(i) = ev.Jmax_local_stage1_LMH;
D.Jmax_local_stage2_LMH(i) = ev.Jmax_local_stage2_LMH;
D.CPFmax_stage1(i) = ev.CPFmax_stage1;
D.CPFmax_stage2(i) = ev.CPFmax_stage2;
D.dP_stage1_MPa(i) = ev.dP_stage1_MPa;
D.dP_stage2_MPa(i) = ev.dP_stage2_MPa;
D.Cb_max_kg_m3(i) = ev.Cb_max_kg_m3;
D.Qf_PV_stage1_m3h(i) = ev.Qf_PV_stage1_m3h;
D.Qf_PV_stage2_m3h(i) = ev.Qf_PV_stage2_m3h;
D.Qb_PV_stage1_m3h(i) = ev.Qb_PV_stage1_m3h;
D.Qb_PV_stage2_m3h(i) = ev.Qb_PV_stage2_m3h;
D.Qhpp_m3h(i) = ev.Qhpp_m3h;
D.PXout_gauge_MPa(i) = ev.PXout_gauge_MPa;
D.PX_excess_pressure_MPa(i) = ev.PX_excess_pressure_MPa;
D.PX_booster_deltaP_MPa(i) = ev.PX_booster_deltaP_MPa;
D.PX_leakage_pct(i) = ev.PX_leakage_pct;
D.PX_mix_pct(i) = ev.PX_mix_pct;
D.PX_iterations(i) = ev.PX_iterations;
D.PhysicalFeasible(i) = ev.physical_feasible;
D.RecoveryTargetMet(i) = abs(D.Recovery_error(i)) <= cfg.optim.recovery_accept_tolerance;
D.DatasetValid(i) = D.PhysicalFeasible(i) && D.RecoveryTargetMet(i);
D.FeasibilityMarginScaled(i) = ev.feasibility_margin_scaled;
D.MaxConstraintViolationScaled(i) = ev.max_constraint_violation_scaled;
D.ExitFlag(i) = 1;
D.FminconIterations(i) = NaN;
D.FminconFunctionCount(i) = NaN;
D.LocalStartsAttempted(i) = 0;
D.OptimizerMethod(i) = "global_recovery_manifold_repair";
D.RootEvalCountCoarse(i) = nScanRows;
D.RootEvalCountFinal(i) = nFinalRootEval;
D.HybridSeedRankUsed(i) = NaN;
D.HybridSeedP1_N30_MPa(i) = NaN;
D.HybridSeedP2_N30_MPa(i) = NaN;
D.HybridN150SeedTrials(i) = NaN;
D.Runtime_s(i) = runtime_s;
D.FailureReason(i) = "";
D.ErrorMessage(i) = "";
end

function T = make_summary(id,Qf,Tin,Cf,Rt,oldP1,oldP2,oldW,oldCp,newP1,newP2,newW,newCp,dW,dWpct,runtime_s,replaced)
T = table(id,Qf,Tin,Cf,Rt,oldP1,oldP2,oldW,oldCp,newP1,newP2,newW,newCp,dW,dWpct,runtime_s,logical(replaced), ...
    'VariableNames', {'DOE_ID','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'Old_P1_MPa','Old_P2_MPa','Old_W_kW','Old_Cp_mg_L','New_P1_MPa','New_P2_MPa','New_W_kW','New_Cp_mg_L', ...
    'PowerReduction_kW','PowerReduction_pct','RepairRuntime_s','Replaced'});
end
