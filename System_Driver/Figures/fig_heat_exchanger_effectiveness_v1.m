function pngFile = fig_heat_exchanger_effectiveness_v1(Hourly,~,~,outDir)
%FIG_HEAT_EXCHANGER_EFFECTIVENESS_V1 Save heat-exchanger effectiveness figure.

h = localColumn(Hourly,'source_hour');
epsEvap = localColumn(Hourly,'effectiveness_evaporator');
epsCond = localColumn(Hourly,'effectiveness_condenser');
epsPH = localColumn(Hourly,'effectiveness_preheater');

fig = figure('Visible','off','Color','w','Name','V1 heat exchanger effectiveness');
try
    fig.Position(3:4) = [1200 650];
catch
end

ax = axes(fig);
hold(ax,'on');
plot(ax,h,epsEvap,'-','LineWidth',1.35);
plot(ax,h,epsCond,'-','LineWidth',1.35);
plot(ax,h,epsPH,'-','LineWidth',1.35);
grid(ax,'on');
xlabel(ax,'Source hour');
ylabel(ax,'Effectiveness (-)');
title(ax,'Heat exchanger effectiveness');
legend(ax,{'Evaporator','Condenser','Preheater'},'Location','best');

finiteVals = [epsEvap(:); epsCond(:); epsPH(:)];
finiteVals = finiteVals(isfinite(finiteVals));
if isempty(finiteVals) || (min(finiteVals) >= 0 && max(finiteVals) <= 1.05)
    ylim(ax,[0 1.05]);
end

pngFile = localSaveFigure(fig,outDir,'heat_exchanger_effectiveness_v1');
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
