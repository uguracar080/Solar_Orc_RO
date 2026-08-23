function [HourlyPartial,SummaryPartial,OutputFiles] = recover_partial_workspace_v1(partialMatFile,outputDir)
%RECOVER_PARTIAL_WORKSPACE_V1 Build hourly CSV outputs from a paused solver workspace.
%
% Usage:
%   recover_partial_workspace_v1("F:\...\Results\partial_workspace_hour_1504_20260823_120611.mat")

if nargin < 1 || isempty(partialMatFile)
    error('recover_partial_workspace_v1:MissingFile','partialMatFile is required.');
end
if nargin < 2 || isempty(outputDir)
    outputDir = fileparts(char(partialMatFile));
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

S = load(partialMatFile);
if isfield(S,'lastDone') && ~isempty(S.lastDone)
    lastDone = S.lastDone;
elseif isfield(S,'it') && ~isempty(S.it)
    lastDone = max(0,S.it - 1);
else
    lastDone = localInferLastDone(S);
end
lastDone = max(0,min(lastDone,numel(S.hour)));

if lastDone == 0
    error('recover_partial_workspace_v1:NoCompletedHours','No completed hourly rows were found.');
end

varNames = { ...
    'hour','source_hour','DNI_Whm2','T_amb_C','T_wb_C','T_sw_raw_C','Cf_kg_m3', ...
    'Q_solar_useful_W','Q_solar_excess_W','Q_solar_return_sink_W','Q_storage_charge_W','Q_solar_curtailed_W', ...
    'storage_SOC','storage_T_C','storage_E_stored_kWh','solar_flow_factor','solar_V_Lmin_1module', ...
    'W_solar_pump_W','dP_solar_field_Pa','dP_orc_evap_hot_Pa','dP_solar_loop_Pa', ...
    'T_solar_loop_in_C','T_solar_loop_out_C','T_orc_hot_return_raw_C','T_orc_hot_return_C', ...
    'W_ORC_net_W','Q_ORC_evap_W','Q_ORC_cond_W','P_ORC_evap_Pa','P_ORC_cond_Pa', ...
    'T_cw_loop_in_C','T_cw_cond_out_C','T_cw_cond_out_guard_C','T_cw_cond_out_guard_margin_K', ...
    'DeltaT_preheater_available_K','preheater_on','Q_preheater_W','T_RO_in_C','T_cw_after_preheater_C', ...
    'T_CT_out_C','W_CT_fan_W','Q_CT_rejected_W','CT_makeup_m3h','CT_mdot_makeup_kg_s', ...
    'W_available_for_RO_W','N_train_total','N_train_running','W_RO_total_W','Qp_total_m3h', ...
    'ORC_feasible','RO_feasible','coupling_converged','N_coupling_iter', ...
    'solar_loop_residual_K','cw_loop_residual_K', ...
    'solar_status','solar_flow_status','storage_status','orc_status','preheater_status','ct_status','ro_status','system_status'};

data = cell(1,numel(varNames));
for k = 1:numel(varNames)
    data{k} = localSlice(S,varNames{k},lastDone);
end
HourlyPartial = table(data{:},'VariableNames',varNames);
SummaryPartial = localSummarizePartial(HourlyPartial,S.cfg,NaN);
SummaryPartial.partial_source_file = string(partialMatFile);
SummaryPartial.completed_hours = lastDone;

[~,baseName] = fileparts(char(partialMatFile));
hourlyCsv = fullfile(outputDir,[baseName '_hourly.csv']);
summaryCsv = fullfile(outputDir,[baseName '_summary.csv']);
partialMat = fullfile(outputDir,[baseName '_recovered_outputs.mat']);

writetable(HourlyPartial,hourlyCsv);
writetable(SummaryPartial,summaryCsv);
save(partialMat,'HourlyPartial','SummaryPartial','partialMatFile','lastDone');

OutputFiles = struct();
OutputFiles.hourly_csv = hourlyCsv;
OutputFiles.summary_csv = summaryCsv;
OutputFiles.recovered_mat = partialMat;

fprintf('Recovered %d completed hourly rows.\n',lastDone);
fprintf('Hourly CSV : %s\n',hourlyCsv);
fprintf('Summary CSV: %s\n',summaryCsv);
fprintf('MAT output : %s\n',partialMat);
end

function value = localSlice(S,name,lastDone)
if ~isfield(S,name)
    error('recover_partial_workspace_v1:MissingVariable','Missing variable in partial workspace: %s',name);
end
value = S.(name);
if size(value,1) >= lastDone
    value = value(1:lastDone,:);
elseif size(value,2) >= lastDone
    value = value(:,1:lastDone).';
else
    error('recover_partial_workspace_v1:ShortVariable', ...
        'Variable %s has fewer than %d elements.',name,lastDone);
end
end

function lastDone = localInferLastDone(S)
if ~isfield(S,'system_status')
    error('recover_partial_workspace_v1:CannotInferLastDone', ...
        'Cannot infer completed hours because system_status and it are missing.');
end
statusText = string(S.system_status);
isDone = ~(ismissing(statusText) | statusText == "");
idx = find(isDone,1,'last');
if isempty(idx)
    lastDone = 0;
else
    lastDone = idx;
end
end

function Summary = localSummarizePartial(Hourly,cfg,elapsed_s)
dt_h = cfg.sim.dt_s/3600;
Summary = table();
Summary.n_hours = height(Hourly);
Summary.elapsed_s = elapsed_s;
Summary.ORC_operating_hours = sum(Hourly.ORC_feasible)*dt_h;
Summary.RO_operating_hours = sum(Hourly.RO_feasible)*dt_h;
Summary.E_ORC_net_kWh = sum(Hourly.W_ORC_net_W,'omitnan')*dt_h/1000;
Summary.E_solar_pump_kWh = sum(Hourly.W_solar_pump_W,'omitnan')*dt_h/1000;
Summary.E_RO_kWh = sum(Hourly.W_RO_total_W,'omitnan')*dt_h/1000;
Summary.E_CT_fan_kWh = sum(Hourly.W_CT_fan_W,'omitnan')*dt_h/1000;
Summary.E_aux_total_kWh = Summary.E_solar_pump_kWh + Summary.E_CT_fan_kWh;
Summary.E_available_for_RO_kWh = sum(Hourly.W_available_for_RO_W,'omitnan')*dt_h/1000;
Summary.RO_product_water_m3 = sum(Hourly.Qp_total_m3h,'omitnan')*dt_h;
Summary.CT_makeup_water_m3 = sum(Hourly.CT_makeup_m3h,'omitnan')*dt_h;
Summary.Net_product_water_m3 = Summary.RO_product_water_m3 - Summary.CT_makeup_water_m3;
Summary.RO_train_total = max(Hourly.N_train_total);
Summary.RO_train_running_max = max(Hourly.N_train_running);
Summary.RO_train_running_mean_when_on = mean(Hourly.N_train_running(Hourly.N_train_running > 0),'omitnan');
Summary.Preheater_ON_hours = sum(Hourly.preheater_on)*dt_h;
Summary.Preheater_heat_kWh = sum(Hourly.Q_preheater_W,'omitnan')*dt_h/1000;
Summary.E_preheater_to_seawater_kWh = Summary.Preheater_heat_kWh;
Summary.E_preheater_to_seawater_MWh = Summary.E_preheater_to_seawater_kWh/1000;
Summary.Q_preheater_mean_when_on_kW = mean(Hourly.Q_preheater_W(Hourly.preheater_on),'omitnan')/1000;
Summary.Q_preheater_max_kW = max(Hourly.Q_preheater_W,[],'omitnan')/1000;
Summary.CT_heat_rejected_kWh = sum(Hourly.Q_CT_rejected_W,'omitnan')*dt_h/1000;
Summary.Solar_useful_heat_kWh = sum(Hourly.Q_solar_useful_W,'omitnan')*dt_h/1000;
Summary.Solar_excess_heat_kWh = sum(Hourly.Q_solar_excess_W,'omitnan')*dt_h/1000;
Summary.Solar_return_sink_heat_kWh = sum(Hourly.Q_solar_return_sink_W,'omitnan')*dt_h/1000;
Summary.Storage_charge_heat_kWh = sum(Hourly.Q_storage_charge_W,'omitnan')*dt_h/1000;
Summary.Solar_curtailed_heat_kWh = sum(Hourly.Q_solar_curtailed_W,'omitnan')*dt_h/1000;
Summary.Storage_final_SOC = Hourly.storage_SOC(end);
Summary.Storage_final_T_C = Hourly.storage_T_C(end);
Summary.Solar_flow_factor_mean = mean(Hourly.solar_flow_factor,'omitnan');
Summary.Solar_flow_factor_min = min(Hourly.solar_flow_factor);
Summary.Solar_flow_factor_max = max(Hourly.solar_flow_factor);
Summary.RO_domain_fail_hours = sum(Hourly.system_status == "RO_DOMAIN_FAIL")*dt_h;
Summary.RO_infeasible_hours = sum(Hourly.system_status == "RO_INFEASIBLE")*dt_h;
Summary.Power_deficit_hours = sum(Hourly.system_status == "POWER_DEFICIT")*dt_h;
Summary.CT_target_not_met_hours = sum(Hourly.system_status == "CT_TARGET_NOT_MET")*dt_h;
Summary.CT_limited_operating_hours = sum(Hourly.system_status == "OK_CT_LIMITED")*dt_h;
Summary.Coupling_not_converged_hours = sum(~Hourly.coupling_converged)*dt_h;
end
