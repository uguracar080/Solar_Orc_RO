function fig_RO_ANN_dataset_feasibility(dataFile)
%FIG_RO_ANN_DATASET_FEASIBILITY Publication figure for final RO-ANN DOE coverage.
% Expected input: RO_ANN_final_truth_dataset_corrected.csv
% The figure contains three input-space projections and the valid fraction
% of each guided-sampling stratum. Outputs are saved as vector PDF and
% 600-dpi PNG in a local "figures" folder.

%% INPUT
if nargin < 1 || strlength(string(dataFile)) == 0
    dataFile = 'RO_ANN_final_truth_dataset_corrected.csv';
end
if ~isfile(dataFile)
    error('Dataset file not found: %s', dataFile);
end

%% LOAD DATA
D = readtable(dataFile, 'TextType', 'string');
valid = D.DatasetValid == 1;
N = height(D);
Nvalid = sum(valid);

%% OUTPUT FOLDER
outDir = fullfile(fileparts(which(mfilename)), 'figures');
if strlength(string(fileparts(which(mfilename)))) == 0
    outDir = fullfile(pwd, 'figures');
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% FIGURE SETUP
f = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 18.0 14.5]);
tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
set(f, 'DefaultAxesFontName', 'Times New Roman');
set(f, 'DefaultAxesFontSize', 9.5);
C = lines(2);

%% (a) Qf - R
ax1 = nexttile(tl, 1);
plot_projection(ax1, D.Qf_train_m3h, D.R_target, valid, ...
    'Q_{f,train} (m^3 h^{-1})', 'R_{target}', C);
title(ax1, '(a) Feed flow - recovery');

%% (b) Temperature - R
ax2 = nexttile(tl, 2);
plot_projection(ax2, D.T_RO_in_C, D.R_target, valid, ...
    'T_{RO,in} (^{\circ}C)', 'R_{target}', C);
title(ax2, '(b) RO inlet temperature - recovery');

%% (c) Salinity - R
ax3 = nexttile(tl, 3);
plot_projection(ax3, D.Cf_kg_m3, D.R_target, valid, ...
    'C_f (kg m^{-3})', 'R_{target}', C);
title(ax3, '(c) Feed salinity - recovery');

%% (d) Valid fraction by guided-sampling stratum
ax4 = nexttile(tl, 4);
order = ["HighConfidenceCore", "ScoreBoundaryProbe", ...
         "LowTemperatureChallenge", "FlowEdgeChallenge"];
labels = ["Core", "Boundary", "Low-T", "Flow-edge"];
validPct = zeros(numel(order),1);
counts = zeros(numel(order),1);
validCounts = zeros(numel(order),1);
for i = 1:numel(order)
    mask = string(D.DOE_Type) == order(i);
    counts(i) = sum(mask);
    validCounts(i) = sum(valid(mask));
    validPct(i) = 100 * validCounts(i) / max(counts(i),1);
end
b = bar(ax4, categorical(labels, labels), validPct, 0.68);
b.FaceColor = 'flat';
for i = 1:numel(order)
    b.CData(i,:) = C(1,:);
end
ylim(ax4, [0 105]);
ylabel(ax4, 'Valid points (%)');
grid(ax4, 'on');
box(ax4, 'on');
title(ax4, '(d) Valid fraction by sampling stratum');
for i = 1:numel(order)
    text(ax4, i, validPct(i) + 2.0, ...
        sprintf('%.1f%%\n%d/%d', validPct(i), validCounts(i), counts(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontName', 'Times New Roman', 'FontSize', 8.5);
end

%% LEGEND AND TITLE
lg = legend(ax1, {'Infeasible', 'Feasible'}, 'Location', 'best');
lg.Box = 'off';
title(tl, sprintf('Final guided DOE: %d points, %d valid (%.1f%%)', ...
    N, Nvalid, 100*Nvalid/N), 'FontName', 'Times New Roman', ...
    'FontSize', 11, 'FontWeight', 'bold');

%% EXPORT
pdfFile = fullfile(outDir, 'Fig_ANN1_final_DOE_feasibility.pdf');
pngFile = fullfile(outDir, 'Fig_ANN1_final_DOE_feasibility.png');
exportgraphics(f, pdfFile, 'ContentType', 'vector');
exportgraphics(f, pngFile, 'Resolution', 600);
fprintf('Saved:\n  %s\n  %s\n', pdfFile, pngFile);
end

function plot_projection(ax, x, y, valid, xlab, ylab, C)
% Plot infeasible points first and feasible points on top.
hold(ax, 'on');
scatter(ax, x(~valid), y(~valid), 15, ...
    'Marker', 'o', 'MarkerEdgeColor', C(2,:), ...
    'LineWidth', 0.7, 'MarkerFaceColor', 'none');
scatter(ax, x(valid), y(valid), 16, ...
    'Marker', 'o', 'MarkerEdgeColor', C(1,:), ...
    'MarkerFaceColor', C(1,:), 'MarkerFaceAlpha', 0.32, ...
    'MarkerEdgeAlpha', 0.55);
xlabel(ax, xlab, 'Interpreter', 'tex');
ylabel(ax, ylab, 'Interpreter', 'tex');
grid(ax, 'on');
box(ax, 'on');
end
