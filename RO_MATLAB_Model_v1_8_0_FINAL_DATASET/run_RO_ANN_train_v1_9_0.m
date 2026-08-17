function Results = run_RO_ANN_train_v1_9_0(final_mat_file)
% RO ANN v1.9.0
% Trains:
%   (1) conservative feasibility classifier: [Qf,T,Cf,R] -> DatasetValid
%   (2) separate performance ANNs: W_RO, P1*, P2*
%   (3) hybrid product-salinity model: Cp-boundary classifier + off-boundary margin ANN
% Fixed final Train/Validation/Test assignment is preserved. Blind Test is never
% used for architecture/threshold selection.

if nargin < 1 || strlength(string(final_mat_file)) == 0
    final_mat_file = 'RO_ANN_final_truth_dataset.mat';
end

%% CONFIG
cfg = local_config();
rng(cfg.master_seed, 'twister');

%% PREFLIGHT / DATA LOAD
Info = test_RO_ANN_training_preflight(final_mat_file);
S = load(final_mat_file, 'Dataset', 'DOE');
D = S.Dataset;
DOE = S.DOE;
[tf, loc] = ismember(D.DOE_ID, DOE.DOE_ID);
if ~all(tf), error('DOE_ID merge failure.'); end
D.DataSplit = string(DOE.DataSplit(loc));

X = [D.Qf_train_m3h, D.T_RO_in_C, D.Cf_kg_m3, D.R_target];
yValid = double(D.DatasetValid == 1);

idxTrain = D.DataSplit == "Train";
idxVal   = D.DataSplit == "Validation";
idxTest  = D.DataSplit == "Test";
idxPhysValid = D.DatasetValid == 1;

fprintf('\n============================================================\n');
fprintf('RO ANN v1.9.0 - MODEL TRAINING\n');
fprintf('============================================================\n');
fprintf('Architecture candidates : %d\n', numel(cfg.architectures));
fprintf('Random seeds/candidate  : %d\n', numel(cfg.seeds));
fprintf('Blind test is held out from all model selection.\n\n');

%% FEASIBILITY CLASSIFIER: FINAL-ONLY vs PRIOR-ENRICHED
fprintf('--- FEASIBILITY CLASSIFIER ---\n');
XtrFinal = X(idxTrain,:); ytrFinal = yValid(idxTrain);
Xval = X(idxVal,:); yval = yValid(idxVal);
Xtest = X(idxTest,:); ytest = yValid(idxTest);

% Candidate A: final-train only.
[ClsA, SearchA] = train_classifier_search(XtrFinal, ytrFinal, Xval, yval, cfg, "FinalOnly", true);

% Candidate B: final-train + prior envelope/pilot, if files are available.
[XPrior, yPrior, priorInfo] = load_classifier_prior();
if ~isempty(XPrior)
    XtrEnriched = [XtrFinal; XPrior];
    ytrEnriched = [ytrFinal; yPrior];
    [ClsB, SearchB] = train_classifier_search(XtrEnriched, ytrEnriched, Xval, yval, cfg, "PriorEnriched", true);
    if classifier_selection_score(ClsB.ValidationMetrics, cfg) > classifier_selection_score(ClsA.ValidationMetrics, cfg)
        Feasibility = ClsB;
        SearchClassifier = [SearchA; SearchB];
    else
        Feasibility = ClsA;
        SearchClassifier = [SearchA; SearchB];
    end
else
    Feasibility = ClsA;
    SearchClassifier = SearchA;
end

pTestValid = classifier_probability(Feasibility, Xtest);
yhatTestValid = double(pTestValid >= Feasibility.Threshold);
Feasibility.TestMetrics = classifier_metrics(ytest, yhatTestValid, pTestValid);

fprintf('Selected classifier      : %s | hidden=%s | seed=%d | threshold=%.3f\n', ...
    Feasibility.TrainingMode, hidden_to_string(Feasibility.HiddenSizes), Feasibility.Seed, Feasibility.Threshold);
print_classifier_metrics('Validation', Feasibility.ValidationMetrics);
print_classifier_metrics('Blind Test', Feasibility.TestMetrics);
fprintf('Prior training rows used : %d (valid %d / invalid %d)\n\n', ...
    priorInfo.N, priorInfo.Nvalid, priorInfo.Ninvalid);

%% PERFORMANCE VALID SPLITS
idxRegTrain = idxTrain & idxPhysValid;
idxRegVal   = idxVal   & idxPhysValid;
idxRegTest  = idxTest  & idxPhysValid;
XregTrain = X(idxRegTrain,:);
XregVal   = X(idxRegVal,:);
XregTest  = X(idxRegTest,:);

%% W, P1, P2 REGRESSION ANNs
fprintf('--- PERFORMANCE REGRESSION ANNs ---\n');
regNames = ["W_RO_train_kW","P1_opt_gauge_MPa","P2_opt_gauge_MPa"];
Regressors = struct();
SearchRegression = table();
for k = 1:numel(regNames)
    vn = char(regNames(k));
    ytr = D.(vn)(idxRegTrain);
    yv  = D.(vn)(idxRegVal);
    yt  = D.(vn)(idxRegTest);
    [M, Search] = train_regressor_search(XregTrain, ytr, XregVal, yv, XregTest, yt, cfg, regNames(k));
    key = matlab.lang.makeValidName(vn);
    Regressors.(key) = M;
    SearchRegression = [SearchRegression; Search]; %#ok<AGROW>
    fprintf('%-18s hidden=%-7s seed=%d | Val RMSE %.5g | Test RMSE %.5g | Test R2 %.6f\n', ...
        vn, hidden_to_string(M.HiddenSizes), M.Seed, M.ValidationMetrics.RMSE, M.TestMetrics.RMSE, M.TestMetrics.R2);
end

%% Cp HYBRID MODEL
fprintf('\n--- PRODUCT SALINITY HYBRID MODEL ---\n');
Cp = D.Cp_mg_L;
cpActive = abs(Cp - cfg.Cp_limit_mgL) <= cfg.Cp_active_tolerance_mgL;

% Boundary-active classifier uses only valid rows.
XcpTrain = X(idxRegTrain,:); ycpActTrain = double(cpActive(idxRegTrain));
XcpVal   = X(idxRegVal,:);   ycpActVal   = double(cpActive(idxRegVal));
XcpTest  = X(idxRegTest,:);  ycpActTest  = double(cpActive(idxRegTest));
[CpActive, SearchCpActive] = train_classifier_search(XcpTrain, ycpActTrain, XcpVal, ycpActVal, cfg, "CpBoundary", false);

% Off-boundary margin regression: margin = 500 - Cp, only where Cp boundary is inactive.
idxMarginTrain = idxRegTrain & ~cpActive;
idxMarginVal   = idxRegVal   & ~cpActive;
idxMarginTest  = idxRegTest  & ~cpActive;
margin = cfg.Cp_limit_mgL - Cp;
if sum(idxMarginTrain) < 50 || sum(idxMarginVal) < 10 || sum(idxMarginTest) < 10
    error('Cp off-boundary margin dataset too small for robust train/val/test regression.');
end
[CpMargin, SearchCpMargin] = train_regressor_search( ...
    X(idxMarginTrain,:), margin(idxMarginTrain), ...
    X(idxMarginVal,:), margin(idxMarginVal), ...
    X(idxMarginTest,:), margin(idxMarginTest), cfg, "Cp_margin_mg_L");

% Tune only the Cp switching threshold on VALIDATION by final Cp RMSE.
pActVal = classifier_probability(CpActive, XcpVal);
marginValPred = max(0.0, regressor_predict(CpMargin, XcpVal));
CpTrueVal = Cp(idxRegVal);
[cpSwitchThreshold, cpValMetrics] = tune_cp_switch_threshold( ...
    pActVal, marginValPred, CpTrueVal, cfg);

% Blind test evaluation.
pActTest = classifier_probability(CpActive, XcpTest);
marginTestPred = max(0.0, regressor_predict(CpMargin, XcpTest));
CpTrueTest = Cp(idxRegTest);
CpPredTest = combine_cp_prediction(pActTest, marginTestPred, cpSwitchThreshold, cfg.Cp_limit_mgL);
cpTestMetrics = regression_metrics(CpTrueTest, CpPredTest);
yCpActivePredTest = double(pActTest >= cpSwitchThreshold);
cpActiveTestMetrics = classifier_metrics(ycpActTest, yCpActivePredTest, pActTest);

CpModel = struct();
CpModel.ActiveClassifier = CpActive;
CpModel.MarginRegressor = CpMargin;
CpModel.SwitchThreshold = cpSwitchThreshold;
CpModel.ValidationMetrics = cpValMetrics;
CpModel.TestMetrics = cpTestMetrics;
CpModel.ActiveTestMetrics = cpActiveTestMetrics;
CpModel.CpLimit_mgL = cfg.Cp_limit_mgL;
CpModel.ActiveTolerance_mgL = cfg.Cp_active_tolerance_mgL;

fprintf('Cp active valid fraction : %.1f %%\n', 100*mean(cpActive(idxPhysValid)));
fprintf('Cp switch threshold      : %.3f\n', cpSwitchThreshold);
fprintf('Cp validation RMSE/MAE   : %.4f / %.4f mg/L\n', cpValMetrics.RMSE, cpValMetrics.MAE);
fprintf('Cp blind-test RMSE/MAE   : %.4f / %.4f mg/L | R2 %.6f\n', cpTestMetrics.RMSE, cpTestMetrics.MAE, cpTestMetrics.R2);

%% DERIVED SEC TEST METRICS (physics-derived, not ANN target)
Wmodel = Regressors.W_RO_train_kW;
WpredTest = regressor_predict(Wmodel, XregTest);
QpPredTest = XregTest(:,1) .* XregTest(:,4);
SECpredTest = WpredTest ./ QpPredTest;
SECtrueTest = D.SEC_kWh_m3(idxRegTest);
SECtestMetrics = regression_metrics(SECtrueTest, SECpredTest);
fprintf('\nDerived SEC blind test   : RMSE %.5f kWh/m3 | MAE %.5f | R2 %.6f\n', ...
    SECtestMetrics.RMSE, SECtestMetrics.MAE, SECtestMetrics.R2);

%% BUILD MODELS STRUCT
Models = struct();
Models.Version = 'v1.9.0';
Models.InputNames = {'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target'};
Models.Feasibility = Feasibility;
Models.Regressors = Regressors;
Models.Cp = CpModel;
Models.Meta.CreationDate = string(datetime('now'));
Models.Meta.FinalTruthFile = string(final_mat_file);
Models.Meta.NTotal = height(D);
Models.Meta.NValid = sum(idxPhysValid);
Models.Meta.NValidTrain = sum(idxRegTrain);
Models.Meta.NValidValidation = sum(idxRegVal);
Models.Meta.NValidTest = sum(idxRegTest);
Models.Meta.FeasibilityTestN = sum(idxTest);
Models.Meta.CpBoundaryValidFraction = mean(cpActive(idxPhysValid));
Models.Meta.TrainingConfig = cfg;

%% TEST PREDICTION TABLE
Pred = table();
Pred.DOE_ID = D.DOE_ID(idxTest);
Pred.DatasetValid = ytest;
Pred.Pvalid = pTestValid;
Pred.ValidPred = yhatTestValid;
Pred.Qf_train_m3h = Xtest(:,1);
Pred.T_RO_in_C = Xtest(:,2);
Pred.Cf_kg_m3 = Xtest(:,3);
Pred.R_target = Xtest(:,4);

% Performance columns only for truth-valid blind-test rows; map by DOE_ID.
regTestIDs = D.DOE_ID(idxRegTest);
[tfReg, locReg] = ismember(Pred.DOE_ID, regTestIDs);
Pred.W_true_kW = NaN(height(Pred),1); Pred.W_pred_kW = NaN(height(Pred),1);
Pred.P1_true_MPa = NaN(height(Pred),1); Pred.P1_pred_MPa = NaN(height(Pred),1);
Pred.P2_true_MPa = NaN(height(Pred),1); Pred.P2_pred_MPa = NaN(height(Pred),1);
Pred.Cp_true_mgL = NaN(height(Pred),1); Pred.Cp_pred_mgL = NaN(height(Pred),1);
Pred.SEC_true_kWh_m3 = NaN(height(Pred),1); Pred.SEC_pred_kWh_m3 = NaN(height(Pred),1);
if any(tfReg)
    idr = find(tfReg);
    j = locReg(tfReg);
    Pred.W_true_kW(idr) = D.W_RO_train_kW(idxRegTest);
    Pred.W_pred_kW(idr) = WpredTest(j);
    P1pred = regressor_predict(Regressors.P1_opt_gauge_MPa, XregTest);
    P2pred = regressor_predict(Regressors.P2_opt_gauge_MPa, XregTest);
    Pred.P1_true_MPa(idr) = D.P1_opt_gauge_MPa(idxRegTest);
    Pred.P1_pred_MPa(idr) = P1pred(j);
    Pred.P2_true_MPa(idr) = D.P2_opt_gauge_MPa(idxRegTest);
    Pred.P2_pred_MPa(idr) = P2pred(j);
    Pred.Cp_true_mgL(idr) = CpTrueTest(j);
    Pred.Cp_pred_mgL(idr) = CpPredTest(j);
    Pred.SEC_true_kWh_m3(idr) = SECtrueTest(j);
    Pred.SEC_pred_kWh_m3(idr) = SECpredTest(j);
end

%% SUMMARY TABLES
RegressionSummary = build_regression_summary(Regressors, CpModel, SECtestMetrics);
ClassifierSummary = build_classifier_summary(Feasibility, CpModel);

%% SAVE
writetable(SearchClassifier, 'RO_ANN_classifier_architecture_search.csv');
writetable(SearchRegression, 'RO_ANN_regression_architecture_search.csv');
writetable(SearchCpActive, 'RO_ANN_Cp_active_architecture_search.csv');
writetable(SearchCpMargin, 'RO_ANN_Cp_margin_architecture_search.csv');
writetable(RegressionSummary, 'RO_ANN_regression_test_metrics.csv');
writetable(ClassifierSummary, 'RO_ANN_classifier_test_metrics.csv');
writetable(Pred, 'RO_ANN_blind_test_predictions.csv');

%% RESULTS STRUCT (assign after file outputs are ready, then resave)
Results = struct();
Results.Preflight = Info;
Results.FeasibilityValidation = Feasibility.ValidationMetrics;
Results.FeasibilityTest = Feasibility.TestMetrics;
Results.RegressionSummary = RegressionSummary;
Results.ClassifierSummary = ClassifierSummary;
Results.CpValidation = CpModel.ValidationMetrics;
Results.CpTest = CpModel.TestMetrics;
Results.SECtest = SECtestMetrics;
Results.PriorInfo = priorInfo;
save('RO_ANN_models_v1_9_0.mat', 'Models', 'Results', 'cfg', '-v7.3');

fprintf('\n============================================================\n');
fprintf('ANN TRAINING COMPLETE\n');
fprintf('Models      : RO_ANN_models_v1_9_0.mat\n');
fprintf('Blind preds : RO_ANN_blind_test_predictions.csv\n');
fprintf('Reg metrics : RO_ANN_regression_test_metrics.csv\n');
fprintf('Cls metrics : RO_ANN_classifier_test_metrics.csv\n');
fprintf('============================================================\n\n');
end

%% =========================== LOCAL FUNCTIONS ===========================
function cfg = local_config()
cfg.master_seed = 20260812;
cfg.architectures = {[12],[20],[16 8],[24 12]};
cfg.seeds = [20260812, 20260829, 20260907];
cfg.reg_train_fcn = 'trainlm';
cfg.cls_train_fcn = 'trainscg';
cfg.reg_epochs = 700;
cfg.cls_epochs = 1000;
cfg.max_fail = 30;
cfg.min_gradient = 1e-8;
cfg.invalid_specificity_target = 0.98;
cfg.threshold_grid = (0.05:0.01:0.95).';
cfg.Cp_limit_mgL = 500.0;
cfg.Cp_active_tolerance_mgL = 1.0e-6;
cfg.Cp_switch_grid = (0.05:0.01:0.95).';
end

function [Model, Search] = train_regressor_search(Xtr, ytr, Xv, yv, Xt, yt, cfg, targetName)
[muX, sigX] = fit_scaler(Xtr);
muY = mean(ytr, 'omitnan');
sigY = std(ytr, 0, 'omitnan');
if ~isfinite(sigY) || sigY < 1e-12, sigY = 1.0; end
XtrN = apply_scaler(Xtr, muX, sigX);
XvN = apply_scaler(Xv, muX, sigX);
Xtv = [XtrN; XvN].';
ytN = (ytr - muY) ./ sigY;
yvN = (yv - muY) ./ sigY;
Ytv = [ytN; yvN].';
ntr = size(Xtr,1); nv = size(Xv,1);
rows = [];
bestScore = inf; Model = struct();
for ia = 1:numel(cfg.architectures)
    h = cfg.architectures{ia};
    for is = 1:numel(cfg.seeds)
        seed = cfg.seeds(is);
        rng(seed, 'twister');
        net = fitnet(h, cfg.reg_train_fcn);
        net.inputs{1}.processFcns = {};
        net.outputs{net.numLayers}.processFcns = {};
        net.divideFcn = 'divideind';
        net.divideParam.trainInd = 1:ntr;
        net.divideParam.valInd = ntr + (1:nv);
        net.divideParam.testInd = [];
        net.performFcn = 'mse';
        net.trainParam.epochs = cfg.reg_epochs;
        net.trainParam.max_fail = cfg.max_fail;
        net.trainParam.min_grad = cfg.min_gradient;
        net.trainParam.showWindow = false;
        net.trainParam.showCommandLine = false;
        net = configure(net, Xtv, Ytv);
        net = init(net);
        [net,tr] = train(net, Xtv, Ytv);
        predV = (net(XvN.').' .* sigY + muY).';
        Mv = regression_metrics(yv, predV);
        row = table(string(targetName), string(hidden_to_string(h)), seed, Mv.RMSE, Mv.MAE, Mv.R2, Mv.MAPE_pct, tr.best_epoch, ...
            'VariableNames', {'Target','Hidden','Seed','Val_RMSE','Val_MAE','Val_R2','Val_MAPE_pct','BestEpoch'});
        if isempty(rows), rows = row; else, rows = [rows; row]; end %#ok<AGROW>
        if Mv.RMSE < bestScore
            bestScore = Mv.RMSE;
            Model.Net = net;
            Model.HiddenSizes = h;
            Model.Seed = seed;
            Model.MuX = muX;
            Model.SigX = sigX;
            Model.MuY = muY;
            Model.SigY = sigY;
            Model.TargetName = string(targetName);
            Model.ValidationMetrics = Mv;
            Model.BestEpoch = tr.best_epoch;
        end
    end
end
Search = rows;
predT = regressor_predict(Model, Xt);
Model.TestMetrics = regression_metrics(yt, predT);
end

function yhat = regressor_predict(Model, X)
Xn = apply_scaler(X, Model.MuX, Model.SigX);
yhat = (Model.Net(Xn.').' .* Model.SigY) + Model.MuY;
yhat = double(yhat(:));
end

function [Model, Search] = train_classifier_search(Xtr, ytr, Xv, yv, cfg, trainingMode, conservative)
[muX, sigX] = fit_scaler(Xtr);
XvN = apply_scaler(Xv, muX, sigX);
rows = [];
bestScore = -inf; Model = struct();
for ia = 1:numel(cfg.architectures)
    h = cfg.architectures{ia};
    for is = 1:numel(cfg.seeds)
        seed = cfg.seeds(is);
        rng(seed, 'twister');
        [Xbal, ybal] = balance_binary_training(Xtr, ytr);
        XbalN = apply_scaler(Xbal, muX, sigX);
        Xtv = [XbalN; XvN].';
        ytv = [ybal; yv];
        Ttv = [1-ytv, ytv].';
        ntr = size(XbalN,1); nv = size(XvN,1);
        net = patternnet(h, cfg.cls_train_fcn);
        net.performFcn = 'crossentropy';
        net.inputs{1}.processFcns = {};
        net.outputs{net.numLayers}.processFcns = {};
        net.divideFcn = 'divideind';
        net.divideParam.trainInd = 1:ntr;
        net.divideParam.valInd = ntr + (1:nv);
        net.divideParam.testInd = [];
        net.trainParam.epochs = cfg.cls_epochs;
        net.trainParam.max_fail = cfg.max_fail;
        net.trainParam.min_grad = cfg.min_gradient;
        net.trainParam.showWindow = false;
        net.trainParam.showCommandLine = false;
        net = configure(net, Xtv, Ttv);
        net = init(net);
        [net,tr] = train(net, Xtv, Ttv);
        Yv = net(XvN.'); pV = double(Yv(2,:).');
        if conservative
            [th, Mv] = tune_conservative_threshold(yv, pV, cfg.threshold_grid, cfg.invalid_specificity_target);
        else
            [th, Mv] = tune_balanced_threshold(yv, pV, cfg.threshold_grid);
        end
        score = classifier_candidate_score(Mv, conservative, cfg.invalid_specificity_target);
        row = table(string(trainingMode), string(hidden_to_string(h)), seed, th, Mv.SensitivityValid, Mv.SpecificityInvalid, ...
            Mv.BalancedAccuracy, Mv.PrecisionValid, Mv.F1Valid, Mv.AUROC, score, tr.best_epoch, ...
            'VariableNames', {'TrainingMode','Hidden','Seed','Threshold','Val_SensitivityValid','Val_SpecificityInvalid', ...
            'Val_BalancedAccuracy','Val_PrecisionValid','Val_F1Valid','Val_AUROC','SelectionScore','BestEpoch'});
        if isempty(rows), rows = row; else, rows = [rows; row]; end %#ok<AGROW>
        if score > bestScore
            bestScore = score;
            Model.Net = net;
            Model.HiddenSizes = h;
            Model.Seed = seed;
            Model.MuX = muX;
            Model.SigX = sigX;
            Model.Threshold = th;
            Model.ValidationMetrics = Mv;
            Model.TrainingMode = string(trainingMode);
            Model.BestEpoch = tr.best_epoch;
        end
    end
end
Search = rows;
end

function p = classifier_probability(Model, X)
Xn = apply_scaler(X, Model.MuX, Model.SigX);
Y = Model.Net(Xn.');
p = double(Y(2,:).');
end

function [Xbal, ybal] = balance_binary_training(X, y)
y = double(y(:));
i0 = find(y == 0); i1 = find(y == 1);
if isempty(i0) || isempty(i1), error('Binary training requires both classes.'); end
n = max(numel(i0), numel(i1));
j0 = i0(randi(numel(i0), n, 1));
j1 = i1(randi(numel(i1), n, 1));
idx = [j0; j1];
idx = idx(randperm(numel(idx)));
Xbal = X(idx,:); ybal = y(idx);
end

function [thBest, Mbest] = tune_conservative_threshold(y, p, grid, specTarget)
bestKey = [-inf,-inf,-inf]; thBest = 0.5; Mbest = classifier_metrics(y, double(p>=0.5), p);
for i = 1:numel(grid)
    th = grid(i); M = classifier_metrics(y, double(p>=th), p);
    meets = double(M.SpecificityInvalid >= specTarget);
    if meets > 0
        key = [1, M.SensitivityValid, M.BalancedAccuracy];
    else
        key = [0, M.BalancedAccuracy - 2*max(0,specTarget-M.SpecificityInvalid), M.SensitivityValid];
    end
    if lex_greater(key, bestKey)
        bestKey = key; thBest = th; Mbest = M;
    end
end
end

function [thBest, Mbest] = tune_balanced_threshold(y, p, grid)
best = -inf; thBest = 0.5; Mbest = classifier_metrics(y, double(p>=0.5), p);
for i = 1:numel(grid)
    th = grid(i); M = classifier_metrics(y, double(p>=th), p);
    score = M.BalancedAccuracy + 0.05*M.F1Valid;
    if score > best
        best = score; thBest = th; Mbest = M;
    end
end
end

function s = classifier_candidate_score(M, conservative, specTarget)
if conservative
    if M.SpecificityInvalid >= specTarget
        s = 1000 + M.SensitivityValid + 0.10*M.BalancedAccuracy + 0.01*M.F1Valid;
    else
        s = M.BalancedAccuracy - 2*max(0,specTarget-M.SpecificityInvalid);
    end
else
    s = M.BalancedAccuracy + 0.05*M.F1Valid;
end
end

function s = classifier_selection_score(M, cfg)
s = classifier_candidate_score(M, true, cfg.invalid_specificity_target);
end

function M = classifier_metrics(y, yhat, p)
y = double(y(:)); yhat = double(yhat(:)); p = double(p(:));
TP = sum(y==1 & yhat==1); FN = sum(y==1 & yhat==0);
TN = sum(y==0 & yhat==0); FP = sum(y==0 & yhat==1);
M.N = numel(y); M.TP=TP; M.FN=FN; M.TN=TN; M.FP=FP;
M.SensitivityValid = TP / max(TP+FN,1);
M.SpecificityInvalid = TN / max(TN+FP,1);
M.BalancedAccuracy = 0.5*(M.SensitivityValid + M.SpecificityInvalid);
M.PrecisionValid = TP / max(TP+FP,1);
M.F1Valid = 2*M.PrecisionValid*M.SensitivityValid / max(M.PrecisionValid+M.SensitivityValid,eps);
M.Accuracy = (TP+TN)/max(numel(y),1);
M.FalseFeasibleRate = FP/max(TN+FP,1);
M.AUROC = compute_auc(y,p);
end

function M = regression_metrics(y, yp)
y = double(y(:)); yp = double(yp(:));
e = yp-y; ae=abs(e);
M.N = numel(y);
M.RMSE = sqrt(mean(e.^2,'omitnan'));
M.MAE = mean(ae,'omitnan');
M.MaxAE = max(ae,[],'omitnan');
M.P95AE = prctile(ae,95);
den = sum((y-mean(y,'omitnan')).^2,'omitnan');
M.R2 = 1 - sum(e.^2,'omitnan')/max(den,eps);
M.MAPE_pct = 100*mean(ae./max(abs(y),1e-12),'omitnan');
rngY = max(y)-min(y);
M.NRMSE_range_pct = 100*M.RMSE/max(rngY,1e-12);
end

function [mu, sig] = fit_scaler(X)
mu = mean(X,1,'omitnan'); sig = std(X,0,1,'omitnan'); sig(~isfinite(sig) | sig<1e-12)=1.0;
end

function Xn = apply_scaler(X, mu, sig)
Xn = (double(X)-mu)./sig;
end

function [XPrior, yPrior, info] = load_classifier_prior()
XPrior = []; yPrior = [];
info = struct('N',0,'Nvalid',0,'Ninvalid',0);
if exist('RO_feasibility_envelope.csv','file')==2 && exist('RO_feasibility_envelope_probes.csv','file')==2
    E = readtable('RO_feasibility_envelope.csv','TextType','string');
    P = readtable('RO_feasibility_envelope_probes.csv','TextType','string');
    [tf,loc] = ismember(P.State_ID,E.State_ID);
    if all(tf)
        XP = [E.Qf_train_m3h(loc),E.T_RO_in_C(loc),E.Cf_kg_m3(loc),P.R_target];
        yP = double(P.DatasetValid==1);
        finite = all(isfinite(XP),2) & isfinite(yP);
        XPrior=[XPrior;XP(finite,:)]; yPrior=[yPrior;yP(finite)]; %#ok<AGROW>
    end
end
if exist('RO_ANN_probe_guided_pilot.csv','file')==2
    P = readtable('RO_ANN_probe_guided_pilot.csv','TextType','string');
    XP=[P.Qf_train_m3h,P.T_RO_in_C,P.Cf_kg_m3,P.R_target]; yP=double(P.DatasetValid==1);
    finite=all(isfinite(XP),2)&isfinite(yP);
    XPrior=[XPrior;XP(finite,:)]; yPrior=[yPrior;yP(finite)]; %#ok<AGROW>
end
info.N=size(XPrior,1); info.Nvalid=sum(yPrior==1); info.Ninvalid=sum(yPrior==0);
end

function [thBest, Mbest] = tune_cp_switch_threshold(pAct, marginPred, CpTrue, cfg)
best=inf; thBest=0.5; Mbest=regression_metrics(CpTrue, combine_cp_prediction(pAct,marginPred,0.5,cfg.Cp_limit_mgL));
for i=1:numel(cfg.Cp_switch_grid)
    th=cfg.Cp_switch_grid(i);
    CpPred=combine_cp_prediction(pAct,marginPred,th,cfg.Cp_limit_mgL);
    M=regression_metrics(CpTrue,CpPred);
    if M.RMSE < best
        best=M.RMSE; thBest=th; Mbest=M;
    end
end
end

function CpPred = combine_cp_prediction(pAct, marginPred, th, CpLimit)
CpPred = CpLimit - max(0.0,double(marginPred(:)));
active = double(pAct(:)) >= th;
CpPred(active) = CpLimit;
CpPred = min(CpLimit,max(0.0,CpPred));
end

function auc = compute_auc(y,p)
y=double(y(:)); p=double(p(:));
if numel(unique(y))<2, auc=NaN; return; end
if exist('perfcurve','file')==2
    try
        [~,~,~,auc]=perfcurve(y,p,1); return;
    catch
    end
end
[ps,ord]=sort(p,'descend'); %#ok<ASGLU>
ys=y(ord); P=sum(ys==1); N=sum(ys==0);
tpr=[0;cumsum(ys==1)/max(P,1)]; fpr=[0;cumsum(ys==0)/max(N,1)];
auc=trapz(fpr,tpr);
end

function tf = lex_greater(a,b)
tf=false;
for i=1:numel(a)
    if a(i)>b(i), tf=true; return; elseif a(i)<b(i), return; end
end
end

function s = hidden_to_string(h)
s = strjoin(string(h),'-');
end

function print_classifier_metrics(label,M)
fprintf('%s: Sens(valid)=%.3f | Spec(invalid)=%.3f | BalAcc=%.3f | Precision=%.3f | F1=%.3f | AUC=%.3f | FP=%d\n', ...
    label,M.SensitivityValid,M.SpecificityInvalid,M.BalancedAccuracy,M.PrecisionValid,M.F1Valid,M.AUROC,M.FP);
end

function T = build_regression_summary(R,Cp,SEC)
name=["W_RO_train_kW";"P1_opt_gauge_MPa";"P2_opt_gauge_MPa";"Cp_hybrid_mg_L";"SEC_derived_kWh_m3"];
M={R.W_RO_train_kW.TestMetrics;R.P1_opt_gauge_MPa.TestMetrics;R.P2_opt_gauge_MPa.TestMetrics;Cp.TestMetrics;SEC};
n=numel(M); RMSE=zeros(n,1); MAE=RMSE; R2=RMSE; MAPE=RMSE; MaxAE=RMSE; P95AE=RMSE; NRMSE=RMSE;
for i=1:n
    RMSE(i)=M{i}.RMSE; MAE(i)=M{i}.MAE; R2(i)=M{i}.R2; MAPE(i)=M{i}.MAPE_pct; MaxAE(i)=M{i}.MaxAE; P95AE(i)=M{i}.P95AE; NRMSE(i)=M{i}.NRMSE_range_pct;
end
T=table(name,RMSE,MAE,R2,MAPE,MaxAE,P95AE,NRMSE,'VariableNames',{'Target','RMSE','MAE','R2','MAPE_pct','MaxAE','P95AE','NRMSE_range_pct'});
end

function T = build_classifier_summary(F,Cp)
name=["Feasibility";"CpBoundary"];
M={F.TestMetrics;Cp.ActiveTestMetrics};
n=2; Sens=zeros(n,1); Spec=Sens; Bal=Sens; Prec=Sens; F1=Sens; AUC=Sens; FFR=Sens; Acc=Sens;
for i=1:n
    Sens(i)=M{i}.SensitivityValid; Spec(i)=M{i}.SpecificityInvalid; Bal(i)=M{i}.BalancedAccuracy; Prec(i)=M{i}.PrecisionValid; F1(i)=M{i}.F1Valid; AUC(i)=M{i}.AUROC; FFR(i)=M{i}.FalseFeasibleRate; Acc(i)=M{i}.Accuracy;
end
T=table(name,Sens,Spec,Bal,Prec,F1,AUC,FFR,Acc,'VariableNames',{'Classifier','SensitivityPositive','SpecificityNegative','BalancedAccuracy','PrecisionPositive','F1Positive','AUROC','FalsePositiveRate','Accuracy'});
end
