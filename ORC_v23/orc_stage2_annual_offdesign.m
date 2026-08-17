function orcAnnual = orc_stage2_annual_offdesign(orcDesign,orcAnnualInput,config)
% ORC_STAGE2_ANNUAL_OFFDESIGN Run fixed-geometry ORC off-design simulation.
%
% The Stage-1 geometry is not resized. Each timestep calls either forced
% fixed-geometry rating or dispatch-based off-design operation.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 3 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % annual timer [-]

% =========================================================================
% DEFAULT DESIGN-POINT SINGLE-TIMESTEP INPUT
% =========================================================================
if nargin < 2 || isempty(orcAnnualInput)
    orcAnnualInput = struct();                       % default check [-]
end

if ~isfield(orcAnnualInput,'orcHotStream')
    orcAnnualInput.orcHotStream = orcDesign.orc_hotStream_design; % [-]
end
if ~isfield(orcAnnualInput,'orcColdStream')
    orcAnnualInput.orcColdStream = orcDesign.orc_coldStream_design; % [-]
end
if ~isfield(orcAnnualInput,'orcOperatingInput')
    op = struct();
    op.orc_P_evap = orcDesign.orc_thermo.P_orcevap;   % [Pa]
    op.orc_P_cond = orcDesign.orc_thermo.P_orccond;   % [Pa]
    op.orc_mdot = orcDesign.orc_thermo.mdot_orc;      % [kg/s]
    orcAnnualInput.orcOperatingInput = op;            % [-]
end
if ~isfield(orcAnnualInput,'orc_dt_s')
    orcAnnualInput.orc_dt_s = config.sim_dt_s;        % [s]
end

if ~isfield(orcAnnualInput,'orc_useDispatch')
    orcAnnualInput.orc_useDispatch = strcmpi(config.orc_stage2_operatingMode,'dispatch'); % [-]
end

% =========================================================================
% TIMESTEP COUNT
% =========================================================================
nHot = numel(orcAnnualInput.orcHotStream);            % [-]
nCold = numel(orcAnnualInput.orcColdStream);          % [-]
nOp = numel(orcAnnualInput.orcOperatingInput);        % [-]
nStep = max([nHot,nCold,nOp]);                        % [-]

if isscalar(orcAnnualInput.orc_dt_s)
    dt_s = repmat(orcAnnualInput.orc_dt_s,nStep,1);   % [s]
else
    dt_s = orcAnnualInput.orc_dt_s(:);                % [s]
end
if numel(dt_s) ~= nStep
    error('orc_stage2_annual_offdesign:DtSize', ...
        'orc_dt_s must be scalar or have one value per timestep.');
end

% =========================================================================
% PREALLOCATE OUTPUT ARRAYS
% =========================================================================
orc_W_net = NaN(nStep,1);                             % [W]
orc_Q_evap = NaN(nStep,1);                            % [W]
orc_Q_cond = NaN(nStep,1);                            % [W]
orc_mdot = NaN(nStep,1);                              % [kg/s]
orc_P_evap = NaN(nStep,1);                            % [Pa]
orc_P_cond = NaN(nStep,1);                            % [Pa]
orc_T_htf_in = NaN(nStep,1);                          % [K]
orc_T_htf_out = NaN(nStep,1);                         % [K]
orc_T_cw_in = NaN(nStep,1);                           % [K]
orc_T_cw_out = NaN(nStep,1);                          % [K]
orc_dp_evap_wf = NaN(nStep,1);                        % [Pa]
orc_dp_cond_wf = NaN(nStep,1);                        % [Pa]
orc_A_ratio_evap = NaN(nStep,1);                      % [-]
orc_A_ratio_cond = NaN(nStep,1);                      % [-]
orc_feasible = false(nStep,1);                        % [-]
orc_stepTime_s = NaN(nStep,1);                        % [s]
orc_dispatch_nCand = zeros(nStep,1);                     % [-]
orc_dispatch_nRated = zeros(nStep,1);                    % [-]
orc_warmStartUsed = false(nStep,1);                      % [-]
orc_status = cell(nStep,1);                              % status text [-]
orcStep = cell(nStep,1);                              % detailed steps [-]

% =========================================================================
% TIMESTEP LOOP
% =========================================================================
progressState = localProgressStart(config,nStep,dt_s,orcAnnualInput.orc_useDispatch); % progress indicator [-]
orcWarmStartOp = [];                                  % previous feasible dispatch point [-]
for it = 1:nStep
    progressState = localProgressBeginStep(progressState,config,it,nStep,dt_s,orcTimer); % GUI/command progress [-]

    orcHotStream_t = localPick(orcAnnualInput.orcHotStream,it);       % [-]
    orcColdStream_t = localPick(orcAnnualInput.orcColdStream,it);     % [-]
    orcOperatingInput_t = localPick(orcAnnualInput.orcOperatingInput,it); % [-]

    if orcAnnualInput.orc_useDispatch && config.orc_stage2_dispatch_useWarmStart && ...
            ~isempty(orcWarmStartOp)
        orcOperatingInput_t.orc_warmStartOperatingInput = orcWarmStartOp; % previous feasible point [-]
        orc_warmStartUsed(it) = true;                  % diagnostic [-]
    end

    if orcAnnualInput.orc_useDispatch
        orcStep{it} = orc_offdesign_dispatch( ...
            orcDesign,orcHotStream_t,orcColdStream_t,orcOperatingInput_t,config);
    else
        orcStep{it} = orc_offdesign_rating( ...
            orcDesign,orcHotStream_t,orcColdStream_t,orcOperatingInput_t,config);
    end

    th = orcStep{it}.orc_thermo;                       % [-]
    er = orcStep{it}.orc_evaporator_rate;              % [-]
    cr = orcStep{it}.orc_condenser_rate;               % [-]

    orc_W_net(it) = th.W_orcnet;                       % [W]
    orc_Q_evap(it) = th.Q_orcevap;                     % [W]
    orc_Q_cond(it) = th.Q_orccond;                     % [W]
    orc_mdot(it) = th.mdot_orc;                        % [kg/s]
    orc_P_evap(it) = th.P_orcevap;                     % [Pa]
    orc_P_cond(it) = th.P_orccond;                     % [Pa]
    orc_T_htf_in(it) = er.T_orchtf_in;                 % [K]
    orc_T_htf_out(it) = er.T_orchtf_out;               % [K]
    orc_T_cw_in(it) = cr.T_orccw_in;                   % [K]
    orc_T_cw_out(it) = cr.T_orccw_out;                 % [K]
    orc_dp_evap_wf(it) = er.dp_orcevap_wf;             % [Pa]
    orc_dp_cond_wf(it) = cr.dp_orccond_wf;             % [Pa]
    orc_A_ratio_evap(it) = er.A_ratio;                 % [-]
    orc_A_ratio_cond(it) = cr.A_ratio;                 % [-]
    orc_feasible(it) = orcStep{it}.orc_feasible;       % [-]
    orc_stepTime_s(it) = orcStep{it}.orc_elapsed_s;    % [s]
    orc_status{it} = localGetField(orcStep{it},'orc_status',''); % [-]
    if isfield(orcStep{it},'orc_dispatch')
        orc_dispatch_nCand(it) = orcStep{it}.orc_dispatch.orc_nCandidatesEvaluated; % [-]
        orc_dispatch_nRated(it) = localCountRatedCandidates(orcStep{it}.orc_dispatch.orc_candidateLog); % [-]
    end

    if orcAnnualInput.orc_useDispatch
        if strcmpi(orc_status{it},'dispatch-on') || orc_feasible(it)
            orcWarmStartOp = localStepToOperatingInput(orcStep{it}); % update previous feasible point [-]
        elseif ~config.orc_stage2_dispatch_keepWarmStartAfterOff
            orcWarmStartOp = [];                      % optional reset after OFF [-]
        end
    end

    progressState = localProgressUpdate(progressState,config,it,nStep,dt_s, ...
        orcAnnualInput.orc_useDispatch,orcStep{it},orc_W_net(it),orc_feasible(it), ...
        orc_dispatch_nCand(it),orc_dispatch_nRated(it),orc_stepTime_s(it),orcTimer); % [-]
end
localProgressFinish(progressState,config);            % finish progress line [-]

% =========================================================================
% ANNUAL / PERIOD INTEGRALS
% =========================================================================
orc_E_net_kWh = sum(orc_W_net.*dt_s)/3.6e6;           % [kWh]
orc_E_evap_kWh = sum(orc_Q_evap.*dt_s)/3.6e6;         % [kWh]
orc_E_cond_kWh = sum(orc_Q_cond.*dt_s)/3.6e6;         % [kWh]
orcHours = sum(dt_s)/3600;                            % [h]
orcFeasibleHours = sum(dt_s(orc_feasible))/3600;      % [h]

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcAnnual = struct();
orcAnnual.orc_modelVersion = config.orc_modelVersion; % [-]
orcAnnual.orc_nStep = nStep;                          % [-]
orcAnnual.orc_dt_s = dt_s;                            % [s]
orcAnnual.orc_W_net = orc_W_net;                      % [W]
orcAnnual.orc_Q_evap = orc_Q_evap;                    % [W]
orcAnnual.orc_Q_cond = orc_Q_cond;                    % [W]
orcAnnual.orc_mdot = orc_mdot;                        % [kg/s]
orcAnnual.orc_P_evap = orc_P_evap;                    % [Pa]
orcAnnual.orc_P_cond = orc_P_cond;                    % [Pa]
orcAnnual.orc_T_htf_in = orc_T_htf_in;                % [K]
orcAnnual.orc_T_htf_out = orc_T_htf_out;              % [K]
orcAnnual.orc_T_cw_in = orc_T_cw_in;                  % [K]
orcAnnual.orc_T_cw_out = orc_T_cw_out;                % [K]
orcAnnual.orc_dp_evap_wf = orc_dp_evap_wf;            % [Pa]
orcAnnual.orc_dp_cond_wf = orc_dp_cond_wf;            % [Pa]
orcAnnual.orc_A_ratio_evap = orc_A_ratio_evap;        % [-]
orcAnnual.orc_A_ratio_cond = orc_A_ratio_cond;        % [-]
orcAnnual.orc_feasible = orc_feasible;                % [-]
orcAnnual.orc_stepTime_s = orc_stepTime_s;            % [s]
orcAnnual.orc_dispatch_nCandidates = orc_dispatch_nCand; % [-]
orcAnnual.orc_dispatch_nRatedCandidates = orc_dispatch_nRated; % [-]
orcAnnual.orc_warmStartUsed = orc_warmStartUsed;      % [-]
orcAnnual.orc_status = orc_status;                    % [-]
orcAnnual.orc_useDispatch = orcAnnualInput.orc_useDispatch; % [-]
orcAnnual.orcStep = orcStep;                          % detailed cells [-]
orcAnnual.orc_E_net_kWh = orc_E_net_kWh;              % [kWh]
orcAnnual.orc_E_evap_kWh = orc_E_evap_kWh;            % [kWh]
orcAnnual.orc_E_cond_kWh = orc_E_cond_kWh;            % [kWh]
orcAnnual.orc_hours = orcHours;                       % [h]
orcAnnual.orc_feasibleHours = orcFeasibleHours;       % [h]
orcAnnual.orc_elapsed_s = toc(orcTimer);              % [s]

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
if config.orc_stage2_printSummary
    fprintf('\n============================================================\n');
    fprintf('ORC STAGE-2 FIXED-GEOMETRY OFF-DESIGN - V%s\n',config.orc_modelVersion);
    fprintf('============================================================\n');
    fprintf('Timesteps          : %10d\n',nStep);
    fprintf('Mean W_orcnet      : %10.2f kW\n',mean(orc_W_net)/1e3);
    fprintf('E_orcnet           : %10.3f kWh\n',orc_E_net_kWh);
    fprintf('Feasible hours     : %10.3f h\n',orcFeasibleHours);
fprintf('Feasible steps     : %10d / %-10d\n',sum(orc_feasible),nStep);
    fprintf('Operating mode     : %10s\n',localModeText(orcAnnualInput.orc_useDispatch));
    if orcAnnualInput.orc_useDispatch
        fprintf('Mean dispatch cand.: %10.2f\n',mean(orc_dispatch_nCand));
        fprintf('Max dispatch cand. : %10.0f\n',max(orc_dispatch_nCand));
        fprintf('Mean HX-rated cand.: %10.2f\n',mean(orc_dispatch_nRated));
        fprintf('Warm-start steps   : %10d / %-10d\n',sum(orc_warmStartUsed),nStep);
    end
    fprintf('Area tol.          : %10.3f %%\n',100*config.orc_stage2_areaTol_rel);
    fprintf('Max evap A ratio   : %10.4f\n',max(orc_A_ratio_evap));
    fprintf('Max cond A ratio   : %10.4f\n',max(orc_A_ratio_cond));
    fprintf('Stage-2 time       : %10.2f s\n',orcAnnual.orc_elapsed_s);
    fprintf('============================================================\n');
end

end

% =========================================================================
% LOCAL HELPER
% =========================================================================
function state = localProgressStart(config,nStep,dt_s,useDispatch)
% Initialize either a GUI waitbar or a lightweight command-window progress indicator.
state = struct();                                    % [-]
state.enabled = isfield(config,'orc_stage2_progressEnabled') && config.orc_stage2_progressEnabled; % [-]
state.mode = 'none';                                % progress mode [-]
state.handle = [];                                  % waitbar handle [-]
state.lastLen = 0;                                  % previous printed line length [-]
state.nStep = nStep;                                % [-]
state.totalHours = sum(dt_s)/3600;                  % [h]
state.useDispatch = useDispatch;                    % [-]

if ~state.enabled
    return
end

if isfield(config,'orc_stage2_progressMode')
    reqMode = lower(strtrim(config.orc_stage2_progressMode)); % [-]
else
    reqMode = 'command';                            % backward-compatible default [-]
end

if strcmpi(reqMode,'none') || strcmpi(reqMode,'off')
    state.enabled = false;                          % disabled [-]
    return
end

if strcmpi(reqMode,'waitbar') || strcmpi(reqMode,'gui')
    try
        msg = sprintf('ORC Stage-2 %s\nBasliyor: 0/%d\nToplam gecen sure: 0s',localModeText(useDispatch),nStep); % [-]
        state.handle = waitbar(0,msg,'Name','ORC Stage-2 progress'); % GUI progress [-]
        state.mode = 'waitbar';                     % [-]
        return
    catch
        if isfield(config,'orc_stage2_progressCommandFallback') && config.orc_stage2_progressCommandFallback
            state.mode = 'command';                 % fallback [-]
            fprintf('\n');                          % keep progress separate from previous output [-]
            return
        else
            state.enabled = false;                  % silently disable if waitbar unavailable [-]
            return
        end
    end
end

state.mode = 'command';                             % command-window progress [-]
fprintf('\n');                                      % keep progress separate from previous output [-]
end


function state = localProgressBeginStep(state,config,it,nStep,dt_s,orcTimer)
% Show which timestep has just started, especially for GUI waitbar mode.
if ~state.enabled
    return
end
every = max(1,round(config.orc_stage2_progressEvery)); % [-]
if it ~= nStep && mod(it,every) ~= 0 && it ~= 1
    return
end
if ~strcmpi(state.mode,'waitbar')
    return
end
if isempty(state.handle) || ~ishandle(state.handle)
    state.enabled = false;                          % user closed waitbar or invalid handle [-]
    return
end
frac = max(0,(it-1)/max(nStep,1));                  % progress before solving this step [-]
elapsed_s = toc(orcTimer);                          % [s]
startHour = sum(dt_s(1:it-1))/3600;                 % [h]
endHour = sum(dt_s(1:it))/3600;                     % [h]
msg = sprintf('Saat %d/%d basladi\nSimulasyon saati: %.2f-%.2f h\nToplam gecen sure: %s', ...
    it,nStep,startHour,endHour,localFormatTime(elapsed_s)); % [-]
try
    waitbar(frac,state.handle,msg);                 % GUI update [-]
    drawnow limitrate                               % keep GUI responsive [-]
catch
    state.enabled = false;                          % tolerate GUI closure/errors [-]
end
end

function state = localProgressUpdate(state,config,it,nStep,dt_s,useDispatch,orcStep,W_net,feasible,nCand,nRated,stepTime_s,orcTimer)
% Update the selected progress indicator.
if ~state.enabled
    return
end
every = max(1,round(config.orc_stage2_progressEvery)); % [-]
if it ~= nStep && mod(it,every) ~= 0
    return
end
frac = it/max(nStep,1);                             % [-]
barWidth = max(10,round(config.orc_stage2_progressBarWidth)); % [-]
nFill = min(barWidth,max(0,round(frac*barWidth)));  % [-]
barText = [repmat('#',1,nFill),repmat('-',1,barWidth-nFill)]; % [-]
elapsed_s = toc(orcTimer);                          % [s]
if it > 0
    eta_s = elapsed_s*(nStep-it)/it;                % [s]
else
    eta_s = NaN;                                    % [s]
end
simHour = sum(dt_s(1:it))/3600;                     % [h]
runText = 'OFF';                                    % [-]
if feasible
    runText = 'ON ';                                % [-]
end
modeText = localModeText(useDispatch);              % [-]
statusText = localGetField(orcStep,'orc_status',''); % [-]

if strcmpi(state.mode,'waitbar')
    if isempty(state.handle) || ~ishandle(state.handle)
        state.enabled = false;                      % user closed waitbar or invalid handle [-]
        return
    end
    textMode = 'simple';                            % GUI text mode [-]
    if isfield(config,'orc_stage2_progressWaitbarText')
        textMode = lower(strtrim(config.orc_stage2_progressWaitbarText)); % [-]
    end
    if strcmpi(textMode,'detailed')
        msg = sprintf(['ORC Stage-2 %s: %d/%d  (h = %.2f / %.2f)\n', ...
            '%s   W = %.1f kW   Nc = %d   Nr = %d\n', ...
            'Step %.1f s   ETA %s   %s'], ...
            modeText,it,nStep,simHour,state.totalHours,strtrim(runText),W_net/1e3, ...
            nCand,nRated,stepTime_s,localFormatTime(eta_s),statusText); % [-]
    else
        msg = sprintf('Saat %d/%d tamamlandi\nSimulasyon saati: %.2f/%.2f h\nToplam gecen sure: %s', ...
            it,nStep,simHour,state.totalHours,localFormatTime(elapsed_s)); % [-]
    end
    try
        waitbar(frac,state.handle,msg);             % GUI update [-]
        drawnow limitrate                           % keep GUI responsive [-]
    catch
        state.enabled = false;                      % tolerate GUI closure/errors [-]
    end
    return
end

line = sprintf('ORC Stage-2 %s [%s] %4d/%-4d h=%7.2f/%-7.2f %3s W=%7.1f kW Nc=%3d Nr=%3d step=%6.1fs ETA=%s %s', ...
    modeText,barText,it,nStep,simHour,state.totalHours,runText,W_net/1e3,nCand,nRated,stepTime_s, ...
    localFormatTime(eta_s),statusText);
if config.orc_stage2_progressSingleLine
    pad = repmat(' ',1,max(0,state.lastLen-numel(line))); % clear tail [-]
    fprintf('\r%s%s',line,pad);                    % single-line update [-]
else
    fprintf('%s\n',line);                          % multi-line log [-]
end
state.lastLen = numel(line);                        % [-]
end

function localProgressFinish(state,config)
% Close or finalize the selected progress indicator.
if ~(isstruct(state) && isfield(state,'enabled') && state.enabled)
    return
end
if isfield(state,'mode') && strcmpi(state.mode,'waitbar')
    if isfield(config,'orc_stage2_progressWaitbarCloseOnFinish') && ...
            config.orc_stage2_progressWaitbarCloseOnFinish && ...
            isfield(state,'handle') && ~isempty(state.handle) && ishandle(state.handle)
        try
            close(state.handle);                    % close GUI waitbar [-]
        catch
        end
    end
elseif config.orc_stage2_progressSingleLine
    fprintf('\n');                                  % next output starts on new line [-]
end
end

function text = localFormatTime(seconds)
% Compact seconds/minutes/hours formatter for progress output.
if ~(isfinite(seconds) && seconds >= 0)
    text = '--';                                    % [-]
elseif seconds < 60
    text = sprintf('%.0fs',seconds);                % [-]
elseif seconds < 3600
    text = sprintf('%.1fmin',seconds/60);           % [-]
else
    text = sprintf('%.1fh',seconds/3600);           % [-]
end
end

function text = localModeText(useDispatch)
if useDispatch
    text = 'dispatch';
else
    text = 'forced';
end
end

function op = localStepToOperatingInput(orcStep)
% Convert a selected timestep output into the next warm-start command.
th = orcStep.orc_thermo;                             % selected thermodynamics [-]
op = struct();                                      % operating input [-]
op.orc_P_evap = th.P_orcevap;                       % [Pa]
op.orc_P_cond = th.P_orccond;                       % [Pa]
op.orc_mdot = th.mdot_orc;                          % [kg/s]

% Store the external-boundary condition that produced this warm-start.
% Dispatch uses these metadata to avoid promoting a stale low-load point
% when the next timestep has substantially better or worse source/sink data.
if isfield(orcStep,'orc_hotStream') && isstruct(orcStep.orc_hotStream)
    op.orc_hot_T_in = localGetField(orcStep.orc_hotStream,'T_in',NaN); % [K]
    op.orc_hot_mdot = localGetField(orcStep.orc_hotStream,'mdot',NaN); % [kg/s]
end
if isfield(orcStep,'orc_coldStream') && isstruct(orcStep.orc_coldStream)
    op.orc_cold_T_in = localGetField(orcStep.orc_coldStream,'T_in',NaN); % [K]
    op.orc_cold_mdot = localGetField(orcStep.orc_coldStream,'mdot',NaN); % [kg/s]
end
end

function n = localCountRatedCandidates(cand)
% Count candidates that reached HX rating rather than being pre-screened.
if isempty(cand)
    n = 0;                                           % [-]
    return
end
status = {cand.status};                              % status cell [-]
n = 0;                                               % [-]
for i = 1:numel(status)
    st = status{i};                                  % [-]
    if isempty(st)
        continue
    end
    if isempty(strfind(st,'prescreen'))
        n = n + 1;                                   % HX-rated or validated [-]
    end
end
end

function value = localGetField(s,fieldName,defaultValue)
if isstruct(s) && isfield(s,fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function item = localPick(arrayLike,it)
% Pick timestep item; repeat scalar input for all timesteps.
if numel(arrayLike) == 1
    item = arrayLike;                                  % repeated [-]
else
    item = arrayLike(it);                              % timestep item [-]
end
end
