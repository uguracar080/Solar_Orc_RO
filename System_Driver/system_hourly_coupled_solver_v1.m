function [Hourly,SolarHourly,orcAnnual] = system_hourly_coupled_solver_v1(cfg,WeatherData,SeawaterData, ...
    orcDesign,PHDesign,CTDesign,CTConfig,orcConfig,orcTemplates,nHours,sourceHour)
%SYSTEM_HOURLY_COUPLED_SOLVER_V1 Hourly closed-loop Solar-ORC-RO-CT solver.
%
% Each hour solves the solar/evaporator return loop and the
% condenser/preheater/cooling-tower return loop with fixed component geometry.

if nargin < 10 || isempty(nHours)
    nHours = min([height(WeatherData),height(SeawaterData)]);
end
if nargin < 11 || isempty(sourceHour)
    sourceHour = cfg.sim.startHour + (0:nHours-1).' * cfg.sim.dt_s/3600;
end

solver = localSolverConfig(cfg);
hour = (1:nHours).';
source_hour = sourceHour(:);

BlankSolarInput = struct('DNI_Wm2',0,'T_amb_C',25,'WindSpd_ms',1.0, ...
    'T_HTF_in_K',cfg.solar.T_HTF_in_K);
SolarHourly = repmat(solar_field_ptc_v1(BlankSolarInput,cfg.solar),nHours,1);
BlankStep = localBlankOrcStep(orcDesign,orcTemplates.orcHotDesign,orcTemplates.orcColdDesign,orcConfig);
orcStep = repmat({BlankStep},nHours,1);

DNI_Whm2 = nan(nHours,1);
T_amb_C = nan(nHours,1);
T_wb_C = nan(nHours,1);
T_sw_raw_C = nan(nHours,1);
Cf_kg_m3 = nan(nHours,1);
Q_solar_useful_W = nan(nHours,1);
Q_solar_excess_W = zeros(nHours,1);
Q_solar_return_sink_W = zeros(nHours,1);
Q_storage_charge_W = zeros(nHours,1);
Q_solar_curtailed_W = zeros(nHours,1);
storage_SOC = nan(nHours,1);
storage_T_C = nan(nHours,1);
storage_E_stored_kWh = nan(nHours,1);
solar_flow_factor = ones(nHours,1);
solar_V_Lmin_1module = nan(nHours,1);
W_solar_pump_W = zeros(nHours,1);
dP_solar_field_Pa = zeros(nHours,1);
dP_orc_evap_hot_Pa = zeros(nHours,1);
dP_solar_loop_Pa = zeros(nHours,1);
T_solar_loop_in_C = nan(nHours,1);
T_solar_loop_out_C = nan(nHours,1);
T_orc_hot_return_raw_C = nan(nHours,1);
T_orc_hot_return_C = nan(nHours,1);
W_ORC_net_W = nan(nHours,1);
Q_ORC_evap_W = nan(nHours,1);
Q_ORC_cond_W = nan(nHours,1);
P_ORC_evap_Pa = nan(nHours,1);
P_ORC_cond_Pa = nan(nHours,1);
T_cw_loop_in_C = nan(nHours,1);
T_cw_cond_out_C = nan(nHours,1);
T_cw_cond_out_guard_C = nan(nHours,1);
T_cw_cond_out_guard_margin_K = nan(nHours,1);
DeltaT_preheater_available_K = nan(nHours,1);
preheater_on = false(nHours,1);
Q_preheater_W = nan(nHours,1);
T_RO_in_C = nan(nHours,1);
T_cw_after_preheater_C = nan(nHours,1);
T_CT_out_C = nan(nHours,1);
W_CT_fan_W = zeros(nHours,1);
Q_CT_rejected_W = zeros(nHours,1);
CT_makeup_m3h = zeros(nHours,1);
CT_mdot_makeup_kg_s = zeros(nHours,1);
W_available_for_RO_W = zeros(nHours,1);
N_train_total = repmat(max(0,round(cfg.ro.N_train_total)),nHours,1);
N_train_running = zeros(nHours,1);
W_RO_total_W = zeros(nHours,1);
Qp_total_m3h = zeros(nHours,1);
RO_InTrainingDomain = false(nHours,1);
RO_ClassifierFeasible = false(nHours,1);
RO_ANN_Feasible = false(nHours,1);
RO_P_feasible = nan(nHours,1);
RO_Qp_train_m3h = nan(nHours,1);
RO_W_train_kW = nan(nHours,1);
RO_SEC_kWh_m3 = nan(nHours,1);
RO_Cp_mg_L = nan(nHours,1);
RO_P1_opt_gauge_MPa = nan(nHours,1);
RO_P2_opt_gauge_MPa = nan(nHours,1);
RO_P_CpBoundary = nan(nHours,1);
RO_raw_Qp_train_m3h = nan(nHours,1);
RO_raw_W_train_kW = nan(nHours,1);
RO_raw_SEC_kWh_m3 = nan(nHours,1);
RO_raw_Cp_mg_L = nan(nHours,1);
RO_raw_P1_opt_gauge_MPa = nan(nHours,1);
RO_raw_P2_opt_gauge_MPa = nan(nHours,1);
ORC_feasible = false(nHours,1);
RO_feasible = false(nHours,1);
coupling_converged = false(nHours,1);
N_coupling_iter = zeros(nHours,1);
solar_loop_residual_K = nan(nHours,1);
cw_loop_residual_K = nan(nHours,1);
system_status = strings(nHours,1);
solar_status = strings(nHours,1);
solar_flow_status = strings(nHours,1);
solar_flow_search_status = strings(nHours,1);
solar_flow_candidates_evaluated = zeros(nHours,1);
solar_flow_full_search_used = false(nHours,1);
solar_solver_warm_start_used = false(nHours,1);
storage_status = strings(nHours,1);
orc_status = strings(nHours,1);
preheater_status = strings(nHours,1);
ct_status = strings(nHours,1);
ro_status = strings(nHours,1);
orc_off_reason = strings(nHours,1);
orc_dispatch_best_status = strings(nHours,1);
orc_dispatch_n_candidates_available = zeros(nHours,1);
orc_dispatch_n_candidates_evaluated = zeros(nHours,1);
orc_dispatch_best_W_net_W = nan(nHours,1);
orc_dispatch_best_evap_A_ratio = nan(nHours,1);
orc_dispatch_best_cond_A_ratio = nan(nHours,1);
orc_dispatch_best_evap_pinch_K = nan(nHours,1);
orc_dispatch_best_cond_pinch_K = nan(nHours,1);
t_solar_select_s = zeros(nHours,1);
t_orc_dispatch_s = zeros(nHours,1);
t_ro_heat_rejection_dispatch_s = zeros(nHours,1);
t_storage_s = zeros(nHours,1);
t_hour_s = zeros(nHours,1);

TsolarGuess_K = cfg.solar.T_HTF_in_K;
TcwGuess_C = cfg.orc.cw_target_in_C;
warmStartOp = [];
PHWasOn = false;
StorageState = [];
SolarSearchState = localBlankSolarSearchState();

hWait = localOpenWaitbar(cfg,'Coupled hourly solver');
for it = 1:nHours
    hourTimer = tic;
    localUpdateWaitbar(hWait,it,nHours, ...
        sprintf('Coupled system: step %d/%d, source hour %.2f',it,nHours,source_hour(it)));

    DNI_Whm2(it) = WeatherData.DNI_Whm2(it);
    T_amb_C(it) = WeatherData.T_amb_C(it);
    T_wb_C(it) = WeatherData.T_wb_C(it);
    T_sw_raw_C(it) = SeawaterData.SeaWater_Temperature_C(it);
    Cf_kg_m3(it) = localSeawaterConcentration(SeawaterData,it);

    State = localBlankState(TsolarGuess_K,TcwGuess_C,PHWasOn);
    State.SolarSearchState = SolarSearchState;
    for iter = 1:solver.max_iter
        State.iter = iter;
        State = localSolveOneCouplingIteration(State,cfg,WeatherData,SeawaterData,it, ...
            orcDesign,PHDesign,CTDesign,CTConfig,orcConfig,orcTemplates,warmStartOp);

        if abs(State.solar_residual_K) <= solver.tol_solar_K && ...
                abs(State.cw_residual_K) <= solver.tol_cw_K
            State.converged = true;
            break
        end

        if iter < solver.max_iter
            State.TsolarIn_K = localRelax(State.TsolarIn_K,State.TsolarNext_K,solver.relax);
            State.TcwIn_C = localRelax(State.TcwIn_C,State.TcwNext_C,solver.relax);
        end
    end

    SolarHourly(it) = State.SolarOut;
    orcStep{it} = State.orcStep;
    if State.ORC_feasible
        warmStartOp = localStepToOperatingInput(State.orcStep);
    end
    SolarSearchState = State.SolarSearchState;

    TsolarGuess_K = localNextGuess(State.TsolarNext_K,cfg.solar.T_HTF_in_K);
    TcwGuess_C = localNextGuess(State.TcwNext_C,cfg.orc.cw_target_in_C);
    PHWasOn = logical(localGet(State.PHOut,'preheater_on',false));

    Q_solar_useful_W(it) = localGet(State.SolarOut,'Q_useful_W',0);
    solar_flow_factor(it) = State.solar_flow_factor;
    solar_V_Lmin_1module(it) = localGet(State.SolarOut,'V_Lmin_1module',NaN);
    W_solar_pump_W(it) = State.W_solar_pump_W;
    dP_solar_field_Pa(it) = State.dP_solar_field_Pa;
    dP_orc_evap_hot_Pa(it) = State.dP_orc_evap_hot_Pa;
    dP_solar_loop_Pa(it) = State.dP_solar_loop_Pa;
    Q_solar_return_sink_W(it) = State.Q_solar_return_sink_W;
    Q_solar_excess_W(it) = max(max(0,Q_solar_useful_W(it) - State.Q_ORC_evap_W), ...
        Q_solar_return_sink_W(it));
    storageTimer = tic;
    [StorageState,StorageOut] = localRunStorage(cfg,StorageState,Q_solar_excess_W(it));
    t_storage_s(it) = toc(storageTimer);
    Q_storage_charge_W(it) = StorageOut.Q_charge_W;
    Q_solar_curtailed_W(it) = StorageOut.Q_curtailed_W;
    storage_SOC(it) = StorageOut.SOC;
    storage_T_C(it) = StorageOut.T_C;
    storage_E_stored_kWh(it) = StorageOut.E_stored_kWh;
    T_solar_loop_in_C(it) = State.TsolarIn_K - 273.15;
    T_solar_loop_out_C(it) = localGet(State.SolarOut,'T_HTF_out_K',State.TsolarIn_K) - 273.15;
    T_orc_hot_return_raw_C(it) = State.TsolarNextRaw_K - 273.15;
    T_orc_hot_return_C(it) = State.TsolarNext_K - 273.15;
    W_ORC_net_W(it) = State.W_ORC_net_W;
    Q_ORC_evap_W(it) = State.Q_ORC_evap_W;
    Q_ORC_cond_W(it) = State.Q_ORC_cond_W;
    P_ORC_evap_Pa(it) = State.P_ORC_evap_Pa;
    P_ORC_cond_Pa(it) = State.P_ORC_cond_Pa;
    T_cw_loop_in_C(it) = State.TcwIn_C;
    T_cw_cond_out_C(it) = State.TcwCondOut_C;
    T_cw_cond_out_guard_C(it) = State.TcwCondOutGuard_C;
    T_cw_cond_out_guard_margin_K(it) = State.TcwCondOut_C - State.TcwCondOutGuard_C;
    DeltaT_preheater_available_K(it) = localGet(State.PHOut,'deltaT_available_K', ...
        State.TcwCondOut_C - T_sw_raw_C(it));
    preheater_on(it) = logical(localGet(State.PHOut,'preheater_on',false));
    Q_preheater_W(it) = State.PHOut.Q_recovered_W;
    T_RO_in_C(it) = State.PHOut.T_RO_in_C;
    T_cw_after_preheater_C(it) = State.PHOut.T_cw_out_C;
    T_CT_out_C(it) = State.TcwNext_C;
    W_CT_fan_W(it) = State.CTOut.W_fan_W;
    Q_CT_rejected_W(it) = State.CTOut.Q_rejected_W;
    CT_makeup_m3h(it) = localGetCtWaterUse(State.CTOut,'V_makeup_m3_h',0);
    CT_mdot_makeup_kg_s(it) = localGetCtWaterUse(State.CTOut,'mdot_makeup_kg_s',0);
    W_available_for_RO_W(it) = State.W_available_for_RO_W;
    N_train_running(it) = State.N_train_running;
    W_RO_total_W(it) = State.W_RO_total_W;
    Qp_total_m3h(it) = State.Qp_total_m3h;
    RO_InTrainingDomain(it) = State.RO_InTrainingDomain;
    RO_ClassifierFeasible(it) = State.RO_ClassifierFeasible;
    RO_ANN_Feasible(it) = State.RO_ANN_Feasible;
    RO_P_feasible(it) = State.RO_P_feasible;
    RO_Qp_train_m3h(it) = State.RO_Qp_train_m3h;
    RO_W_train_kW(it) = State.RO_W_train_kW;
    RO_SEC_kWh_m3(it) = State.RO_SEC_kWh_m3;
    RO_Cp_mg_L(it) = State.RO_Cp_mg_L;
    RO_P1_opt_gauge_MPa(it) = State.RO_P1_opt_gauge_MPa;
    RO_P2_opt_gauge_MPa(it) = State.RO_P2_opt_gauge_MPa;
    RO_P_CpBoundary(it) = State.RO_P_CpBoundary;
    RO_raw_Qp_train_m3h(it) = State.RO_raw_Qp_train_m3h;
    RO_raw_W_train_kW(it) = State.RO_raw_W_train_kW;
    RO_raw_SEC_kWh_m3(it) = State.RO_raw_SEC_kWh_m3;
    RO_raw_Cp_mg_L(it) = State.RO_raw_Cp_mg_L;
    RO_raw_P1_opt_gauge_MPa(it) = State.RO_raw_P1_opt_gauge_MPa;
    RO_raw_P2_opt_gauge_MPa(it) = State.RO_raw_P2_opt_gauge_MPa;
    ORC_feasible(it) = State.ORC_feasible;
    RO_feasible(it) = State.RO_feasible;
    coupling_converged(it) = State.converged;
    N_coupling_iter(it) = State.iter;
    solar_loop_residual_K(it) = State.solar_residual_K;
    cw_loop_residual_K(it) = State.cw_residual_K;
    solar_status(it) = string(localGet(State.SolarOut,'status',''));
    solar_flow_status(it) = string(State.solar_flow_status);
    solar_flow_search_status(it) = string(State.solar_flow_search_status);
    solar_flow_candidates_evaluated(it) = State.solar_flow_candidates_evaluated;
    solar_flow_full_search_used(it) = State.solar_flow_full_search_used;
    solar_solver_warm_start_used(it) = State.solar_solver_warm_start_used;
    storage_status(it) = string(StorageOut.status);
    orc_status(it) = string(State.orc_status);
    preheater_status(it) = string(State.PHOut.status);
    ct_status(it) = string(State.CTOut.status);
    ro_status(it) = string(State.ro_status);
    system_status(it) = string(State.system_status);
    OrCdiag = localOrcDispatchDiagnostics(State.orcStep,State.ORC_feasible,State.orc_status);
    orc_off_reason(it) = string(OrCdiag.off_reason);
    orc_dispatch_best_status(it) = string(OrCdiag.best_status);
    orc_dispatch_n_candidates_available(it) = OrCdiag.n_candidates_available;
    orc_dispatch_n_candidates_evaluated(it) = OrCdiag.n_candidates_evaluated;
    orc_dispatch_best_W_net_W(it) = OrCdiag.best_W_net_W;
    orc_dispatch_best_evap_A_ratio(it) = OrCdiag.best_evap_A_ratio;
    orc_dispatch_best_cond_A_ratio(it) = OrCdiag.best_cond_A_ratio;
    orc_dispatch_best_evap_pinch_K(it) = OrCdiag.best_evap_pinch_K;
    orc_dispatch_best_cond_pinch_K(it) = OrCdiag.best_cond_pinch_K;
    t_solar_select_s(it) = State.timing_solar_select_s;
    t_orc_dispatch_s(it) = State.timing_orc_dispatch_s;
    t_ro_heat_rejection_dispatch_s(it) = State.timing_ro_heat_rejection_dispatch_s;
    t_hour_s(it) = toc(hourTimer);
end
localCloseWaitbar(hWait);

Hourly = table(hour,source_hour,DNI_Whm2,T_amb_C,T_wb_C,T_sw_raw_C,Cf_kg_m3, ...
    Q_solar_useful_W,Q_solar_excess_W,Q_solar_return_sink_W,Q_storage_charge_W,Q_solar_curtailed_W, ...
    storage_SOC,storage_T_C,storage_E_stored_kWh,solar_flow_factor,solar_V_Lmin_1module, ...
    W_solar_pump_W,dP_solar_field_Pa,dP_orc_evap_hot_Pa,dP_solar_loop_Pa, ...
    T_solar_loop_in_C,T_solar_loop_out_C,T_orc_hot_return_raw_C,T_orc_hot_return_C, ...
    W_ORC_net_W,Q_ORC_evap_W,Q_ORC_cond_W,P_ORC_evap_Pa,P_ORC_cond_Pa, ...
    T_cw_loop_in_C,T_cw_cond_out_C,T_cw_cond_out_guard_C,T_cw_cond_out_guard_margin_K, ...
    DeltaT_preheater_available_K,preheater_on,Q_preheater_W,T_RO_in_C,T_cw_after_preheater_C, ...
    T_CT_out_C,W_CT_fan_W,Q_CT_rejected_W,CT_makeup_m3h,CT_mdot_makeup_kg_s, ...
    W_available_for_RO_W,N_train_total,N_train_running,W_RO_total_W,Qp_total_m3h, ...
    RO_InTrainingDomain,RO_ClassifierFeasible,RO_ANN_Feasible,RO_P_feasible, ...
    RO_Qp_train_m3h,RO_W_train_kW,RO_SEC_kWh_m3,RO_Cp_mg_L, ...
    RO_P1_opt_gauge_MPa,RO_P2_opt_gauge_MPa,RO_P_CpBoundary, ...
    RO_raw_Qp_train_m3h,RO_raw_W_train_kW,RO_raw_SEC_kWh_m3,RO_raw_Cp_mg_L, ...
    RO_raw_P1_opt_gauge_MPa,RO_raw_P2_opt_gauge_MPa, ...
    ORC_feasible,RO_feasible,coupling_converged,N_coupling_iter, ...
    solar_loop_residual_K,cw_loop_residual_K, ...
    solar_status,solar_flow_status,solar_flow_search_status,solar_flow_candidates_evaluated, ...
    solar_flow_full_search_used,solar_solver_warm_start_used, ...
    storage_status,orc_status,preheater_status,ct_status,ro_status,system_status, ...
    orc_off_reason,orc_dispatch_n_candidates_available,orc_dispatch_n_candidates_evaluated, ...
    orc_dispatch_best_status,orc_dispatch_best_W_net_W,orc_dispatch_best_evap_A_ratio, ...
    orc_dispatch_best_cond_A_ratio,orc_dispatch_best_evap_pinch_K,orc_dispatch_best_cond_pinch_K, ...
    t_solar_select_s,t_orc_dispatch_s,t_ro_heat_rejection_dispatch_s,t_storage_s,t_hour_s);

orcAnnual = localBuildOrcAnnual(orcConfig,orcStep,cfg.sim.dt_s);
end

function State = localSolveOneCouplingIteration(State,cfg,WeatherData,SeawaterData,it, ...
    orcDesign,PHDesign,CTDesign,CTConfig,orcConfig,orcTemplates,warmStartOp)
SolarInput = struct();
SolarInput.DNI_Wm2 = WeatherData.DNI_Whm2(it);
SolarInput.T_amb_C = WeatherData.T_amb_C(it);
SolarInput.WindSpd_ms = WeatherData.WindSpd_ms(it);
SolarInput.T_HTF_in_K = State.TsolarIn_K;
tSolar = tic;
    [State.SolarOut,State.solar_flow_factor,State.solar_flow_status, ...
        State.SolarSearchState,SearchDiag] = ...
        localSelectSolarOperatingPoint(SolarInput,cfg.solar,State.SolarSearchState);
State.timing_solar_select_s = State.timing_solar_select_s + toc(tSolar);
State.solar_flow_search_status = SearchDiag.status;
State.solar_flow_candidates_evaluated = SearchDiag.candidates_evaluated;
State.solar_flow_full_search_used = SearchDiag.full_search_used;
State.solar_solver_warm_start_used = SearchDiag.solver_warm_start_used;

    if localSolarShouldShutDown(cfg,State.SolarOut)
        State = localApplySolarOffState(State,cfg,orcDesign,orcTemplates,orcConfig,SeawaterData,it);
        return
    end

    hotStream = localSolarToOrcHotStream(State.SolarOut,State.TsolarIn_K,cfg,orcTemplates.orcHotDesign);
coldStream = orcTemplates.orcColdDesign;
coldStream.T_in = State.TcwIn_C + 273.15;
State.TcwCondOutGuard_C = localPreheaterCondOutGuardC(cfg,SeawaterData,it);
orcConfigStep = localApplyPreheaterGuardToOrcConfig(orcConfig,cfg,State.TcwCondOutGuard_C);

op = orcTemplates.op;
if ~isempty(warmStartOp)
    op.orc_warmStartOperatingInput = warmStartOp;
end

tOrc = tic;
if strcmpi(cfg.orc.operating_mode,'dispatch')
    State.orcStep = orc_offdesign_dispatch(orcDesign,hotStream,coldStream,op,orcConfigStep);
else
    State.orcStep = orc_offdesign_rating(orcDesign,hotStream,coldStream,op,orcConfigStep);
end
State.timing_orc_dispatch_s = State.timing_orc_dispatch_s + toc(tOrc);

th = State.orcStep.orc_thermo;
er = State.orcStep.orc_evaporator_rate;
cr = State.orcStep.orc_condenser_rate;
State.W_ORC_net_W = th.W_orcnet;
State.Q_ORC_evap_W = th.Q_orcevap;
State.Q_ORC_cond_W = th.Q_orccond;
State.P_ORC_evap_Pa = th.P_orcevap;
State.P_ORC_cond_Pa = th.P_orccond;
State.TsolarNextRaw_K = er.T_orchtf_out;
State.TsolarNext_K = er.T_orchtf_out;
State.TcwCondOut_C = cr.T_orccw_out - 273.15;
State = localApplySolarPump(State,cfg,orcConfig,hotStream,er);
State = localApplySolarReturnSink(State,cfg,orcConfig,hotStream);
State.ORC_feasible = State.orcStep.orc_feasible && th.W_orcnet > 0;
State.orc_status = localGet(State.orcStep,'orc_status','');

if ~State.ORC_feasible
    State.PHOut = localBlankPHOut(State.TcwCondOut_C,SeawaterData.SeaWater_Temperature_C(it));
    State.TcwNext_C = cfg.orc.cw_target_in_C;
    State.CTOut = localBlankCTOut(State.TcwNext_C);
    State.W_available_for_RO_W = 0;
    State.N_train_running = 0;
    State.W_RO_total_W = 0;
    State.Qp_total_m3h = 0;
    State = localResetRoDiagnostics(State);
    State.RO_feasible = false;
    State.system_status = "ORC_OFF";
    State.ro_status = "SKIPPED_ORC_OFF";
    State.solar_residual_K = State.TsolarNext_K - State.TsolarIn_K;
    State.cw_residual_K = State.TcwNext_C - State.TcwIn_C;
    return
end

tDispatch = tic;
Dispatch = localDispatchRoTrains(cfg,WeatherData,SeawaterData,it, ...
    State.TcwCondOut_C,State.W_ORC_net_W - State.W_solar_pump_W, ...
    State.Q_ORC_cond_W,PHDesign,CTDesign,CTConfig,State.PHWasOn);
State.timing_ro_heat_rejection_dispatch_s = State.timing_ro_heat_rejection_dispatch_s + toc(tDispatch);
State.PHOut = Dispatch.PHOut;
State.CTOut = Dispatch.CTOut;
State.TcwNext_C = Dispatch.CTOut.T_w_out_C;
State.W_available_for_RO_W = Dispatch.W_available_for_RO_W;
State.N_train_running = Dispatch.N_train_running;
State.W_RO_total_W = Dispatch.W_RO_total_W;
State.Qp_total_m3h = Dispatch.Qp_total_m3h;
State.RO_InTrainingDomain = Dispatch.RO_InTrainingDomain;
State.RO_ClassifierFeasible = Dispatch.RO_ClassifierFeasible;
State.RO_ANN_Feasible = Dispatch.RO_ANN_Feasible;
State.RO_P_feasible = Dispatch.RO_P_feasible;
State.RO_Qp_train_m3h = Dispatch.RO_Qp_train_m3h;
State.RO_W_train_kW = Dispatch.RO_W_train_kW;
State.RO_SEC_kWh_m3 = Dispatch.RO_SEC_kWh_m3;
State.RO_Cp_mg_L = Dispatch.RO_Cp_mg_L;
State.RO_P1_opt_gauge_MPa = Dispatch.RO_P1_opt_gauge_MPa;
State.RO_P2_opt_gauge_MPa = Dispatch.RO_P2_opt_gauge_MPa;
State.RO_P_CpBoundary = Dispatch.RO_P_CpBoundary;
State.RO_raw_Qp_train_m3h = Dispatch.RO_raw_Qp_train_m3h;
State.RO_raw_W_train_kW = Dispatch.RO_raw_W_train_kW;
State.RO_raw_SEC_kWh_m3 = Dispatch.RO_raw_SEC_kWh_m3;
State.RO_raw_Cp_mg_L = Dispatch.RO_raw_Cp_mg_L;
State.RO_raw_P1_opt_gauge_MPa = Dispatch.RO_raw_P1_opt_gauge_MPa;
State.RO_raw_P2_opt_gauge_MPa = Dispatch.RO_raw_P2_opt_gauge_MPa;
State.RO_feasible = Dispatch.RO_feasible;
State.ro_status = Dispatch.ro_status;
State.system_status = Dispatch.system_status;
State.solar_residual_K = State.TsolarNext_K - State.TsolarIn_K;
State.cw_residual_K = State.TcwNext_C - State.TcwIn_C;
end

function Dispatch = localDispatchRoTrains(cfg,WeatherData,SeawaterData,it,TcwHotC,WorcNetW,QcondW,PHDesign,CTDesign,CTConfig,PHWasOn)
Ntotal = max(0,round(cfg.ro.N_train_total));
TswRawC = SeawaterData.SeaWater_Temperature_C(it);
Dispatch = localBlankDispatch(TcwHotC,TswRawC,Ntotal);
if Ntotal < 1
    Dispatch.system_status = "NO_RO_TRAIN_INSTALLED";
    Dispatch.ro_status = "NO_RO_TRAIN_INSTALLED";
    [Dispatch.CTOut,~] = localRunCoolingTower(cfg,WeatherData,it,TcwHotC,CTDesign,CTConfig);
    Dispatch.W_available_for_RO_W = WorcNetW - Dispatch.CTOut.W_fan_W;
    return
end

firstDomainFail = [];
firstInfeasible = [];
firstPowerDeficit = [];
for nTrain = Ntotal:-1:1
    cand = localEvaluateRoTrainCandidate(cfg,WeatherData,SeawaterData,it, ...
        TcwHotC,WorcNetW,QcondW,PHDesign,CTDesign,CTConfig,nTrain,PHWasOn);
    if cand.RO_domain_fail
        if isempty(firstDomainFail), firstDomainFail = cand; end
        continue
    end
    if cand.RO_infeasible
        if isempty(firstInfeasible), firstInfeasible = cand; end
        continue
    end
    if cand.W_available_for_RO_W < cand.W_RO_total_W
        if isempty(firstPowerDeficit), firstPowerDeficit = cand; end
        continue
    end
    Dispatch = cand;
    Dispatch.RO_feasible = true;
    Dispatch.ro_status = "OK";
    if localIsCoolingTowerOk(cand.CTOut)
        Dispatch.system_status = "OK";
    else
        Dispatch.system_status = "OK_CT_LIMITED";
    end
    return
end

if ~isempty(firstPowerDeficit)
    Dispatch = localBlankDispatch(TcwHotC,TswRawC,Ntotal);
    [Dispatch.CTOut,~] = localRunCoolingTower(cfg,WeatherData,it,TcwHotC,CTDesign,CTConfig);
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

function cand = localEvaluateRoTrainCandidate(cfg,WeatherData,SeawaterData,it,TcwHotC,WorcNetW,QcondW,PHDesign,CTDesign,CTConfig,nTrain,PHWasOn)
TswRawC = SeawaterData.SeaWater_Temperature_C(it);
Cf = localSeawaterConcentration(SeawaterData,it);
cand = localBlankDispatch(TcwHotC,TswRawC,cfg.ro.N_train_total);
cand.N_train_running = nTrain;
mdotSw = nTrain * cfg.ro.Qf_train_m3h * cfg.ro.rho_seawater_kgm3 / 3600;

PHInput = struct();
PHInput.T_hot_in_C = TcwHotC;
PHInput.T_cold_in_C = TswRawC;
PHInput.mdot_hot_kg_s = cfg.orc.mdot_cw_design_kg_s;
PHInput.mdot_cold_kg_s = mdotSw;
PHInput.Q_available_W = QcondW;
PHInput.T_cold_out_target_C = localPreheaterTargetC(cfg,TswRawC);
cand.PHOut = localRunPreheaterControl(cfg,PHInput,PHDesign,PHWasOn);
[cand.CTOut,~] = localRunCoolingTower(cfg,WeatherData,it,cand.PHOut.T_cw_out_C,CTDesign,CTConfig);
cand.W_available_for_RO_W = WorcNetW - cand.CTOut.W_fan_W;

ROOut = ro_predict_ann_surrogate_v1_9_1(cfg.ro.model_file, ...
    cfg.ro.Qf_train_m3h,cand.PHOut.T_RO_in_C,Cf,cfg.ro.R_target);
cand = localAttachRoDiagnostics(cand,ROOut);
cand.RO_domain_fail = ~ROOut.InTrainingDomain(1);
cand.RO_infeasible = ~ROOut.Feasible(1);
if ~cand.RO_domain_fail && ~cand.RO_infeasible
    cand.W_RO_total_W = nTrain * ROOut.W_RO_train_kW(1) * 1000;
    cand.Qp_total_m3h = nTrain * ROOut.Qp_train_m3h(1);
end
end

function PHOut = localRunPreheaterControl(cfg,PHInput,PHDesign,PHWasOn)
ctrl = localPreheaterControl(cfg,PHInput.T_hot_in_C,PHInput.T_cold_in_C,PHWasOn);
if ~ctrl.on
    PHOut = localBlankPHOut(PHInput.T_hot_in_C,PHInput.T_cold_in_C);
    PHOut.status = ctrl.status;
else
    PHOut = preheater_sthe_rating_v1(PHInput,PHDesign);
    if ctrl.deadband
        PHOut.status = ['PH_ON_DEADBAND_' char(string(PHOut.status))];
    elseif strcmpi(string(PHOut.status),"OK")
        PHOut.status = 'PH_ON';
    else
        PHOut.status = ['PH_ON_' char(string(PHOut.status))];
    end
end
PHOut.preheater_on = ctrl.on;
PHOut.deltaT_available_K = ctrl.deltaT_available_K;
PHOut.deltaT_ON_K = ctrl.deltaT_ON_K;
PHOut.deltaT_OFF_K = ctrl.deltaT_OFF_K;
end

function ctrl = localPreheaterControl(cfg,TcwHotC,TswRawC,PHWasOn)
dTOn = localGetNested(cfg,'preheater','deltaT_ON_K', ...
    localGetNested(cfg,'preheater','dT_min_K',3.0));
dTOff = localGetNested(cfg,'preheater','deltaT_OFF_K',dTOn);
dTOff = min(dTOff,dTOn);
dTAvailable = TcwHotC - TswRawC;

ctrl = struct();
ctrl.deltaT_available_K = dTAvailable;
ctrl.deltaT_ON_K = dTOn;
ctrl.deltaT_OFF_K = dTOff;
ctrl.deadband = false;
if isfinite(dTAvailable) && dTAvailable >= dTOn
    ctrl.on = true;
    ctrl.status = 'PH_ON';
elseif isfinite(dTAvailable) && dTAvailable <= dTOff
    ctrl.on = false;
    ctrl.status = 'PH_OFF_LOW_DT';
else
    ctrl.on = logical(PHWasOn);
    ctrl.deadband = true;
    if ctrl.on
        ctrl.status = 'PH_ON_DEADBAND';
    else
        ctrl.status = 'PH_OFF_DEADBAND';
    end
end
end

function targetC = localPreheaterTargetC(cfg,TswC)
riseTarget = TswC + localGetNested(cfg,'preheater','T_RO_in_rise_C',0);
minTarget = localGetNested(cfg,'preheater','T_RO_in_min_C',-Inf);
maxTarget = localGetNested(cfg,'preheater','T_RO_in_max_C',Inf);
targetC = min(max(riseTarget,minTarget),maxTarget);
end

function hot = localSolarToOrcHotStream(SolarOut,Treturn_K,cfg,hotTemplate)
hot = hotTemplate;
if ~isfield(SolarOut,'feasible') || ~SolarOut.feasible || SolarOut.Q_useful_W <= 0
    hot.T_in = max(Treturn_K,cfg.orc.solar_adapter_return_T_K) + cfg.orc.solar_adapter_min_deltaT_K;
    hot.mdot = 1e-6;
    return
end

if localIsSyltherm800(hot.fluid)
    hot.T_in = max(SolarOut.T_HTF_out_K,Treturn_K + cfg.orc.solar_adapter_min_deltaT_K);
    hot.mdot = max(SolarOut.mdot_HTF_kg_s,1e-6);
    return
end

Tin = max(SolarOut.T_HTF_out_K,Treturn_K + cfg.orc.solar_adapter_min_deltaT_K);
deltaT = max(Tin - Treturn_K,cfg.orc.solar_adapter_min_deltaT_K);
cpEq = 4180;
hot.T_in = Tin;
hot.mdot = max(SolarOut.Q_useful_W/(cpEq*deltaT),1e-6);
end

function targetC = localPreheaterCondOutGuardC(cfg,SeawaterData,it)
% Minimum condenser outlet temperature needed for useful preheater duty.
enabled = localGetNested(cfg,'preheater','enforce_cond_out_above_feed',false);
if ~enabled
    targetC = NaN;
    return
end
marginK = localGetNested(cfg,'preheater','cond_out_min_deltaT_to_feed_K', ...
    localGetNested(cfg,'preheater','dT_min_K',3.0));
targetC = SeawaterData.SeaWater_Temperature_C(it) + marginK;
end

function stepConfig = localApplyPreheaterGuardToOrcConfig(baseConfig,cfg,targetC)
% Tell ORC dispatch to skip candidates that cannot feed the preheater.
stepConfig = baseConfig;
enabled = localGetNested(cfg,'preheater','enforce_cond_out_above_feed',false);
stepConfig.orc_dispatch_preheaterGuardEnabled = enabled && isfinite(targetC);
stepConfig.orc_dispatch_minCondOutletTemp_C = targetC;
end

function [SolarOut,flowFactor,flowStatus,SearchState,SearchDiag] = localSelectSolarOperatingPoint(SolarInput,SolarConfig,SearchState)
if nargin < 3 || isempty(SearchState)
    SearchState = localBlankSolarSearchState();
end
SearchDiag = localBlankSolarSearchDiag();
fc = localFlowControlConfig(SolarConfig);
Vref = localGet(SolarConfig,'V_Lmin_1module_reference',localGet(SolarConfig,'V_Lmin_1module',56.8));
if ~fc.enabled
    SolarInput.V_Lmin_1module = Vref;
    cacheIn = localGetSolarSolverCache(SearchState,1.0);
    if ~isempty(cacheIn)
        SolarInput.solver_cache = cacheIn;
        SearchDiag.solver_warm_start_used = true;
    end
    SolarOut = solar_field_ptc_v1(SolarInput,SolarConfig);
    flowFactor = 1;
    flowStatus = "FIXED_FLOW";
    [SolarOut,flowStatus] = localApplySolarOperatingGuards(SolarOut,flowStatus,fc);
    SearchDiag.status = "FIXED_FLOW";
    SearchDiag.candidates_evaluated = 1;
    SearchState = localUpdateSolarSearchState(SearchState,flowFactor,SolarInput,SolarOut);
    return
end

factors = unique([fc.factor_list(:); 1.0]);
factors = factors(isfinite(factors) & factors > 0);
if isempty(factors)
    factors = 1;
end

useAdaptive = localShouldUseAdaptiveSolarSearch(fc,SearchState,SolarInput);
if useAdaptive
    localFactors = localLocalFactorSubset(factors,SearchState.last_factor,fc.local_neighbor_steps);
    [Candidate,usedWarmStart] = localEvaluateSolarCandidates(SolarInput,SolarConfig,SearchState,Vref,fc,localFactors);
    SearchDiag.candidates_evaluated = numel(localFactors);
    SearchDiag.solver_warm_start_used = usedWarmStart;
    idx = localChooseSolarCandidate(Candidate,fc);
    needFull = localSolarCandidateNeedsFullFallback(Candidate,idx,factors,fc);
    if needFull
        [CandidateFull,usedWarmStartFull] = localEvaluateSolarCandidates(SolarInput,SolarConfig,SearchState,Vref,fc,factors);
        Candidate = CandidateFull;
        idx = localChooseSolarCandidate(Candidate,fc);
        SearchDiag.candidates_evaluated = SearchDiag.candidates_evaluated + numel(factors);
        SearchDiag.solver_warm_start_used = SearchDiag.solver_warm_start_used || usedWarmStartFull;
        SearchDiag.full_search_used = true;
        SearchDiag.status = "ADAPTIVE_FALLBACK_FULL";
    else
        SearchDiag.full_search_used = false;
        SearchDiag.status = "ADAPTIVE_LOCAL";
    end
else
    [Candidate,usedWarmStart] = localEvaluateSolarCandidates(SolarInput,SolarConfig,SearchState,Vref,fc,factors);
    idx = localChooseSolarCandidate(Candidate,fc);
    SearchDiag.candidates_evaluated = numel(factors);
    SearchDiag.solver_warm_start_used = usedWarmStart;
    SearchDiag.full_search_used = true;
    SearchDiag.status = "FULL_SEARCH";
end

SolarOut = Candidate(idx).SolarOut;
flowFactor = Candidate(idx).factor;
if abs(flowFactor - 1) <= 1e-9
    flowStatus = "NOMINAL_FLOW";
elseif flowFactor > 1
    flowStatus = "FLOW_INCREASED";
else
    flowStatus = "FLOW_REDUCED";
end
[SolarOut,flowStatus] = localApplySolarOperatingGuards(SolarOut,flowStatus,fc);
SearchState = localUpdateSolarSearchState(SearchState,flowFactor,SolarInput,SolarOut);
end

function [Candidate,usedWarmStart] = localEvaluateSolarCandidates(SolarInput,SolarConfig,SearchState,Vref,fc,factors)
Candidate = repmat(struct('SolarOut',struct(),'factor',NaN,'ToutC',NaN, ...
    'deltaT_K',NaN,'QusefulW',NaN,'feasible',false),numel(factors),1);
usedWarmStart = false;
for i = 1:numel(factors)
    trialInput = SolarInput;
    trialInput.V_Lmin_1module = Vref*factors(i);
    cacheIn = localGetSolarSolverCache(SearchState,factors(i));
    if ~isempty(cacheIn)
        trialInput.solver_cache = cacheIn;
        usedWarmStart = true;
    end
    trialOut = solar_field_ptc_v1(trialInput,SolarConfig);
    TinK = localGet(trialOut,'T_HTF_in_K',trialInput.T_HTF_in_K);
    ToutK = localGet(trialOut,'T_HTF_out_K',TinK);
    ToutC = localGet(trialOut,'T_HTF_out_K',localGet(trialOut,'T_HTF_in_K',NaN)) - 273.15;
    deltaT_K = ToutK - TinK;
    Candidate(i).SolarOut = trialOut;
    Candidate(i).factor = factors(i);
    Candidate(i).ToutC = ToutC;
    Candidate(i).deltaT_K = deltaT_K;
    Candidate(i).QusefulW = localGet(trialOut,'Q_useful_W',0);
    Candidate(i).feasible = localGet(trialOut,'feasible',false) && ...
        isfinite(deltaT_K) && deltaT_K >= fc.min_deltaT_gain_K && ...
        isfinite(ToutC) && ToutC <= fc.T_out_max_C;
end
end

function tf = localShouldUseAdaptiveSolarSearch(fc,SearchState,SolarInput)
tf = false;
if ~strcmpi(string(fc.search_mode),"adaptive_local_then_full")
    return
end
if ~isstruct(SearchState) || ~localGet(SearchState,'valid',false)
    return
end
if ~isfinite(localGet(SearchState,'last_factor',NaN))
    return
end

DNI = localGet(SolarInput,'DNI_Wm2',0);
TinK = localGet(SolarInput,'T_HTF_in_K',NaN);
lastDNI = localGet(SearchState,'last_DNI_Wm2',NaN);
lastTinK = localGet(SearchState,'last_Tin_K',NaN);
if ~(isfinite(DNI) && isfinite(TinK) && isfinite(lastDNI) && isfinite(lastTinK))
    return
end

dDNI = abs(DNI - lastDNI);
relDNI = dDNI/max(abs(lastDNI),50);
dTin = abs(TinK - lastTinK);
tf = dDNI <= fc.full_search_dni_abs_change_Wm2 && ...
    relDNI <= fc.full_search_dni_rel_change && ...
    dTin <= fc.full_search_Tin_change_K;
end

function localFactors = localLocalFactorSubset(factors,lastFactor,neighborSteps)
neighborSteps = max(0,round(neighborSteps));
[~,idx] = min(abs(factors - lastFactor));
i1 = max(1,idx-neighborSteps);
i2 = min(numel(factors),idx+neighborSteps);
localFactors = factors(i1:i2);
end

function tf = localSolarCandidateNeedsFullFallback(Candidate,idx,factors,fc)
tf = true;
if isempty(Candidate) || idx < 1 || idx > numel(Candidate)
    return
end
if numel(Candidate) >= numel(factors)
    tf = false;
    return
end
if ~Candidate(idx).feasible
    return
end

localFactors = [Candidate.factor];
selectedFactor = Candidate(idx).factor;
[~,globalIdx] = min(abs(factors - selectedFactor));
isLocalLowEdge = abs(selectedFactor - min(localFactors)) <= 1e-9 && globalIdx > 1;
isLocalHighEdge = abs(selectedFactor - max(localFactors)) <= 1e-9 && globalIdx < numel(factors);
if isLocalLowEdge || isLocalHighEdge
    return
end

ToutC = Candidate(idx).ToutC;
marginC = max(0,fc.full_search_temp_margin_C);
if isfinite(ToutC) && (ToutC >= fc.T_out_max_C - marginC || ToutC <= fc.T_out_min_C + marginC)
    return
end
tf = false;
end

function SearchState = localUpdateSolarSearchState(SearchState,flowFactor,SolarInput,SolarOut)
if ~localGet(SolarOut,'feasible',false) || localGet(SolarOut,'Q_useful_W',0) <= 0
    SearchState = localBlankSolarSearchState();
    return
end
SearchState.valid = true;
SearchState.last_factor = flowFactor;
SearchState.last_DNI_Wm2 = localGet(SolarInput,'DNI_Wm2',NaN);
SearchState.last_Tin_K = localGet(SolarInput,'T_HTF_in_K',NaN);
if isfield(SolarOut,'solver_cache') && isstruct(SolarOut.solver_cache)
    SearchState = localStoreSolarSolverCache(SearchState,flowFactor,SolarOut.solver_cache);
end
end

function cache = localGetSolarSolverCache(SearchState,factor)
cache = [];
if ~isstruct(SearchState) || ~isfield(SearchState,'cache') || isempty(SearchState.cache)
    return
end
for i = 1:numel(SearchState.cache)
    if isfield(SearchState.cache(i),'factor') && abs(SearchState.cache(i).factor - factor) <= 1e-9
        cache = SearchState.cache(i).solver_cache;
        return
    end
end
end

function SearchState = localStoreSolarSolverCache(SearchState,factor,solverCache)
if ~isfield(SearchState,'cache') || isempty(SearchState.cache)
    SearchState.cache = struct('factor',{},'solver_cache',{});
end
for i = 1:numel(SearchState.cache)
    if abs(SearchState.cache(i).factor - factor) <= 1e-9
        SearchState.cache(i).solver_cache = solverCache;
        return
    end
end
k = numel(SearchState.cache) + 1;
SearchState.cache(k).factor = factor;
SearchState.cache(k).solver_cache = solverCache;
end

function S = localBlankSolarSearchState()
S = struct();
S.valid = false;
S.last_factor = NaN;
S.last_DNI_Wm2 = NaN;
S.last_Tin_K = NaN;
S.cache = struct('factor',{},'solver_cache',{});
end

function D = localBlankSolarSearchDiag()
D = struct();
D.status = "UNINITIALIZED";
D.candidates_evaluated = 0;
D.full_search_used = false;
D.solver_warm_start_used = false;
end

function [SolarOut,flowStatus] = localApplySolarOperatingGuards(SolarOut,flowStatus,fc)
TinK = localGet(SolarOut,'T_HTF_in_K',NaN);
ToutK = localGet(SolarOut,'T_HTF_out_K',TinK);
ToutC = ToutK - 273.15;
deltaT_K = ToutK - TinK;
if isfinite(ToutC) && ToutC > fc.T_out_max_C
    flowStatus = "FLOW_MAX_HIGH_TEMP";
    SolarOut.feasible = false;
    SolarOut.Q_useful_W = 0;
    SolarOut.status = 'TEMP_LIMIT_HIGH';
elseif isfinite(deltaT_K) && deltaT_K < fc.min_deltaT_gain_K && ...
        ~strcmpi(string(localGet(SolarOut,'status','')),"SOLAR_OFF")
    flowStatus = "LOW_SOLAR_GAIN";
    SolarOut.feasible = false;
    SolarOut.Q_useful_W = 0;
    SolarOut.status = 'LOW_SOLAR_GAIN';
end
end

function tf = localSolarShouldShutDown(cfg,SolarOut)
enabled = localGetNested(cfg,'solar','shutdown_when_no_useful_heat',true);
tf = enabled && (~isfield(SolarOut,'feasible') || ~SolarOut.feasible || ...
    localGet(SolarOut,'Q_useful_W',0) <= 0);
end

function State = localApplySolarOffState(State,cfg,orcDesign,orcTemplates,orcConfig,SeawaterData,it)
Tstandby_K = cfg.solar.T_HTF_in_K;
State.TsolarIn_K = Tstandby_K;
State.TsolarNextRaw_K = Tstandby_K;
State.TsolarNext_K = Tstandby_K;
State.SolarOut.T_HTF_in_K = Tstandby_K;
State.SolarOut.T_HTF_out_K = Tstandby_K;
State.SolarOut.mdot_HTF_kg_s = 0;
State.SolarOut.Q_useful_W = 0;
State.SolarOut.dP_HTF_Pa = 0;
State.SolarOut.feasible = false;
State.TcwNext_C = State.TcwIn_C;
State.TcwCondOut_C = State.TcwIn_C;
State.PHOut = localBlankPHOut(State.TcwIn_C,SeawaterData.SeaWater_Temperature_C(it));
State.CTOut = localBlankCTOut(State.TcwIn_C);
State.orcStep = localBuildFastOffOrcStep(orcDesign,orcTemplates,orcConfig,Tstandby_K,State.TcwIn_C);
State.ORC_feasible = false;
State.RO_feasible = false;
State = localResetRoDiagnostics(State);
State.system_status = "SYSTEM_OFF_SOLAR_OFF";
State.orc_status = "skipped-solar-off";
State.ro_status = "SKIPPED_SOLAR_OFF";
State.SolarSearchState = localBlankSolarSearchState();
State.solar_flow_search_status = "SOLAR_OFF_RESET";
State.solar_flow_candidates_evaluated = 0;
State.solar_flow_full_search_used = false;
State.solar_solver_warm_start_used = false;
State.solar_residual_K = 0;
State.cw_residual_K = 0;
end

function idx = localChooseSolarCandidate(Candidate,fc)
Tout = [Candidate.ToutC];
Q = [Candidate.QusefulW];
feas = [Candidate.feasible];
factor = [Candidate.factor];

withinBand = feas & Tout >= fc.T_out_min_C & Tout <= fc.T_out_max_C;
if any(withinBand)
    idxList = find(withinBand);
    switch lower(string(fc.selection_mode))
        case "closest_target"
            [~,k] = min(abs(Tout(idxList) - fc.T_out_target_C) + 1e-3*abs(factor(idxList) - 1));
        otherwise
            [~,k] = max(Q(idxList) - 1e3*abs(Tout(idxList) - fc.T_out_target_C));
    end
    idx = idxList(k);
    return
end

belowMax = feas & Tout <= fc.T_out_max_C;
if any(belowMax)
    idxList = find(belowMax);
    [~,k] = max(Tout(idxList) - 1e-3*abs(factor(idxList) - 1));
    idx = idxList(k);
    return
end

if any(feas)
    idxList = find(feas);
    [~,k] = min(Tout(idxList));
    idx = idxList(k);
    return
end

[~,idx] = min(abs(factor - 1));
end

function fc = localFlowControlConfig(SolarConfig)
fc = struct();
fc.enabled = false;
fc.factor_list = 1;
fc.selection_mode = 'max_heat_below_limit';
fc.search_mode = 'adaptive_local_then_full';
fc.local_neighbor_steps = 1;
fc.full_search_dni_abs_change_Wm2 = 150.0;
fc.full_search_dni_rel_change = 0.35;
fc.full_search_Tin_change_K = 8.0;
fc.full_search_temp_margin_C = 8.0;
fc.T_out_target_C = 390;
fc.T_out_min_C = 160;
fc.T_out_max_C = 400;
fc.min_deltaT_gain_K = localGet(SolarConfig,'min_deltaT_gain_K',5.0);
if isfield(SolarConfig,'flow_control') && isstruct(SolarConfig.flow_control)
    C = SolarConfig.flow_control;
    fc.enabled = localGet(C,'enabled',fc.enabled);
    fc.factor_list = localGet(C,'factor_list',fc.factor_list);
    fc.selection_mode = localGet(C,'selection_mode',fc.selection_mode);
    fc.search_mode = localGet(C,'search_mode',fc.search_mode);
    fc.local_neighbor_steps = localGet(C,'local_neighbor_steps',fc.local_neighbor_steps);
    fc.full_search_dni_abs_change_Wm2 = localGet(C,'full_search_dni_abs_change_Wm2',fc.full_search_dni_abs_change_Wm2);
    fc.full_search_dni_rel_change = localGet(C,'full_search_dni_rel_change',fc.full_search_dni_rel_change);
    fc.full_search_Tin_change_K = localGet(C,'full_search_Tin_change_K',fc.full_search_Tin_change_K);
    fc.full_search_temp_margin_C = localGet(C,'full_search_temp_margin_C',fc.full_search_temp_margin_C);
    fc.T_out_target_C = localGet(C,'T_out_target_C',fc.T_out_target_C);
    fc.T_out_min_C = localGet(C,'T_out_min_C',fc.T_out_min_C);
    fc.T_out_max_C = localGet(C,'T_out_max_C',fc.T_out_max_C);
    fc.min_deltaT_gain_K = localGet(C,'min_deltaT_gain_K',fc.min_deltaT_gain_K);
end
end

function State = localApplySolarPump(State,cfg,orcConfig,hotStream,evapRate)
State.dP_solar_field_Pa = max(0,localGet(State.SolarOut,'dP_HTF_Pa',0));
State.dP_orc_evap_hot_Pa = max(0,localGet(evapRate,'dp_orchtf',0));
State.dP_solar_loop_Pa = State.dP_solar_field_Pa + State.dP_orc_evap_hot_Pa;
State.W_solar_pump_W = 0;
pumpCfg = localGetNested(cfg,'solar','pump',struct());
if ~isstruct(pumpCfg) || ~localGet(pumpCfg,'enabled',false)
    return
end

mdot = max(0,localGet(State.SolarOut,'mdot_HTF_kg_s',0));
if mdot <= 0 || State.dP_solar_loop_Pa <= 0
    return
end

etaHyd = localGet(pumpCfg,'eta_hydraulic',0.75);
etaMotor = localGet(pumpCfg,'eta_motor',0.95);
etaTotal = max(etaHyd*etaMotor,eps);
Tin = localGet(State.SolarOut,'T_HTF_in_K',hotStream.T_in);
Tout = localGet(State.SolarOut,'T_HTF_out_K',hotStream.T_in);
Tavg = 0.5*(Tin + Tout);
try
    rho = orc_stream_properties(orcConfig,hotStream,'D','T',Tavg,'P',hotStream.P_in);
catch
    rho = 850;
end
rho = max(rho,eps);
State.W_solar_pump_W = mdot*State.dP_solar_loop_Pa/(rho*etaTotal);
end

function State = localApplySolarReturnSink(State,cfg,orcConfig,hotStream)
State.Q_solar_return_sink_W = 0;
if ~isfield(cfg,'storage') || ~isstruct(cfg.storage) || ...
        ~localGet(cfg.storage,'solar_return_sink_enabled',false)
    return
end

TinTarget = State.TsolarIn_K;
Traw = State.TsolarNextRaw_K;
if ~(isfinite(Traw) && isfinite(TinTarget) && Traw > TinTarget)
    return
end

mdot = max(0,localGet(State.SolarOut,'mdot_HTF_kg_s',0));
if mdot <= 0
    return
end

Tavg = 0.5*(Traw + TinTarget);
try
    cp = orc_stream_properties(orcConfig,hotStream,'C','T',Tavg,'P',hotStream.P_in);
catch
    cp = 2000;
end
State.Q_solar_return_sink_W = max(0,mdot*cp*(Traw - TinTarget));
State.TsolarNext_K = TinTarget;
end

function [StorageState,StorageOut] = localRunStorage(cfg,StorageState,Q_excess_W)
if isfield(cfg,'storage') && isstruct(cfg.storage)
    storageCfg = cfg.storage;
else
    storageCfg = struct('enabled',false);
end
Input = struct();
Input.Q_charge_request_W = max(0,Q_excess_W);
Input.dt_s = cfg.sim.dt_s;
[StorageState,StorageOut] = storage_water_tank_v1(StorageState,Input,storageCfg);
end

function tf = localIsSyltherm800(fluid)
name = regexprep(lower(char(string(fluid))),'[^a-z0-9]','');
tf = any(strcmp(name,{'syltherm800','syltherm'}));
end

function State = localBlankState(TsolarIn_K,TcwIn_C,PHWasOn)
if nargin < 3
    PHWasOn = false;
end
State = struct();
State.TsolarIn_K = TsolarIn_K;
State.TsolarNext_K = TsolarIn_K;
State.TsolarNextRaw_K = TsolarIn_K;
State.TcwIn_C = TcwIn_C;
State.TcwNext_C = TcwIn_C;
State.TcwCondOut_C = TcwIn_C;
State.TcwCondOutGuard_C = NaN;
State.W_ORC_net_W = 0;
State.Q_ORC_evap_W = 0;
State.Q_ORC_cond_W = 0;
State.Q_solar_return_sink_W = 0;
State.W_solar_pump_W = 0;
State.dP_solar_field_Pa = 0;
State.dP_orc_evap_hot_Pa = 0;
State.dP_solar_loop_Pa = 0;
State.P_ORC_evap_Pa = NaN;
State.P_ORC_cond_Pa = NaN;
State.N_train_running = 0;
State.W_RO_total_W = 0;
State.Qp_total_m3h = 0;
State.W_available_for_RO_W = 0;
State = localResetRoDiagnostics(State);
State.ORC_feasible = false;
State.RO_feasible = false;
State.converged = false;
State.iter = 0;
State.solar_residual_K = NaN;
State.cw_residual_K = NaN;
State.PHWasOn = logical(PHWasOn);
State.orc_status = "";
State.ro_status = "RO_OFF";
State.solar_flow_factor = 1;
State.solar_flow_status = "UNINITIALIZED";
State.solar_flow_search_status = "UNINITIALIZED";
State.solar_flow_candidates_evaluated = 0;
State.solar_flow_full_search_used = false;
State.solar_solver_warm_start_used = false;
State.system_status = "UNINITIALIZED";
State.timing_solar_select_s = 0;
State.timing_orc_dispatch_s = 0;
State.timing_ro_heat_rejection_dispatch_s = 0;
State.SolarSearchState = localBlankSolarSearchState();
State.SolarOut = struct();
State.orcStep = struct();
State.PHOut = localBlankPHOut(TcwIn_C,NaN);
State.CTOut = localBlankCTOut(TcwIn_C);
end

function Dispatch = localBlankDispatch(TcwHotC,TswRawC,Ntotal)
Dispatch = struct();
Dispatch.N_train_total = Ntotal;
Dispatch.N_train_running = 0;
Dispatch.W_RO_total_W = 0;
Dispatch.Qp_total_m3h = 0;
Dispatch.W_available_for_RO_W = 0;
Dispatch = localResetRoDiagnostics(Dispatch);
Dispatch.RO_feasible = false;
Dispatch.RO_domain_fail = false;
Dispatch.RO_infeasible = false;
Dispatch.system_status = "POWER_DEFICIT";
Dispatch.ro_status = "RO_OFF";
Dispatch.PHOut = localBlankPHOut(TcwHotC,TswRawC);
Dispatch.CTOut = localBlankCTOut(TcwHotC);
end

function S = localResetRoDiagnostics(S)
S.RO_InTrainingDomain = false;
S.RO_ClassifierFeasible = false;
S.RO_ANN_Feasible = false;
S.RO_P_feasible = NaN;
S.RO_Qp_train_m3h = NaN;
S.RO_W_train_kW = NaN;
S.RO_SEC_kWh_m3 = NaN;
S.RO_Cp_mg_L = NaN;
S.RO_P1_opt_gauge_MPa = NaN;
S.RO_P2_opt_gauge_MPa = NaN;
S.RO_P_CpBoundary = NaN;
S.RO_raw_Qp_train_m3h = NaN;
S.RO_raw_W_train_kW = NaN;
S.RO_raw_SEC_kWh_m3 = NaN;
S.RO_raw_Cp_mg_L = NaN;
S.RO_raw_P1_opt_gauge_MPa = NaN;
S.RO_raw_P2_opt_gauge_MPa = NaN;
end

function cand = localAttachRoDiagnostics(cand,ROOut)
cand.RO_InTrainingDomain = logical(ROOut.InTrainingDomain(1));
cand.RO_ClassifierFeasible = logical(ROOut.ClassifierFeasible(1));
cand.RO_ANN_Feasible = logical(ROOut.Feasible(1));
cand.RO_P_feasible = ROOut.P_feasible(1);
cand.RO_Qp_train_m3h = ROOut.Qp_train_m3h(1);
cand.RO_W_train_kW = ROOut.W_RO_train_kW(1);
cand.RO_SEC_kWh_m3 = ROOut.SEC_kWh_m3(1);
cand.RO_Cp_mg_L = ROOut.Cp_mg_L(1);
cand.RO_P1_opt_gauge_MPa = ROOut.P1_opt_gauge_MPa(1);
cand.RO_P2_opt_gauge_MPa = ROOut.P2_opt_gauge_MPa(1);
cand.RO_P_CpBoundary = ROOut.P_CpBoundary(1);
cand.RO_raw_Qp_train_m3h = ROOut.Raw_Qp_train_m3h(1);
cand.RO_raw_W_train_kW = ROOut.Raw_W_RO_train_kW(1);
cand.RO_raw_SEC_kWh_m3 = ROOut.Raw_SEC_kWh_m3(1);
cand.RO_raw_Cp_mg_L = ROOut.Raw_Cp_mg_L(1);
cand.RO_raw_P1_opt_gauge_MPa = ROOut.Raw_P1_opt_gauge_MPa(1);
cand.RO_raw_P2_opt_gauge_MPa = ROOut.Raw_P2_opt_gauge_MPa(1);
end

function PHOut = localBlankPHOut(TcwHotC,TswRawC)
PHOut = struct();
PHOut.Q_recovered_W = 0;
PHOut.T_RO_in_C = TswRawC;
PHOut.T_cw_out_C = TcwHotC;
PHOut.T_hot_out_C = TcwHotC;
PHOut.T_sw_out_C = TswRawC;
PHOut.preheater_on = false;
PHOut.deltaT_available_K = TcwHotC - TswRawC;
PHOut.deltaT_ON_K = NaN;
PHOut.deltaT_OFF_K = NaN;
PHOut.feasible = true;
PHOut.status = 'SKIPPED_RO_OFF';
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

CTInput = struct();
CTInput.T_w_in_C = TcwInC;
CTInput.mdot_water = cfg.orc.mdot_cw_design_kg_s;
CTInput.T_w_out_target_C = targetC;
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

function D = localOrcDispatchDiagnostics(orcStep,ORCFeasible,orcStatus)
D = struct();
D.off_reason = "";
D.best_status = "";
D.n_candidates_available = 0;
D.n_candidates_evaluated = 0;
D.best_W_net_W = NaN;
D.best_evap_A_ratio = NaN;
D.best_cond_A_ratio = NaN;
D.best_evap_pinch_K = NaN;
D.best_cond_pinch_K = NaN;

if ORCFeasible
    D.off_reason = "ON";
    return
end

statusText = string(orcStatus);
if statusText == "skipped-solar-off"
    D.off_reason = "SOLAR_OFF";
    return
end

if ~isstruct(orcStep) || ~isfield(orcStep,'orc_dispatch') || ~isstruct(orcStep.orc_dispatch)
    D.off_reason = "NO_DISPATCH_LOG";
    return
end

disp = orcStep.orc_dispatch;
D.n_candidates_available = localGet(disp,'orc_nCandidatesAvailable',0);
D.n_candidates_evaluated = localGet(disp,'orc_nCandidatesEvaluated',0);
if ~isfield(disp,'orc_candidateLog') || isempty(disp.orc_candidateLog)
    D.off_reason = "NO_CANDIDATE_LOG";
    return
end

log = disp.orc_candidateLog(:);
status = strings(numel(log),1);
W = nan(numel(log),1);
for i = 1:numel(log)
    status(i) = string(localGet(log(i),'status',''));
    W(i) = localGet(log(i),'W_orcnet',NaN);
end

finiteW = isfinite(W);
if any(finiteW)
    idxList = find(finiteW);
    [~,k] = max(W(idxList));
    ib = idxList(k);
else
    ib = 1;
end

best = log(ib);
D.best_status = status(ib);
D.best_W_net_W = localGet(best,'W_orcnet',NaN);
D.best_evap_A_ratio = localGet(best,'evap_A_ratio',NaN);
D.best_cond_A_ratio = localGet(best,'cond_A_ratio',NaN);
D.best_evap_pinch_K = localGet(best,'evap_pinch_K',NaN);
D.best_cond_pinch_K = localGet(best,'cond_pinch_K',NaN);

D.off_reason = localClassifyOrcOffReason(status,best);
end

function reason = localClassifyOrcOffReason(status,best)
status = status(strlength(status) > 0);
if isempty(status)
    reason = "UNKNOWN_NO_STATUS";
    return
end

if any(contains(status,"prescreen-source-cold"))
    reason = "SOURCE_TOO_COLD";
    return
end
if any(contains(status,"prescreen-sink-hot"))
    reason = "SINK_TOO_HOT";
    return
end
if any(contains(status,"prescreen-hot-capacity"))
    reason = "HOT_STREAM_CAPACITY";
    return
end
if any(contains(status,"prescreen-cold-capacity"))
    reason = "COLD_STREAM_CAPACITY";
    return
end
if all(contains(status,"prescreen-low-power"))
    reason = "MIN_POWER_OR_LOW_NET_WORK";
    return
end
if any(contains(status,"preheater-temp-guard"))
    reason = "PREHEATER_COND_OUT_GUARD";
    return
end

evapA = localGet(best,'evap_A_ratio',NaN);
condA = localGet(best,'cond_A_ratio',NaN);
evapPinch = localGet(best,'evap_pinch_K',NaN);
condPinch = localGet(best,'cond_pinch_K',NaN);
guarded = localGet(best,'guardedFlag',false) || localGet(best,'errorFlag',false);

if guarded || any(contains(status,"guarded") | contains(status,"error") | contains(status,"thrown"))
    reason = "NUMERICAL_OR_PROPERTY_GUARD";
elseif isfinite(evapPinch) && evapPinch <= 0
    reason = "EVAPORATOR_PINCH_LIMIT";
elseif isfinite(condPinch) && condPinch <= 0
    reason = "CONDENSER_PINCH_LIMIT";
elseif isfinite(evapA) && evapA > 1.01
    reason = "EVAPORATOR_AREA_LIMIT";
elseif isfinite(condA) && condA > 1.01
    reason = "CONDENSER_AREA_LIMIT";
else
    reason = "NO_FEASIBLE_DISPATCH_CANDIDATE";
end
end

function orcAnnual = localBuildOrcAnnual(config,orcStep,dt_s)
nStep = numel(orcStep);
orcAnnual = struct();
orcAnnual.orc_modelVersion = config.orc_modelVersion;
orcAnnual.orc_nStep = nStep;
orcAnnual.orc_dt_s = repmat(dt_s,nStep,1);
fields = {'orc_W_net','orc_Q_evap','orc_Q_cond','orc_mdot','orc_P_evap','orc_P_cond', ...
    'orc_T_htf_in','orc_T_htf_out','orc_T_cw_in','orc_T_cw_out', ...
    'orc_A_ratio_evap','orc_A_ratio_cond'};
for i = 1:numel(fields)
    orcAnnual.(fields{i}) = nan(nStep,1);
end
orcAnnual.orc_feasible = false(nStep,1);
orcAnnual.orc_status = cell(nStep,1);
orcAnnual.orcStep = orcStep;
for it = 1:nStep
    st = orcStep{it};
    th = st.orc_thermo;
    er = st.orc_evaporator_rate;
    cr = st.orc_condenser_rate;
    orcAnnual.orc_W_net(it) = th.W_orcnet;
    orcAnnual.orc_Q_evap(it) = th.Q_orcevap;
    orcAnnual.orc_Q_cond(it) = th.Q_orccond;
    orcAnnual.orc_mdot(it) = th.mdot_orc;
    orcAnnual.orc_P_evap(it) = th.P_orcevap;
    orcAnnual.orc_P_cond(it) = th.P_orccond;
    orcAnnual.orc_T_htf_in(it) = er.T_orchtf_in;
    orcAnnual.orc_T_htf_out(it) = er.T_orchtf_out;
    orcAnnual.orc_T_cw_in(it) = cr.T_orccw_in;
    orcAnnual.orc_T_cw_out(it) = cr.T_orccw_out;
    orcAnnual.orc_A_ratio_evap(it) = er.A_ratio;
    orcAnnual.orc_A_ratio_cond(it) = cr.A_ratio;
    orcAnnual.orc_feasible(it) = st.orc_feasible;
    orcAnnual.orc_status{it} = localGet(st,'orc_status','');
end
orcAnnual.orc_E_net_kWh = sum(orcAnnual.orc_W_net.*orcAnnual.orc_dt_s,'omitnan')/3.6e6;
orcAnnual.orc_E_evap_kWh = sum(orcAnnual.orc_Q_evap.*orcAnnual.orc_dt_s,'omitnan')/3.6e6;
orcAnnual.orc_E_cond_kWh = sum(orcAnnual.orc_Q_cond.*orcAnnual.orc_dt_s,'omitnan')/3.6e6;
orcAnnual.orc_hours = sum(orcAnnual.orc_dt_s)/3600;
orcAnnual.orc_feasibleHours = sum(orcAnnual.orc_dt_s(orcAnnual.orc_feasible))/3600;
end

function Step = localBlankOrcStep(orcDesign,hotStream,coldStream,config)
op = struct('orc_P_evap',orcDesign.orc_thermo.P_orcevap, ...
    'orc_P_cond',orcDesign.orc_thermo.P_orccond, ...
    'orc_mdot',orcDesign.orc_thermo.mdot_orc);
Step = orc_offdesign_dispatch(orcDesign,hotStream,coldStream,op,config);
end

function Step = localBuildFastOffOrcStep(orcDesign,orcTemplates,config,Tsolar_K,Tcw_C)
hotStream = orcTemplates.orcHotDesign;
coldStream = orcTemplates.orcColdDesign;
hotStream.T_in = Tsolar_K;
coldStream.T_in = Tcw_C + 273.15;

thermo = struct();
thermo.orc_fluid = config.orc_fluid;
thermo.P_orc_crit = localGet(orcDesign.orc_thermo,'P_orc_crit',NaN);
thermo.P_orcevap = localGet(orcDesign.orc_thermo,'P_orcevap',NaN);
thermo.P_orccond = localGet(orcDesign.orc_thermo,'P_orccond',NaN);
thermo.P_orcpump_out = thermo.P_orcevap;
thermo.P_orcturb_out = thermo.P_orccond;
thermo.dp_orcevap_wf = 0;
thermo.dp_orccond_wf = 0;
thermo.mdot_orc = 0;
thermo.W_orcturb = 0;
thermo.W_orcpump = 0;
thermo.W_orcnet = 0;
thermo.Q_orcevap = 0;
thermo.Q_orccond = 0;
thermo.eta_orc_th = 0;
thermo.orc_energyBalanceOK = true;

Step = struct();
Step.orc_modelVersion = config.orc_modelVersion;
Step.orc_thermo = thermo;
Step.orc_evaporator_rate = localFastBlankHxRate('evaporator',hotStream.T_in);
Step.orc_condenser_rate = localFastBlankHxRate('condenser',coldStream.T_in);
Step.orc_hotStream = hotStream;
Step.orc_coldStream = coldStream;
Step.orc_operatingInput = struct('orc_P_evap',thermo.P_orcevap, ...
    'orc_P_cond',thermo.P_orccond,'orc_mdot',0);
Step.orc_hydraulicIterLog = struct([]);
Step.orc_hydraulicConverged = false;
Step.orc_hydraulicFinalRel = NaN;
Step.orc_hydraulicNiter = 0;
Step.orc_errorCaught = false;
Step.orc_errorMessage = '';
Step.orc_status = 'skipped-solar-off';
Step.orc_feasible = false;
Step.orc_dispatch = struct('orc_mode','skipped','orc_foundFeasible',false, ...
    'orc_nCandidatesAvailable',0,'orc_nCandidatesEvaluated',0, ...
    'orc_candidateLog',struct([]),'orc_elapsed_s',0);
Step.orc_elapsed_s = 0;
end

function hx = localFastBlankHxRate(hxType,T_in)
hx = struct();
hx.orc_hxType = hxType;
hx.N_parallel_installed = 0;
hx.N_parallel_active = 0;
hx.A_geo_module = NaN;
hx.A_req_module = 0;
hx.A_ratio = 0;
hx.A_tol_rel = NaN;
hx.Q_orcevap_module = 0;
hx.Q_orcevap_total = 0;
hx.Q_orccond_module = 0;
hx.Q_orccond_total = 0;
hx.T_orchtf_in = T_in;
hx.T_orchtf_int = T_in;
hx.T_orchtf_out = T_in;
hx.T_orccw_in = T_in;
hx.T_orccw_int = T_in;
hx.T_orccw_out = T_in;
hx.dp_orcevap_wf = 0;
hx.dp_orccond_wf = 0;
hx.dp_orchtf = 0;
hx.dp_orccw = 0;
hx.deltaT_pinch = NaN;
hx.orc_areaOK = false;
hx.orc_approachOK = false;
hx.orc_feasible = false;
hx.orc_elapsed_s = 0;
hx.zones = struct();
end

function op = localStepToOperatingInput(orcStep)
th = orcStep.orc_thermo;
op = struct('orc_P_evap',th.P_orcevap,'orc_P_cond',th.P_orccond,'orc_mdot',th.mdot_orc);
if isfield(orcStep,'orc_hotStream')
    op.orc_hot_T_in = localGet(orcStep.orc_hotStream,'T_in',NaN);
    op.orc_hot_mdot = localGet(orcStep.orc_hotStream,'mdot',NaN);
end
if isfield(orcStep,'orc_coldStream')
    op.orc_cold_T_in = localGet(orcStep.orc_coldStream,'T_in',NaN);
    op.orc_cold_mdot = localGet(orcStep.orc_coldStream,'mdot',NaN);
end
end

function solver = localSolverConfig(cfg)
solver = struct();
solver.max_iter = localGetNested(cfg,'coupling','max_iter',12);
solver.tol_solar_K = localGetNested(cfg,'coupling','tol_solar_K',1.00);
solver.tol_cw_K = localGetNested(cfg,'coupling','tol_cw_K',0.25);
solver.relax = localGetNested(cfg,'coupling','relax',1.00);
end

function y = localRelax(oldValue,newValue,relax)
if isfinite(newValue)
    y = (1-relax)*oldValue + relax*newValue;
else
    y = oldValue;
end
end

function y = localNextGuess(value,defaultValue)
if isfinite(value)
    y = value;
else
    y = defaultValue;
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

function Cf = localSeawaterConcentration(T,it)
names = T.Properties.VariableNames;
if any(strcmp(names,'Cf_kg_m3'))
    Cf = T.Cf_kg_m3(it);
elseif any(strcmp(names,'Salinity_kg_m3'))
    Cf = T.Salinity_kg_m3(it);
elseif any(strcmp(names,'Salinity_CMEMS_native'))
    Cf = T.Salinity_CMEMS_native(it);
else
    error('system_hourly_coupled_solver_v1:MissingSalinity', ...
        'No recognized salinity/concentration column was found in seawater table.');
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

function value = localGet(S,fieldName,defaultValue)
if isstruct(S) && isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end

function value = localGetNested(S,sectionName,fieldName,defaultValue)
if isfield(S,sectionName) && isstruct(S.(sectionName)) && ...
        isfield(S.(sectionName),fieldName) && ~isempty(S.(sectionName).(fieldName))
    value = S.(sectionName).(fieldName);
else
    value = defaultValue;
end
end
