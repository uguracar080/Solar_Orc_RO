function Out = ro_predict_ann_surrogate_v1_9_0(ModelFile, Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target)
% Predicts the v1.9.0 RO surrogate for scalar or equal-size vector inputs.
% Feasibility is evaluated first. Performance outputs are NaN when rejected.

if nargin < 1 || strlength(string(ModelFile)) == 0
    ModelFile = 'RO_ANN_models_v1_9_0.mat';
end
S = load(ModelFile,'Models'); Models=S.Models;

Qf=double(Qf_train_m3h(:)); T=double(T_RO_in_C(:)); Cf=double(Cf_kg_m3(:)); R=double(R_target(:));
n=max([numel(Qf),numel(T),numel(Cf),numel(R)]);
Qf=expand_scalar(Qf,n); T=expand_scalar(T,n); Cf=expand_scalar(Cf,n); R=expand_scalar(R,n);
X=[Qf,T,Cf,R];

pValid=classifier_probability_local(Models.Feasibility,X);
Feasible=pValid>=Models.Feasibility.Threshold;

W=regressor_predict_local(Models.Regressors.W_RO_train_kW,X);
P1=regressor_predict_local(Models.Regressors.P1_opt_gauge_MPa,X);
P2=regressor_predict_local(Models.Regressors.P2_opt_gauge_MPa,X);

pCpActive=classifier_probability_local(Models.Cp.ActiveClassifier,X);
margin=max(0.0,regressor_predict_local(Models.Cp.MarginRegressor,X));
Cp=Models.Cp.CpLimit_mgL-margin;
Cp(pCpActive>=Models.Cp.SwitchThreshold)=Models.Cp.CpLimit_mgL;
Cp=min(Models.Cp.CpLimit_mgL,max(0.0,Cp));

Qp=Qf.*R;
SEC=W./Qp;

W(~Feasible)=NaN; P1(~Feasible)=NaN; P2(~Feasible)=NaN; Cp(~Feasible)=NaN; Qp(~Feasible)=NaN; SEC(~Feasible)=NaN;
Out=table(Qf,T,Cf,R,pValid,Feasible,Qp,W,SEC,Cp,P1,P2,pCpActive, ...
    'VariableNames',{'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target','P_feasible','Feasible', ...
    'Qp_train_m3h','W_RO_train_kW','SEC_kWh_m3','Cp_mg_L','P1_opt_gauge_MPa','P2_opt_gauge_MPa','P_CpBoundary'});
end

function v=expand_scalar(v,n)
if numel(v)==1, v=repmat(v,n,1); elseif numel(v)~=n, error('Inputs scalar veya ayni uzunlukta vector olmalidir.'); end
end
function p=classifier_probability_local(M,X)
Xn=(double(X)-M.MuX)./M.SigX; Y=M.Net(Xn.'); p=double(Y(2,:).');
end
function y=regressor_predict_local(M,X)
Xn=(double(X)-M.MuX)./M.SigX; y=(M.Net(Xn.').' .* M.SigY)+M.MuY; y=double(y(:));
end
