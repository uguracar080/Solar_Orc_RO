function fig_RO_ANN_blind_parity(predictionFile)
%FIG_RO_ANN_BLIND_PARITY Parity plots for final RO ANN surrogate.
% Expected input: RO_ANN_blind_test_predictions_v1_9_1.csv
% Only truth-valid rows in the preassigned test partition are plotted.
% Four ANN-predicted quantities are shown: RO power, P1*, P2*, and Cp.

%% INPUT
if nargin < 1 || strlength(string(predictionFile)) == 0
    predictionFile = 'RO_ANN_blind_test_predictions_v1_9_1.csv';
end
if ~isfile(predictionFile)
    error('Prediction file not found: %s', predictionFile);
end

%% LOAD DATA
P = readtable(predictionFile, 'TextType', 'string');
mask = P.DatasetValid == 1 & isfinite(P.W_true_kW) & isfinite(P.W_pred_kW);
P = P(mask,:);

%% OUTPUT FOLDER
scriptDir = fileparts(which(mfilename));
if isempty(scriptDir), scriptDir = pwd; end
outDir = fullfile(scriptDir, 'figures');
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% FIGURE SETUP
f = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 18.0 15.0]);
tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
set(f, 'DefaultAxesFontName', 'Times New Roman');
set(f, 'DefaultAxesFontSize', 9.5);

%% PANELS
ax1 = nexttile(tl,1);
parity_panel(ax1, P.W_true_kW, P.W_pred_kW, ...
    'High-fidelity W_{RO} (kW)', 'ANN W_{RO} (kW)', '(a) RO power');

ax2 = nexttile(tl,2);
parity_panel(ax2, P.P1_true_MPa, P.P1_pred_MPa, ...
    'High-fidelity P_1^* (MPa(g))', 'ANN P_1^* (MPa(g))', '(b) Stage-1 pressure');

ax3 = nexttile(tl,3);
parity_panel(ax3, P.P2_true_MPa, P.P2_pred_MPa, ...
    'High-fidelity P_2^* (MPa(g))', 'ANN P_2^* (MPa(g))', '(c) Stage-2 pressure');

ax4 = nexttile(tl,4);
parity_panel(ax4, P.Cp_true_mgL, P.Cp_pred_mgL, ...
    'High-fidelity C_p (mg L^{-1})', 'ANN C_p (mg L^{-1})', '(d) Product salinity');

title(tl, sprintf('RO ANN surrogate parity on the preassigned test set (n = %d valid points)', height(P)), ...
    'FontName', 'Times New Roman', 'FontSize', 11, 'FontWeight', 'bold');

%% EXPORT
pdfFile = fullfile(outDir, 'Fig_ANN2_blind_test_parity.pdf');
pngFile = fullfile(outDir, 'Fig_ANN2_blind_test_parity.png');
exportgraphics(f, pdfFile, 'ContentType', 'vector');
exportgraphics(f, pngFile, 'Resolution', 600);
fprintf('Saved:\n  %s\n  %s\n', pdfFile, pngFile);
end

function parity_panel(ax, y, yp, xlab, ylab, panelTitle)
% Draw one parity panel and calculate metrics directly from plotted data.
y = double(y(:));
yp = double(yp(:));
finite = isfinite(y) & isfinite(yp);
y = y(finite); yp = yp(finite);
err = yp - y;
rmse = sqrt(mean(err.^2));
mae = mean(abs(err));
den = sum((y - mean(y)).^2);
r2 = 1 - sum(err.^2) / max(den, eps);

lo = min([y; yp]);
hi = max([y; yp]);
span = hi - lo;
if span <= 0, span = max(abs(lo),1); end
pad = 0.04 * span;
lims = [lo-pad, hi+pad];

hold(ax,'on');
scatter(ax, y, yp, 18, 'filled', 'MarkerFaceAlpha', 0.42, 'MarkerEdgeAlpha', 0.55);
plot(ax, lims, lims, '--', 'LineWidth', 1.1);
xlim(ax, lims); ylim(ax, lims);
axis(ax, 'square');
grid(ax,'on'); box(ax,'on');
xlabel(ax, xlab, 'Interpreter', 'tex');
ylabel(ax, ylab, 'Interpreter', 'tex');
title(ax, panelTitle);
text(ax, 0.04, 0.96, sprintf('R^2 = %.6f\nRMSE = %.4g\nMAE = %.4g', r2, rmse, mae), ...
    'Units','normalized', 'HorizontalAlignment','left', 'VerticalAlignment','top', ...
    'FontName','Times New Roman', 'FontSize',8.5, 'BackgroundColor','w', 'Margin',3);
end
