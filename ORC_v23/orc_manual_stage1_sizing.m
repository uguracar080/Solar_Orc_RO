%% ORC_MANUAL_STAGE1_SIZING
% Standalone manual ORC Stage-1 sizing analysis.
%
% This script does not call the system driver, solar field, cooling tower,
% storage, RO, or weather readers. It only uses the ORC_v23 model functions
% in this folder with the manually entered design-point boundary conditions
% below. No result or figure file is saved.

clear all
clc

%% Manual inputs
script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);

manual = struct();
manual.reset_property_cache = true;
manual.run_stage2_design_point_check = true;
manual.open_figure = true;

% ORC working fluid and cycle sizing target.
manual.orc_fluid = 'R1233zd(E)';
manual.orc_W_nom_W = 250e3;              % Net ORC power target [W]
manual.orc_P_evap_des_Pa = 10.7e5;       % Evaporator outlet / turbine inlet pressure [Pa]
manual.orc_P_cond_des_Pa = 1.2e5;        % Condenser outlet / pump inlet pressure [Pa]

% Manual evaporator hot-stream boundary condition.
manual.hot_fluid = 'Water';
manual.hot_T_in_C = 120.0;
manual.hot_P_in_Pa = 10e5;
manual.hot_mdot_kg_s = 30.0;

% Manual condenser cooling-stream boundary condition.
manual.cold_fluid = 'Water';
manual.cold_T_in_C = 15.0;
manual.cold_P_in_Pa = 2e5;
manual.cold_mdot_kg_s = 100.0;

% Optional model switches for this standalone test.
manual.use_hydraulic_feedback = true;
manual.stage2_use_hydraulic_feedback = true;

%% Model setup
ORCManualTimer = tic;

config = struct();
config.orc_fluid = manual.orc_fluid;
config.orc_stage1_useHydraulicFeedback = manual.use_hydraulic_feedback;
config.orc_stage2_useHydraulicFeedback = manual.stage2_use_hydraulic_feedback;
config.orc_stage2_progressEnabled = false;
config.orc_stage2_printSummary = false;
config = orc_default_config(config);

if config.orc_property_cache_enabled && manual.reset_property_cache
    orc_properties(config,'CACHERESET');
end

systemInput = struct();
systemInput.orc_W_nom = manual.orc_W_nom_W;
systemInput.orc_P_evap_des = manual.orc_P_evap_des_Pa;
systemInput.orc_P_cond_des = manual.orc_P_cond_des_Pa;

orcHotStream = struct();
orcHotStream.fluid = manual.hot_fluid;
orcHotStream.T_in = manual.hot_T_in_C + 273.15;
orcHotStream.P_in = manual.hot_P_in_Pa;
orcHotStream.mdot = manual.hot_mdot_kg_s;

orcColdStream = struct();
orcColdStream.fluid = manual.cold_fluid;
orcColdStream.T_in = manual.cold_T_in_C + 273.15;
orcColdStream.P_in = manual.cold_P_in_Pa;
orcColdStream.mdot = manual.cold_mdot_kg_s;

%% Stage-1 sizing
ORCManualStage1Timer = tic;
orcDesign = orc_stage1_sizing(systemInput,orcHotStream,orcColdStream,config);
ORCManualTiming = struct();
ORCManualTiming.stage1_s = toc(ORCManualStage1Timer);

%% Optional fixed-geometry design-point rating check
orcStage2DesignPoint = struct();
ORCManualTiming.stage2_design_point_s = NaN;

if manual.run_stage2_design_point_check
    orcOperatingInput = struct();
    orcOperatingInput.orc_P_evap = orcDesign.orc_thermo.P_orcevap;
    orcOperatingInput.orc_P_cond = orcDesign.orc_thermo.P_orccond;
    orcOperatingInput.orc_mdot = orcDesign.orc_thermo.mdot_orc;

    ORCManualStage2Timer = tic;
    orcStage2DesignPoint = orc_offdesign_rating( ...
        orcDesign,orcHotStream,orcColdStream,orcOperatingInput,config);
    ORCManualTiming.stage2_design_point_s = toc(ORCManualStage2Timer);
end

ORCManualTiming.total_s = toc(ORCManualTimer);

%% Compact workspace summary
th = orcDesign.orc_thermo;
ev = orcDesign.orc_evaporator;
co = orcDesign.orc_condenser;

ORCManualSummary = table();
ORCManualSummary.orc_fluid = string(th.orc_fluid);
ORCManualSummary.W_net_kW = th.W_orcnet/1e3;
ORCManualSummary.W_turb_kW = th.W_orcturb/1e3;
ORCManualSummary.W_pump_kW = th.W_orcpump/1e3;
ORCManualSummary.Q_evap_kW = th.Q_orcevap/1e3;
ORCManualSummary.Q_cond_kW = th.Q_orccond/1e3;
ORCManualSummary.eta_th_pct = 100*th.eta_orc_th;
ORCManualSummary.mdot_orc_kg_s = th.mdot_orc;
ORCManualSummary.P_evap_bar = th.P_orcevap/1e5;
ORCManualSummary.P_cond_bar = th.P_orccond/1e5;
ORCManualSummary.T_turb_in_C = th.T_orcturb_in - 273.15;
ORCManualSummary.T_pump_in_C = th.T_orcpump_in - 273.15;
ORCManualSummary.hot_T_in_C = manual.hot_T_in_C;
ORCManualSummary.hot_mdot_kg_s = manual.hot_mdot_kg_s;
ORCManualSummary.cold_T_in_C = manual.cold_T_in_C;
ORCManualSummary.cold_mdot_kg_s = manual.cold_mdot_kg_s;
ORCManualSummary.evap_modules = ev.N_parallel_installed;
ORCManualSummary.cond_modules = co.N_parallel_installed;
ORCManualSummary.evap_area_margin_pct = 100*ev.module.areaMargin;
ORCManualSummary.cond_area_margin_pct = 100*co.module.areaMargin;
ORCManualSummary.evap_dp_wf_kPa = th.dp_orcevap_wf/1e3;
ORCManualSummary.cond_dp_wf_kPa = th.dp_orccond_wf/1e3;
ORCManualSummary.design_ok = logical(orcDesign.orc_designOK);
ORCManualSummary.stage1_time_s = ORCManualTiming.stage1_s;
ORCManualSummary.total_time_s = ORCManualTiming.total_s;

localPrintManualSummary(ORCManualSummary,orcDesign,orcStage2DesignPoint,manual,ORCManualTiming);

if manual.open_figure
    localPlotManualOrcSummary(ORCManualSummary,orcDesign,orcStage2DesignPoint,manual);
end

%% Local functions
function localPrintManualSummary(summary,orcDesign,orcStage2DesignPoint,manual,timing)
fprintf('\nManual ORC Stage-1 sizing analysis\n');
fprintf('Working fluid      : %s\n',summary.orc_fluid);
fprintf('Net power          : %.3f kW\n',summary.W_net_kW);
fprintf('Thermal efficiency : %.3f %%\n',summary.eta_th_pct);
fprintf('Evaporator duty    : %.3f kW\n',summary.Q_evap_kW);
fprintf('Condenser duty     : %.3f kW\n',summary.Q_cond_kW);
fprintf('ORC mass flow      : %.5f kg/s\n',summary.mdot_orc_kg_s);
fprintf('P evap / cond      : %.3f / %.3f bar\n',summary.P_evap_bar,summary.P_cond_bar);
fprintf('Hot stream         : %.2f C, %.3f kg/s\n',summary.hot_T_in_C,summary.hot_mdot_kg_s);
fprintf('Cold stream        : %.2f C, %.3f kg/s\n',summary.cold_T_in_C,summary.cold_mdot_kg_s);
fprintf('Evap modules       : %d\n',summary.evap_modules);
fprintf('Cond modules       : %d\n',summary.cond_modules);
fprintf('Design feasible    : %d\n',summary.design_ok);

if manual.run_stage2_design_point_check
    fprintf('\nFixed-geometry design-point check\n');
    fprintf('Status             : %s\n',orcStage2DesignPoint.orc_status);
    fprintf('Feasible           : %d\n',orcStage2DesignPoint.orc_feasible);
    fprintf('W net              : %.3f kW\n',orcStage2DesignPoint.orc_thermo.W_orcnet/1e3);
    fprintf('Evap A ratio       : %.4f\n',orcStage2DesignPoint.orc_evaporator_rate.A_ratio);
    fprintf('Cond A ratio       : %.4f\n',orcStage2DesignPoint.orc_condenser_rate.A_ratio);
    fprintf('Hydraulic conv.    : %d\n',orcStage2DesignPoint.orc_hydraulicConverged);
end

fprintf('\nTiming\n');
fprintf('Stage-1 sizing     : %.3f s\n',timing.stage1_s);
if manual.run_stage2_design_point_check
    fprintf('Stage-2 check      : %.3f s\n',timing.stage2_design_point_s);
end
fprintf('Total elapsed      : %.3f s\n',timing.total_s);
fprintf('\nWorkspace outputs  : ORCManualSummary, orcDesign, orcStage2DesignPoint, config, manual, ORCManualTiming\n');

if isfield(orcDesign,'orc_flags')
    fprintf('Feasibility flags  : orcDesign.orc_flags\n');
end
end

function localPlotManualOrcSummary(summary,orcDesign,orcStage2DesignPoint,manual)
figure('Name','Manual ORC Stage-1 sizing','Color','w');
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

nexttile;
energyVals = [summary.Q_evap_kW,summary.W_net_kW,summary.Q_cond_kW];
b = bar(energyVals);
grid on;
box on;
set(gca,'XTickLabel',{'Q evap','W net','Q cond'});
ylabel('kW');
title('Cycle energy rates');
localAddBarLabels(b,energyVals,'%.1f');
text(0.03,0.92,sprintf('\\eta_{th} = %.2f %%',summary.eta_th_pct), ...
    'Units','normalized','FontWeight','bold','BackgroundColor','w', ...
    'EdgeColor',[0.5 0.5 0.5],'Margin',6);

nexttile;
pressureX = 1:2;
pressureVals = [summary.P_evap_bar,summary.P_cond_bar];
satTempVals = [summary.T_turb_in_C,summary.T_pump_in_C];
yyaxis left;
bP = bar(pressureX-0.16,pressureVals,0.30);
grid on;
box on;
set(gca,'XTick',pressureX,'XTickLabel',{'Evap','Cond'});
ylabel('bar');
localAddBarLabelsAtX(pressureX-0.16,pressureVals,'%.2f');

yyaxis right;
bT = bar(pressureX+0.16,satTempVals,0.30);
ylabel('degC');
localAddBarLabelsAtX(pressureX+0.16,satTempVals,'%.1f');
title('Cycle pressure and phase-change temperature');
legend([bP,bT],{'Pressure','Phase-change temp'},'Location','best');

nexttile;
tempVals = [summary.hot_T_in_C,summary.cold_T_in_C];
b = bar(tempVals);
grid on;
box on;
set(gca,'XTickLabel',{'Hot in','Cold in'});
ylabel('degC');
title('Manual stream temperatures');
localAddBarLabels(b,tempVals,'%.1f');

nexttile;
evGeom = orcDesign.orc_evaporator.module.geometry;
coGeom = orcDesign.orc_condenser.module.geometry;
x = 1:2;
tubeCountVals = [evGeom.Nt,coGeom.Nt];
tubeLengthVals = [evGeom.Ltube,coGeom.Ltube];
shellDiameterVals = [evGeom.Dshell,coGeom.Dshell];

yyaxis left;
bNt = bar(x-0.22,tubeCountVals,0.24);
ylabel('Tube count [-]');
localAddBarLabelsAtX(x-0.22,tubeCountVals,'%.0f');

yyaxis right;
bLt = bar(x+0.05,tubeLengthVals,0.24);
hold on;
bDs = bar(x+0.32,shellDiameterVals,0.24);
ylabel('Length / diameter [m]');
localAddBarLabelsAtX(x+0.05,tubeLengthVals,'%.2f');
localAddBarLabelsAtX(x+0.32,shellDiameterVals,'%.3f');

set(gca,'XTick',x,'XTickLabel',{'Evap','Cond'});
title('STHE geometry');
legend([bNt,bLt,bDs],{'Tube count','Tube length','Shell diameter'},'Location','best');
grid on;
box on;
areaText = sprintf('A_{evap,total} = %.1f m^2\nA_{cond,total} = %.1f m^2', ...
    orcDesign.orc_evaporator.total.A_total, ...
    orcDesign.orc_condenser.total.A_total);
text(0.03,0.92,areaText,'Units','normalized','FontWeight','bold', ...
    'BackgroundColor','w','EdgeColor',[0.5 0.5 0.5],'Margin',6);

drawnow;
end

function localAddBarLabels(barHandle,values,fmt)
x = barHandle.XEndPoints;
y = barHandle.YEndPoints;
labels = compose(fmt,values);
text(x,y,labels,'HorizontalAlignment','center', ...
    'VerticalAlignment','bottom','FontSize',9);
end

function localAddBarLabelsAtX(x,values,fmt)
labels = compose(fmt,values);
text(x,values,labels,'HorizontalAlignment','center', ...
    'VerticalAlignment','bottom','FontSize',9);
end
