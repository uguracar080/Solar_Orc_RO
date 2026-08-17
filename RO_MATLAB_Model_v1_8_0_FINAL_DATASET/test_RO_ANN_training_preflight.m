function Info = test_RO_ANN_training_preflight(final_mat_file)
% RO ANN v1.9.0 training preflight.
% R2023b-compatible checks only; no ANN is trained here.

if nargin < 1 || strlength(string(final_mat_file)) == 0
    final_mat_file = 'RO_ANN_final_truth_dataset.mat';
end

fprintf('\n============================================================\n');
fprintf('RO ANN v1.9.0 - TRAINING PREFLIGHT\n');
fprintf('============================================================\n');

requiredFcn = {'fitnet','patternnet','train','trainlm','trainscg'};
fcnInfo = strings(numel(requiredFcn),1);
for i = 1:numel(requiredFcn)
    fcnPath = which(requiredFcn{i});
    if isempty(fcnPath)
        error('%s bulunamadi. Deep Learning Toolbox / Neural Network functions gerekli.', requiredFcn{i});
    end
    fcnInfo(i) = string(fcnPath);
end

if exist(final_mat_file, 'file') ~= 2
    error('Final MAT dosyasi bulunamadi: %s', final_mat_file);
end

S = load(final_mat_file, 'Dataset', 'DOE');
if ~isfield(S, 'Dataset') || ~istable(S.Dataset)
    error('MAT dosyasinda Dataset table bulunamadi.');
end
if ~isfield(S, 'DOE') || ~istable(S.DOE)
    error('MAT dosyasinda DOE table bulunamadi. DataSplit bilgisi icin DOE gereklidir.');
end

D = S.Dataset;
DOE = S.DOE;
requiredData = {'DOE_ID','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'DatasetValid','W_RO_train_kW','Cp_mg_L','P1_opt_gauge_MPa','P2_opt_gauge_MPa'};
requiredDOE = {'DOE_ID','DataSplit'};
for i = 1:numel(requiredData)
    if ~ismember(requiredData{i}, D.Properties.VariableNames)
        error('Dataset kolonu eksik: %s', requiredData{i});
    end
end
for i = 1:numel(requiredDOE)
    if ~ismember(requiredDOE{i}, DOE.Properties.VariableNames)
        error('DOE kolonu eksik: %s', requiredDOE{i});
    end
end

[tf, loc] = ismember(D.DOE_ID, DOE.DOE_ID);
if ~all(tf)
    error('Dataset.DOE_ID ile DOE.DOE_ID tam eslesmiyor.');
end
Split = string(DOE.DataSplit(loc));
Valid = D.DatasetValid == 1;

Info = struct();
Info.N_total = height(D);
Info.N_valid = sum(Valid);
Info.N_invalid = sum(~Valid);
Info.N_train = sum(Split == "Train");
Info.N_validation = sum(Split == "Validation");
Info.N_test = sum(Split == "Test");
Info.N_valid_train = sum(Valid & Split == "Train");
Info.N_valid_validation = sum(Valid & Split == "Validation");
Info.N_valid_test = sum(Valid & Split == "Test");
Info.N_invalid_train = sum(~Valid & Split == "Train");
Info.N_invalid_validation = sum(~Valid & Split == "Validation");
Info.N_invalid_test = sum(~Valid & Split == "Test");
Info.Cp_boundary_count = sum(Valid & abs(D.Cp_mg_L - 500.0) <= 1.0e-6);
Info.Cp_boundary_fraction = Info.Cp_boundary_count / max(Info.N_valid,1);

fprintf('Total points             : %d\n', Info.N_total);
fprintf('Valid / invalid          : %d / %d\n', Info.N_valid, Info.N_invalid);
fprintf('Split total T/V/Test     : %d / %d / %d\n', Info.N_train, Info.N_validation, Info.N_test);
fprintf('Valid split T/V/Test     : %d / %d / %d\n', Info.N_valid_train, Info.N_valid_validation, Info.N_valid_test);
fprintf('Invalid split T/V/Test   : %d / %d / %d\n', Info.N_invalid_train, Info.N_invalid_validation, Info.N_invalid_test);
fprintf('Cp=500 active valid      : %d / %d (%.1f %%)\n', Info.Cp_boundary_count, Info.N_valid, 100*Info.Cp_boundary_fraction);
for i = 1:numel(requiredFcn)
    fprintf('%-24s: OK  (%s)\n', requiredFcn{i}, fcnInfo(i));
end
fprintf('ANN TRAINING PREFLIGHT   : PASS\n');
fprintf('============================================================\n\n');
end
