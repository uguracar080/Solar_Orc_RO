function pngFile = fig_status_counts_v1(Hourly,~,~,outDir)
%FIG_STATUS_COUNTS_V1 Save top-level system-status count figure.

status = string(Hourly.system_status);
values = unique(status);
counts = zeros(numel(values),1);
for i = 1:numel(values)
    counts(i) = sum(status == values(i));
end

fig = figure('Visible','off','Color','w','Name','V1 status counts');
ax = axes(fig);
bar(ax,counts);
grid(ax,'on');
set(ax,'XTick',1:numel(values),'XTickLabel',cellstr(values));
xtickangle(ax,25);
ylabel(ax,'Number of steps');
title(ax,'System status counts');
pngFile = localSaveFigure(fig,outDir,'status_counts_v1');
close(fig);
end

function pngFile = localSaveFigure(fig,outDir,baseName)
pngFile = fullfile(outDir,[baseName '.png']);
figFile = fullfile(outDir,[baseName '.fig']);
try
    exportgraphics(fig,pngFile,'Resolution',180);
catch
    saveas(fig,pngFile);
end
savefig(fig,figFile);
end
