function pngFile = fig_water_balance_v1(Hourly,~,cfg,outDir)
%FIG_WATER_BALANCE_V1 Save hourly and cumulative water-production figure.

dt_h = cfg.sim.dt_s/3600;
net_m3h = Hourly.Qp_total_m3h - Hourly.CT_makeup_m3h;
cumProduct = cumsum(Hourly.Qp_total_m3h)*dt_h;
cumMakeup = cumsum(Hourly.CT_makeup_m3h)*dt_h;
cumNet = cumsum(net_m3h)*dt_h;

fig = figure('Visible','off','Color','w','Name','V1 water balance');
subplot(2,1,1);
hold on;
plot(Hourly.source_hour,Hourly.Qp_total_m3h,'-','LineWidth',1.3);
plot(Hourly.source_hour,Hourly.CT_makeup_m3h,'-','LineWidth',1.1);
plot(Hourly.source_hour,net_m3h,'-','LineWidth',1.3);
grid on;
xlabel('Source hour');
ylabel('Water flow (m3/h)');
title('Hourly water balance');
legend({'RO product','CT makeup','Net product'},'Location','best');

subplot(2,1,2);
hold on;
plot(Hourly.source_hour,cumProduct,'-','LineWidth',1.3);
plot(Hourly.source_hour,cumMakeup,'-','LineWidth',1.1);
plot(Hourly.source_hour,cumNet,'-','LineWidth',1.3);
grid on;
xlabel('Source hour');
ylabel('Cumulative water (m3)');
title('Cumulative water balance');
legend({'RO product','CT makeup','Net product'},'Location','best');

pngFile = localSaveFigure(fig,outDir,'water_balance_v1');
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
