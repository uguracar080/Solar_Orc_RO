%% CT_QUICKSTART_PHASE1
% Phase 1 with project-wide CT-prefixed structures.
% This is a script so it can be run directly from the MATLAB editor.

clearvars -except ProjectConfig WeatherData
clc

CTTimerTotal = tic;

CTTimerInit = tic;
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
addpath(fullfile(fileparts(thisDir),'Weather'));
CTTiming.initialization_s = toc(CTTimerInit);

CTTimerSetup = tic;
CTConfig = ct_default_config();
CTAmbient = struct('T_db_C',35,'T_wb_C',24,'P_atm_Pa',101325);
CTTiming.setup_s = toc(CTTimerSetup);

fprintf('\nCooling Tower v1 - Phase 1 quickstart\n');
fprintf('1) Psychrometrics sanity check\n');
CTTimerPsych = tic;
CTAir = ct_psychrometrics(CTAmbient,CTConfig);
CTTiming.psychrometrics_s = toc(CTTimerPsych);
fprintf('   omega = %.6f kg/kg_da, h = %.3f kJ/kg_da, RH = %.2f %%\n', ...
    CTAir.omega,CTAir.h_kJkgda,CTAir.RH_pct);
fprintf('   backend = %s\n',CTAir.backend_used{1});

fprintf('\n2) Old-model regression + proper Merkel L/G sweep\n');
CTTimerValidation = tic;
CTResults = ct_validate_old_model_case(CTConfig); %#ok<NASGU>
CTTiming.old_model_validation_s = toc(CTTimerValidation);

CTTiming.total_s = toc(CTTimerTotal);

fprintf('\nTiming:\n');
fprintf('  Initialization          : %.3f s\n',CTTiming.initialization_s);
fprintf('  Setup                   : %.3f s\n',CTTiming.setup_s);
fprintf('  Psychrometrics check    : %.3f s\n',CTTiming.psychrometrics_s);
fprintf('  Merkel validation       : %.3f s\n',CTTiming.old_model_validation_s);
fprintf('  Total elapsed time      : %.3f s\n',CTTiming.total_s);

fprintf('\nPhase 1 complete. Next milestone: CTDesign + rated airflow/transfer characteristic.\n');
