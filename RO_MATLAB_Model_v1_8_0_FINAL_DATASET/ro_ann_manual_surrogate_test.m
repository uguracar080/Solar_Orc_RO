%% RO_ANN_MANUAL_SURROGATE_TEST
% Standalone manual RO ANN surrogate test.
%
% This script does not retrain the ANN, run the detailed RO truth model, or
% call any system driver. It only loads the frozen ANN model file and calls
% the existing deployment wrapper ro_predict_ann_surrogate_v1_9_1.m with
% the manually entered operating points below. No result or figure file is
% saved.

clearvars
clc

%% Manual inputs
script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);

manual = struct();
manual.model_file = fullfile(script_dir,'RO_ANN_models_v1_9_1.mat');
manual.open_figure = true;

% Single manual operating limits.
% Final deployment domain enforced by ro_predict_ann_surrogate_v1_9_1:
%   Qf_train_m3h : 47.5 to 63.0
%   T_RO_in_C    : 20.0 to 45.0
%   Cf_kg_m3     : 38.5 to 41.5
%   R_target     : 0.399 to 0.571
manual.Qf_train_m3h = 53.0;
manual.T_RO_in_C = 30.0;
manual.Cf_kg_m3 = 39.5;
manual.R_target = 0.54;

%% Run ANN surrogate
ROManualTimer = tic;

if ~isfile(manual.model_file)
    error('roAnnManual:ModelFileMissing', ...
        'ANN model file was not found: %s',manual.model_file);
end

ROAnnManualResults = ro_predict_ann_surrogate_v1_9_1( ...
    manual.model_file, ...
    manual.Qf_train_m3h, ...
    manual.T_RO_in_C, ...
    manual.Cf_kg_m3, ...
    manual.R_target);

ROAnnManualTiming = struct();
ROAnnManualTiming.total_s = toc(ROManualTimer);
ROAnnManualTiming.n_cases = height(ROAnnManualResults);
ROAnnManualTiming.seconds_per_case = ...
    ROAnnManualTiming.total_s/max(ROAnnManualTiming.n_cases,1);

ROAnnManualSummary = ROAnnManualResults;
ROAnnManualSummary.case_id = (1:height(ROAnnManualSummary)).';
ROAnnManualSummary = movevars(ROAnnManualSummary,'case_id','Before',1);

localPrintSummary(ROAnnManualSummary,manual,ROAnnManualTiming);

if manual.open_figure
    localPlotManualAnnResults(ROAnnManualSummary,manual);
end

%% Local functions
function localPrintSummary(results,manual,timing)
fprintf('\nManual RO ANN surrogate test\n');
fprintf('Model file        : %s\n',manual.model_file);
fprintf('Cases             : %d\n',height(results));
fprintf('In domain         : %d / %d\n',nnz(results.InTrainingDomain),height(results));
fprintf('Feasible          : %d / %d\n',nnz(results.Feasible),height(results));

is_ok = results.Feasible;
if any(is_ok)
    fprintf('Mean Qp           : %.3f m3/h over feasible cases\n', ...
        mean(results.Qp_train_m3h(is_ok),'omitnan'));
    fprintf('Mean W_RO         : %.3f kW over feasible cases\n', ...
        mean(results.W_RO_train_kW(is_ok),'omitnan'));
    fprintf('Mean SEC          : %.4f kWh/m3 over feasible cases\n', ...
        mean(results.SEC_kWh_m3(is_ok),'omitnan'));
    fprintf('Mean Cp           : %.3f mg/L over feasible cases\n', ...
        mean(results.Cp_mg_L(is_ok),'omitnan'));
else
    fprintf('No manually entered case was feasible.\n');
end

fprintf('Elapsed time      : %.3f s  (%.6f s/case)\n', ...
    timing.total_s,timing.seconds_per_case);
fprintf('\nWorkspace outputs : ROAnnManualSummary, ROAnnManualResults, manual, ROAnnManualTiming\n');
end

function localPlotManualAnnResults(results,manual)
modelInfo = localLoadModelInfo(manual.model_file);

figure('Name','Manual RO ANN surrogate test','Color','w');
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

nexttile;
inputX = 1:4;
inputLeftVals = [results.Qf_train_m3h,results.T_RO_in_C,results.Cf_kg_m3];
yyaxis left;
bIn = bar(inputX(1:3),inputLeftVals,0.45);
grid on;
box on;
ylabel('Qf [m3/h], T [degC], Cf [kg/m3]');
localAddBarLabels(bIn,inputLeftVals,{'%.1f','%.1f','%.1f'});

yyaxis right;
bR = bar(inputX(4),results.R_target,0.45);
ylim([0 1]);
ylabel('Recovery [-]');
localAddBarLabels(bR,results.R_target,{'%.3f'});

set(gca,'XTick',inputX,'XTickLabel', ...
    {'Qf [m3/h]','T in [degC]','Cf [kg/m3]','R [-]'});
title('Manual ANN inputs');

nexttile;
domain = localDeploymentDomain();
domainVals = [ ...
    (results.Qf_train_m3h-domain.Qf_min)/(domain.Qf_max-domain.Qf_min), ...
    (results.T_RO_in_C-domain.T_min)/(domain.T_max-domain.T_min), ...
    (results.Cf_kg_m3-domain.Cf_min)/(domain.Cf_max-domain.Cf_min), ...
    (results.R_target-domain.R_min)/(domain.R_max-domain.R_min)];
b = bar(domainVals);
ylim([0 1]);
grid on;
box on;
set(gca,'XTickLabel',{'Qf','T','Cf','R'});
ylabel('Normalized position [-]');
title('Deployment-domain position');
localAddBarLabels(b,domainVals,{'%.2f','%.2f','%.2f','%.2f'});
statusText = sprintf('P feasible = %.3f, threshold = %.3f', ...
    results.P_feasible,modelInfo.feasibility_threshold);
text(0.03,0.92,statusText,'Units','normalized','FontWeight','bold', ...
    'BackgroundColor','w','EdgeColor',[0.5 0.5 0.5],'Margin',6);

nexttile;
outputX = 1:4;
outputLeftVals = [results.Qp_train_m3h,results.W_RO_train_kW,results.SEC_kWh_m3];
yyaxis left;
bOut = bar(outputX(1:3),outputLeftVals,0.45);
grid on;
box on;
ylabel('Qp [m3/h], W [kW], SEC [kWh/m3]');
localAddBarLabels(bOut,outputLeftVals,{'%.2f','%.1f','%.3f'});

yyaxis right;
bCp = bar(outputX(4),results.Cp_mg_L,0.45);
ylabel('Cp [mg/L]');
localAddBarLabels(bCp,results.Cp_mg_L,{'%.1f'});

set(gca,'XTick',outputX,'XTickLabel', ...
    {'Qp [m3/h]','W RO [kW]','SEC [kWh/m3]','Cp [mg/L]'});
title('ANN performance outputs');

nexttile;
pressureVals = [results.P1_opt_gauge_MPa,results.P2_opt_gauge_MPa];
b = bar(pressureVals);
grid on;
box on;
set(gca,'XTickLabel',{'P1 opt','P2 opt'});
ylabel('Gauge pressure [MPa]');
title('Optimized RO pressures');
localAddBarLabels(b,pressureVals,{'%.3f','%.3f'});

drawnow;
end

function modelInfo = localLoadModelInfo(model_file)
S = load(model_file,'Models');
modelInfo = struct();
modelInfo.feasibility_threshold = S.Models.Feasibility.Threshold;
end

function domain = localDeploymentDomain()
domain = struct();
domain.Qf_min = 47.5;
domain.Qf_max = 63.0;
domain.T_min = 20.0;
domain.T_max = 45.0;
domain.Cf_min = 38.5;
domain.Cf_max = 41.5;
domain.R_min = 0.399;
domain.R_max = 0.571;
end

function localAddBarLabels(barHandle,values,fmts)
x = barHandle.XEndPoints;
y = barHandle.YEndPoints;
labels = strings(numel(values),1);
for i = 1:numel(values)
    labels(i) = compose(fmts{i},values(i));
end
for i = 1:numel(values)
    if isfinite(values(i))
        text(x(i),y(i),labels(i),'HorizontalAlignment','center', ...
            'VerticalAlignment','bottom','FontSize',9);
    end
end
end
