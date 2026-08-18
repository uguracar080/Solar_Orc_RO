function Results = run_RO_ANN_external_verification_v1_9_1(n_external, model_file, reference_file)
%RUN_RO_ANN_EXTERNAL_VERIFICATION_V1_9_1
% Independent post-training external verification of the frozen RO ANN v1.9.1.
%
% This function MUST be run only after ANN architecture, weights and classifier
% threshold have been frozen. The external DOE is generated without using ANN
% predictions, feasibility probabilities, kNN scores, training labels or test
% residuals. New operating points are selected from an independently scrambled
% Sobol sequence, restricted only by the deployment domain and analytic necessary
% conditions of the physics-based RO model. Near-duplicates of the original
% 2400-point dataset are explicitly excluded.
%
% The workflow is:
%   1) Generate an independent external DOE (default 300 points).
%   2) Evaluate every point with the validated N=150 high-fidelity RO model.
%   3) Recheck initially invalid points with the independent recovery-manifold
%      root optimizer to reduce false invalid labels caused by optimizer failure.
%   4) Screen every valid point for local pressure-branch errors using an N=30
%      recovery-manifold scan. Suspicious points are repaired with a global N=150
%      P1 scan plus successive local refinements.
%   5) Only after truth labels are frozen, load the final ANN v1.9.1 and predict
%      feasibility, W_RO, P1*, P2* and Cp. Qp and SEC are calculated physically.
%   6) Save external verification metrics, predictions and a publication-ready
%      six-panel figure (four parity plots, ROC curve and confusion matrix).
%
% Required files/functions in the MATLAB path/current folder:
%   RO_ANN_models_v1_9_1.mat
%   RO_ANN_final_truth_dataset_corrected.csv (or MAT; used only for distance check)
%   ro_ann_config.m and all validated RO physics/optimizer functions
%   ro_generate_training_dataset.m
%   ro_optimize_train_point_root.m
%   ro_find_P2_for_recovery.m
%
% Default usage:
%   Results = run_RO_ANN_external_verification_v1_9_1;
%
% Optional usage:
%   Results = run_RO_ANN_external_verification_v1_9_1(300, ...
%       'RO_ANN_models_v1_9_1.mat', ...
%       'RO_ANN_final_truth_dataset_corrected.csv');
%
% IMPORTANT: If a completed external verification exists, the audited MAT file
% is reused so that rerunning the function only regenerates predictions/figures.
% Delete the external-verification output files intentionally if a new DOE is
% desired. Do not use external verification results to retrain or retune v1.9.1.

%% USER-LEVEL INPUTS
if nargin < 1 || isempty(n_external)
    n_external = 300; % Publication-scale independent external verification size.
end
if nargin < 2 || strlength(string(model_file)) == 0
    model_file = 'RO_ANN_models_v1_9_1.mat'; % Frozen final ANN model file.
end
if nargin < 3 || strlength(string(reference_file)) == 0
    reference_file = 'RO_ANN_final_truth_dataset_corrected.csv'; % Original 2400-point dataset for anti-duplicate screening only.
end
n_external = round(double(n_external));
if n_external < 50
    error('External verification icin en az 50 nokta onerilir. Girilen n_external=%d.', n_external);
end
if ~isfile(model_file)
    error('Frozen ANN model dosyasi bulunamadi: %s', model_file);
end
if ~isfile(reference_file)
    error('Reference truth dataset bulunamadi: %s', reference_file);
end

%% FIXED EXTERNAL-VERIFICATION SETTINGS
rng_seed = 20260813;              % Independent reproducible randomization seed.
candidate_pool_size = max(20000, 60*n_external); % Large pool for independent space filling.
min_ref_distance = 0.035;         % Minimum normalized Euclidean distance from all original DOE rows.
min_external_distance = 0.030;    % Minimum normalized distance among new external points.
R_floor = 0.400;                  % Slightly inside the deployed ANN lower recovery bound.
R_ceiling = 0.570;                % Slightly inside the deployed ANN upper recovery bound.
R_analytic_guard = 0.001;         % Keeps candidates just inside analytic necessary upper limits.
branch_scan_nP1 = 9;              % Cheap N=30 local-branch screening resolution.
branch_trigger_abs_kW = 1.0;      % Minimum absolute power gap that triggers expensive N=150 repair.
branch_trigger_rel = 0.010;        % Minimum relative power gap that triggers N=150 repair.
repair_coarse_nP1 = 41;           % Global N=150 repair grid if a branch anomaly is detected.
repair_local_nP1 = 21;            % Points per local N=150 refinement level.
repair_levels = 3;                % Successive local refinement levels.

%% FILENAMES
stem_doe = 'RO_ANN_external_verification_DOE_v1_9_1';
stem_truth = 'RO_ANN_external_verification_truth_v1_9_1';
audited_mat = 'RO_ANN_external_verification_audited_v1_9_1.mat';
audited_csv = 'RO_ANN_external_verification_audited_v1_9_1.csv';
audit_csv = 'RO_ANN_external_verification_truth_audit_v1_9_1.csv';
pred_csv = 'RO_ANN_external_verification_predictions_v1_9_1.csv';
reg_csv = 'RO_ANN_external_verification_regression_metrics_v1_9_1.csv';
cls_csv = 'RO_ANN_external_verification_classifier_metrics_v1_9_1.csv';
summary_txt = 'RO_ANN_external_verification_summary_v1_9_1.txt';
fig_png = 'Fig_RO_ANN_external_verification_v1_9_1.png';
fig_pdf = 'Fig_RO_ANN_external_verification_v1_9_1.pdf';

%% VALIDATED PHYSICS CONFIGURATION
cfg = ro_ann_config();
cfg.compute.use_parallel = true;
cfg.compute.batch_size = 24;

%% DEPLOYMENT DOMAIN (identical to the final v1.9.1 wrapper)
Domain.Qf_min = 47.5;
Domain.Qf_max = 63.0;
Domain.T_min = 20.0;
Domain.T_max = 45.0;
Domain.Cf_min = 38.5;
Domain.Cf_max = 41.5;
Domain.R_min = 0.399;
Domain.R_max = 0.571;
NormLB = [Domain.Qf_min, Domain.T_min, Domain.Cf_min, Domain.R_min];
NormUB = [Domain.Qf_max, Domain.T_max, Domain.Cf_max, Domain.R_max];

fprintf('\n============================================================\n');
fprintf('RO ANN v1.9.1 - INDEPENDENT EXTERNAL VERIFICATION\n');
fprintf('============================================================\n');
fprintf('Frozen model             : %s\n', model_file);
fprintf('Requested external points: %d\n', n_external);
fprintf('Sampling uses ANN scores : NO\n');
fprintf('Truth discretization     : N=%d\n', cfg.hybrid.final_N_segments);
fprintf('Original dataset retrain : NO\n');
fprintf('============================================================\n\n');

%% STEP 1 - GENERATE OR LOAD THE INDEPENDENT EXTERNAL DOE
if isfile([stem_doe '.csv'])
    DOE = readtable([stem_doe '.csv'], 'TextType', 'string');
    if height(DOE) ~= n_external
        error(['Mevcut external DOE %d satir ancak n_external=%d istendi. ' ...
            'Yeni DOE icin eski external verification dosyalarini farkli klasore alin/silin.'], height(DOE), n_external);
    end
    fprintf('Existing external DOE loaded: %s.csv\n', stem_doe);
else
    RefX = load_reference_inputs(reference_file);
    DOE = generate_external_doe(n_external, candidate_pool_size, rng_seed, RefX, ...
        min_ref_distance, min_external_distance, R_floor, R_ceiling, R_analytic_guard, ...
        Domain, NormLB, NormUB, cfg);
    writetable(DOE, [stem_doe '.csv']);
    save([stem_doe '.mat'], 'DOE', 'Domain', 'NormLB', 'NormUB', 'rng_seed', '-v7.3');
    fprintf('Independent external DOE generated: %s.csv\n', stem_doe);
end

%% STEP 2-4 - HIGH-FIDELITY TRUTH EVALUATION, INVALID RESCUE AND BRANCH AUDIT
if isfile(audited_mat)
    S_aud = load(audited_mat, 'Dataset', 'DOE', 'AuditSummary');
    Dataset = S_aud.Dataset;
    DOE = S_aud.DOE;
    if isfield(S_aud, 'AuditSummary')
        AuditSummary = S_aud.AuditSummary;
    else
        AuditSummary = table();
    end
    if height(Dataset) ~= n_external
        error('Existing audited external dataset boyutu n_external ile uyumlu degil.');
    end
    fprintf('Audited external truth dataset reused: %s\n', audited_mat);
else
    Dataset = ro_generate_training_dataset(DOE, cfg, stem_truth);

    % Recheck every initially invalid, analytically admissible row with the independent
    % recovery-manifold root optimizer. This step does not use ANN information.
    invalid_idx = find(~Dataset.DatasetValid & Dataset.AnalyticScreenPassed);
    root_rescued = false(height(Dataset),1);
    if ~isempty(invalid_idx)
        fprintf('\nIndependent root-rescue check for %d initially invalid points...\n', numel(invalid_idx));
        root_rows = cell(numel(invalid_idx),1);
        parfor kk = 1:numel(invalid_idx)
            i = invalid_idx(kk);
            rr = ro_optimize_train_point_root(Dataset.DOE_ID(i), "ExternalVerificationRootRescue", ...
                Dataset.Qf_train_m3h(i), Dataset.T_RO_in_C(i), Dataset.Cf_kg_m3(i), Dataset.R_target(i), cfg);
            root_rows{kk} = rr;
        end
        for kk = 1:numel(invalid_idx)
            i = invalid_idx(kk);
            rr = root_rows{kk};
            if rr.DatasetValid
                Dataset(i,:) = struct2table(rr, 'AsArray', true);
                Dataset.DOE_Type(i) = "ExternalVerification_RootRescued";
                root_rescued(i) = true;
            end
        end
    end

    % Independent cheap N=30 recovery-manifold scan on all valid rows. The ANN is
    % still not loaded. This detects pressure-branch anomalies similar to the three
    % points repaired in the original 2400-point dataset.
    valid_idx = find(Dataset.DatasetValid);
    fprintf('N=30 pressure-branch screening for %d valid external points...\n', numel(valid_idx));
    Screen = repmat(struct('BestW_N30',NaN,'BestP1_N30',NaN,'PotentialBranch',false), numel(valid_idx),1);
    parfor kk = 1:numel(valid_idx)
        i = valid_idx(kk);
        Screen(kk) = branch_screen_one(Dataset(i,:), cfg, branch_scan_nP1, branch_trigger_abs_kW, branch_trigger_rel);
    end

    branch_flag = false(height(Dataset),1);
    bestW_N30 = NaN(height(Dataset),1);
    bestP1_N30 = NaN(height(Dataset),1);
    for kk = 1:numel(valid_idx)
        i = valid_idx(kk);
        bestW_N30(i) = Screen(kk).BestW_N30;
        bestP1_N30(i) = Screen(kk).BestP1_N30;
        branch_flag(i) = Screen(kk).PotentialBranch;
    end

    % The previously observed seed-stagnation signature is an additional physics-
    % optimizer diagnostic; it is independent of ANN prediction residuals.
    seed_stagnation = Dataset.DatasetValid & ...
        isfinite(Dataset.FminconFunctionCount) & ...
        Dataset.FminconFunctionCount >= cfg.hybrid.max_function_evaluations & ...
        isfinite(Dataset.HybridSeedP1_N30_MPa) & ...
        abs(Dataset.P1_opt_gauge_MPa - Dataset.HybridSeedP1_N30_MPa) <= 1.0e-8;

    % Every root-rescued valid row is globally refined because the root optimizer is
    % used here for feasibility rescue rather than accepted as the final energy optimum.
    repair_flag = (branch_flag | seed_stagnation | root_rescued) & Dataset.DatasetValid;
    repair_idx = find(repair_flag);
    repaired = false(height(Dataset),1);
    repair_gain_kW = zeros(height(Dataset),1);

    if ~isempty(repair_idx)
        fprintf('Global N=150 recovery-manifold repair for %d external points...\n', numel(repair_idx));
        repaired_rows = cell(numel(repair_idx),1);
        repair_info = cell(numel(repair_idx),1);
        parfor kk = 1:numel(repair_idx)
            i = repair_idx(kk);
            [rrow, info] = global_repair_external_row(Dataset(i,:), cfg, repair_coarse_nP1, repair_local_nP1, repair_levels);
            repaired_rows{kk} = rrow;
            repair_info{kk} = info;
        end
        for kk = 1:numel(repair_idx)
            i = repair_idx(kk);
            info = repair_info{kk};
            if info.Replaced
                Dataset(i,:) = struct2table(repaired_rows{kk}, 'AsArray', true);
                Dataset.DOE_Type(i) = "ExternalVerification_GlobalRepair";
                repaired(i) = true;
                repair_gain_kW(i) = info.PowerReduction_kW;
            end
        end
    end

    AuditSummary = table(Dataset.DOE_ID, root_rescued, bestW_N30, bestP1_N30, branch_flag, ...
        seed_stagnation, repair_flag, repaired, repair_gain_kW, ...
        'VariableNames', {'DOE_ID','RootRescued','BestW_N30_kW','BestP1_N30_MPa','BranchScreenFlag', ...
        'SeedStagnationFlag','RepairRequested','Repaired','PowerReduction_kW'});

    writetable(Dataset, audited_csv);
    writetable(AuditSummary, audit_csv);
    save(audited_mat, 'Dataset', 'DOE', 'cfg', 'AuditSummary', '-v7.3');

    fprintf('\nTruth audit complete: valid=%d/%d | root rescued=%d | global repairs=%d\n', ...
        sum(Dataset.DatasetValid), height(Dataset), sum(root_rescued), sum(repaired));
end

%% STEP 5 - LOAD THE FROZEN ANN ONLY AFTER TRUTH LABELS ARE FINAL
S_model = load(model_file, 'Models');
if ~isfield(S_model, 'Models')
    error('Model MAT dosyasinda Models struct bulunamadi.');
end
Models = S_model.Models;
X = [Dataset.Qf_train_m3h, Dataset.T_RO_in_C, Dataset.Cf_kg_m3, Dataset.R_target];

pValid = classifier_probability_local(Models.Feasibility, X);
ValidPred = pValid >= Models.Feasibility.Threshold;

W_pred = regressor_predict_local(Models.Regressors.W_RO_train_kW, X);
P1_pred = regressor_predict_local(Models.Regressors.P1_opt_gauge_MPa, X);
P2_pred = regressor_predict_local(Models.Regressors.P2_opt_gauge_MPa, X);
pCpActive = classifier_probability_local(Models.Cp.ActiveClassifier, X);
CpMargin = max(0.0, regressor_predict_local(Models.Cp.MarginRegressor, X));
Cp_pred = Models.Cp.CpLimit_mgL - CpMargin;
Cp_pred(pCpActive >= Models.Cp.SwitchThreshold) = Models.Cp.CpLimit_mgL;
Cp_pred = min(Models.Cp.CpLimit_mgL, max(0.0, Cp_pred));
Qp_pred = Dataset.Qf_train_m3h .* Dataset.R_target;
SEC_pred = W_pred ./ Qp_pred;

%% EXTERNAL CLASSIFIER METRICS
TruthValid = logical(Dataset.DatasetValid);
ClsMetrics = classifier_metrics(TruthValid, ValidPred, pValid);
ClsMetrics.Threshold = Models.Feasibility.Threshold;
ClsMetrics.N = height(Dataset);
ClsMetricsTable = struct2table(rmfield(ClsMetrics, {'FPR_curve','TPR_curve'}), 'AsArray', true);
writetable(ClsMetricsTable, cls_csv);

%% EXTERNAL REGRESSION METRICS (ALL TRUTH-VALID POINTS, INDEPENDENT OF CLASSIFIER GATE)
Dv = TruthValid;
RegMetrics = [ ...
    regression_metric_row("W_RO_train_kW", Dataset.W_RO_train_kW(Dv), W_pred(Dv)); ...
    regression_metric_row("P1_opt_gauge_MPa", Dataset.P1_opt_gauge_MPa(Dv), P1_pred(Dv)); ...
    regression_metric_row("P2_opt_gauge_MPa", Dataset.P2_opt_gauge_MPa(Dv), P2_pred(Dv)); ...
    regression_metric_row("Cp_hybrid_mg_L", Dataset.Cp_mg_L(Dv), Cp_pred(Dv)); ...
    regression_metric_row("SEC_derived_kWh_m3", Dataset.SEC_kWh_m3(Dv), SEC_pred(Dv))];
writetable(RegMetrics, reg_csv);

%% SAVE POINT-BY-POINT EXTERNAL PREDICTIONS
Predictions = table(Dataset.DOE_ID, TruthValid, pValid, ValidPred, ...
    Dataset.Qf_train_m3h, Dataset.T_RO_in_C, Dataset.Cf_kg_m3, Dataset.R_target, ...
    Dataset.W_RO_train_kW, W_pred, Dataset.P1_opt_gauge_MPa, P1_pred, ...
    Dataset.P2_opt_gauge_MPa, P2_pred, Dataset.Cp_mg_L, Cp_pred, ...
    Dataset.SEC_kWh_m3, SEC_pred, pCpActive, ...
    'VariableNames', {'External_ID','TruthValid','P_feasible','ANN_ValidPred', ...
    'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'W_true_kW','W_pred_kW','P1_true_MPa','P1_pred_MPa','P2_true_MPa','P2_pred_MPa', ...
    'Cp_true_mgL','Cp_pred_mgL','SEC_true_kWh_m3','SEC_pred_kWh_m3','P_CpBoundary'});

% Performance truth values of invalid points are not meaningful for surrogate-error
% reporting; keep inputs/classifier outputs but blank the physical regression columns.
invalid = ~TruthValid;
truth_pred_cols = {'W_true_kW','W_pred_kW','P1_true_MPa','P1_pred_MPa','P2_true_MPa','P2_pred_MPa', ...
    'Cp_true_mgL','Cp_pred_mgL','SEC_true_kWh_m3','SEC_pred_kWh_m3'};
for jj = 1:numel(truth_pred_cols)
    Predictions.(truth_pred_cols{jj})(invalid) = NaN;
end
writetable(Predictions, pred_csv);

%% STEP 6 - PUBLICATION-READY EXTERNAL VERIFICATION FIGURE
make_external_verification_figure(Dataset, W_pred, P1_pred, P2_pred, Cp_pred, ...
    TruthValid, ValidPred, pValid, ClsMetrics, RegMetrics, fig_png, fig_pdf);

%% TEXT SUMMARY
fid = fopen(summary_txt, 'w');
if fid ~= -1
    fprintf(fid, 'RO ANN v1.9.1 - INDEPENDENT EXTERNAL VERIFICATION\n');
    fprintf(fid, 'External points: %d\n', height(Dataset));
    fprintf(fid, 'Truth-valid points: %d (%.2f%%)\n', sum(TruthValid), 100*mean(TruthValid));
    fprintf(fid, 'Classifier threshold: %.3f\n', Models.Feasibility.Threshold);
    fprintf(fid, 'Sensitivity: %.6f\n', ClsMetrics.Sensitivity);
    fprintf(fid, 'Specificity: %.6f\n', ClsMetrics.Specificity);
    fprintf(fid, 'Balanced accuracy: %.6f\n', ClsMetrics.BalancedAccuracy);
    fprintf(fid, 'Precision: %.6f\n', ClsMetrics.Precision);
    fprintf(fid, 'F1: %.6f\n', ClsMetrics.F1);
    fprintf(fid, 'AUROC: %.6f\n', ClsMetrics.AUROC);
    for i = 1:height(RegMetrics)
        fprintf(fid, '%s: N=%d RMSE=%.8g MAE=%.8g R2=%.8f MaxAE=%.8g P95AE=%.8g\n', ...
            char(RegMetrics.Target(i)), RegMetrics.N(i), RegMetrics.RMSE(i), RegMetrics.MAE(i), ...
            RegMetrics.R2(i), RegMetrics.MaxAE(i), RegMetrics.P95AE(i));
    end
    fclose(fid);
end

%% COMMAND-WINDOW SUMMARY
fprintf('\n============================================================\n');
fprintf('EXTERNAL VERIFICATION COMPLETE - FROZEN v1.9.1\n');
fprintf('============================================================\n');
fprintf('External truth points : %d\n', height(Dataset));
fprintf('Truth-valid points    : %d (%.1f%%)\n', sum(TruthValid), 100*mean(TruthValid));
fprintf('Classifier            : Sens=%.3f | Spec=%.3f | BalAcc=%.3f | Precision=%.3f | F1=%.3f | AUC=%.3f | FP=%d | FN=%d\n', ...
    ClsMetrics.Sensitivity, ClsMetrics.Specificity, ClsMetrics.BalancedAccuracy, ...
    ClsMetrics.Precision, ClsMetrics.F1, ClsMetrics.AUROC, ClsMetrics.FP, ClsMetrics.FN);
for i = 1:height(RegMetrics)
    fprintf('%-20s N=%3d | RMSE=%-10.5g | MAE=%-10.5g | R2=%.6f | P95AE=%-.5g\n', ...
        RegMetrics.Target(i), RegMetrics.N(i), RegMetrics.RMSE(i), RegMetrics.MAE(i), RegMetrics.R2(i), RegMetrics.P95AE(i));
end
fprintf('Predictions CSV       : %s\n', pred_csv);
fprintf('Regression metrics    : %s\n', reg_csv);
fprintf('Classifier metrics    : %s\n', cls_csv);
fprintf('Truth audit           : %s\n', audit_csv);
fprintf('Figure PNG            : %s\n', fig_png);
fprintf('Figure PDF            : %s\n', fig_pdf);
fprintf('IMPORTANT: Do not retrain/retune the ANN using this external set.\n');
fprintf('============================================================\n');

%% RETURN STRUCT
Results = struct();
Results.DOE = DOE;
Results.Dataset = Dataset;
Results.Predictions = Predictions;
Results.RegressionMetrics = RegMetrics;
Results.ClassifierMetrics = ClsMetrics;
Results.AuditSummary = AuditSummary;
Results.FigurePNG = fig_png;
Results.FigurePDF = fig_pdf;
end

%% ========================================================================
function RefX = load_reference_inputs(reference_file)
% Load only original DOE inputs. These are used exclusively to prevent external
% verification points from being near-duplicates of the 2400 development rows.
[~,~,ext] = fileparts(reference_file);
if strcmpi(ext,'.mat')
    S = load(reference_file, 'Dataset');
    if ~isfield(S,'Dataset')
        error('Reference MAT dosyasinda Dataset bulunamadi.');
    end
    T = S.Dataset;
else
    T = readtable(reference_file, 'TextType', 'string');
end
needed = {'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target'};
if ~all(ismember(needed, T.Properties.VariableNames))
    error('Reference dataset gerekli 4 input kolonunu icermiyor.');
end
RefX = double(T{:,needed});
end

%% ========================================================================
function DOE = generate_external_doe(n, pool_n, seed, RefX, min_ref_dist, min_ext_dist, ...
    R_floor, R_ceiling, R_guard, Domain, NormLB, NormUB, cfg)
% Generate independent Sobol points. ANN/model files are intentionally not read.
rng(seed, 'twister');
p = sobolset(4, 'Skip', 8192, 'Leap', 37);
p = scramble(p, 'MatousekAffineOwen');
U = net(p, pool_n);

Qf = Domain.Qf_min + U(:,1) * (Domain.Qf_max - Domain.Qf_min);
T = Domain.T_min + U(:,2) * (Domain.T_max - Domain.T_min);
Cf = Domain.Cf_min + U(:,3) * (Domain.Cf_max - Domain.Cf_min);

% Vectorized analytic necessary upper recovery envelope from the same membrane,
% geometry and constraints used by ro_analytic_screen_train_point.
mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years);
A_total = (cfg.geometry.N_PV_stage1*cfg.geometry.n_elements_stage1 + ...
    cfg.geometry.N_PV_stage2*cfg.geometry.n_elements_stage2) * mem.active_area_m2;
Qp_flux_max = mem.max_system_average_flux_LMH * A_total / 1000.0;
Rmax_flux = Qp_flux_max ./ Qf;
Rmax_brine = 1.0 - cfg.geometry.N_PV_stage2 * mem.min_brine_flow_m3h ./ Qf;
Rmax_Cb = (cfg.constraints.Cb_max_kg_m3 - Cf) ./ ...
    (cfg.constraints.Cb_max_kg_m3 - cfg.constraints.Cp_max_kg_m3);
Rmax = min([repmat(cfg.domain.R_max,pool_n,1), Rmax_flux, Rmax_brine, Rmax_Cb], [], 2);
Rhi = min(R_ceiling, Rmax - R_guard);
keep = Rhi > R_floor;
Qf = Qf(keep); T = T(keep); Cf = Cf(keep); Rhi = Rhi(keep); U4 = U(keep,4);
R = R_floor + U4 .* (Rhi - R_floor);
X = [Qf,T,Cf,R];

% Confirm analytic admissibility using the canonical screening function.
analytic_pass = false(size(Qf));
for i = 1:numel(Qf)
    s = ro_analytic_screen_train_point(Qf(i),T(i),Cf(i),R(i),cfg);
    analytic_pass(i) = s.pass;
end
X = X(analytic_pass,:);

% Normalize in the final deployment domain.
Xn = (X - NormLB) ./ (NormUB - NormLB);
RefN = (RefX - NormLB) ./ (NormUB - NormLB);

% Exclude candidates too close to any original development point.
keep_ref = min_distance_mask(Xn, RefN, min_ref_dist);
X = X(keep_ref,:);
Xn = Xn(keep_ref,:);

% Deterministic greedy space filling among the new external points.
selected = false(size(X,1),1);
sel_idx = zeros(n,1);
count = 0;
for i = 1:size(X,1)
    if count == 0
        count = 1;
        selected(i) = true;
        sel_idx(count) = i;
    else
        d2 = sum((Xn(sel_idx(1:count),:) - Xn(i,:)).^2,2);
        if all(d2 >= min_ext_dist^2)
            count = count + 1;
            selected(i) = true;
            sel_idx(count) = i;
            if count == n
                break;
            end
        end
    end
end
if count < n
    error(['Independent candidate pool yalnizca %d/%d nokta secti. ' ...
        'candidate_pool_size veya distance ayarlarini artirin/gevsetin.'], count, n);
end
X = X(sel_idx(1:n),:);

DOE_ID = (1:n).';
DOE_Type = repmat("ExternalVerification", n, 1);
DOE = table(DOE_ID, DOE_Type, X(:,1), X(:,2), X(:,3), X(:,4), ...
    'VariableNames', {'DOE_ID','DOE_Type','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target'});
end

%% ========================================================================
function keep = min_distance_mask(X, Ref, min_dist)
% Memory-safe minimum Euclidean distance check without Statistics Toolbox.
keep = true(size(X,1),1);
chunk = 250;
limit2 = min_dist^2;
for a = 1:chunk:size(X,1)
    b = min(a+chunk-1,size(X,1));
    Q = X(a:b,:);
    minD2 = inf(size(Q,1),1);
    for j = 1:size(Ref,1)
        d2 = sum((Q - Ref(j,:)).^2,2);
        minD2 = min(minD2,d2);
    end
    keep(a:b) = minD2 >= limit2;
end
end

%% ========================================================================
function S = branch_screen_one(rowTable, cfg, nP1, abs_trigger, rel_trigger)
% Cheap, ANN-independent N=30 recovery-manifold screen for a lower-power branch.
Qf = rowTable.Qf_train_m3h(1);
Tin = rowTable.T_RO_in_C(1);
Cf = rowTable.Cf_kg_m3(1);
Rt = rowTable.R_target(1);
oldW = rowTable.W_RO_train_kW(1);

mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years);
pi_feed = ro_osmotic_pressure_du2014(Tin, Cf, mem);
P1lb = max(cfg.hybrid.P1_lb_MPa, pi_feed + cfg.hybrid.P1_osmotic_margin_MPa);
P1ub = cfg.hybrid.P1_ub_MPa;
P1grid = linspace(P1lb, P1ub, nP1);

bestW = inf;
bestP1 = NaN;
for k = 1:numel(P1grid)
    rr = ro_find_P2_for_recovery(Qf,Tin,Cf,Rt,P1grid(k),cfg,cfg.hybrid.seed_N_segments,NaN);
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success && rr.ev.physical_feasible && isfinite(rr.ev.W_RO_kW)
        if rr.ev.W_RO_kW < bestW
            bestW = rr.ev.W_RO_kW;
            bestP1 = P1grid(k);
        end
    end
end
if ~isfinite(bestW)
    bestW = NaN;
end
trigger = isfinite(bestW) && (oldW - bestW) > max(abs_trigger, rel_trigger*oldW);
S = struct('BestW_N30',bestW,'BestP1_N30',bestP1,'PotentialBranch',trigger);
end

%% ========================================================================
function [rowOut, Info] = global_repair_external_row(rowTable, cfg, nCoarse, nLocal, nLevels)
% Robust N=150 minimum-power search on the recovery-equality manifold.
rowOut = table2struct(rowTable);
Qf = rowOut.Qf_train_m3h;
Tin = rowOut.T_RO_in_C;
Cf = rowOut.Cf_kg_m3;
Rt = rowOut.R_target;
oldW = rowOut.W_RO_train_kW;

mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years);
pi_feed = ro_osmotic_pressure_du2014(Tin, Cf, mem);
P1lb = max(cfg.hybrid.P1_lb_MPa, pi_feed + cfg.hybrid.P1_osmotic_margin_MPa);
P1ub = cfg.hybrid.P1_ub_MPa;

P1grid = unique([linspace(P1lb,P1ub,nCoarse), rowOut.P1_opt_gauge_MPa]);
[bestP1,bestP2,bestW,bestEv] = scan_best_N150(P1grid,Qf,Tin,Cf,Rt,cfg);
if ~isfinite(bestW)
    Info = struct('Replaced',false,'PowerReduction_kW',0,'OldW_kW',oldW,'NewW_kW',NaN);
    return;
end

halfWidth = (P1ub-P1lb)/max(nCoarse-1,1);
for lev = 1:nLevels
    lo = max(P1lb,bestP1-halfWidth);
    hi = min(P1ub,bestP1+halfWidth);
    P1local = unique([linspace(lo,hi,nLocal),bestP1]);
    [p1,p2,w,ev] = scan_best_N150(P1local,Qf,Tin,Cf,Rt,cfg);
    if isfinite(w) && w < bestW
        bestP1=p1; bestP2=p2; bestW=w; bestEv=ev;
    end
    halfWidth = halfWidth/10;
end

% One final root evaluation at the selected P1 to freeze all detailed outputs.
rr = ro_find_P2_for_recovery(Qf,Tin,Cf,Rt,bestP1,cfg,cfg.hybrid.final_N_segments,bestP2);
if ~(rr.target_met && ~isempty(rr.ev) && rr.ev.success && rr.ev.physical_feasible)
    Info = struct('Replaced',false,'PowerReduction_kW',0,'OldW_kW',oldW,'NewW_kW',bestW);
    return;
end
bestP2 = rr.P2_gauge_MPa;
bestEv = rr.ev;
bestW = bestEv.W_RO_kW;
improvement = oldW-bestW;
replace = improvement > 0.05 || ~rowOut.DatasetValid;
if replace
    rowOut = apply_ev_to_row(rowOut,bestEv,bestP1,bestP2,Rt,cfg);
end
Info = struct('Replaced',replace,'PowerReduction_kW',max(improvement,0),'OldW_kW',oldW,'NewW_kW',bestW);
end

%% ========================================================================
function [bestP1,bestP2,bestW,bestEv] = scan_best_N150(P1grid,Qf,Tin,Cf,Rt,cfg)
bestP1=NaN; bestP2=NaN; bestW=inf; bestEv=[];
for k = 1:numel(P1grid)
    rr = ro_find_P2_for_recovery(Qf,Tin,Cf,Rt,P1grid(k),cfg,cfg.hybrid.final_N_segments,NaN);
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success && rr.ev.physical_feasible && isfinite(rr.ev.W_RO_kW)
        if rr.ev.W_RO_kW < bestW
            bestP1=P1grid(k); bestP2=rr.P2_gauge_MPa; bestW=rr.ev.W_RO_kW; bestEv=rr.ev;
        end
    end
end
if ~isfinite(bestW)
    bestW=NaN;
end
end

%% ========================================================================
function r = apply_ev_to_row(r,ev,P1,P2,Rt,cfg)
r.Qp_train_m3h = ev.Qp_train_m3h;
r.Recovery_actual = ev.Recovery;
r.Recovery_error = ev.Recovery-Rt;
r.Cp_mg_L = ev.Cp_mg_L;
r.W_RO_train_kW = ev.W_RO_kW;
r.SEC_kWh_m3 = ev.SEC_kWh_m3;
r.P1_opt_gauge_MPa = P1;
r.P2_opt_gauge_MPa = P2;
r.Javg_LMH = ev.Javg_LMH;
r.Jfirst_stage1_LMH = ev.Jfirst_stage1_LMH;
r.Jfirst_stage2_LMH = ev.Jfirst_stage2_LMH;
r.Jmax_local_stage1_LMH = ev.Jmax_local_stage1_LMH;
r.Jmax_local_stage2_LMH = ev.Jmax_local_stage2_LMH;
r.CPFmax_stage1 = ev.CPFmax_stage1;
r.CPFmax_stage2 = ev.CPFmax_stage2;
r.dP_stage1_MPa = ev.dP_stage1_MPa;
r.dP_stage2_MPa = ev.dP_stage2_MPa;
r.Cb_max_kg_m3 = ev.Cb_max_kg_m3;
r.Qf_PV_stage1_m3h = ev.Qf_PV_stage1_m3h;
r.Qf_PV_stage2_m3h = ev.Qf_PV_stage2_m3h;
r.Qb_PV_stage1_m3h = ev.Qb_PV_stage1_m3h;
r.Qb_PV_stage2_m3h = ev.Qb_PV_stage2_m3h;
r.Qhpp_m3h = ev.Qhpp_m3h;
r.PXout_gauge_MPa = ev.PXout_gauge_MPa;
r.PX_excess_pressure_MPa = ev.PX_excess_pressure_MPa;
r.PX_booster_deltaP_MPa = ev.PX_booster_deltaP_MPa;
r.PX_leakage_pct = ev.PX_leakage_pct;
r.PX_mix_pct = ev.PX_mix_pct;
r.PX_iterations = ev.PX_iterations;
r.PhysicalFeasible = ev.physical_feasible;
r.RecoveryTargetMet = abs(r.Recovery_error) <= cfg.optim.recovery_accept_tolerance;
r.DatasetValid = r.PhysicalFeasible && r.RecoveryTargetMet;
r.FeasibilityMarginScaled = ev.feasibility_margin_scaled;
r.MaxConstraintViolationScaled = ev.max_constraint_violation_scaled;
r.ExitFlag = 1;
r.FminconIterations = NaN;
r.FminconFunctionCount = NaN;
r.LocalStartsAttempted = 0;
r.OptimizerMethod = "external_global_recovery_manifold";
r.RootEvalCountCoarse = NaN;
r.RootEvalCountFinal = NaN;
r.HybridSeedRankUsed = NaN;
r.HybridSeedP1_N30_MPa = NaN;
r.HybridSeedP2_N30_MPa = NaN;
r.HybridN150SeedTrials = NaN;
r.FailureReason = "";
r.ErrorMessage = "";
end

%% ========================================================================
function p = classifier_probability_local(M,X)
Xn = (double(X)-M.MuX)./M.SigX;
Y = M.Net(Xn.');
p = double(Y(2,:).');
end

%% ========================================================================
function y = regressor_predict_local(M,X)
Xn = (double(X)-M.MuX)./M.SigX;
y = (M.Net(Xn.').' .* M.SigY) + M.MuY;
y = double(y(:));
end

%% ========================================================================
function M = classifier_metrics(y,pred,score)
y = logical(y(:)); pred = logical(pred(:)); score = double(score(:));
TP = sum(y & pred); TN = sum(~y & ~pred); FP = sum(~y & pred); FN = sum(y & ~pred);
Sens = TP/max(TP+FN,1);
Spec = TN/max(TN+FP,1);
Prec = TP/max(TP+FP,1);
F1 = 2*Prec*Sens/max(Prec+Sens,eps);
Bal = 0.5*(Sens+Spec);
Acc = (TP+TN)/max(numel(y),1);
[FPR,TPR,AUC] = roc_curve_local(y,score);
M = struct('Sensitivity',Sens,'Specificity',Spec,'BalancedAccuracy',Bal,'Precision',Prec, ...
    'F1',F1,'AUROC',AUC,'Accuracy',Acc,'TP',TP,'TN',TN,'FP',FP,'FN',FN, ...
    'FPR_curve',FPR,'TPR_curve',TPR);
end

%% ========================================================================
function [FPR,TPR,AUC] = roc_curve_local(y,score)
% Exact empirical ROC grouping equal score values; no Statistics Toolbox needed.
[ss,ord] = sort(score,'descend');
y = y(ord);
P = sum(y); N = sum(~y);
if P==0 || N==0
    FPR=[0;1]; TPR=[0;1]; AUC=NaN; return;
end
groupEnd = [find(diff(ss)~=0); numel(ss)];
TPcum = cumsum(y);
FPcum = cumsum(~y);
TPR = [0; TPcum(groupEnd)/P; 1];
FPR = [0; FPcum(groupEnd)/N; 1];
% Remove duplicate terminal coordinate if already present.
keep = [true; diff(FPR)~=0 | diff(TPR)~=0];
FPR = FPR(keep); TPR = TPR(keep);
AUC = trapz(FPR,TPR);
end

%% ========================================================================
function T = regression_metric_row(name,y,yhat)
y=double(y(:)); yhat=double(yhat(:));
mask=isfinite(y)&isfinite(yhat);
y=y(mask); yhat=yhat(mask);
e=yhat-y;
N=numel(y);
RMSE=sqrt(mean(e.^2));
MAE=mean(abs(e));
SST=sum((y-mean(y)).^2);
if SST>0, R2=1-sum(e.^2)/SST; else, R2=NaN; end
nz=abs(y)>eps;
if any(nz), MAPE=100*mean(abs(e(nz)./y(nz))); else, MAPE=NaN; end
MaxAE=max(abs(e));
P95AE=percentile_local(abs(e),95);
rangeY=max(y)-min(y);
if rangeY>0, NRMSE=100*RMSE/rangeY; else, NRMSE=NaN; end
T=table(string(name),N,RMSE,MAE,R2,MAPE,MaxAE,P95AE,NRMSE, ...
    'VariableNames',{'Target','N','RMSE','MAE','R2','MAPE_pct','MaxAE','P95AE','NRMSE_range_pct'});
end

%% ========================================================================
function q = percentile_local(x,p)
x=sort(double(x(:)));
if isempty(x), q=NaN; return; end
if numel(x)==1, q=x; return; end
pos=1+(numel(x)-1)*(p/100);
lo=floor(pos); hi=ceil(pos);
if lo==hi, q=x(lo); else, q=x(lo)+(pos-lo)*(x(hi)-x(lo)); end
end

%% ========================================================================
function make_external_verification_figure(D,Wp,P1p,P2p,Cpp,TruthValid,ValidPred,pValid,Cls,Reg,fig_png,fig_pdf)
valid = logical(TruthValid);
fig = figure('Color','w','Position',[80 80 1500 900]);
tl = tiledlayout(fig,2,3,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('Independent external verification of frozen RO ANN v1.9.1 (N=%d; truth-valid=%d)',height(D),sum(valid)), ...
    'FontWeight','bold','FontSize',13);

parity_panel(nexttile(tl,1),D.W_RO_train_kW(valid),Wp(valid),'W_{RO} (kW)',metric_lookup(Reg,"W_RO_train_kW"));
parity_panel(nexttile(tl,2),D.P1_opt_gauge_MPa(valid),P1p(valid),'P_1^* (MPa(g))',metric_lookup(Reg,"P1_opt_gauge_MPa"));
parity_panel(nexttile(tl,3),D.P2_opt_gauge_MPa(valid),P2p(valid),'P_2^* (MPa(g))',metric_lookup(Reg,"P2_opt_gauge_MPa"));
parity_panel(nexttile(tl,4),D.Cp_mg_L(valid),Cpp(valid),'C_p (mg/L)',metric_lookup(Reg,"Cp_hybrid_mg_L"));

% ROC panel.
ax5 = nexttile(tl,5);
plot(ax5,Cls.FPR_curve,Cls.TPR_curve,'LineWidth',1.7); hold(ax5,'on');
plot(ax5,[0 1],[0 1],'--','LineWidth',1.0);
xlabel(ax5,'False-positive rate'); ylabel(ax5,'True-positive rate');
title(ax5,sprintf('Feasibility ROC: AUC = %.3f',Cls.AUROC));
xlim(ax5,[0 1]); ylim(ax5,[0 1]); grid(ax5,'on'); box(ax5,'on');
text(ax5,0.05,0.18,sprintf('Sens. = %.3f\nSpec. = %.3f\nBal. acc. = %.3f', ...
    Cls.Sensitivity,Cls.Specificity,Cls.BalancedAccuracy),'VerticalAlignment','bottom');

% Confusion-matrix panel.
ax6 = nexttile(tl,6);
C = [Cls.TN,Cls.FP;Cls.FN,Cls.TP];
imagesc(ax6,C); axis(ax6,'image');
set(ax6,'XTick',[1 2],'XTickLabel',{'Pred. invalid','Pred. valid'}, ...
    'YTick',[1 2],'YTickLabel',{'Truth invalid','Truth valid'});
title(ax6,sprintf('Classifier at frozen threshold: FP=%d, FN=%d',Cls.FP,Cls.FN));
for r=1:2
    for c=1:2
        text(ax6,c,r,sprintf('%d',C(r,c)),'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontWeight','bold','FontSize',12,'Color','k');
    end
end
box(ax6,'on');

exportgraphics(fig,fig_png,'Resolution',600);
exportgraphics(fig,fig_pdf,'ContentType','vector');
end

%% ========================================================================
function parity_panel(ax,y,yhat,labeltxt,M)
scatter(ax,y,yhat,22,'filled','MarkerFaceAlpha',0.55); hold(ax,'on');
lo=min([y(:);yhat(:)]); hi=max([y(:);yhat(:)]); span=max(hi-lo,eps);
lo=lo-0.03*span; hi=hi+0.03*span;
plot(ax,[lo hi],[lo hi],'--','LineWidth',1.2);
xlim(ax,[lo hi]); ylim(ax,[lo hi]); axis(ax,'square'); grid(ax,'on'); box(ax,'on');
xlabel(ax,['High-fidelity model: ' labeltxt]);
ylabel(ax,['ANN surrogate: ' labeltxt]);
title(ax,labeltxt);
text(ax,0.05,0.94,sprintf('R^2 = %.6f\nRMSE = %.4g\nMAE = %.4g\nN = %d',M.R2,M.RMSE,M.MAE,M.N), ...
    'Units','normalized','VerticalAlignment','top','BackgroundColor','w','Margin',3);
end

%% ========================================================================
function M = metric_lookup(T,name)
i=find(T.Target==string(name),1,'first');
if isempty(i), error('Metric row bulunamadi: %s',name); end
M=struct('N',T.N(i),'RMSE',T.RMSE(i),'MAE',T.MAE(i),'R2',T.R2(i));
end
