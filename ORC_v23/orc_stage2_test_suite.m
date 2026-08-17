function orcTest = orc_stage2_test_suite(orcDesign,config)
% ORC_STAGE2_TEST_SUITE Run comprehensive fixed-geometry ORC stress tests.
%
% The test suite keeps the Stage-1 evaporator and condenser geometry frozen.
% It perturbs hot-stream, cooling-stream and ORC operating inputs to check
% whether Stage-2 rating remains numerically robust across normal and extreme
% operating conditions. Some extreme cases are expected to be infeasible.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 2 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % suite timer [-]

% =========================================================================
% DESIGN BASELINE
% =========================================================================
orcHotBase = orcDesign.orc_hotStream_design;         % design hot stream [-]
orcColdBase = orcDesign.orc_coldStream_design;       % design cold stream [-]
orcThermoBase = orcDesign.orc_thermo;                % design ORC state [-]

opBase = struct();                                   % design command [-]
opBase.orc_P_evap = orcThermoBase.P_orcevap;         % [Pa]
opBase.orc_P_cond = orcThermoBase.P_orccond;         % [Pa]
opBase.orc_mdot = orcThermoBase.mdot_orc;            % [kg/s]

T_sat_evap = orcThermoBase.T_orcturb_in;             % evap saturation [K]
T_sat_cond = orcThermoBase.T_orcpump_in;             % cond saturation [K]

% =========================================================================
% CASE DEFINITION
% =========================================================================
caseList = localBuildCases(orcHotBase,orcColdBase,opBase, ...
    T_sat_evap,T_sat_cond);                          % test definitions [-]
nCase = numel(caseList);                             % [-]

% =========================================================================
% PREALLOCATE RESULT STRUCT
% =========================================================================
blank = localBlankResult();                          % empty row [-]
caseResult = repmat(blank,nCase,1);                  % results [-]

% =========================================================================
% RUN CASES WITH ERROR CAPTURE
% =========================================================================
for ic = 1:nCase
    c = caseList(ic);                                % current case [-]
    tCase = tic;                                     % case timer [-]

    try
        orcStep = orc_offdesign_rating( ...
            orcDesign,c.orcHotStream,c.orcColdStream,c.orcOperatingInput,config);

        er = orcStep.orc_evaporator_rate;            % evaporator rating [-]
        cr = orcStep.orc_condenser_rate;             % condenser rating [-]
        th = orcStep.orc_thermo;                     % ORC thermo [-]

        r = blank;                                   % result row [-]
        r.caseNo = ic;                               % [-]
        r.caseName = c.caseName;                     % [-]
        r.caseGroup = c.caseGroup;                   % [-]
        r.expected = c.expected;                     % [-]
        r.T_orchtf_in_C = c.orcHotStream.T_in - 273.15; % [C]
        r.mdot_orchtf = c.orcHotStream.mdot;         % [kg/s]
        r.T_orccw_in_C = c.orcColdStream.T_in - 273.15; % [C]
        r.mdot_orccw = c.orcColdStream.mdot;         % [kg/s]
        r.mdot_orc = th.mdot_orc;                    % [kg/s]
        r.P_orcevap_bar = th.P_orcevap/1e5;          % [bar]
        r.P_orccond_bar = th.P_orccond/1e5;          % [bar]
        r.W_orcnet_kW = th.W_orcnet/1e3;             % [kW]
        r.Q_orcevap_kW = th.Q_orcevap/1e3;           % [kW]
        r.Q_orccond_kW = th.Q_orccond/1e3;           % [kW]
        r.T_orchtf_out_C = er.T_orchtf_out - 273.15; % [C]
        r.T_orccw_out_C = cr.T_orccw_out - 273.15;   % [C]
        r.evap_A_ratio = er.A_ratio;                 % [-]
        r.cond_A_ratio = cr.A_ratio;                 % [-]
        r.evap_pinch_K = er.deltaT_pinch;            % [K]
        r.cond_pinch_K = cr.deltaT_pinch;            % [K]
        r.dp_evap_wf_kPa = er.dp_orcevap_wf/1e3;     % [kPa]
        r.dp_cond_wf_kPa = cr.dp_orccond_wf/1e3;     % [kPa]
        r.hydraulicConv = orcStep.orc_hydraulicConverged; % [-]
        r.hydraulicRel = orcStep.orc_hydraulicFinalRel; % [-]
        r.feasible = orcStep.orc_feasible;           % [-]
        r.errorFlag = false;                         % no thrown error [-]
        r.guardedFlag = localGetStepField(orcStep,'orc_errorCaught',false); % [-]
        r.errorMessage = localGetStepField(orcStep,'orc_errorMessage',''); % [-]
        r.status = localGetStepField(orcStep,'orc_status','rated'); % [-]
        r.elapsed_s = toc(tCase);                    % [s]
        r.orcStep = orcStep;                         % detailed output [-]
        caseResult(ic) = r;                          % store [-]

    catch ME
        r = blank;                                   % failed row [-]
        r.caseNo = ic;                               % [-]
        r.caseName = c.caseName;                     % [-]
        r.caseGroup = c.caseGroup;                   % [-]
        r.expected = c.expected;                     % [-]
        r.T_orchtf_in_C = c.orcHotStream.T_in - 273.15; % [C]
        r.mdot_orchtf = c.orcHotStream.mdot;         % [kg/s]
        r.T_orccw_in_C = c.orcColdStream.T_in - 273.15; % [C]
        r.mdot_orccw = c.orcColdStream.mdot;         % [kg/s]
        r.mdot_orc = c.orcOperatingInput.orc_mdot;   % [kg/s]
        r.P_orcevap_bar = c.orcOperatingInput.orc_P_evap/1e5; % [bar]
        r.P_orccond_bar = c.orcOperatingInput.orc_P_cond/1e5; % [bar]
        r.feasible = false;                          % failed [-]
        r.errorFlag = true;                          % thrown error [-]
        r.guardedFlag = false;                       % not guarded [-]
        r.errorMessage = ME.message;                 % diagnostic [-]
        r.status = 'thrown-error';                   % status text [-]
        r.elapsed_s = toc(tCase);                    % [s]
        caseResult(ic) = r;                          % store [-]
    end
end

% =========================================================================
% SUMMARY METRICS
% =========================================================================
feas = [caseResult.feasible]';                       % [-]
err = [caseResult.errorFlag]';                       % [-]
guard = [caseResult.guardedFlag]';                   % [-]
finiteOK = ~err;                                     % [-]
Aev = [caseResult.evap_A_ratio]';                    % [-]
Aco = [caseResult.cond_A_ratio]';                    % [-]
Pe = [caseResult.evap_pinch_K]';                     % [K]
Pc = [caseResult.cond_pinch_K]';                     % [K]

orcSummary = struct();                               % summary [-]
orcSummary.nCases = nCase;                           % [-]
orcSummary.nFinite = sum(finiteOK);                  % [-]
orcSummary.nFeasible = sum(feas);                    % [-]
orcSummary.nCaughtErrors = sum(err);                 % [-]
orcSummary.nGuardedInfeasible = sum(guard);          % [-]
orcSummary.maxEvapAreaRatio = max(Aev(~isnan(Aev))); % [-]
orcSummary.maxCondAreaRatio = max(Aco(~isnan(Aco))); % [-]
orcSummary.minEvapPinch_K = min(Pe(~isnan(Pe)));     % [K]
orcSummary.minCondPinch_K = min(Pc(~isnan(Pc)));     % [K]
orcSummary.elapsed_s = toc(orcTimer);                % [s]

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcTest = struct();                                  % output [-]
orcTest.orc_modelVersion = config.orc_modelVersion;  % [-]
orcTest.orc_caseResult = caseResult;                 % struct array [-]
orcTest.orc_summary = orcSummary;                    % summary [-]
orcTest.orc_elapsed_s = orcSummary.elapsed_s;        % [s]

% =========================================================================
% OPTIONAL CSV EXPORT
% =========================================================================
if config.orc_stage2_test_exportCsv
    localExportCsv(caseResult,config.orc_stage2_test_csvFile); % file [-]
end

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
if config.orc_stage2_test_printSummary
    localPrintSummary(caseResult,orcSummary,config);  % console [-]
end

end

% =========================================================================
% CASE BUILDER
% =========================================================================
function caseList = localBuildCases(hot0,cold0,op0,T_sat_evap,T_sat_cond)
% Build normal, part-load, overload and extreme stress-test cases.
caseList = struct([]);                               % dynamic list [-]

% -------------------------------------------------------------------------
% Baseline and normal sweeps.
% -------------------------------------------------------------------------
caseList = localAddCase(caseList,'BASE','design point','normal', ...
    hot0,cold0,op0,1,0,1,0,1,1,1,1);

hotDeltaK = [-20,-10,10,25];                         % HTF inlet sweep [K]
for i = 1:numel(hotDeltaK)
    nm = sprintf('HTF inlet %+g K',hotDeltaK(i));     % case name [-]
    caseList = localAddCase(caseList,'HTF_T',nm,'mixed', ...
        hot0,cold0,op0,1,hotDeltaK(i),1,0,1,1,1,1);
end

hotFlow = [0.50,0.75,1.25,1.50];                     % hot-flow factors [-]
for i = 1:numel(hotFlow)
    nm = sprintf('HTF flow %.2fx',hotFlow(i));        % case name [-]
    caseList = localAddCase(caseList,'HTF_FLOW',nm,'mixed', ...
        hot0,cold0,op0,hotFlow(i),0,1,0,1,1,1,1);
end

cwDeltaK = [-5,10,20,30];                            % CW inlet sweep [K]
for i = 1:numel(cwDeltaK)
    nm = sprintf('CW inlet %+g K',cwDeltaK(i));       % case name [-]
    caseList = localAddCase(caseList,'CW_T',nm,'mixed', ...
        hot0,cold0,op0,1,0,1,cwDeltaK(i),1,1,1,1);
end

cwFlow = [0.50,0.75,1.25,1.50];                      % CW-flow factors [-]
for i = 1:numel(cwFlow)
    nm = sprintf('CW flow %.2fx',cwFlow(i));          % case name [-]
    caseList = localAddCase(caseList,'CW_FLOW',nm,'mixed', ...
        hot0,cold0,op0,1,0,cwFlow(i),0,1,1,1,1);
end

orcLoad = [0.40,0.60,0.80,1.10,1.25];                % ORC flow factors [-]
for i = 1:numel(orcLoad)
    nm = sprintf('ORC flow %.2fx',orcLoad(i));        % case name [-]
    caseList = localAddCase(caseList,'ORC_LOAD',nm,'mixed', ...
        hot0,cold0,op0,1,0,1,0,orcLoad(i),1,1,1);
end

% -------------------------------------------------------------------------
% Pressure sweeps.
% -------------------------------------------------------------------------
PeFac = [0.85,0.95,1.05];                            % evap pressure factors [-]
for i = 1:numel(PeFac)
    nm = sprintf('Pevap %.2fx',PeFac(i));             % case name [-]
    caseList = localAddCase(caseList,'PRESSURE',nm,'mixed', ...
        hot0,cold0,op0,1,0,1,0,1,PeFac(i),1,1);
end

PcFac = [0.80,1.20,1.50];                            % cond pressure factors [-]
for i = 1:numel(PcFac)
    nm = sprintf('Pcond %.2fx',PcFac(i));             % case name [-]
    caseList = localAddCase(caseList,'PRESSURE',nm,'mixed', ...
        hot0,cold0,op0,1,0,1,0,1,1,PcFac(i),1);
end

% -------------------------------------------------------------------------
% Extreme but useful consistency checks.
% -------------------------------------------------------------------------
hotNearSat = (T_sat_evap + 2) - hot0.T_in;           % source barely hot [K]
hotVeryHot = 50;                                     % high solar/PCM [K]
cwNearCond = (T_sat_cond - 2) - cold0.T_in;          % sink almost condensing [K]

caseList = localAddCase(caseList,'EXTREME','source near pinch','expected fail', ...
    hot0,cold0,op0,1,hotNearSat,1,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','very hot source','normal', ...
    hot0,cold0,op0,1,hotVeryHot,1,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','very low HTF flow','expected fail', ...
    hot0,cold0,op0,0.30,0,1,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','sink near condensing','expected fail', ...
    hot0,cold0,op0,1,0,1,cwNearCond,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','very low CW flow','expected fail', ...
    hot0,cold0,op0,1,0,0.30,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','high load low source','expected fail', ...
    hot0,cold0,op0,0.60,-15,1,0,1.20,1,1,1);
caseList = localAddCase(caseList,'EXTREME','hot sink high cond P','mixed', ...
    hot0,cold0,op0,1,0,1,25,1,1,1.45,1);
end

function caseList = localAddCase(caseList,group,name,expected,hot0,cold0,op0, ...
    hotFlowFac,hotDeltaK,coldFlowFac,coldDeltaK,orcFlowFac,PevapFac,PcondFac,dtFac)
% Append one case by scaling baseline streams and command.
h = hot0;                                            % hot stream [-]
c = cold0;                                           % cold stream [-]
op = op0;                                            % operating command [-]

h.T_in = hot0.T_in + hotDeltaK;                       % [K]
h.mdot = max(1e-6,hot0.mdot*hotFlowFac);             % [kg/s]
c.T_in = cold0.T_in + coldDeltaK;                    % [K]
c.mdot = max(1e-6,cold0.mdot*coldFlowFac);           % [kg/s]
op.orc_mdot = max(1e-8,op0.orc_mdot*orcFlowFac);     % [kg/s]
op.orc_P_evap = max(1,op0.orc_P_evap*PevapFac);      % [Pa]
op.orc_P_cond = max(1,op0.orc_P_cond*PcondFac);      % [Pa]

idx = numel(caseList) + 1;                            % next index [-]
caseList(idx).caseName = name;                        % [-]
caseList(idx).caseGroup = group;                      % [-]
caseList(idx).expected = expected;                    % [-]
caseList(idx).orcHotStream = h;                       % [-]
caseList(idx).orcColdStream = c;                      % [-]
caseList(idx).orcOperatingInput = op;                 % [-]
caseList(idx).orc_dt_s = 3600*dtFac;                  % [s]
end

% =========================================================================
% RESULT HELPERS
% =========================================================================
function r = localBlankResult()
% Create a result row with NaN defaults.
r = struct();                                        % [-]
r.caseNo = NaN;                                      % [-]
r.caseName = '';                                     % [-]
r.caseGroup = '';                                    % [-]
r.expected = '';                                     % [-]
r.T_orchtf_in_C = NaN;                               % [C]
r.mdot_orchtf = NaN;                                 % [kg/s]
r.T_orccw_in_C = NaN;                                % [C]
r.mdot_orccw = NaN;                                  % [kg/s]
r.mdot_orc = NaN;                                    % [kg/s]
r.P_orcevap_bar = NaN;                               % [bar]
r.P_orccond_bar = NaN;                               % [bar]
r.W_orcnet_kW = NaN;                                 % [kW]
r.Q_orcevap_kW = NaN;                                % [kW]
r.Q_orccond_kW = NaN;                                % [kW]
r.T_orchtf_out_C = NaN;                              % [C]
r.T_orccw_out_C = NaN;                               % [C]
r.evap_A_ratio = NaN;                                % [-]
r.cond_A_ratio = NaN;                                % [-]
r.evap_pinch_K = NaN;                                % [K]
r.cond_pinch_K = NaN;                                % [K]
r.dp_evap_wf_kPa = NaN;                              % [kPa]
r.dp_cond_wf_kPa = NaN;                              % [kPa]
r.hydraulicConv = false;                             % [-]
r.hydraulicRel = NaN;                                % [-]
r.feasible = false;                                  % [-]
r.errorFlag = false;                                 % [-]
r.guardedFlag = false;                               % guarded error flag [-]
r.errorMessage = '';                                 % [-]
r.status = '';                                       % status text [-]
r.elapsed_s = NaN;                                   % [s]
r.orcStep = [];                                      % detailed output [-]
end

function localPrintSummary(res,summary,config)
% Print compact stress-test table and summary.
fprintf('\n============================================================\n');
fprintf('ORC STAGE-2 COMPREHENSIVE TEST SUITE - V%s\n',config.orc_modelVersion);
fprintf('============================================================\n');
fprintf('Cases              : %10d\n',summary.nCases);
fprintf('Finite cases       : %10d\n',summary.nFinite);
fprintf('Feasible cases     : %10d\n',summary.nFeasible);
fprintf('Caught errors      : %10d\n',summary.nCaughtErrors);
if isfield(summary,'nGuardedInfeasible')
    fprintf('Guarded infeasible : %10d\n',summary.nGuardedInfeasible);
end
fprintf('Max evap A ratio   : %10.4f\n',summary.maxEvapAreaRatio);
fprintf('Max cond A ratio   : %10.4f\n',summary.maxCondAreaRatio);
fprintf('Min evap pinch     : %10.3f K\n',summary.minEvapPinch_K);
fprintf('Min cond pinch     : %10.3f K\n',summary.minCondPinch_K);
fprintf('Test-suite time    : %10.2f s\n',summary.elapsed_s);

if config.orc_stage2_test_printCaseTable
    fprintf('------------------------------------------------------------\n');
    fprintf('%3s %-11s %-24s %4s %8s %8s %7s %7s %7s\n', ...
        '#','Group','Case','OK','W[kW]','Aevap','Acond','PinE','PinC');
    fprintf('------------------------------------------------------------\n');
    for i = 1:numel(res)
        okText = 'NO';                                % default [-]
        if res(i).feasible
            okText = 'YES';                           % feasible [-]
        elseif res(i).errorFlag
            okText = 'ERR';                           % thrown error [-]
        elseif res(i).guardedFlag
            okText = 'GRD';                           % guarded infeasible [-]
        end
        fprintf('%3d %-11s %-24s %4s %8.1f %8.3f %7.3f %7.2f %7.2f\n', ...
            res(i).caseNo,localShort(res(i).caseGroup,11), ...
            localShort(res(i).caseName,24),okText, ...
            res(i).W_orcnet_kW,res(i).evap_A_ratio,res(i).cond_A_ratio, ...
            res(i).evap_pinch_K,res(i).cond_pinch_K);
    end
end
fprintf('============================================================\n');
end

function s = localShort(s,n)
% Trim long text for compact command-window table.
if numel(s) > n
    s = s(1:n);                                      % clipped [-]
end
end


function value = localGetStepField(s,fieldName,defaultValue)
% Safely read an optional field from a nested step struct.
if isstruct(s) && isfield(s,fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);                            % available value [-]
else
    value = defaultValue;                             % default [-]
end
end

function localExportCsv(res,fileName)
% Export scalar case results without detailed nested structs.
try
    T = rmfield(res,'orcStep');                       % remove nested data [-]
    T = struct2table(T);                              % table [-]
    writetable(T,fileName);                           % CSV [-]
catch
    warning('orc_stage2_test_suite:CsvExportFailed', ...
        'Could not export Stage-2 test-suite CSV.');
end
end
