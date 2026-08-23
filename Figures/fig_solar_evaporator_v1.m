function pngFile = fig_solar_evaporator_v1(Hourly,~,~,outDir)
%FIG_SOLAR_EVAPORATOR_V1 Save solar-field and ORC-evaporator diagnostic figure.

h = Hourly.source_hour;

fig = figure('Visible','off','Color','w','Name','V1 solar field and evaporator');
try
    fig.Position(3:4) = [1200 860];
catch
end

subplot(4,1,1);
yyaxis left;
plot(h,localColumn(Hourly,'DNI_Whm2') ,'-','LineWidth',1.2);
ylabel('DNI (W/m2)');
yyaxis right;
plot(h,localColumn(Hourly,'solar_flow_factor'),'-o','LineWidth',1.0,'MarkerSize',4);
ylabel('Flow factor (-)');
grid on;
title('Solar resource and flow control');
xlabel('Source hour');
legend({'DNI','Solar flow factor'},'Location','best');

subplot(4,1,2);
hold on;
plot(h,localColumn(Hourly,'Q_solar_useful_W')/1000,'-','LineWidth',1.3);
plot(h,localColumn(Hourly,'Q_ORC_evap_W')/1000,'--','LineWidth',1.3);
plot(h,localColumn(Hourly,'Q_solar_excess_W')/1000,':','LineWidth',1.2);
plot(h,localColumn(Hourly,'Q_solar_curtailed_W')/1000,'-.','LineWidth',1.1);
grid on;
ylabel('Heat rate (kW)');
title('Solar heat versus evaporator heat uptake');
xlabel('Source hour');
legend({'Solar useful','ORC evaporator','Solar excess','Solar curtailed'},'Location','best');

subplot(4,1,3);
hold on;
plot(h,localColumn(Hourly,'T_solar_loop_in_C'),'-','LineWidth',1.2);
plot(h,localColumn(Hourly,'T_solar_loop_out_C'),'-','LineWidth',1.2);
plot(h,localColumn(Hourly,'T_orc_hot_return_C'),'--','LineWidth',1.1);
try
    yline(400,'k:','400 degC','LineWidth',1.0);
catch
end
grid on;
ylabel('Temperature (degC)');
title('HTF temperatures around solar field and evaporator');
xlabel('Source hour');
legend({'Solar inlet','Solar outlet','Evaporator hot return','400 degC limit'},'Location','best');

subplot(4,1,4);
yyaxis left;
hold on;
plot(h,localColumn(Hourly,'dP_solar_field_Pa')/1000,'-','LineWidth',1.1);
plot(h,localColumn(Hourly,'dP_orc_evap_hot_Pa')/1000,'--','LineWidth',1.1);
plot(h,localColumn(Hourly,'dP_solar_loop_Pa')/1000,':','LineWidth',1.2);
ylabel('Pressure drop (kPa)');
yyaxis right;
plot(h,localColumn(Hourly,'W_solar_pump_W')/1000,'-o','LineWidth',1.0,'MarkerSize',4);
ylabel('Solar pump power (kW)');
grid on;
title('Solar-loop hydraulics');
xlabel('Source hour');
legend({'Solar field dP','Evaporator hot-side dP','Total solar-loop dP','Solar pump'},'Location','best');

pngFile = localSaveFigure(fig,outDir,'solar_evaporator_v1');
close(fig);
end

function values = localColumn(Hourly,name)
if istable(Hourly) && ismember(name,Hourly.Properties.VariableNames)
    values = Hourly.(name);
elseif isstruct(Hourly) && isfield(Hourly,name)
    values = Hourly.(name);
else
    values = nan(localNumRows(Hourly),1);
end
values = double(values);
end

function n = localNumRows(Hourly)
if istable(Hourly)
    n = height(Hourly);
elseif isstruct(Hourly)
    names = fieldnames(Hourly);
    if isempty(names)
        n = 0;
    else
        n = numel(Hourly.(names{1}));
    end
else
    n = 0;
end
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
