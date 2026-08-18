function fig_RO_ANN_classifier_performance(predictionFile, threshold)
%FIG_RO_ANN_CLASSIFIER_PERFORMANCE ROC and confusion matrix for feasibility ANN.
% Expected input: RO_ANN_blind_test_predictions_v1_9_1.csv
% The default operating threshold is the final v1.9.1 value, 0.80.

%% INPUT
if nargin < 1 || strlength(string(predictionFile)) == 0
    predictionFile = 'RO_ANN_blind_test_predictions_v1_9_1.csv';
end
if nargin < 2 || isempty(threshold)
    threshold = 0.80;
end
if ~isfile(predictionFile)
    error('Prediction file not found: %s', predictionFile);
end

%% LOAD TEST LABELS AND SCORES
P = readtable(predictionFile, 'TextType', 'string');
y = double(P.DatasetValid == 1);
p = double(P.Pvalid);
yhat = double(p >= threshold);

%% CONFUSION COUNTS
TP = sum(y==1 & yhat==1);
FN = sum(y==1 & yhat==0);
TN = sum(y==0 & yhat==0);
FP = sum(y==0 & yhat==1);
sens = TP / max(TP+FN,1);
spec = TN / max(TN+FP,1);
prec = TP / max(TP+FP,1);
f1 = 2*prec*sens / max(prec+sens,eps);
bal = 0.5*(sens+spec);

%% ROC CURVE (BASE-MATLAB IMPLEMENTATION)
% Sort classifier scores from high to low and accumulate positive/negative
% decisions. This avoids dependence on Statistics and Machine Learning Toolbox.
[~,ord] = sort(p,'descend');
ys = y(ord);
Npos = sum(ys==1);
Nneg = sum(ys==0);
tprSort = [0; cumsum(ys==1) ./ max(Npos,1)];
fprSort = [0; cumsum(ys==0) ./ max(Nneg,1)];
auc = trapz(fprSort,tprSort);
opFpr = 1-spec;
opTpr = sens;

%% OUTPUT FOLDER
scriptDir = fileparts(which(mfilename));
if isempty(scriptDir), scriptDir = pwd; end
outDir = fullfile(scriptDir, 'figures');
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% FIGURE SETUP
f = figure('Color','w','Units','centimeters','Position',[2 2 18.0 8.6]);
tl = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
set(f,'DefaultAxesFontName','Times New Roman');
set(f,'DefaultAxesFontSize',9.5);

%% (a) ROC
ax1 = nexttile(tl,1);
hold(ax1,'on');
plot(ax1, fprSort, tprSort, 'LineWidth',1.5);
plot(ax1, [0 1], [0 1], '--', 'LineWidth',1.0);
scatter(ax1, opFpr, opTpr, 48, 'filled');
xlim(ax1,[0 1]); ylim(ax1,[0 1]);
axis(ax1,'square'); grid(ax1,'on'); box(ax1,'on');
xlabel(ax1,'False-positive rate (1 - specificity)');
ylabel(ax1,'True-positive rate (sensitivity)');
title(ax1,'(a) Feasibility classifier ROC');
text(ax1,0.05,0.95,sprintf('AUC = %.3f\nThreshold = %.2f\nSensitivity = %.3f\nSpecificity = %.3f', ...
    auc, threshold, sens, spec), 'Units','normalized', ...
    'VerticalAlignment','top','BackgroundColor','w','Margin',3, ...
    'FontName','Times New Roman','FontSize',8.5);

%% (b) CONFUSION MATRIX
ax2 = nexttile(tl,2);
M = [TN FP; FN TP];
imagesc(ax2,M);
axis(ax2,'equal'); axis(ax2,'tight');
set(ax2,'XTick',1:2,'XTickLabel',{'Pred. invalid','Pred. valid'}, ...
        'YTick',1:2,'YTickLabel',{'True invalid','True valid'}, ...
        'YDir','normal');
xlabel(ax2,'Predicted class');
ylabel(ax2,'True class');
title(ax2,'(b) Test-set confusion matrix');
colorbar(ax2);
for r = 1:2
    for c = 1:2
        text(ax2,c,r,sprintf('%d',M(r,c)), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontWeight','bold','FontName','Times New Roman','FontSize',11, ...
            'Color','k','BackgroundColor','w','Margin',2);
    end
end
text(ax2,0.02,-0.18,sprintf('Balanced accuracy = %.3f; Precision = %.3f; F1 = %.3f',bal,prec,f1), ...
    'Units','normalized','FontName','Times New Roman','FontSize',8.5);

title(tl,'Final feasibility classifier on the preassigned test partition', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');

%% EXPORT
pdfFile = fullfile(outDir,'Fig_ANN3_classifier_performance.pdf');
pngFile = fullfile(outDir,'Fig_ANN3_classifier_performance.png');
exportgraphics(f,pdfFile,'ContentType','vector');
exportgraphics(f,pngFile,'Resolution',600);
fprintf('Saved:\n  %s\n  %s\n',pdfFile,pngFile);
end
