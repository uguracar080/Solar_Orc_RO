function config = orc_default_config(config)
% ORC_DEFAULT_CONFIG Create ORC defaults inside the common config struct.

% =========================================================================
% INPUT CHECK
% =========================================================================
if nargin < 1 || isempty(config)
    config = struct();
end

% =========================================================================
% PROPERTY MODEL
% =========================================================================
config = setDefault(config,'orc_modelVersion','0.23');            % ORC model version [-]
config = setDefault(config,'orc_fluid','R1233zd(E)');           % working fluid [-]
config = setDefault(config,'orc_property_backend','coolprop');  % property backend [-]
config = setDefault(config,'orc_useFluidGrid',false);           % use property grid [-]
config = setDefault(config,'orc_fluidGridFile','');             % property grid file [-]
config = setDefault(config,'orc_r1233zde_k_useNist',true);     % use NIST k for R1233zd(E) [-]
config = setDefault(config,'orc_r1233zde_k_includeCritical',false); % critical enhancement [-]

% =========================================================================
% THERMODYNAMIC MODEL
% =========================================================================
config = setDefault(config,'orc_eta_turb',0.85);                % turbine isentropic efficiency [-]
config = setDefault(config,'orc_eta_pump',0.80);                % pump isentropic efficiency [-]
config = setDefault(config,'orc_turbineInletMode','sat_vapor'); % turbine inlet mode [-]
config = setDefault(config,'orc_condOutletMode','sat_liquid');  % condenser outlet mode [-]

% =========================================================================
% NUMERICAL SETTINGS
% =========================================================================
config = setDefault(config,'orc_tol_energy_rel',1e-8);          % energy balance tolerance [-]
config = setDefault(config,'orc_tol_hydraulic_rel',1e-3);       % hydraulic convergence tolerance [-]
config = setDefault(config,'orc_tol_geometry_rel',1e-5);        % geometry iteration tolerance [-]
config = setDefault(config,'orc_stage2_areaTol_rel',1e-2);       % rating area tolerance [-]
config = setDefault(config,'orc_hx_designAreaMargin',5e-3);      % design area margin [-]
config = setDefault(config,'orc_tol_htc_rel',1e-5);             % HTC iteration tolerance [-]
config = setDefault(config,'orc_max_hydraulic_iter',12);        % hydraulic iterations [-]
config = setDefault(config,'orc_hydraulic_relaxation',0.65);     % dP under-relaxation [-]
config = setDefault(config,'orc_hydraulic_finalRelTol',1e-2);    % relaxed final dP consistency tolerance [-]
config = setDefault(config,'orc_hydraulic_printIterLog',false);     % print dP iteration log [-]
config = setDefault(config,'orc_stage1_useHydraulicFeedback',true); % iterate HX dP in Stage 1 [-]
config = setDefault(config,'orc_max_geometry_iter',30);         % geometry iterations [-]
config = setDefault(config,'orc_max_htc_iter',50);              % HTC iterations [-]
config = setDefault(config,'orc_hx_nSegments',5);               % equal-duty base segments [-]
config = setDefault(config,'orc_hx_twophaseDpModel','homogeneous'); % preliminary 2ph dP model [-]
config = setDefault(config,'orc_hx_twophaseDpSegments',5);     % quality segments for 2ph dP [-]
config = setDefault(config,'orc_hx_twophaseDpIncludeAccel',false); % include acceleration term [-]
config = setDefault(config,'orc_hx_twophaseDpMinQuality',1e-4); % endpoint quality clamp [-]
config = setDefault(config,'orc_profile_timing',true);         % print solver timing [-]
config = setDefault(config,'orc_run_kaska_validation',true);   % quickstart block flag [-]
config = setDefault(config,'orc_run_sthe_core_check',true);    % quickstart block flag [-]
config = setDefault(config,'orc_run_stage1_sizing',true);      % quickstart block flag [-]
config = setDefault(config,'orc_run_stage2_annual_check',true); % quickstart block flag [-]
config = setDefault(config,'orc_run_stage2_test_suite',false);  % forced-command stress tests [-]
config = setDefault(config,'orc_run_stage2_dispatch_test_suite',false); % dispatch stress tests [-]
config = setDefault(config,'orc_run_stage2_synthetic_annual_dispatch_test',true); % synthetic annual/day dispatch test [-]
config = setDefault(config,'orc_property_cache_enabled',true); % cache property calls [-]
config = setDefault(config,'orc_property_cache_maxEntries',250000); % cache reset size [-]
config = setDefault(config,'orc_property_cache_stats_enabled',true); % track cache hit/miss diagnostics [-]
config = setDefault(config,'orc_property_cache_resetAtQuickstart',true); % clean timing baseline [-]

% =========================================================================
% STHE GENERAL SETTINGS
% =========================================================================
config = setDefault(config,'orc_hx_shellPasses',1);             % shell passes [-]
config = setDefault(config,'orc_hx_tubePasses_baseline',1);     % implemented tube passes [-]
config = setDefault(config,'orc_hx_layoutAngle_deg',60);        % tube layout angle [deg]
config = setDefault(config,'orc_hx_baffleCutRatio',0.35);       % baffle cut / shell diameter [-]
config = setDefault(config,'orc_hx_baffleSpacingTarget',0.30);  % target baffle spacing [m]
config = setDefault(config,'orc_hx_maxParallelUnits',20);       % maximum parallel modules [-]
config = setDefault(config,'orc_hx_maxShellDiameter',2.00);     % shell diameter upper limit [m]
config = setDefault(config,'orc_hx_minShellDiameter',0.30);     % shell diameter lower limit [m]
config = setDefault(config,'orc_hx_maxTubeLength',8.00);        % baseline practical limit [m]
config = setDefault(config,'orc_hx_minTubeLength',0.50);        % baseline practical limit [m]
config = setDefault(config,'orc_hx_Nt_min',20);                 % minimum tube count [-]
config = setDefault(config,'orc_hx_Nt_step',20);                % legacy tube-count increment [-]
config = setDefault(config,'orc_hx_Nt_max',1200);               % maximum tube count [-]
config = setDefault(config,'orc_hx_Nt_searchMode','coarseFine'); % Nt search mode [-]
config = setDefault(config,'orc_hx_Nt_step_coarse',100);       % coarse Nt increment [-]
config = setDefault(config,'orc_hx_Nt_step_fine',20);          % fine Nt increment [-]
config = setDefault(config,'orc_hx_Nt_fineHalfWindow',140);    % fine search half-window [-]
config = setDefault(config,'orc_hx_useSearchHints',true);      % reuse previous Nt [-]
config = setDefault(config,'orc_hx_hintHalfWindow',100);       % hint search half-window [-]
config = setDefault(config,'orc_hx_storeCandidateLogFull',false); % store all candidates [-]               % maximum tube count [-]
config = setDefault(config,'orc_hx_minApproach_K',1e-4);        % numerical positive approach [K]

% =========================================================================
% BELL-DELAWARE ASSUMPTIONS
% =========================================================================
config = setDefault(config,'orc_hx_useSealingStrips',true);     % use Jb=fb=1 [-]
config = setDefault(config,'orc_hx_equalBaffleSpacing',true);   % use Js=fs=1 [-]
config = setDefault(config,'orc_hx_useJrCorrection',false);     % adverse-gradient correction [-]

% =========================================================================
% EVAPORATOR TUBE FAMILY
% =========================================================================
config = setDefault(config,'orc_evap_tube_do',0.01905);         % tube outside diameter [m]
config = setDefault(config,'orc_evap_tube_wall',0.00200);       % tube wall thickness [m]
config = setDefault(config,'orc_evap_tube_pitch',0.02540);      % tube pitch [m]
config = setDefault(config,'orc_evap_tubePassCandidates',1);    % v0.7 implemented passes [-]

% =========================================================================
% CONDENSER TUBE FAMILY
% =========================================================================
config = setDefault(config,'orc_cond_tube_do',0.02540);         % tube outside diameter [m]
config = setDefault(config,'orc_cond_tube_wall',0.00200);       % tube wall thickness [m]
config = setDefault(config,'orc_cond_tube_pitch',0.03175);      % tube pitch [m]
config = setDefault(config,'orc_cond_tubePassCandidates',1);    % v0.7 implemented passes [-]

% =========================================================================
% HEAT-TRANSFER CORRELATIONS
% =========================================================================
config = setDefault(config,'orc_evap_boilingCorrelation','PalenMostinski'); % boiling model [-]
config = setDefault(config,'orc_cond_condensationCorrelation','NusseltKern'); % condensation model [-]
config = setDefault(config,'orc_hx_includeWallResistance',false); % wall resistance in U [-]
config = setDefault(config,'orc_hx_includeFouling',false);      % fouling resistance in U [-]

% =========================================================================
% TWO-STAGE SYSTEM LOGIC
% =========================================================================
config = setDefault(config,'orc_stage2_requireFrozenGeometry',true); % enforce fixed geometry [-]
config = setDefault(config,'orc_stage2_enableModuleStaging',false);  % parallel module staging [-]
config = setDefault(config,'orc_stage2_printSummary',true);       % print annual summary [-]

% Stage-2 progress display
config = setDefault(config,'orc_stage2_progressEnabled',true);       % timestep progress indicator [-]
config = setDefault(config,'orc_stage2_progressMode','waitbar');     % 'waitbar','command','none' [-]
config = setDefault(config,'orc_stage2_progressWaitbarText','simple'); % 'simple' or 'detailed' [-]
config = setDefault(config,'orc_stage2_progressEvery',1);            % update interval in timesteps [-]
config = setDefault(config,'orc_stage2_progressSingleLine',true);    % command-mode carriage-return line [-]
config = setDefault(config,'orc_stage2_progressBarWidth',28);        % progress bar width [-]
config = setDefault(config,'orc_stage2_progressWaitbarCloseOnFinish',true); % close GUI waitbar at finish [-]
config = setDefault(config,'orc_stage2_progressCommandFallback',false); % fallback to command if GUI unavailable [-]
config = setDefault(config,'orc_stage2_useHydraulicFeedback',true); % fixed-geometry dP iteration [-]
config = setDefault(config,'orc_stage2_operatingMode','forced');      % forced or dispatch [-]
config = setDefault(config,'orc_stage2_dispatch_useWarmStart',true); % annual dispatch uses previous feasible point [-]
config = setDefault(config,'orc_stage2_dispatch_keepWarmStartAfterOff',true); % keep last good point after OFF [-]
config = setDefault(config,'orc_stage2_dispatch_warmStartMoveDuplicate',true); % move duplicate warm-start to early slot [-]
config = setDefault(config,'orc_stage2_dispatch_warmStartSimilarityOnly',true); % early warm-start only if external streams are similar [-]
config = setDefault(config,'orc_stage2_dispatch_warmStart_Ttol_K',3.0); % stream temperature similarity tolerance [K]
config = setDefault(config,'orc_stage2_dispatch_warmStart_mdotRelTol',0.10); % stream flow similarity tolerance [-]
config = setDefault(config,'orc_dispatch_stopAtFirstFeasible',true);  % speed-first dispatch [-]
config = setDefault(config,'orc_dispatch_maxCandidates',80);          % max dispatch candidates [-]
config = setDefault(config,'orc_dispatch_minPowerFraction',0.05);     % low-load shutdown floor [-]
config = setDefault(config,'orc_dispatch_mdotFactors',[1.00 0.97 0.95 0.90 0.85 0.80 0.75 0.70 0.60 0.50 0.40 0.30 0.20 0.10]); % load search [-]
config = setDefault(config,'orc_dispatch_pevapFactors',[1.00 0.98 0.95 0.90 0.85 0.80 0.75 0.70 0.65 0.60]); % evap pressure search [-]
config = setDefault(config,'orc_dispatch_pcondFactors',[1.00 1.10 1.20 1.35 1.50 1.80 2.20 2.60]); % cond pressure search [-]
config = setDefault(config,'orc_dispatch_fastScreening',true);        % one-pass candidate screen [-]
config = setDefault(config,'orc_dispatch_fastMaxIter',1);             % screening hydraulic iterations [-]
config = setDefault(config,'orc_dispatch_validateSelected',true);     % exact-check selected candidate [-]
config = setDefault(config,'orc_dispatch_useThermoPrescreen',true);   % skip impossible candidates early [-]
config = setDefault(config,'orc_dispatch_capacityPrescreen',true); % stream heat-capacity prescreen [-]
config = setDefault(config,'orc_dispatch_capacityApproach_K',1.0); % capacity-screen terminal approach [K]
config = setDefault(config,'orc_dispatch_capacityToleranceFactor',1.08); % avoid over-pruning [-]
config = setDefault(config,'orc_dispatch_candidateListLimit',320); % built candidate list cap [-]
config = setDefault(config,'orc_dispatch_coverageMdotFactors',[1.00 0.90 0.80 0.70 0.60 0.50 0.40 0.30]); % early coverage mdot search [-]
config = setDefault(config,'orc_dispatch_useCoverageTier',true); % interleave low-load candidates earlier [-]
config = setDefault(config,'orc_dispatch_printSummary',true);        % print dispatch tests [-]
config = setDefault(config,'orc_dispatch_test_exportCsv',false);     % export dispatch CSV [-]
config = setDefault(config,'orc_dispatch_test_csvFile','orc_stage2_dispatch_results.csv'); % CSV name [-]
config = setDefault(config,'orc_synthetic_annual_nStep',24);          % synthetic dispatch-profile timesteps [-]
config = setDefault(config,'orc_synthetic_annual_dt_s',3600);         % synthetic profile timestep [s]
config = setDefault(config,'orc_synthetic_annual_printTable',true);   % print synthetic timestep table [-]
config = setDefault(config,'orc_stage2_returnInfeasibleOnError',true); % guard extreme states [-]
config = setDefault(config,'orc_stage2_test_printSummary',true);  % print stress-test summary [-]
config = setDefault(config,'orc_stage2_test_printCaseTable',true); % print compact case table [-]
config = setDefault(config,'orc_stage2_test_exportCsv',false);    % export stress-test CSV [-]
config = setDefault(config,'orc_stage2_test_csvFile','orc_stage2_test_results.csv'); % CSV name [-]
config = setDefault(config,'sim_dt_s',3600);                      % default timestep [s]

end

% =========================================================================
% LOCAL HELPER
% =========================================================================
function config = setDefault(config,fieldName,defaultValue)
% Keep a user-defined value; otherwise apply the default.
if ~isfield(config,fieldName) || isempty(config.(fieldName))
    config.(fieldName) = defaultValue;
end
end
