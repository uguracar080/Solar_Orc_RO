function Out = ro_predict_ann_surrogate_v1_9_1(ModelFile, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target)
%RO_PREDICT_ANN_SURROGATE_V1_9_1 Predict final RO ANN surrogate outputs.
%
% Inputs may be scalars or equal-length vectors.
% The deployment wrapper does not allow extrapolation outside the final DOE
% domain used for ANN/classifier development. Points outside that domain are
% returned as Feasible=false and all performance outputs are NaN.
%
% Final v1.9.1 input DOE domain:
%   Qf_train : 47.5 to 63.0 m3/h
%   T_RO_in  : 20.0 to 45.0 degC
%   Cf       : 38.5 to 41.5 kg/m3
%   R_target : 0.399 to 0.571
%
% Feasibility is evaluated first using the threshold stored in the trained
% model file. Qp and SEC are then calculated from physical identities rather
% than learned as independent ANN outputs.

if nargin < 1 || strlength(string(ModelFile)) == 0
    ModelFile = 'RO_ANN_models_v1_9_1.mat';
end

S = load(ModelFile,'Models');
Models = S.Models;

Qf = double(Qf_train_m3h(:));
T  = double(T_RO_in_C(:));
Cf = double(Cf_kg_m3(:));
R  = double(R_target(:));

n = max([numel(Qf),numel(T),numel(Cf),numel(R)]);
Qf = expand_scalar(Qf,n);
T  = expand_scalar(T,n);
Cf = expand_scalar(Cf,n);
R  = expand_scalar(R,n);
X  = [Qf,T,Cf,R];

%% Final DOE-domain guard: do not permit ANN extrapolation
Domain.Qf_min = 47.5;
Domain.Qf_max = 63.0;
Domain.T_min  = 20.0;
Domain.T_max  = 45.0;
Domain.Cf_min = 38.5;
Domain.Cf_max = 41.5;
Domain.R_min  = 0.399;
Domain.R_max  = 0.571;

InTrainingDomain = ...
    Qf >= Domain.Qf_min & Qf <= Domain.Qf_max & ...
    T  >= Domain.T_min  & T  <= Domain.T_max  & ...
    Cf >= Domain.Cf_min & Cf <= Domain.Cf_max & ...
    R  >= Domain.R_min  & R  <= Domain.R_max;

%% Feasibility classifier
pValid = classifier_probability_local(Models.Feasibility,X);
ClassifierFeasible = pValid >= Models.Feasibility.Threshold;
Feasible = InTrainingDomain & ClassifierFeasible;

%% Performance regressors
W  = regressor_predict_local(Models.Regressors.W_RO_train_kW,X);
P1 = regressor_predict_local(Models.Regressors.P1_opt_gauge_MPa,X);
P2 = regressor_predict_local(Models.Regressors.P2_opt_gauge_MPa,X);

%% Hybrid product-salinity prediction
pCpActive = classifier_probability_local(Models.Cp.ActiveClassifier,X);
margin = max(0.0,regressor_predict_local(Models.Cp.MarginRegressor,X));
Cp = Models.Cp.CpLimit_mgL - margin;
Cp(pCpActive >= Models.Cp.SwitchThreshold) = Models.Cp.CpLimit_mgL;
Cp = min(Models.Cp.CpLimit_mgL,max(0.0,Cp));

%% Physics-derived outputs
Qp  = Qf .* R;
SEC = W ./ Qp;

%% Reject infeasible or out-of-domain points
W(~Feasible)   = NaN;
P1(~Feasible)  = NaN;
P2(~Feasible)  = NaN;
Cp(~Feasible)  = NaN;
Qp(~Feasible)  = NaN;
SEC(~Feasible) = NaN;

Out = table(Qf,T,Cf,R,InTrainingDomain,pValid,ClassifierFeasible,Feasible, ...
    Qp,W,SEC,Cp,P1,P2,pCpActive, ...
    'VariableNames',{'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
    'InTrainingDomain','P_feasible','ClassifierFeasible','Feasible', ...
    'Qp_train_m3h','W_RO_train_kW','SEC_kWh_m3','Cp_mg_L', ...
    'P1_opt_gauge_MPa','P2_opt_gauge_MPa','P_CpBoundary'});
end

function v = expand_scalar(v,n)
if numel(v)==1
    v = repmat(v,n,1);
elseif numel(v)~=n
    error('Inputs scalar veya ayni uzunlukta vector olmalidir.');
end
end

function p = classifier_probability_local(M,X)
Xn = (double(X)-M.MuX)./M.SigX;
Y = M.Net(Xn.');
p = double(Y(2,:).');
end

function y = regressor_predict_local(M,X)
Xn = (double(X)-M.MuX)./M.SigX;
y = (M.Net(Xn.').' .* M.SigY) + M.MuY;
y = double(y(:));
end
