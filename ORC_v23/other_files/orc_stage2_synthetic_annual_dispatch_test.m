function orcSynthetic = orc_stage2_synthetic_annual_dispatch_test(orcDesign,config)
% ORC_STAGE2_SYNTHETIC_ANNUAL_DISPATCH_TEST Run a compact synthetic profile.
%
% The profile is not a solar-field model.  It is a deterministic stress test
% for the annual dispatch interface before PTC/PCM/cooling-tower coupling.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 2 || isempty(config)
    config = struct();
end
config = orc_default_config(config);
orcTimer = tic;                                      % test timer [-]

% =========================================================================
% BUILD SYNTHETIC DAY/ANNUAL-LIKE PROFILE
% =========================================================================
nStep = config.orc_synthetic_annual_nStep;           % [-]
dt_s = config.orc_synthetic_annual_dt_s;             % [s]
hour = (0:nStep-1)';                                 % profile index [h]
localHour = mod(hour,24);                            % synthetic local hour [h]

hot0 = orcDesign.orc_hotStream_design;               % design hot stream [-]
cold0 = orcDesign.orc_coldStream_design;             % design cold stream [-]

solar = max(0,sin(pi*(localHour-6)/12));             % daylight shape [-]
pcmTail = 0.28*exp(-((localHour-1)/4).^2) + ...
          0.23*exp(-((localHour-22)/4).^2);          % low night/shoulder support [-]
avail = min(1.05,solar + pcmTail);                   % heat availability index [-]

T_hot = hot0.T_in - 48 + 62*avail + 6*exp(-((localHour-14)/3).^2); % [K]
mdot_hot = hot0.mdot.*max(0.05,0.12 + 0.93*avail);   % [kg/s]
T_cold = cold0.T_in + 2 + 9*solar + 2*sin(2*pi*(localHour-15)/24); % [K]
mdot_cold = cold0.mdot.*(1.05 - 0.18*solar + 0.04*cos(2*pi*localHour/24)); % [kg/s]
mdot_cold = max(0.25*cold0.mdot,mdot_cold);          % [kg/s]

orcHotStream(1,nStep) = hot0;                        % preallocate hot streams [-]
orcColdStream(1,nStep) = cold0;                      % preallocate cold streams [-]
for it = 1:nStep
    orcHotStream(it) = hot0;                         % copy design stream [-]
    orcHotStream(it).T_in = T_hot(it);               % [K]
    orcHotStream(it).mdot = mdot_hot(it);            % [kg/s]
    orcColdStream(it) = cold0;                       % copy design stream [-]
    orcColdStream(it).T_in = T_cold(it);             % [K]
    orcColdStream(it).mdot = mdot_cold(it);          % [kg/s]
end

op = struct();                                       % design maximum command [-]
op.orc_P_evap = orcDesign.orc_thermo.P_orcevap;      % [Pa]
op.orc_P_cond = orcDesign.orc_thermo.P_orccond;      % [Pa]
op.orc_mdot = orcDesign.orc_thermo.mdot_orc;         % [kg/s]

orcAnnualInput = struct();                           % annual input [-]
orcAnnualInput.orcHotStream = orcHotStream;          % [-]
orcAnnualInput.orcColdStream = orcColdStream;        % [-]
orcAnnualInput.orcOperatingInput = op;               % scalar max command [-]
orcAnnualInput.orc_dt_s = repmat(dt_s,nStep,1);      % [s]
orcAnnualInput.orc_useDispatch = true;               % dispatch mode [-]

% =========================================================================
% RUN ANNUAL DISPATCH
% =========================================================================
printBackup = config.orc_stage2_printSummary;        % preserve config [-]
config.orc_stage2_printSummary = false;              % custom summary below [-]
orcAnnual = orc_stage2_annual_dispatch(orcDesign,orcAnnualInput,config); % [-]
config.orc_stage2_printSummary = printBackup;        % restore [-]

% =========================================================================
% SUMMARY
% =========================================================================
running = orcAnnual.orc_feasible;                    % [-]
W_kW = orcAnnual.orc_W_net/1e3;                      % [kW]
Nc = orcAnnual.orc_dispatch_nCandidates;             % [-]
Nr = orcAnnual.orc_dispatch_nRatedCandidates;        % [-]

summary = struct();                                  % summary [-]
summary.nStep = nStep;                               % [-]
summary.dt_s = dt_s;                                 % [s]
summary.operatingHours = sum(running)*dt_s/3600;     % [h]
summary.offHours = sum(~running)*dt_s/3600;          % [h]
summary.E_orcnet_kWh = orcAnnual.orc_E_net_kWh;      % [kWh]
summary.meanW_all_kW = mean(W_kW);                   % [kW]
summary.meanW_running_kW = localMean(W_kW(running)); % [kW]
summary.maxW_kW = localMax(W_kW);                    % [kW]
summary.minRunningW_kW = localMin(W_kW(running));    % [kW]
summary.meanCandidates = mean(Nc);                   % [-]
summary.maxCandidates = max(Nc);                     % [-]
summary.meanRatedCandidates = mean(Nr);              % [-]
summary.maxRatedCandidates = max(Nr);                % [-]
summary.maxEvapAreaRatio = max(orcAnnual.orc_A_ratio_evap); % [-]
summary.maxCondAreaRatio = max(orcAnnual.orc_A_ratio_cond); % [-]
summary.elapsed_s = toc(orcTimer);                   % [s]

orcSynthetic = struct();                             % output [-]
orcSynthetic.orc_modelVersion = config.orc_modelVersion; % [-]
orcSynthetic.orc_hour = hour;                        % [h]
orcSynthetic.orc_localHour = localHour;              % [h]
orcSynthetic.orc_heatAvailability = avail;           % [-]
orcSynthetic.orcAnnualInput = orcAnnualInput;        % [-]
orcSynthetic.orcAnnual = orcAnnual;                  % [-]
orcSynthetic.orc_summary = summary;                  % [-]
orcSynthetic.orc_elapsed_s = summary.elapsed_s;      % [s]

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
fprintf('\n============================================================\n');
fprintf('ORC STAGE-2 SYNTHETIC ANNUAL DISPATCH TEST - V%s\n',config.orc_modelVersion);
fprintf('============================================================\n');
fprintf('Timesteps          : %10d\n',nStep);
fprintf('Operating hours    : %10.3f h\n',summary.operatingHours);
fprintf('ORC-off hours      : %10.3f h\n',summary.offHours);
fprintf('E_orcnet           : %10.3f kWh\n',summary.E_orcnet_kWh);
fprintf('Mean W all         : %10.2f kW\n',summary.meanW_all_kW);
fprintf('Mean W running     : %10.2f kW\n',summary.meanW_running_kW);
fprintf('Min/Max W running  : %10.2f / %-10.2f kW\n',summary.minRunningW_kW,summary.maxW_kW);
fprintf('Max evap A ratio   : %10.4f\n',summary.maxEvapAreaRatio);
fprintf('Max cond A ratio   : %10.4f\n',summary.maxCondAreaRatio);
fprintf('Mean/max candidates: %10.2f / %-10.0f\n',summary.meanCandidates,summary.maxCandidates);
fprintf('Mean/max HX-rated  : %10.2f / %-10.0f\n',summary.meanRatedCandidates,summary.maxRatedCandidates);
fprintf('Warm-start steps   : %10d / %-10d\n',sum(orcAnnual.orc_warmStartUsed),nStep);
fprintf('Synthetic time     : %10.2f s\n',summary.elapsed_s);

if config.orc_synthetic_annual_printTable
    fprintf('------------------------------------------------------------\n');
    fprintf('  h  Thtf  mdotH   Tcw  mdotC   RUN    W[kW]   mdot     Pe     Pc    Nc   Nr\n');
    fprintf('------------------------------------------------------------\n');
    for it = 1:nStep
        runText = 'OFF';
        if running(it)
            runText = 'ON ';
        end
        fprintf('%3d %5.1f %6.2f %5.1f %6.2f   %3s  %7.1f %6.3f %6.2f %6.2f %5d %4d\n', ...
            it,orcAnnual.orc_T_htf_in(it)-273.15,orcHotStream(it).mdot, ...
            orcAnnual.orc_T_cw_in(it)-273.15,orcColdStream(it).mdot,runText, ...
            W_kW(it),orcAnnual.orc_mdot(it),orcAnnual.orc_P_evap(it)/1e5, ...
            orcAnnual.orc_P_cond(it)/1e5,Nc(it),Nr(it));
    end
end
fprintf('============================================================\n');

end

function v = localMean(x)
if isempty(x)
    v = NaN;
else
    v = mean(x);
end
end

function v = localMax(x)
if isempty(x)
    v = NaN;
else
    v = max(x);
end
end

function v = localMin(x)
if isempty(x)
    v = NaN;
else
    v = min(x);
end
end
