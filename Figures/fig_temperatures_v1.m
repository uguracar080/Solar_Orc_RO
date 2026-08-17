function pngFile = fig_temperatures_v1(Hourly,~,~,outDir)
%FIG_TEMPERATURES_V1 Save seawater, RO-feed, and condenser-loop temperatures.

fig = figure('Visible','off','Color','w','Name','V1 temperatures');
ax = axes(fig);
hold(ax,'on');
plot(ax,Hourly.source_hour,Hourly.T_sw_raw_C,'-o','LineWidth',1.3,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.T_RO_in_C,'-s','LineWidth',1.3,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.T_cw_cond_out_C,'-^','LineWidth',1.1,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.T_cw_after_preheater_C,'-d','LineWidth',1.1,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.T_amb_C,'-v','LineWidth',1.0,'MarkerSize',5);
plot(ax,Hourly.source_hour,Hourly.T_wb_C,'-x','LineWidth',1.0,'MarkerSize',6);
grid(ax,'on');
xlabel(ax,'Source hour');
ylabel(ax,'Temperature (degC)');
title(ax,'System temperatures');
legend(ax,{'Raw seawater','RO inlet','CW after condenser','CW after preheater','Ambient DB','Ambient WB'}, ...
    'Location','best');
pngFile = localSaveFigure(fig,outDir,'temperatures_v1');
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
