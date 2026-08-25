function Hourly = system_hourly_dispatch_v1(cfg,WeatherData,SeawaterData,SolarHourly,orcAnnual,PHDesign,CTDesign,CTConfig,nHours,sourceHour)
%SYSTEM_HOURLY_DISPATCH_V1 Couple ORC, preheater, RO ANN, and CT outputs.

if nargin < 9 || isempty(nHours)
    nHours = min([height(WeatherData),height(SeawaterData),numel(SolarHourly),orcAnnual.orc_nStep]);
end
if nargin < 10 || isempty(sourceHour)
    startHour = localGetNested(cfg,'sim','startHour',0);
    sourceHour = startHour + (0:nHours-1).' * cfg.sim.dt_s/3600;
end

hour = (1:nHours).';
source_hour = sourceHour(:);
DNI_Whm2 = nan(nHours,1);
T_amb_C = nan(nHours,1);
T_wb_C = nan(nHours,1);
T_sw_raw_C = nan(nHours,1);
Cf_kg_m3 = nan(nHours,1);
Q_solar_useful_W = nan(nHours,1);
W_ORC_net_W = nan(nHours,1);
Q_ORC_cond_W = nan(nHours,1);
T_cw_cond_out_C = nan(nHours,1);
Q_preheater_W = nan(nHours,1);
T_RO_in_C = nan(nHours,1);
T_cw_after_preheater_C = nan(nHours,1);
W_CT_fan_W = zeros(nHours,1);
Q_CT_rejected_W = zeros(nHours,1);
CT_makeup_m3h = zeros(nHours,1);
CT_mdot_makeup_kg_s = zeros(nHours,1);
W_RO_total_W = zeros(nHours,1);
Qp_total_m3h = zeros(nHours,1);
N_train_total = repmat(max(0,round(cfg.ro.N_train_total)),nHours,1);
N_train_running = zeros(nHours,1);
W_available_for_RO_W = zeros(nHours,1);
ORC_feasible = false(nHours,1);
RO_feasible = false(nHours,1);
system_status = strings(nHours,1);
solar_status = strings(nHours,1);
orc_status = strings(nHours,1);
preheater_status = strings(nHours,1);
ct_status = strings(nHours,1);
ro_status = strings(nHours,1);

DispatchWaitbar = localOpenWaitbar(cfg,'System hourly dispatch');
for it = 1:nHours
    localUpdateWaitbar(DispatchWaitbar,it,nHours, ...
        sprintf('System dispatch: step %d/%d, source hour %.2f',it,nHours,source_hour(it)));
    DNI_Whm2(it) = WeatherData.DNI_Whm2(it);
    T_amb_C(it) = WeatherData.T_amb_C(it);
    T_wb_C(it) = WeatherData.T_wb_C(it);
    T_sw_raw_C(it) = SeawaterData.SeaWater_Temperature_C(it);
    Cf_kg_m3(it) = localSeawaterConcentration(SeawaterData,it);

    Q_solar_useful_W(it) = localGet(SolarHourly(it),'Q_useful_W',NaN);
    solar_status(it) = string(localGet(SolarHourly(it),'status',''));

    W_ORC_net_W(it) = orcAnnual.orc_W_net(it);
    Q_ORC_cond_W(it) = orcAnnual.orc_Q_cond(it);
    T_cw_cond_out_C(it) = orcAnnual.orc_T_cw_out(it) - 273.15;
    ORC_feasible(it) = orcAnnual.orc_feasible(it);
    orc_status(it) = string(orcAnnual.orc_status{it});

    if ~ORC_feasible(it) || ~isfinite(W_ORC_net_W(it)) || W_ORC_net_W(it) <= 0
        T_RO_in_C(it) = T_sw_raw_C(it);
        T_cw_after_preheater_C(it) = T_cw_cond_out_C(it);
        preheater_status(it) = "SKIPPED_ORC_OFF";
        ct_status(it) = "SKIPPED_ORC_OFF";
        ro_status(it) = "SKIPPED_ORC_OFF";
        system_status(it) = "ORC_OFF";
        continue
    end

    Dispatch = localDispatchRoTrains(cfg,WeatherData,it, ...
        T_cw_cond_out_C(it),T_sw_raw_C(it),Cf_kg_m3(it),W_ORC_net_W(it), ...
        Q_ORC_cond_W(it),PHDesign,CTDesign,CTConfig);
    PHOut = Dispatch.PHOut;
    CTOut = Dispatch.CTOut;
    ctWasNeeded = Dispatch.ctWasNeeded;

    Q_preheater_W(it) = PHOut.Q_recovered_W;
    T_RO_in_C(it) = PHOut.T_RO_in_C;
    T_cw_after_preheater_C(it) = PHOut.T_cw_out_C;
    preheater_status(it) = string(PHOut.status);

    W_CT_fan_W(it) = CTOut.W_fan_W;
    Q_CT_rejected_W(it) = CTOut.Q_rejected_W;
    CT_makeup_m3h(it) = localGetCtWaterUse(CTOut,'V_makeup_m3_h',0);
    CT_mdot_makeup_kg_s(it) = localGetCtWaterUse(CTOut,'mdot_makeup_kg_s',0);
    ct_status(it) = string(CTOut.status);
    W_available_for_RO_W(it) = Dispatch.W_available_for_RO_W;
    N_train_running(it) = Dispatch.N_train_running;
    W_RO_total_W(it) = Dispatch.W_RO_total_W;
    Qp_total_m3h(it) = Dispatch.Qp_total_m3h;
    RO_feasible(it) = Dispatch.RO_feasible;
    ro_status(it) = string(Dispatch.ro_status);

    if ~Dispatch.RO_feasible
        system_status(it) = string(Dispatch.system_status);
    elseif ctWasNeeded && ~localIsCoolingTowerOk(CTOut)
        system_status(it) = "CT_TARGET_NOT_MET";
    else
        system_status(it) = "OK";
    end
end
localCloseWaitbar(DispatchWaitbar);

Hourly = table(hour,source_hour,DNI_Whm2,T_amb_C,T_wb_C,T_sw_raw_C,Cf_kg_m3, ...
    Q_solar_useful_W,W_ORC_net_W,Q_ORC_cond_W,T_cw_cond_out_C, ...
    Q_preheater_W,T_RO_in_C,T_cw_after_preheater_C,W_CT_fan_W, ...
    Q_CT_rejected_W,CT_makeup_m3h,CT_mdot_makeup_kg_s,W_available_for_RO_W, ...
    N_train_total,N_train_running,W_RO_total_W,Qp_total_m3h, ...
    ORC_feasible,RO_feasible, ...
    solar_status,orc_status,preheater_status,ct_status,ro_status,system_status);
end

function Dispatch = localDispatchRoTrains(cfg,WeatherData,it,TcwHotC,TswRawC,Cf,WorcNetW,QcondW,PHDesign,CTDesign,CTConfig)
Ntotal = max(0,round(cfg.ro.N_train_total));
Dispatch = localBlankDispatch(TcwHotC,TswRawC,Ntotal);
if Ntotal < 1
    Dispatch.system_status = "NO_RO_TRAIN_INSTALLED";
    Dispatch.ro_status = "NO_RO_TRAIN_INSTALLED";
    [Dispatch.CTOut,Dispatch.ctWasNeeded] = localRunCoolingTower(cfg,WeatherData,it,TcwHotC,CTDesign,CTConfig);
    Dispatch.W_available_for_RO_W = WorcNetW - Dispatch.CTOut.W_fan_W;
    return
end

firstDomainFail = [];
firstInfeasible = [];
firstPowerDeficit = [];

for nTrain = Ntotal:-1:1
    cand = localEvaluateRoTrainCandidate(cfg,WeatherData,it, ...
        TcwHotC,TswRawC,Cf,WorcNetW,QcondW,PHDesign,CTDesign,CTConfig,nTrain);

    if cand.RO_domain_fail
        if isempty(firstDomainFail)
            firstDomainFail = cand;
        end
        continue
    end
    if cand.RO_infeasible
        if isempty(firstInfeasible)
            firstInfeasible = cand;
        end
        continue
    end
    if cand.W_available_for_RO_W < cand.W_RO_total_W
        if isempty(firstPowerDeficit)
            firstPowerDeficit = cand;
        end
        continue
    end

    Dispatch = cand;
    Dispatch.RO_feasible = true;
    Dispatch.ro_status = "OK";
    return
end

if ~isempty(firstPowerDeficit)
    Dispatch = localBlankDispatch(TcwHotC,TswRawC,Ntotal);
    [Dispatch.CTOut,Dispatch.ctWasNeeded] = localRunCoolingTower(cfg,WeatherData,it,TcwHotC,CTDesign,CTConfig);
    Dispatch.W_available_for_RO_W = WorcNetW - Dispatch.CTOut.W_fan_W;
    Dispatch.system_status = "POWER_DEFICIT";
    Dispatch.ro_status = "POWER_LIMIT_NO_TRAIN";
elseif ~isempty(firstDomainFail)
    Dispatch = firstDomainFail;
    Dispatch.system_status = "RO_DOMAIN_FAIL";
    Dispatch.ro_status = "RO_DOMAIN_FAIL";
elseif ~isempty(firstInfeasible)
    Dispatch = firstInfeasible;
    Dispatch.system_status = "RO_INFEASIBLE";
    Dispatch.ro_status = "RO_INFEASIBLE";
end
end

function cand = localEvaluateRoTrainCandidate(cfg,WeatherData,it,TcwHotC,TswRawC,Cf,WorcNetW,QcondW,PHDesign,CTDesign,CTConfig,nTrain)
cand = localBlankDispatch(TcwHotC,TswRawC,cfg.ro.N_train_total);
cand.N_train_running = nTrain;
mdotSw = nTrain * cfg.ro.Qf_train_m3h * cfg.ro.rho_seawater_kgm3 / 3600;

PHInput = struct();
PHInput.T_hot_in_C = TcwHotC;
PHInput.T_cold_in_C = TswRawC;
PHInput.mdot_hot_kg_s = cfg.orc.mdot_cw_design_kg_s;
PHInput.mdot_cold_kg_s = mdotSw;
PHInput.Q_available_W = QcondW;
PHInput.T_cold_out_target_C = min(TswRawC + cfg.preheater.T_RO_in_rise_C, ...
    cfg.preheater.T_RO_in_max_C);

cand.PHOut = preheater_sthe_rating_v1(PHInput,PHDesign);

ROOut = ro_predict_ann_surrogate_v1_9_1(cfg.ro.model_file, ...
    cfg.ro.Qf_train_m3h,cand.PHOut.T_RO_in_C,Cf,cfg.ro.R_target);
cand.RO_domain_fail = ~ROOut.InTrainingDomain(1);
cand.RO_infeasible = ~ROOut.Feasible(1);
if ~cand.RO_domain_fail && ~cand.RO_infeasible
    cand.W_RO_total_W = nTrain * ROOut.W_RO_train_kW(1) * 1000;
    cand.Qp_total_m3h = nTrain * ROOut.Qp_train_m3h(1);
end
if cand.RO_domain_fail || cand.RO_infeasible
    return
end

cand.W_available_for_RO_W = WorcNetW;
if cand.W_RO_total_W > cand.W_available_for_RO_W
    return
end

[cand.CTOut,cand.ctWasNeeded] = localRunCoolingTower(cfg,WeatherData,it, ...
    cand.PHOut.T_cw_out_C,CTDesign,CTConfig);
cand.W_available_for_RO_W = WorcNetW - cand.CTOut.W_fan_W;
end

function Dispatch = localBlankDispatch(TcwHotC,TswRawC,Ntotal)
Dispatch = struct();
Dispatch.N_train_total = Ntotal;
Dispatch.N_train_running = 0;
Dispatch.W_RO_total_W = 0;
Dispatch.Qp_total_m3h = 0;
Dispatch.W_available_for_RO_W = 0;
Dispatch.RO_feasible = false;
Dispatch.RO_domain_fail = false;
Dispatch.RO_infeasible = false;
Dispatch.system_status = "POWER_DEFICIT";
Dispatch.ro_status = "RO_OFF";
Dispatch.PHOut = localBlankPHOut(TcwHotC,TswRawC);
Dispatch.CTOut = localBlankCTOut(TcwHotC);
Dispatch.ctWasNeeded = false;
end

function PHOut = localBlankPHOut(TcwHotC,TswRawC)
PHOut = struct();
PHOut.Q_recovered_W = 0;
PHOut.T_RO_in_C = TswRawC;
PHOut.T_cw_out_C = TcwHotC;
PHOut.T_hot_out_C = TcwHotC;
PHOut.T_sw_out_C = TswRawC;
PHOut.feasible = true;
PHOut.status = 'SKIPPED_RO_OFF';
end

function value = localGetNested(S,sectionName,fieldName,defaultValue)
if isfield(S,sectionName) && isstruct(S.(sectionName)) && ...
        isfield(S.(sectionName),fieldName) && ~isempty(S.(sectionName).(fieldName))
    value = S.(sectionName).(fieldName);
else
    value = defaultValue;
end
end

function tf = localIsCoolingTowerOk(CTOut)
status = string(localGet(CTOut,'status',''));
tf = localGet(CTOut,'feasible',false) && any(strcmpi(status,["OK","TARGET_MET","NOT_NEEDED"]));
end

function value = localGetCtWaterUse(CTOut,fieldName,defaultValue)
if isfield(CTOut,'water_consumption') && isstruct(CTOut.water_consumption) && ...
        isfield(CTOut.water_consumption,fieldName) && ~isempty(CTOut.water_consumption.(fieldName))
    value = CTOut.water_consumption.(fieldName);
elseif isfield(CTOut,fieldName) && ~isempty(CTOut.(fieldName))
    value = CTOut.(fieldName);
else
    value = defaultValue;
end
end

function h = localOpenWaitbar(cfg,titleText)
h = [];
if isfield(cfg,'ui') && isfield(cfg.ui,'use_waitbar') && cfg.ui.use_waitbar && usejava('desktop')
    try
        h = waitbar(0,titleText,'Name','System V1 progress');
    catch
        h = [];
    end
end
end

function localUpdateWaitbar(h,it,n,msg)
if isempty(h) || ~ishandle(h)
    return
end
waitbar(max(0,min(1,it/max(n,1))),h,msg);
drawnow limitrate
end

function localCloseWaitbar(h)
if ~isempty(h) && ishandle(h)
    close(h);
end
end

function [CTOut,ctWasNeeded] = localRunCoolingTower(cfg,WeatherData,it,TcwInC,CTDesign,CTConfig)
CTOut = localBlankCTOut(TcwInC);
targetC = cfg.ct.T_cw_target_C;
ctWasNeeded = isfinite(TcwInC) && TcwInC > targetC + 1e-6;
if ~ctWasNeeded
    CTOut.T_w_out_C = TcwInC;
    CTOut.status = 'NOT_NEEDED';
    CTOut.feasible = true;
    return
end

CTAmbient = struct();
CTAmbient.T_db_C = WeatherData.T_amb_C(it);
CTAmbient.T_wb_C = WeatherData.T_wb_C(it);
CTAmbient.RH_pct = WeatherData.RH_pct(it);
CTAmbient.P_atm_Pa = WeatherData.Patm_Pa(it);
CTAir = ct_psychrometrics(CTAmbient,CTConfig);

CTInput = struct();
CTInput.T_w_in_C = TcwInC;
CTInput.mdot_water = cfg.orc.mdot_cw_design_kg_s;
CTInput.T_w_out_target_C = targetC;
CTInput.air_in = CTAir;

CTOut = ct_solve_fan_for_target(CTInput,CTAmbient,CTDesign,CTConfig);
end

function CTOut = localBlankCTOut(TcwInC)
CTOut = struct();
CTOut.T_w_in_C = TcwInC;
CTOut.T_w_out_C = TcwInC;
CTOut.Q_rejected_W = 0;
CTOut.W_fan_W = 0;
CTOut.mdot_makeup_kg_s = 0;
CTOut.feasible = true;
CTOut.status = 'NOT_NEEDED';
end

function Cf = localSeawaterConcentration(T,it)
names = T.Properties.VariableNames;
if any(strcmp(names,'Cf_kg_m3'))
    Cf = T.Cf_kg_m3(it);
elseif any(strcmp(names,'Salinity_kg_m3'))
    Cf = T.Salinity_kg_m3(it);
elseif any(strcmp(names,'Salinity_CMEMS_native'))
    Cf = T.Salinity_CMEMS_native(it);
else
    error('system_hourly_dispatch_v1:MissingSalinity', ...
        'No recognized salinity/concentration column was found in seawater table.');
end
end

function value = localGet(S,fieldName,defaultValue)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end
