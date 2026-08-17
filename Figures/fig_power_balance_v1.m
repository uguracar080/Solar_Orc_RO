function pngFile = fig_power_balance_v1(Hourly,~,~,outDir)
%FIG_POWER_BALANCE_V1 Save ORC, RO, and cooling-tower power figure.

fig = figure('Visible','off','Color','w','Name','V1 power balance');
ax = axes(fig);
hold(ax,'on');
plot(ax,Hourly.source_hour,Hourly.W_ORC_net_W/1000,'-o','LineWidth',1.4,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.W_available_for_RO_W/1000,'-s','LineWidth',1.2,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.W_RO_total_W/1000,'-^','LineWidth',1.2,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.W_CT_fan_W/1000,'-d','LineWidth',1.0,'MarkerSize',5);
grid(ax,'on');
xlabel(ax,'Source hour');
ylabel(ax,'Power (kW)');
title(ax,'Power balance');
legend(ax,{'ORC net','Available for RO','RO demand','CT fan'},'Location','best');
pngFile = localSaveFigure(fig,outDir,'power_balance_v1');
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
