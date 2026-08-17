%% ORC QUICK START
% Run this script after Python CoolProp is available to MATLAB.
clear all;
clearvars;
clc;

%% ========================================================================
% PATH
% ========================================================================
orcFolder = fileparts(mfilename('fullpath'));
addpath(orcFolder);

%% ========================================================================
% COMMON CONFIG
% ========================================================================
config = struct();
config = orc_default_config(config);

if config.orc_property_cache_enabled && config.orc_property_cache_resetAtQuickstart
    orc_properties(config,'CACHERESET');               % clean cache/stat baseline [-]
end

orcQuickTimer = tic;                                  % total timer [-]

%% ========================================================================
% 1) KASKA CASE-1 VALIDATION
% ========================================================================
if config.orc_run_kaska_validation
    tBlock = tic;                                     % block timer [-]
    orcValidation = orc_validate_kaska(config);       %#ok<NASGU>
    fprintf('Kaska validation time : %.2f s\n',toc(tBlock));
end

%% ========================================================================
% 2) R1233ZD(E) DESIGN-POINT EXAMPLE
% ========================================================================
systemInput = struct();
systemInput.orc_W_nom = 250e3;                       % nominal net ORC power [W]
systemInput.orc_P_evap_des = 10.7e5;                 % example evaporation pressure [Pa]
systemInput.orc_P_cond_des = 1.2e5;                  % example condensation pressure [Pa]

orcHydraulic = struct();
orcHydraulic.orc_dp_evap_wf = 0;                     % first thermodynamic pass [Pa]
orcHydraulic.orc_dp_cond_wf = 0;                     % first thermodynamic pass [Pa]

tBlock = tic;                                        % block timer [-]
orcThermo = orc_thermo_design(systemInput,config,orcHydraulic);
disp(orcThermo)
fprintf('Thermo design time    : %.2f s\n',toc(tBlock));

%% ========================================================================
% 3) STHE GEOMETRY / CORRELATION CORE CHECK
% ========================================================================
if config.orc_run_sthe_core_check
    tBlock = tic;                                     % block timer [-]
    orcStheCheck = orc_sthe_core_check(config);       %#ok<NASGU>
    fprintf('STHE core check time : %.2f s\n',toc(tBlock));
end

%% ========================================================================
% 4) STAGE-1 ORC SIZING CHECK
% ========================================================================
if config.orc_run_stage1_sizing
    orcHotStream = struct();
    orcHotStream.fluid = 'Water';                    % temporary hot stream [-]
    orcHotStream.T_in = 160 + 273.15;                % evaporator inlet [K]
    orcHotStream.P_in = 10e5;                        % keep liquid water [Pa]
    orcHotStream.mdot = 30.0;                        % hot-stream flow [kg/s]

    orcColdStream = struct();
    orcColdStream.fluid = 'Water';                   % cooling water [-]
    orcColdStream.T_in = 15 + 273.15;                % condenser inlet [K]
    orcColdStream.P_in = 2e5;                        % cooling-water pressure [Pa]
    orcColdStream.mdot = 100.0;                      % cooling-water flow [kg/s]

    orcDesign = orc_stage1_sizing(systemInput,orcHotStream,orcColdStream,config); %#ok<NASGU>
end


%% ========================================================================
% 5) STAGE-2 FIXED-GEOMETRY DESIGN-POINT CHECK
% ========================================================================
if config.orc_run_stage2_annual_check && exist('orcDesign','var')
    tBlock = tic;                                     % block timer [-]
    orcAnnualInput = struct();                        % use design streams [-]
    orcAnnualInput.orc_dt_s = config.sim_dt_s;        % one timestep [s]
    orcAnnual = orc_stage2_annual_offdesign(orcDesign,orcAnnualInput,config); %#ok<NASGU>
    fprintf('Stage-2 check time  : %.2f s\n',toc(tBlock));
end



%% ========================================================================
% 6) STAGE-2 COMPREHENSIVE OFF-DESIGN TEST SUITE
% ========================================================================
if config.orc_run_stage2_test_suite && exist('orcDesign','var')
    tBlock = tic;                                     % block timer [-]
    orcStage2Test = orc_stage2_test_suite(orcDesign,config); %#ok<NASGU>
    fprintf('Stage-2 test time   : %.2f s\n',toc(tBlock));
end



%% ========================================================================
% 7) STAGE-2 DISPATCH OFF-DESIGN TEST SUITE
% ========================================================================
if config.orc_run_stage2_dispatch_test_suite && exist('orcDesign','var')
    tBlock = tic;                                     % block timer [-]
    orcStage2DispatchTest = orc_stage2_dispatch_test_suite(orcDesign,config); %#ok<NASGU>
    fprintf('Stage-2 dispatch test time : %.2f s\n',toc(tBlock));
end

%% ========================================================================
% 8) SYNTHETIC ANNUAL/DAY DISPATCH TEST
% ========================================================================
if config.orc_run_stage2_synthetic_annual_dispatch_test && exist('orcDesign','var')
    tBlock = tic;                                     % block timer [-]
    orcSyntheticAnnualDispatch = orc_stage2_synthetic_annual_dispatch_test(orcDesign,config); %#ok<NASGU>
    fprintf('Synthetic annual dispatch test time : %.2f s\n',toc(tBlock));
end

%% ========================================================================
% TOTAL TIME
% ========================================================================
if config.orc_property_cache_stats_enabled
    orcCacheStats = orc_properties(config,'CACHESTATS'); %#ok<NASGU>
    fprintf('\n============================================================\n');
    fprintf('ORC PROPERTY CACHE SUMMARY - V%s\n',config.orc_modelVersion);
    fprintf('============================================================\n');
    fprintf('Requests           : %10d\n',orcCacheStats.nRequests);
    fprintf('Hits / misses      : %10d / %-10d\n',orcCacheStats.nHits,orcCacheStats.nMisses);
    fprintf('Active hit rate    : %10.2f %%\n',100*orcCacheStats.activeHitRate);
    fprintf('Cache entries      : %10d\n',orcCacheStats.nEntries);
    fprintf('Cache resets       : %10d\n',orcCacheStats.nResets);
    fprintf('============================================================\n');
end

fprintf('\nORC quickstart total time : %.2f s\n',toc(orcQuickTimer));
