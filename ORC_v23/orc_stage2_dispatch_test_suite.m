function orcTest = orc_stage2_dispatch_test_suite(orcDesign,config)
% ORC_STAGE2_DISPATCH_TEST_SUITE Stress-test fixed-geometry dispatch logic.
%
% Each case provides boundary streams and a maximum ORC command. The
% dispatcher may reduce ORC mass flow and adjust Pevap/Pcond within the
% configured candidate grid. Heat-exchanger geometry remains frozen.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 2 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % suite timer [-]
if config.orc_property_cache_stats_enabled
    cacheStats0 = orc_properties(config,'CACHESTATS'); % cache counters before suite [-]
else
    cacheStats0 = struct();                            % empty diagnostics [-]
end

% =========================================================================
% BASELINE STREAMS AND MAXIMUM COMMAND
% =========================================================================
hot0 = orcDesign.orc_hotStream_design;               % design hot stream [-]
cold0 = orcDesign.orc_coldStream_design;             % design cold stream [-]
op0 = struct();                                      % design command [-]
op0.orc_P_evap = orcDesign.orc_thermo.P_orcevap;     % [Pa]
op0.orc_P_cond = orcDesign.orc_thermo.P_orccond;     % [Pa]
op0.orc_mdot = orcDesign.orc_thermo.mdot_orc;        % [kg/s]

T_sat_evap = orcDesign.orc_thermo.T_orcturb_in;      % [K]
T_sat_cond = orcDesign.orc_thermo.T_orcpump_in;      % [K]

caseList = localBuildCases(hot0,cold0,op0,T_sat_evap,T_sat_cond); % [-]
nCase = numel(caseList);                             % [-]
blank = localBlankResult();                          % template [-]
caseResult = repmat(blank,nCase,1);                  % preallocate [-]

% =========================================================================
% CASE LOOP
% =========================================================================
for ic = 1:nCase
    c = caseList(ic);                                % case input [-]
    tCase = tic;                                     % case timer [-]
    try
        orcStep = orc_offdesign_dispatch( ...
            orcDesign,c.orcHotStream,c.orcColdStream,c.orcOperatingInput,config); % [-]

        th = orcStep.orc_thermo;                     % [-]
        er = orcStep.orc_evaporator_rate;            % [-]
        cr = orcStep.orc_condenser_rate;             % [-]
        dp = orcStep.orc_dispatch;                   % [-]
        cand = dp.orc_candidateLog;                  % [-]

        r = blank;                                   % row [-]
        r.caseNo = ic;                               % [-]
        r.caseGroup = c.caseGroup;                   % [-]
        r.caseName = c.caseName;                     % [-]
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
        r.running = strcmpi(orcStep.orc_status,'dispatch-on'); % [-]
        r.feasible = orcStep.orc_feasible;           % [-]
        r.status = orcStep.orc_status;               % [-]
        r.nCand = dp.orc_nCandidatesEvaluated;       % [-]
        r.nRatedCand = localCountRatedCandidates(cand); % expensive HX-rated candidates [-]
        r.anyGuardedCandidate = localAnyGuarded(cand); % [-]
        r.errorFlag = false;                         % [-]
        r.errorMessage = localGetStepField(orcStep,'orc_errorMessage',''); % [-]
        r.elapsed_s = toc(tCase);                    % [s]
        r.orcStep = orcStep;                         % detailed output [-]
        caseResult(ic) = r;                          % store [-]
    catch ME
        r = blank;                                   % failed row [-]
        r.caseNo = ic;                               % [-]
        r.caseGroup = c.caseGroup;                   % [-]
        r.caseName = c.caseName;                     % [-]
        r.expected = c.expected;                     % [-]
        r.T_orchtf_in_C = c.orcHotStream.T_in - 273.15; % [C]
        r.mdot_orchtf = c.orcHotStream.mdot;         % [kg/s]
        r.T_orccw_in_C = c.orcColdStream.T_in - 273.15; % [C]
        r.mdot_orccw = c.orcColdStream.mdot;         % [kg/s]
        r.errorFlag = true;                          % [-]
        r.errorMessage = ME.message;                 % diagnostic [-]
        r.status = 'thrown-error';                   % [-]
        r.elapsed_s = toc(tCase);                    % [s]
        caseResult(ic) = r;                          % store [-]
    end
end

% =========================================================================
% SUMMARY METRICS
% =========================================================================
running = [caseResult.running]';                     % [-]
err = [caseResult.errorFlag]';                       % [-]
anyGuard = [caseResult.anyGuardedCandidate]';        % [-]
Aev = [caseResult.evap_A_ratio]';                    % [-]
Aco = [caseResult.cond_A_ratio]';                    % [-]
Pe = [caseResult.evap_pinch_K]';                     % [K]
Pc = [caseResult.cond_pinch_K]';                     % [K]
W = [caseResult.W_orcnet_kW]';                       % [kW]
Nc = [caseResult.nCand]';                            % [-]
Nr = [caseResult.nRatedCand]';                       % [-]

summary = struct();                                  % summary [-]
summary.nCases = nCase;                              % [-]
summary.nRunning = sum(running);                     % [-]
summary.nOff = sum(~running & ~err);                 % [-]
summary.nCaughtErrors = sum(err);                    % [-]
summary.nCasesWithGuardedCandidates = sum(anyGuard); % [-]
summary.meanRunningPower_kW = localMean(W(running)); % [kW]
summary.minRunningPower_kW = localMin(W(running));   % [kW]
summary.maxRunningPower_kW = localMax(W(running));   % [kW]
summary.maxEvapAreaRatio = localMax(Aev(running));   % [-]
summary.maxCondAreaRatio = localMax(Aco(running));   % [-]
summary.minEvapPinch_K = localMin(Pe(running));      % [K]
summary.minCondPinch_K = localMin(Pc(running));      % [K]
summary.meanCandidates = localMean(Nc(~err));        % [-]
summary.maxCandidates = localMax(Nc(~err));          % [-]
summary.meanRatedCandidates = localMean(Nr(~err));    % [-]
summary.maxRatedCandidates = localMax(Nr(~err));      % [-]
caseTime = [caseResult.elapsed_s]';                  % [s]
summary.meanCaseTime_s = localMean(caseTime(~err));  % [s]
summary.maxCaseTime_s = localMax(caseTime(~err));    % [s]
summary.elapsed_s = toc(orcTimer);                   % [s]
if config.orc_property_cache_stats_enabled
    cacheStats1 = orc_properties(config,'CACHESTATS');  % cache counters after suite [-]
    summary.cacheStats = localCacheDelta(cacheStats0,cacheStats1); % suite cache use [-]
else
    summary.cacheStats = struct();                      % empty diagnostics [-]
end

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcTest = struct();                                  % output [-]
orcTest.orc_modelVersion = config.orc_modelVersion;  % [-]
orcTest.orc_caseResult = caseResult;                 % [-]
orcTest.orc_summary = summary;                       % [-]
orcTest.orc_elapsed_s = summary.elapsed_s;           % [s]

% =========================================================================
% OPTIONAL CSV EXPORT
% =========================================================================
if config.orc_dispatch_test_exportCsv
    localExportCsv(caseResult,config.orc_dispatch_test_csvFile); % file [-]
end

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
if config.orc_dispatch_printSummary
    localPrintSummary(caseResult,summary,config);     % console [-]
end

end

% =========================================================================
% CASE BUILDER
% =========================================================================
function caseList = localBuildCases(hot0,cold0,op0,T_sat_evap,T_sat_cond)
% Build dispatch-oriented cases: low source, hot sink, part load and extremes.
caseList = struct([]);                               % dynamic list [-]

caseList = localAddCase(caseList,'BASE','design point','normal', ...
    hot0,cold0,op0,1,0,1,0,1,1,1,1);

hotDeltaK = [-30,-20,-10,10,25];                     % HTF inlet sweep [K]
for i = 1:numel(hotDeltaK)
    nm = sprintf('HTF inlet %+g K',hotDeltaK(i));     % case name [-]
    caseList = localAddCase(caseList,'HTF_T',nm,'dispatch', ...
        hot0,cold0,op0,1,hotDeltaK(i),1,0,1,1,1,1);
end

hotFlow = [0.30,0.50,0.75,1.25];                     % hot-flow factors [-]
for i = 1:numel(hotFlow)
    nm = sprintf('HTF flow %.2fx',hotFlow(i));        % case name [-]
    caseList = localAddCase(caseList,'HTF_FLOW',nm,'dispatch', ...
        hot0,cold0,op0,hotFlow(i),0,1,0,1,1,1,1);
end

cwDeltaK = [-5,10,20,30];                            % CW inlet sweep [K]
for i = 1:numel(cwDeltaK)
    nm = sprintf('CW inlet %+g K',cwDeltaK(i));       % case name [-]
    caseList = localAddCase(caseList,'CW_T',nm,'dispatch', ...
        hot0,cold0,op0,1,0,1,cwDeltaK(i),1,1,1,1);
end

cwFlow = [0.30,0.50,0.75,1.25];                      % CW-flow factors [-]
for i = 1:numel(cwFlow)
    nm = sprintf('CW flow %.2fx',cwFlow(i));          % case name [-]
    caseList = localAddCase(caseList,'CW_FLOW',nm,'dispatch', ...
        hot0,cold0,op0,1,0,cwFlow(i),0,1,1,1,1);
end

orcDemand = [0.40,0.80,1.25];                        % maximum command factors [-]
for i = 1:numel(orcDemand)
    nm = sprintf('max ORC flow %.2fx',orcDemand(i));  % case name [-]
    caseList = localAddCase(caseList,'ORC_CMD',nm,'dispatch', ...
        hot0,cold0,op0,1,0,1,0,orcDemand(i),1,1,1);
end

hotNearSat = (T_sat_evap + 2) - hot0.T_in;           % source barely hot [K]
hotVeryHot = 50;                                     % high-source test [K]
cwNearCond = (T_sat_cond - 2) - cold0.T_in;          % sink almost condensing [K]

caseList = localAddCase(caseList,'EXTREME','source near pinch','off expected', ...
    hot0,cold0,op0,1,hotNearSat,1,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','very hot source','dispatch', ...
    hot0,cold0,op0,1,hotVeryHot,1,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','very low HTF flow','dispatch/off', ...
    hot0,cold0,op0,0.25,0,1,0,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','sink near condensing','off expected', ...
    hot0,cold0,op0,1,0,1,cwNearCond,1,1,1,1);
caseList = localAddCase(caseList,'EXTREME','high load low source','dispatch', ...
    hot0,cold0,op0,0.60,-15,1,0,1.20,1,1,1);
caseList = localAddCase(caseList,'EXTREME','hot sink high cond P','dispatch', ...
    hot0,cold0,op0,1,0,1,25,1,1,1.45,1);
end

function caseList = localAddCase(caseList,group,name,expected,hot0,cold0,op0, ...
    hotFlowFac,hotDeltaK,coldFlowFac,coldDeltaK,orcFlowFac,PevapFac,PcondFac,dtFac)
% Append one case by scaling baseline streams and maximum command.
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
% RESULT AND PRINT HELPERS
% =========================================================================
function r = localBlankResult()
r = struct();                                        % [-]
r.caseNo = NaN;                                      % [-]
r.caseGroup = '';                                    % [-]
r.caseName = '';                                     % [-]
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
r.running = false;                                   % [-]
r.feasible = false;                                  % [-]
r.status = '';                                       % [-]
r.nCand = 0;                                         % [-]
r.nRatedCand = 0;                                    % [-]
r.anyGuardedCandidate = false;                       % [-]
r.errorFlag = false;                                 % [-]
r.errorMessage = '';                                 % [-]
r.elapsed_s = NaN;                                   % [s]
r.orcStep = [];                                      % detailed output [-]
end

function localPrintSummary(res,summary,config)
fprintf('\n============================================================\n');
fprintf('ORC STAGE-2 DISPATCH TEST SUITE - V%s\n',config.orc_modelVersion);
fprintf('============================================================\n');
fprintf('Cases              : %10d\n',summary.nCases);
fprintf('Running cases      : %10d\n',summary.nRunning);
fprintf('ORC-off cases      : %10d\n',summary.nOff);
fprintf('Caught errors      : %10d\n',summary.nCaughtErrors);
fprintf('Guarded cand. cases: %10d\n',summary.nCasesWithGuardedCandidates);
fprintf('Mean W running     : %10.2f kW\n',summary.meanRunningPower_kW);
fprintf('Min/Max W running  : %10.2f / %-10.2f kW\n',summary.minRunningPower_kW,summary.maxRunningPower_kW);
fprintf('Max evap A ratio   : %10.4f\n',summary.maxEvapAreaRatio);
fprintf('Max cond A ratio   : %10.4f\n',summary.maxCondAreaRatio);
fprintf('Min evap pinch     : %10.3f K\n',summary.minEvapPinch_K);
fprintf('Min cond pinch     : %10.3f K\n',summary.minCondPinch_K);
fprintf('Mean/max candidates: %10.2f / %-10.0f\n',summary.meanCandidates,summary.maxCandidates);
fprintf('Mean/max HX-rated : %10.2f / %-10.0f\n',summary.meanRatedCandidates,summary.maxRatedCandidates);
fprintf('Mean/max case time: %10.2f / %-10.2f s\n',summary.meanCaseTime_s,summary.maxCaseTime_s);
fprintf('Dispatch cand. cap: %10d\n',config.orc_dispatch_maxCandidates);
fprintf('Dispatch time      : %10.2f s\n',summary.elapsed_s);
if isfield(summary,'cacheStats') && isfield(summary.cacheStats,'nRequests')
    fprintf('Cache req/hit/miss : %10d / %-10d / %-10d\n', ...
        summary.cacheStats.nRequests,summary.cacheStats.nHits,summary.cacheStats.nMisses);
    fprintf('Cache hit rate     : %10.2f %%\n',100*summary.cacheStats.activeHitRate);
    fprintf('Cache entries      : %10d\n',summary.cacheStats.nEntriesEnd);
    fprintf('Cache resets       : %10d\n',summary.cacheStats.nResets);
end
fprintf('------------------------------------------------------------\n');
fprintf('%3s %-10s %-23s %4s %8s %7s %6s %6s %7s %7s %5s %5s\n', ...
    '#','Group','Case','RUN','W[kW]','mdot','Pe','Pc','Aevap','Acond','Nc','Nr');
fprintf('------------------------------------------------------------\n');
for i = 1:numel(res)
    runText = 'OFF';                                  % default [-]
    if res(i).running
        runText = 'ON';                               % running [-]
    elseif res(i).errorFlag
        runText = 'ERR';                              % thrown [-]
    end
    fprintf('%3d %-10s %-23s %4s %8.1f %7.3f %6.2f %6.2f %7.3f %7.3f %5d %5d\n', ...
        res(i).caseNo,localShort(res(i).caseGroup,10), ...
        localShort(res(i).caseName,23),runText, ...
        res(i).W_orcnet_kW,res(i).mdot_orc, ...
        res(i).P_orcevap_bar,res(i).P_orccond_bar, ...
        res(i).evap_A_ratio,res(i).cond_A_ratio,res(i).nCand,res(i).nRatedCand);
end
fprintf('============================================================\n');
end


function n = localCountRatedCandidates(cand)
% Count candidates that reached the expensive HX-rating layer.  Candidates
% skipped by thermodynamic/capacity prescreen keep a status beginning with
% 'prescreen-' and are not counted here.
n = 0;                                              % default [-]
if isempty(cand) || ~isstruct(cand) || ~isfield(cand,'status')
    return
end
for k = 1:numel(cand)
    st = cand(k).status;                             % status text [-]
    if isempty(st)
        continue
    end
    if strncmp(st,'prescreen-',10)
        continue
    end
    n = n + 1;                                      % rated candidate [-]
end
end

function tf = localAnyGuarded(cand)
tf = false;                                          % default [-]
if isempty(cand)
    return
end
if isstruct(cand) && isfield(cand,'guardedFlag')
    tf = any([cand.guardedFlag]);                     % [-]
end
end

function value = localGetStepField(s,fieldName,defaultValue)
if isstruct(s) && isfield(s,fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);                            % available [-]
else
    value = defaultValue;                             % default [-]
end
end

function d = localCacheDelta(s0,s1)
% Difference cache counters over the dispatch-test block.
d = struct();                                        % [-]
fields = {'nRequests','nHits','nMisses','nStores','nBypass','nResets'};
for i = 1:numel(fields)
    f = fields{i};                                   % field name [-]
    if isfield(s0,f) && isfield(s1,f)
        d.(f) = s1.(f) - s0.(f);                      % counter delta [-]
    else
        d.(f) = NaN;                                  % unavailable [-]
    end
end
if (d.nHits + d.nMisses) > 0
    d.activeHitRate = d.nHits/(d.nHits + d.nMisses);  % [-]
else
    d.activeHitRate = NaN;                            % [-]
end
if isfield(s1,'nEntries')
    d.nEntriesEnd = s1.nEntries;                      % final cache entries [-]
else
    d.nEntriesEnd = NaN;                              % [-]
end
end

function x = localMean(v)
v = v(isfinite(v));                                  % valid values [-]
if isempty(v), x = NaN; else, x = mean(v); end
end
function x = localMin(v)
v = v(isfinite(v));                                  % valid values [-]
if isempty(v), x = NaN; else, x = min(v); end
end
function x = localMax(v)
v = v(isfinite(v));                                  % valid values [-]
if isempty(v), x = NaN; else, x = max(v); end
end
function s = localShort(s,n)
if numel(s) > n
    s = s(1:n);                                      % clipped [-]
end
end
function localExportCsv(res,fileName)
try
    T = rmfield(res,'orcStep');                       % remove nested data [-]
    T = struct2table(T);                              % table [-]
    writetable(T,fileName);                           % CSV [-]
catch
    warning('orc_stage2_dispatch_test_suite:CsvExportFailed', ...
        'Could not export Stage-2 dispatch CSV.');
end
end
