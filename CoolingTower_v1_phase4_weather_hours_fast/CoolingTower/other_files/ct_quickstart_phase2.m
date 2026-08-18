%% CT_QUICKSTART_PHASE2
% Phase 2: CTDesign + off-design Merkel + fan target solve.
% This is a script so it can be run directly from the MATLAB editor.

clearvars -except ProjectConfig WeatherData
clc

CTTimerTotal = tic;

CTTimerInit = tic;
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
addpath(fullfile(fileparts(thisDir),'Weather'));
CTTiming.initialization_s = toc(CTTimerInit);

CTTimerConfig = tic;
CTConfig = ct_default_config();
CTTiming.config_s = toc(CTTimerConfig);

fprintf('\nCooling Tower v1 - Phase 2 quickstart\n');
fprintf('1) Build rated CTDesign\n');
CTTimerDesign = tic;
CTDesign = ct_rate_design_point(struct(),CTConfig);
CTTiming.design_build_s = toc(CTTimerDesign);
fprintf('   Q_rated       = %.3f MW\n',CTDesign.Q_rated_W/1e6);
fprintf('   T_w in/out    = %.2f / %.2f C\n',CTDesign.T_w_in_rated_C,CTDesign.T_w_out_rated_C);
fprintf('   mdot water    = %.3f kg/s\n',CTDesign.mdot_water_rated);
fprintf('   mdot dry air  = %.3f kg_da/s\n',CTDesign.mdot_air_rated);
fprintf('   L/G rated     = %.3f\n',CTDesign.L_over_G_rated);
fprintf('   Me rated      = %.6f\n',CTDesign.Me_rated);
fprintf('   W fan rated   = %.3f kW\n',CTDesign.W_fan_rated_W/1000);

fprintf('\n2) Off-design at rated condition and full fan\n');
CTAmbient = struct('T_db_C',CTDesign.T_db_rated_C, ...
                   'T_wb_C',CTDesign.T_wb_rated_C, ...
                   'P_atm_Pa',CTDesign.P_atm_rated_Pa);
CTInput = struct();
CTInput.T_w_in_C = CTDesign.T_w_in_rated_C;
CTInput.mdot_water = CTDesign.mdot_water_rated;
CTInput.fan_ratio = 1.0;
CTTimerFullFan = tic;
CTOutput = ct_offdesign_merkel(CTInput,CTAmbient,CTDesign,CTConfig);
CTTiming.full_fan_case_s = toc(CTTimerFullFan);
fprintf('   T_w_out       = %.4f C\n',CTOutput.T_w_out_C);
fprintf('   Q rejected    = %.3f MW\n',CTOutput.Q_rejected_W/1e6);
fprintf('   Approach      = %.4f C\n',CTOutput.approach_C);
fprintf('   Status        = %s\n',CTOutput.status);

fprintf('\n3) Minimum fan ratio for a target cold-water temperature\n');
CTInputTarget = CTInput;
CTInputTarget.T_w_in_C = CTDesign.T_w_in_rated_C;
CTInputTarget.T_w_out_target_C = CTDesign.T_w_out_rated_C + 1.0;
CTTimerTarget = tic;
CTOutputTarget = ct_solve_fan_for_target(CTInputTarget,CTAmbient,CTDesign,CTConfig);
CTTiming.target_solve_s = toc(CTTimerTarget);
fprintf('   Target T_out  = %.3f C\n',CTInputTarget.T_w_out_target_C);
fprintf('   Solved T_out  = %.3f C\n',CTOutputTarget.T_w_out_C);
fprintf('   Fan ratio     = %.4f\n',CTOutputTarget.fan_ratio);
fprintf('   Fan power     = %.3f kW\n',CTOutputTarget.W_fan_W/1000);
fprintf('   Target status = %s\n',CTOutputTarget.status);

CTTiming.total_s = toc(CTTimerTotal);

fprintf('\nTiming:\n');
fprintf('  Initialization          : %.3f s\n',CTTiming.initialization_s);
fprintf('  Config                  : %.3f s\n',CTTiming.config_s);
fprintf('  CTDesign build          : %.3f s\n',CTTiming.design_build_s);
fprintf('  Full-fan CT solve       : %.3f s\n',CTTiming.full_fan_case_s);
fprintf('  Target fan solve        : %.3f s\n',CTTiming.target_solve_s);
fprintf('  Total elapsed time      : %.3f s\n',CTTiming.total_s);

fprintf('\nPhase 2 complete. Next milestone: evaporation/makeup water + selected-hour validation.\n');
