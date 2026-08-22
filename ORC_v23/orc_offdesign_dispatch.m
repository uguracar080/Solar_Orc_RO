function orcStep = orc_offdesign_dispatch(orcDesign,orcHotStream,orcColdStream,orcDispatchInput,config)
% ORC_OFFDESIGN_DISPATCH Find one feasible fixed-geometry ORC operating point.
%
% v0.23 uses the v0.19 tiered dispatch search plus annual warm-start support plus warm-start duplicate promotion:
%   1) thermodynamic and source/sink capacity pre-screening,
%   2) stress-aware ordered candidates for low-source and hot-sink cases,
%   3) one-pass HX screening followed by exact validation of the selected point.
% The physical rating routines are unchanged; this file only changes how
% operating candidates are searched.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 5 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % dispatch timer [-]

if nargin < 4 || isempty(orcDispatchInput)
    orcDispatchInput = struct();                     % default command [-]
end

% Fast screening configuration.  The selected candidate is later validated
% with the original config when config.orc_dispatch_validateSelected is true.
fastConfig = config;                                 % screening config [-]
if config.orc_dispatch_fastScreening
    fastConfig.orc_max_hydraulic_iter = max(1,config.orc_dispatch_fastMaxIter); % [-]
    fastConfig.orc_tol_hydraulic_rel = inf;          % one-pass rating accepted for screening [-]
    fastConfig.orc_hydraulic_finalRelTol = inf;      % consistent diagnostic [-]
end

% =========================================================================
% CANDIDATE OPERATING COMMANDS
% =========================================================================
[candList,ref] = localBuildCandidates(orcDesign,orcHotStream,orcColdStream,orcDispatchInput,config); % [-]
nCand = min(numel(candList),config.orc_dispatch_maxCandidates);           % [-]

candLog = repmat(localBlankCandidateResult(),nCand,1); % compact log [-]
bestStep = [];                                      % best feasible step [-]
bestW = -inf;                                      % [W]
found = false;                                     % feasible flag [-]

% =========================================================================
% ORDERED SEARCH LOOP
% =========================================================================
for ic = 1:nCand
    tCand = tic;                                    % candidate timer [-]
    op = candList(ic).orcOperatingInput;            % command [-]

    r = localBlankCandidateResult();                % compact row [-]
    r.candidateNo = ic;                             % [-]
    r.mdotFactor = candList(ic).mdotFactor;          % [-]
    r.PevapFactor = candList(ic).PevapFactor;        % [-]
    r.PcondFactor = candList(ic).PcondFactor;        % [-]
    r.dispatchScore = candList(ic).dispatchScore;    % [-]
    r.P_orcevap = op.orc_P_evap;                    % [Pa]
    r.P_orccond = op.orc_P_cond;                    % [Pa]
    r.mdot_orc = op.orc_mdot;                       % [kg/s]

    % ---------------------------------------------------------------------
    % Cheap thermodynamic feasibility guard before an HX rating call.
    % ---------------------------------------------------------------------
    if config.orc_dispatch_useThermoPrescreen
        pre = localThermoPrescreen(orcDesign,orcHotStream,orcColdStream,op,config,ref); % [-]
        r.prescreenFlag = true;                      % [-]
        r.status = pre.status;                       % [-]
        r.W_orcnet = pre.W_orcnet;                   % [W]
        r.guardedFlag = pre.guardedFlag;             % [-]
        r.errorMessage = pre.errorMessage;           % [-]
        if ~pre.pass
            r.elapsed_s = toc(tCand);                % [s]
            candLog(ic) = r;                         % store skipped row [-]
            continue
        end
    end

    % ---------------------------------------------------------------------
    % Fast candidate screen or full rating.
    % ---------------------------------------------------------------------
    try
        if config.orc_dispatch_fastScreening
            stScreen = orc_offdesign_rating(orcDesign,orcHotStream,orcColdStream,op,fastConfig); % [-]
        else
            stScreen = orc_offdesign_rating(orcDesign,orcHotStream,orcColdStream,op,config); % [-]
        end
        err = false;                                 % thrown error flag [-]
        msg = localGetStepField(stScreen,'orc_errorMessage',''); % [-]
    catch ME
        stScreen = [];                               % no valid rating [-]
        err = true;                                  % thrown error flag [-]
        msg = ME.message;                            % diagnostic [-]
    end

    r.errorFlag = err;                               % [-]
    r.errorMessage = msg;                            % [-]

    if ~err && isstruct(stScreen)
        r = localFillCandidateFromStep(r,stScreen,ref); % screen metrics [-]
        r = localApplyPreheaterGuard(r,stScreen,config);

        if r.feasible
            % Full validation of promising points prevents a one-pass screen
            % from accepting a false feasible candidate.
            if config.orc_dispatch_fastScreening && config.orc_dispatch_validateSelected
                try
                    stFinal = orc_offdesign_rating(orcDesign,orcHotStream,orcColdStream,op,config); % [-]
                    r = localFillCandidateFromStep(r,stFinal,ref); % exact metrics [-]
                    r = localApplyPreheaterGuard(r,stFinal,config);
                    r.validatedFlag = true;          % [-]
                    stUse = stFinal;                 % selected output [-]
                catch ME2
                    r.errorFlag = true;              % exact validation failed [-]
                    r.errorMessage = ME2.message;    % diagnostic [-]
                    r.status = 'validation-error';   % [-]
                    stUse = [];                      % no output [-]
                end
            else
                stUse = stScreen;                    % no second pass [-]
            end

            if isstruct(stUse) && r.feasible && stUse.orc_thermo.W_orcnet > bestW
                found = true;                        % feasible candidate found [-]
                bestW = stUse.orc_thermo.W_orcnet;   % [W]
                bestStep = stUse;                    % save selected output [-]
                r.elapsed_s = toc(tCand);            % [s]
                candLog(ic) = r;                     % store before exit [-]
                if config.orc_dispatch_stopAtFirstFeasible
                    break
                end
            end
        end
    else
        r.status = 'thrown-error';                   % status text [-]
    end

    r.elapsed_s = toc(tCand);                        % [s]
    candLog(ic) = r;                                 % store [-]
end

% Trim non-evaluated preallocated rows when stopping early.
if found && config.orc_dispatch_stopAtFirstFeasible
    nEval = ic;                                      % evaluated candidates [-]
    candLog = candLog(1:nEval);                      % trim [-]
else
    nEval = nCand;                                   % evaluated candidates [-]
end

% =========================================================================
% DISPATCH SUMMARY
% =========================================================================
orcDispatch = struct();                              % dispatch diagnostics [-]
orcDispatch.orc_mode = 'dispatch';                   % [-]
orcDispatch.orc_foundFeasible = found;               % [-]
orcDispatch.orc_nCandidatesAvailable = numel(candList); % [-]
orcDispatch.orc_nCandidatesEvaluated = nEval;        % [-]
orcDispatch.orc_candidateLog = candLog;              % compact log [-]
orcDispatch.orc_reference = ref;                     % reference command [-]
orcDispatch.orc_elapsed_s = toc(orcTimer);           % [s]
orcDispatch.orc_fastScreening = config.orc_dispatch_fastScreening; % [-]

% =========================================================================
% FINAL OUTPUT
% =========================================================================
if found
    orcStep = bestStep;                              % selected rating [-]
    orcStep.orc_status = 'dispatch-on';              % status text [-]
    orcStep.orc_dispatch = orcDispatch;              % diagnostics [-]
    orcStep.orc_elapsed_s = toc(orcTimer);           % include dispatch time [s]
else
    orcStep = localBuildOffStep(orcDesign,orcHotStream,orcColdStream,orcDispatchInput,config,orcTimer,orcDispatch); % [-]
end

end

% =========================================================================
% CANDIDATE BUILDER
% =========================================================================
function [candList,ref] = localBuildCandidates(orcDesign,orcHotStream,orcColdStream,orcDispatchInput,config)
% Build a stress-aware ordered candidate list.  Source-limited cases receive
% low-Pevap candidates early; sink-limited cases receive high-Pcond candidates
% early.  Low-mdot candidates are still included, but only after high-power
% pressure adaptations have been tried.

Pcrit = orcDesign.orc_thermo.P_orc_crit;             % [Pa]
Pev0 = localGetField(orcDispatchInput,'orc_P_evap',orcDesign.orc_thermo.P_orcevap); % [Pa]
Pco0 = localGetField(orcDispatchInput,'orc_P_cond',orcDesign.orc_thermo.P_orccond); % [Pa]
md0 = localGetField(orcDispatchInput,'orc_mdot',orcDesign.orc_thermo.mdot_orc);     % [kg/s]

Wdes = orcDesign.orc_thermo.W_orcnet;                % design power [W]
ref = struct();                                      % reference command [-]
ref.P_orcevap = Pev0;                                % [Pa]
ref.P_orccond = Pco0;                                % [Pa]
ref.mdot_orc = md0;                                  % [kg/s]
ref.W_design = Wdes;                                 % [W]
ref.W_min = max(0,config.orc_dispatch_minPowerFraction*Wdes); % [W]

% The stress flags are not hard constraints; they only reorder candidates.
hotDesign = orcDesign.orc_hotStream_design;          % design hot stream [-]
coldDesign = orcDesign.orc_coldStream_design;        % design cold stream [-]
sourceStress = false;                                % low heat availability [-]
sinkStress = false;                                  % difficult heat rejection [-]
if isfield(hotDesign,'T_in') && isfield(hotDesign,'mdot')
    sourceStress = sourceStress || orcHotStream.T_in < hotDesign.T_in - 2; % [-]
    sourceStress = sourceStress || orcHotStream.mdot < 0.98*hotDesign.mdot; % [-]
end
if isfield(coldDesign,'T_in') && isfield(coldDesign,'mdot')
    sinkStress = sinkStress || orcColdStream.T_in > coldDesign.T_in + 1; % [-]
    sinkStress = sinkStress || orcColdStream.mdot < 0.98*coldDesign.mdot; % [-]
end
if md0 > 1.02*orcDesign.orc_thermo.mdot_orc
    sourceStress = true;                             % high command can overload HX [-]
    sinkStress = true;                               % high command can overload condenser [-]
end

mdHigh = [1.00 0.97 0.95 0.90 0.85 0.80];            % high-power mdot tier [-]
mdLow  = [0.75 0.70 0.60 0.50 0.40 0.30 0.20 0.10]; % part-load tier [-]

basePairs = [ ...                                    % balanced default pressure pairs [-]
    1.00 1.00;
    0.98 1.00;
    0.95 1.00;
    0.90 1.00;
    0.85 1.00;
    0.80 1.00;
    0.75 1.00;
    0.70 1.00;
    1.00 1.10;
    1.00 1.20;
    1.00 1.35;
    1.00 1.50;
    1.00 1.80;
    0.90 1.10;
    0.85 1.10;
    0.80 1.10;
    0.75 1.10;
    0.80 1.35];

sourcePairs = [ ...                                  % low-source pressure relief [-]
    1.00 1.00;
    0.98 1.00;
    0.95 1.00;
    0.90 1.00;
    0.85 1.00;
    0.80 1.00;
    0.75 1.00;
    0.70 1.00;
    0.65 1.00;
    0.60 1.00;
    0.85 1.10;
    0.80 1.10;
    0.75 1.10;
    0.70 1.10;
    0.65 1.10;
    0.60 1.10;
    0.75 1.20;
    0.70 1.20];

sinkPairs = [ ...                                    % hot-sink / low-CW-flow rejection relief [-]
    1.00 1.00;
    1.00 1.10;
    1.00 1.20;
    1.00 1.35;
    1.00 1.50;
    1.00 1.80;
    1.00 2.20;
    1.00 2.60;
    0.98 1.50;
    0.95 1.80;
    0.90 1.80;
    0.85 1.80;
    0.80 1.80;
    0.75 1.80;
    0.90 2.20;
    0.85 2.20;
    0.80 2.20];

comboPairs = [ ...                                   % simultaneous source/sink stress [-]
    1.00 1.00;
    0.95 1.20;
    0.90 1.35;
    0.85 1.50;
    0.80 1.80;
    0.75 1.80;
    0.70 2.20;
    0.65 2.20;
    0.60 2.20;
    0.80 2.60;
    0.70 2.60];

if sourceStress && sinkStress
    pairPrimary = [comboPairs; sourcePairs; sinkPairs; basePairs]; % [-]
elseif sourceStress
    pairPrimary = [sourcePairs; comboPairs; basePairs; sinkPairs]; % [-]
elseif sinkStress
    pairPrimary = [sinkPairs; comboPairs; basePairs; sourcePairs]; % [-]
else
    pairPrimary = [basePairs; comboPairs; sourcePairs; sinkPairs]; % [-]
end

% Include user/config factors as a final fallback without putting the wide
% Cartesian product at the beginning of the annual dispatch search.
[peGrid,pcGrid] = ndgrid(unique(config.orc_dispatch_pevapFactors,'stable'), ...
    unique(config.orc_dispatch_pcondFactors,'stable')); % [-]
fallbackPairs = [peGrid(:),pcGrid(:)];               % [-]

candList = struct([]);                               % candidate array [-]
keyList = {};                                        % duplicate keys [-]

% v0.19 adds an early coverage tier.  It interleaves moderate part-load
% mass-flow factors with the stress-aware pressure pairs so source-limited
% and sink-limited cases do not spend the whole candidate budget at nominal
% ORC flow before trying lower-load feasible points.
if isfield(config,'orc_dispatch_useCoverageTier') && config.orc_dispatch_useCoverageTier
    [candList,keyList] = localAppendGrid(candList,keyList, ...
        unique(config.orc_dispatch_coverageMdotFactors,'stable'),pairPrimary, ...
        Pev0,Pco0,md0,Pcrit,1.05);
end

% High-mdot pressure adaptation remains as fallback for near-design cases;
% duplicate removal keeps the early coverage tier from repeating candidates.
[candList,keyList] = localAppendGrid(candList,keyList,mdHigh,pairPrimary, ...
    Pev0,Pco0,md0,Pcrit,1.00);
[candList,keyList] = localAppendGrid(candList,keyList,mdLow,pairPrimary, ...
    Pev0,Pco0,md0,Pcrit,0.90);
[candList,keyList] = localAppendGrid(candList,keyList, ...
    unique(config.orc_dispatch_mdotFactors,'stable'),fallbackPairs, ...
    Pev0,Pco0,md0,Pcrit,0.70);

% Annual simulations can pass the previous feasible operating point as a
% warm-start.  It is inserted after the design candidate so improved
% timesteps can still ramp back to nominal immediately, while stressed
% timesteps can reuse the previous part-load solution early in the search.
if isfield(orcDispatchInput,'orc_warmStartOperatingInput') && ...
        isstruct(orcDispatchInput.orc_warmStartOperatingInput)
    candList = localInsertWarmStartCandidate(candList, ...
        orcDispatchInput.orc_warmStartOperatingInput,orcHotStream,orcColdStream,Pev0,Pco0,md0,Pcrit,config);
end

% Keep available list finite even before the runtime maxCandidates cut.
if numel(candList) > config.orc_dispatch_candidateListLimit
    candList = candList(1:config.orc_dispatch_candidateListLimit); % [-]
end
end

function candList = localInsertWarmStartCandidate(candList,warmOp,orcHotStream,orcColdStream,Pev0,Pco0,md0,Pcrit,config)
% Insert the previous feasible point just after the nominal design candidate.
% v0.23 change: when the warm-start point already exists deeper in the
% stress-search grid, move that duplicate up instead of leaving it buried at
% its original candidate number. This keeps smooth annual profiles from
% re-testing 20--60 candidates before reaching the previous operating point.
if ~(isfield(warmOp,'orc_P_evap') && isfield(warmOp,'orc_P_cond') && isfield(warmOp,'orc_mdot'))
    return
end
Pev = warmOp.orc_P_evap;                             % [Pa]
Pco = warmOp.orc_P_cond;                             % [Pa]
md = warmOp.orc_mdot;                                % [kg/s]
if ~(isfinite(Pev) && isfinite(Pco) && isfinite(md) && md > 0)
    return
end
if ~(Pco > 0 && Pev > Pco && Pev < 0.98*Pcrit)
    return
end

% Do not promote a stale warm-start point when the external source/sink has
% changed significantly.  This keeps annual dispatch from locking onto a
% low-load point during improving solar conditions, while retaining the speed
% benefit for genuinely smooth neighbouring timesteps.
if isfield(config,'orc_stage2_dispatch_warmStartSimilarityOnly') && ...
        config.orc_stage2_dispatch_warmStartSimilarityOnly
    if ~localWarmStartStreamsSimilar(warmOp,orcHotStream,orcColdStream,config)
        return
    end
end

duplicateIndex = 0;                                  % [-]
for i = 1:numel(candList)
    opi = candList(i).orcOperatingInput;             % existing command [-]
    same = abs(opi.orc_P_evap-Pev) <= max(1,1e-8*Pev) && ...
           abs(opi.orc_P_cond-Pco) <= max(1,1e-8*Pco) && ...
           abs(opi.orc_mdot-md) <= max(1e-9,1e-8*md); % duplicate check [-]
    if same
        duplicateIndex = i;                          % [-]
        break
    end
end

if duplicateIndex == 1
    return                                           % warm start is the design candidate [-]
elseif duplicateIndex > 1 && isfield(config,'orc_stage2_dispatch_warmStartMoveDuplicate') && ...
        config.orc_stage2_dispatch_warmStartMoveDuplicate
    w = candList(duplicateIndex);                    % move duplicate candidate up [-]
    candList(duplicateIndex) = [];                   % remove original location [-]
else
    if duplicateIndex > 1
        return                                       % old behavior if moving disabled [-]
    end
    op = struct();                                   % warm-start command [-]
    op.orc_P_evap = Pev;                             % [Pa]
    op.orc_P_cond = Pco;                             % [Pa]
    op.orc_mdot = md;                                % [kg/s]

    w = struct();                                    % candidate row [-]
    w.orcOperatingInput = op;                        % [-]
    w.mdotFactor = md/max(md0,eps);                  % [-]
    w.PevapFactor = Pev/max(Pev0,eps);               % [-]
    w.PcondFactor = Pco/max(Pco0,eps);               % [-]
    w.dispatchScore = 1.25*w.mdotFactor;             % [-]
end

% Insert just after the nominal design candidate. The design point remains
% first so clear high-availability timesteps can return to nominal in one
% candidate; the warm-start point is second for smooth off-design periods.
if isempty(candList)
    candList = w;                                    % first row fallback [-]
elseif numel(candList) == 1
    candList = [candList,w];                         % append after design [-]
else
    candList = [candList(1),w,candList(2:end)];      % insert after design [-]
end
end

function isSimilar = localWarmStartStreamsSimilar(warmOp,orcHotStream,orcColdStream,config)
% Decide whether the previous feasible operating point is close enough to
% the current external-boundary condition to be promoted early.  A stale
% low-load warm-start is still available through the normal candidate grid,
% but it should not dominate when solar or cooling conditions changed.
isSimilar = false;                                   % default [-]
if ~(isfield(warmOp,'orc_hot_T_in') && isfield(warmOp,'orc_hot_mdot') && ...
        isfield(warmOp,'orc_cold_T_in') && isfield(warmOp,'orc_cold_mdot'))
    return                                           % no stream metadata [-]
end
Ttol = max(0,config.orc_stage2_dispatch_warmStart_Ttol_K); % [K]
mtol = max(0,config.orc_stage2_dispatch_warmStart_mdotRelTol); % [-]

hotT = abs(orcHotStream.T_in - warmOp.orc_hot_T_in); % [K]
coldT = abs(orcColdStream.T_in - warmOp.orc_cold_T_in); % [K]
hotM = abs(orcHotStream.mdot - warmOp.orc_hot_mdot)/max(abs(warmOp.orc_hot_mdot),eps); % [-]
coldM = abs(orcColdStream.mdot - warmOp.orc_cold_mdot)/max(abs(warmOp.orc_cold_mdot),eps); % [-]

isSimilar = hotT <= Ttol && coldT <= Ttol && hotM <= mtol && coldM <= mtol; % [-]
end

function [candList,keyList] = localAppendGrid(candList,keyList,mdFac,pairs,Pev0,Pco0,md0,Pcrit,scoreBase)
% Append a grid in pressure-pair-major order while removing duplicates.
for ip = 1:size(pairs,1)
    pEF = pairs(ip,1);                               % [-]
    pCF = pairs(ip,2);                               % [-]
    for im = 1:numel(mdFac)
        mFac = mdFac(im);                            % [-]
        if ~(isfinite(mFac) && mFac > 0 && isfinite(pEF) && pEF > 0 && isfinite(pCF) && pCF > 0)
            continue
        end

        Pev = Pev0*pEF;                              % [Pa]
        Pco = Pco0*pCF;                              % [Pa]
        md = md0*mFac;                               % [kg/s]
        if ~(isfinite(Pev) && isfinite(Pco) && isfinite(md) && md > 0)
            continue
        end
        if ~(Pco > 0 && Pev > Pco && Pev < 0.98*Pcrit)
            continue
        end

        key = sprintf('%.6g_%.6g_%.6g',md,Pev,Pco); % duplicate key [-]
        if any(strcmp(keyList,key))
            continue
        end
        keyList{end+1} = key; %#ok<AGROW>

        op = struct();                               % operating command [-]
        op.orc_P_evap = Pev;                         % [Pa]
        op.orc_P_cond = Pco;                         % [Pa]
        op.orc_mdot = md;                            % [kg/s]

        k = numel(candList) + 1;                     % index [-]
        candList(k).orcOperatingInput = op;          % [-]
        candList(k).mdotFactor = mFac;               % [-]
        candList(k).PevapFactor = pEF;               % [-]
        candList(k).PcondFactor = pCF;               % [-]
        candList(k).dispatchScore = scoreBase*mFac;  % [-]
    end
end
end

% =========================================================================
% PRESCREEN AND CANDIDATE HELPERS
% =========================================================================
function pre = localThermoPrescreen(orcDesign,orcHotStream,orcColdStream,op,config,ref)
% Return a cheap pass/fail decision using cycle states, terminal
% temperatures and rough stream heat-capacity limits.  It catches many
% impossible candidates before expensive fixed-geometry HX rating calls.
pre = struct();                                      % output [-]
pre.pass = false;                                    % default [-]
pre.W_orcnet = NaN;                                  % [W]
pre.status = 'prescreen';                            % [-]
pre.guardedFlag = false;                             % [-]
pre.errorMessage = '';                               % [-]

try
    systemInput = struct();                          % thermo input [-]
    systemInput.orc_P_evap_des = op.orc_P_evap;       % [Pa]
    systemInput.orc_P_cond_des = op.orc_P_cond;       % [Pa]
    systemInput.orc_mdot_des = op.orc_mdot;           % [kg/s]

    hyd = struct();                                  % approximate dP [-]
    hyd.orc_dp_evap_wf = localScaleDp(orcDesign.orc_thermo.dp_orcevap_wf,op.orc_mdot,ref.mdot_orc); % [Pa]
    hyd.orc_dp_cond_wf = localScaleDp(orcDesign.orc_thermo.dp_orccond_wf,op.orc_mdot,ref.mdot_orc); % [Pa]

    th = orc_thermo_design(systemInput,config,hyd);  % cycle state [-]
    pre.W_orcnet = th.W_orcnet;                      % [W]

    if ~th.orc_energyBalanceOK || ~isfinite(th.W_orcnet) || th.W_orcnet < ref.W_min
        pre.status = 'prescreen-low-power';          % [-]
        return
    end
    if ~(orcHotStream.T_in > th.T_orcturb_in + config.orc_hx_minApproach_K)
        pre.status = 'prescreen-source-cold';        % [-]
        return
    end
    if ~(orcColdStream.T_in < th.T_orcpump_in - config.orc_hx_minApproach_K)
        pre.status = 'prescreen-sink-hot';           % [-]
        return
    end

    if config.orc_dispatch_capacityPrescreen
        [capOK,capStatus] = localCapacityPrescreen(th,orcHotStream,orcColdStream,config); % [-]
        if ~capOK
            pre.status = capStatus;                  % [-]
            return
        end
    end

    pre.pass = true;                                 % pass guard [-]
    pre.status = 'prescreen-pass';                   % [-]
catch ME
    pre.guardedFlag = true;                          % guarded failure [-]
    pre.errorMessage = ME.message;                   % diagnostic [-]
    pre.status = 'prescreen-guarded';                % [-]
end
end

function [capOK,capStatus] = localCapacityPrescreen(orcThermo,orcHotStream,orcColdStream,config)
% Rough source/sink energy-capacity screen.  The multiplier deliberately
% leaves a small safety margin so candidates are not rejected only because
% the capacity estimate is simpler than the detailed HX rating.
capOK = true;                                        % default [-]
capStatus = 'prescreen-capacity-pass';               % [-]
mult = config.orc_dispatch_capacityToleranceFactor;  % tolerance multiplier [-]
app = max(0,config.orc_dispatch_capacityApproach_K); % [K]

% Hot stream can cool down only to just above the evaporating boundary.
T_hot_limit = min(orcHotStream.T_in - 1e-6,orcThermo.T_orcturb_in + app); % [K]
if ~(T_hot_limit < orcHotStream.T_in)
    capOK = false;                                   % [-]
    capStatus = 'prescreen-hot-capacity';            % [-]
    return
end
h_hot_in = orc_stream_properties(config,orcHotStream,'H','T',orcHotStream.T_in,'P',orcHotStream.P_in); % [J/kg]
h_hot_lim = orc_stream_properties(config,orcHotStream,'H','T',T_hot_limit,'P',orcHotStream.P_in);      % [J/kg]
Q_hot_cap = max(0,orcHotStream.mdot*(h_hot_in-h_hot_lim))*mult; % [W]
if orcThermo.Q_orcevap > Q_hot_cap
    capOK = false;                                   % [-]
    capStatus = 'prescreen-hot-capacity';            % [-]
    return
end

% Cold stream can be heated only to just below the condensing boundary.
T_cold_limit = max(orcColdStream.T_in + 1e-6,orcThermo.T_orcpump_in - app); % [K]
if ~(T_cold_limit > orcColdStream.T_in)
    capOK = false;                                   % [-]
    capStatus = 'prescreen-cold-capacity';           % [-]
    return
end
h_cold_in = orc_stream_properties(config,orcColdStream,'H','T',orcColdStream.T_in,'P',orcColdStream.P_in); % [J/kg]
h_cold_lim = orc_stream_properties(config,orcColdStream,'H','T',T_cold_limit,'P',orcColdStream.P_in);      % [J/kg]
Q_cold_cap = max(0,orcColdStream.mdot*(h_cold_lim-h_cold_in))*mult; % [W]
if orcThermo.Q_orccond > Q_cold_cap
    capOK = false;                                   % [-]
    capStatus = 'prescreen-cold-capacity';           % [-]
    return
end
end

function dp = localScaleDp(dp0,md,md0)
% Rough dP guess for screening; avoids starting every candidate from the
% design dP when the ORC mass flow is far from nominal.
if ~(isfinite(dp0) && isfinite(md) && isfinite(md0) && md0 > 0)
    dp = 0;                                          % [Pa]
else
    dp = max(0,dp0)*(md/md0)^2;                      % [Pa]
end
end

function r = localFillCandidateFromStep(r,st,ref)
% Copy rating metrics into one dispatch-candidate log row.
th = st.orc_thermo;                                  % [-]
er = st.orc_evaporator_rate;                         % [-]
cr = st.orc_condenser_rate;                          % [-]
r.W_orcnet = th.W_orcnet;                            % [W]
r.evap_A_ratio = er.A_ratio;                         % [-]
r.cond_A_ratio = cr.A_ratio;                         % [-]
r.evap_pinch_K = er.deltaT_pinch;                    % [K]
r.cond_pinch_K = cr.deltaT_pinch;                    % [K]
r.condOutletTemp_C = cr.T_orccw_out - 273.15;        % [degC]
r.feasible = st.orc_feasible && th.W_orcnet >= ref.W_min; % [-]
r.guardedFlag = localGetStepField(st,'orc_errorCaught',false); % [-]
r.status = localGetStepField(st,'orc_status','rated'); % [-]
end

function r = localApplyPreheaterGuard(r,st,config)
% Reject otherwise feasible candidates that cannot heat the feed side.
enabled = isfield(config,'orc_dispatch_preheaterGuardEnabled') && ...
    logical(config.orc_dispatch_preheaterGuardEnabled);
if ~enabled
    return
end
targetC = localGetField(config,'orc_dispatch_minCondOutletTemp_C',NaN);
r.preheaterGuardTarget_C = targetC;
if ~r.feasible
    return
end
if ~(isfinite(targetC) && isfield(st,'orc_condenser_rate') && ...
        isfield(st.orc_condenser_rate,'T_orccw_out'))
    r.feasible = false;
    r.preheaterGuardPass = false;
    r.status = 'preheater-temp-guard-missing-target';
    return
end
condOutC = st.orc_condenser_rate.T_orccw_out - 273.15;
r.condOutletTemp_C = condOutC;
r.preheaterGuardMargin_K = condOutC - targetC;
if condOutC < targetC
    r.feasible = false;
    r.preheaterGuardPass = false;
    r.status = 'preheater-temp-guard';
else
    r.preheaterGuardPass = true;
end
end

% =========================================================================
% OFF OUTPUT
% =========================================================================
function orcStep = localBuildOffStep(orcDesign,orcHotStream,orcColdStream,orcDispatchInput,config,orcTimer,orcDispatch)
% Build a safe ORC-off result if no feasible candidate exists.

Pev = localGetField(orcDispatchInput,'orc_P_evap',orcDesign.orc_thermo.P_orcevap); % [Pa]
Pco = localGetField(orcDispatchInput,'orc_P_cond',orcDesign.orc_thermo.P_orccond); % [Pa]

orcThermo = struct();                                % minimal thermo [-]
orcThermo.orc_fluid = config.orc_fluid;              % [-]
orcThermo.P_orc_crit = orcDesign.orc_thermo.P_orc_crit; % [Pa]
orcThermo.P_orcevap = Pev;                           % [Pa]
orcThermo.P_orccond = Pco;                           % [Pa]
orcThermo.P_orcpump_out = Pev;                       % [Pa]
orcThermo.P_orcturb_out = Pco;                       % [Pa]
orcThermo.dp_orcevap_wf = 0;                         % [Pa]
orcThermo.dp_orccond_wf = 0;                         % [Pa]
orcThermo.mdot_orc = 0;                              % [kg/s]
orcThermo.W_orcturb = 0;                             % [W]
orcThermo.W_orcpump = 0;                             % [W]
orcThermo.W_orcnet = 0;                              % [W]
orcThermo.Q_orcevap = 0;                             % [W]
orcThermo.Q_orccond = 0;                             % [W]
orcThermo.eta_orc_th = 0;                            % [-]
orcThermo.orc_energyBalanceOK = true;                % off state is balanced [-]

orcStep = struct();                                  % output [-]
orcStep.orc_modelVersion = config.orc_modelVersion;  % [-]
orcStep.orc_thermo = orcThermo;                      % [-]
orcStep.orc_evaporator_rate = localBlankHxRate('evaporator',orcHotStream.T_in); % [-]
orcStep.orc_condenser_rate = localBlankHxRate('condenser',orcColdStream.T_in);  % [-]
orcStep.orc_hotStream = orcHotStream;                % [-]
orcStep.orc_coldStream = orcColdStream;              % [-]
orcStep.orc_operatingInput = orcDispatchInput;       % [-]
orcStep.orc_hydraulicIterLog = struct([]);           % [-]
orcStep.orc_hydraulicConverged = false;              % [-]
orcStep.orc_hydraulicFinalRel = NaN;                 % [-]
orcStep.orc_hydraulicNiter = 0;                      % [-]
orcStep.orc_errorCaught = false;                     % no thrown error [-]
orcStep.orc_errorMessage = '';                       % [-]
orcStep.orc_status = 'dispatch-off';                 % status text [-]
orcStep.orc_feasible = false;                        % no running ORC point [-]
orcStep.orc_dispatch = orcDispatch;                  % diagnostics [-]
orcStep.orc_elapsed_s = toc(orcTimer);               % [s]
end

function hx = localBlankHxRate(hxType,T_in)
% Create an HX-rate row for an OFF timestep.
hx = struct();                                       % [-]
hx.orc_hxType = hxType;                              % [-]
hx.N_parallel_installed = 0;                         % [-]
hx.N_parallel_active = 0;                            % [-]
hx.A_geo_module = NaN;                               % [m2]
hx.A_req_module = 0;                                 % [m2]
hx.A_ratio = 0;                                      % [-]
hx.A_tol_rel = NaN;                                  % [-]
hx.Q_orcevap_module = 0;                             % [W]
hx.Q_orcevap_total = 0;                              % [W]
hx.Q_orccond_module = 0;                             % [W]
hx.Q_orccond_total = 0;                              % [W]
hx.T_orchtf_in = T_in;                               % [K]
hx.T_orchtf_int = T_in;                              % [K]
hx.T_orchtf_out = T_in;                              % [K]
hx.T_orccw_in = T_in;                                % [K]
hx.T_orccw_int = T_in;                               % [K]
hx.T_orccw_out = T_in;                               % [K]
hx.dp_orcevap_wf = 0;                                % [Pa]
hx.dp_orccond_wf = 0;                                % [Pa]
hx.dp_orchtf = 0;                                    % [Pa]
hx.dp_orccw = 0;                                     % [Pa]
hx.deltaT_pinch = NaN;                               % [K]
hx.orc_areaOK = false;                               % [-]
hx.orc_approachOK = false;                           % [-]
hx.orc_feasible = false;                             % [-]
hx.orc_elapsed_s = 0;                                % [s]
hx.zones = struct();                                 % [-]
end

% =========================================================================
% SMALL HELPERS
% =========================================================================
function r = localBlankCandidateResult()
r = struct();                                        % [-]
r.candidateNo = NaN;                                 % [-]
r.mdotFactor = NaN;                                  % [-]
r.PevapFactor = NaN;                                 % [-]
r.PcondFactor = NaN;                                 % [-]
r.dispatchScore = NaN;                               % [-]
r.P_orcevap = NaN;                                   % [Pa]
r.P_orccond = NaN;                                   % [Pa]
r.mdot_orc = NaN;                                    % [kg/s]
r.W_orcnet = NaN;                                    % [W]
r.evap_A_ratio = NaN;                                % [-]
r.cond_A_ratio = NaN;                                % [-]
r.evap_pinch_K = NaN;                                % [K]
r.cond_pinch_K = NaN;                                % [K]
r.condOutletTemp_C = NaN;                            % [degC]
r.preheaterGuardTarget_C = NaN;                     % [degC]
r.preheaterGuardMargin_K = NaN;                     % [K]
r.preheaterGuardPass = false;                       % [-]
r.feasible = false;                                  % [-]
r.validatedFlag = false;                             % [-]
r.prescreenFlag = false;                             % [-]
r.guardedFlag = false;                               % [-]
r.errorFlag = false;                                 % [-]
r.errorMessage = '';                                 % [-]
r.status = '';                                      % [-]
r.elapsed_s = NaN;                                   % [s]
end

function value = localGetField(s,fieldName,defaultValue)
if isstruct(s) && isfield(s,fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);                            % available value [-]
else
    value = defaultValue;                             % default [-]
end
end

function value = localGetStepField(s,fieldName,defaultValue)
if isstruct(s) && isfield(s,fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);                            % available value [-]
else
    value = defaultValue;                             % default [-]
end
end
