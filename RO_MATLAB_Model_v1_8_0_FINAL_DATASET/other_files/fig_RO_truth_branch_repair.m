function fig_RO_truth_branch_repair(scanFile, summaryFile)
%FIG_RO_TRUTH_BRANCH_REPAIR Optional supplementary figure for truth-model QA.
% Expected inputs:
%   RO_ANN_truth_branch_repair_scan.csv
%   RO_ANN_truth_branch_repair_summary.csv
% The figure documents the recovery-manifold power search used to repair the
% three confirmed local-branch optimizer solutions.

%% INPUT
if nargin < 1 || strlength(string(scanFile)) == 0
    scanFile = 'RO_ANN_truth_branch_repair_scan.csv';
end
if nargin < 2 || strlength(string(summaryFile)) == 0
    summaryFile = 'RO_ANN_truth_branch_repair_summary.csv';
end
if ~isfile(scanFile), error('Repair scan file not found: %s',scanFile); end
if ~isfile(summaryFile), error('Repair summary file not found: %s',summaryFile); end

%% LOAD
S = readtable(scanFile,'TextType','string');
R = readtable(summaryFile,'TextType','string');
ids = R.DOE_ID(:).';

%% OUTPUT FOLDER
scriptDir = fileparts(which(mfilename));
if isempty(scriptDir), scriptDir = pwd; end
outDir = fullfile(scriptDir,'figures');
if ~exist(outDir,'dir'), mkdir(outDir); end

%% FIGURE
f = figure('Color','w','Units','centimeters','Position',[2 2 18.0 6.8]);
tl = tiledlayout(f,1,numel(ids),'TileSpacing','compact','Padding','compact');
set(f,'DefaultAxesFontName','Times New Roman');
set(f,'DefaultAxesFontSize',9.0);

for i = 1:numel(ids)
    id = ids(i);
    ax = nexttile(tl,i);
    mask = S.DOE_ID == id & S.TargetMet == 1 & S.PhysicalFeasible == 1 & isfinite(S.W_kW);
    X = S.P1_MPa(mask);
    Y = S.W_kW(mask);
    [X,ord] = sort(X);
    Y = Y(ord);
    hold(ax,'on');
    scatter(ax,X,Y,13,'filled','MarkerFaceAlpha',0.35,'MarkerEdgeAlpha',0.45);
    rr = R(R.DOE_ID==id,:);
    scatter(ax,rr.Old_P1_MPa,rr.Old_W_kW,62,'x','LineWidth',1.6);
    scatter(ax,rr.New_P1_MPa,rr.New_W_kW,70,'p','filled','LineWidth',1.0);
    xlabel(ax,'P_1 (MPa(g))');
    ylabel(ax,'W_{RO} (kW)');
    grid(ax,'on'); box(ax,'on');
    title(ax,sprintf('DOE %d',id));
    text(ax,0.04,0.96,sprintf('Power reduction = %.2f%%',rr.PowerReduction_pct), ...
        'Units','normalized','VerticalAlignment','top','BackgroundColor','w','Margin',2, ...
        'FontName','Times New Roman','FontSize',8.2);
    if i == 1
        legend(ax,{'Recovery-manifold evaluations','Original local solution','Repaired optimum'}, ...
            'Location','best','Box','off');
    end
end

title(tl,'Targeted recovery-manifold repair of three local optimizer branches', ...
    'FontName','Times New Roman','FontSize',11,'FontWeight','bold');

%% EXPORT
pdfFile = fullfile(outDir,'Fig_S_ANN_truth_branch_repair.pdf');
pngFile = fullfile(outDir,'Fig_S_ANN_truth_branch_repair.png');
exportgraphics(f,pdfFile,'ContentType','vector');
exportgraphics(f,pngFile,'Resolution',600);
fprintf('Saved:\n  %s\n  %s\n',pdfFile,pngFile);
end
