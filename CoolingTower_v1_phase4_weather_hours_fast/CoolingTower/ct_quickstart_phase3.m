%% CT_QUICKSTART_PHASE3
% Phase-3 smoke test: saturated-exit air state + water consumption.
% This is intentionally a script, not a function, so it can be run by
% pressing Run in the MATLAB editor. The calculation functions remain
% separate function files.

clearvars -except WeatherData ProjectConfig
clc

CTTimerTotal = tic;

CTTimerInit = tic;
thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);
addpath(fullfile(fileparts(thisDir),'Weather'));
CTTiming.initialization_s = toc(CTTimerInit);

fprintf('\nCooling Tower v1 - Phase 3 quickstart\n');

CTTimerSetup = tic;
CTConfig = ct_default_config();
% Water-chemistry placeholders for the quickstart only. Keep explicit in
% final project input files.
CTConfig.water_consumption.drift_fraction = 2e-5;
CTConfig.water_consumption.cycles_of_concentration = 5;
CTDesign = ct_rate_design_point(struct(),CTConfig);
CTAmbient = struct();
CTAmbient.T_db_C = CTDesign.T_db_rated_C;
CTAmbient.T_wb_C = CTDesign.T_wb_rated_C;
CTAmbient.P_atm_Pa = CTDesign.P_atm_rated_Pa;
CTTiming.setup_s = toc(CTTimerSetup);

fprintf('1) Rated condition, full fan, with saturated-exit air and water use\n');
CTInput = struct();
CTInput.T_w_in_C = CTDesign.T_w_in_rated_C;
CTInput.mdot_water = CTDesign.mdot_water_rated;
CTInput.fan_ratio = 1.0;
CTTimerFullFan = tic;
CTOutputFull = ct_offdesign_merkel(CTInput,CTAmbient,CTDesign,CTConfig);
CTTiming.full_fan_water_s = toc(CTTimerFullFan);

fprintf('   T_w_out        = %.4f C\n',CTOutputFull.T_w_out_C);
fprintf('   Q rejected     = %.3f MW\n',CTOutputFull.Q_rejected_W/1e6);
fprintf('   T_air_out      = %.3f C\n',CTOutputFull.T_air_out_C);
fprintf('   omega in/out   = %.6f / %.6f kg/kg_da\n',CTOutputFull.omega_air_in,CTOutputFull.omega_air_out);
fprintf('   evap loss      = %.5f kg/s  (%.3f m3/h)\n',CTOutputFull.mdot_evap_kg_s,CTOutputFull.water_consumption.V_evap_m3_h);
fprintf('   drift loss     = %.5f kg/s  (%.3f m3/h)\n',CTOutputFull.mdot_drift_kg_s,CTOutputFull.water_consumption.V_drift_m3_h);
fprintf('   blowdown       = %.5f kg/s  (%.3f m3/h)\n',CTOutputFull.mdot_blowdown_kg_s,CTOutputFull.water_consumption.V_blowdown_m3_h);
fprintf('   makeup         = %.5f kg/s  (%.3f m3/h)\n',CTOutputFull.mdot_makeup_kg_s,CTOutputFull.V_makeup_m3_h);
fprintf('   Status         = %s / %s\n',CTOutputFull.status,CTOutputFull.water_consumption.status);

fprintf('\n2) Minimum fan ratio for relaxed target, with water-use diagnostics\n');
CTTargetInput = CTInput;
CTTargetInput.T_w_out_target_C = CTDesign.T_w_out_rated_C + 1.0;
CTTimerTarget = tic;
CTOutputTarget = ct_solve_fan_for_target(CTTargetInput,CTAmbient,CTDesign,CTConfig);
CTTiming.target_water_s = toc(CTTimerTarget);

fprintf('   Target T_out   = %.3f C\n',CTTargetInput.T_w_out_target_C);
fprintf('   Solved T_out   = %.3f C\n',CTOutputTarget.T_w_out_C);
fprintf('   Fan ratio      = %.4f\n',CTOutputTarget.fan_ratio);
fprintf('   Fan power      = %.3f kW\n',CTOutputTarget.W_fan_W/1000);
fprintf('   Q rejected     = %.3f MW\n',CTOutputTarget.Q_rejected_W/1e6);
fprintf('   T_air_out      = %.3f C\n',CTOutputTarget.T_air_out_C);
fprintf('   evap loss      = %.5f kg/s  (%.3f m3/h)\n',CTOutputTarget.mdot_evap_kg_s,CTOutputTarget.water_consumption.V_evap_m3_h);
fprintf('   makeup         = %.5f kg/s  (%.3f m3/h)\n',CTOutputTarget.mdot_makeup_kg_s,CTOutputTarget.V_makeup_m3_h);
fprintf('   Target status  = %s\n',CTOutputTarget.status);

fprintf('\n3) Zero-air / bypass check\n');
CTBypassInput = CTInput;
CTBypassInput.fan_ratio = 0;
CTTimerBypass = tic;
CTOutputBypass = ct_offdesign_merkel(CTBypassInput,CTAmbient,CTDesign,CTConfig);
CTTiming.bypass_s = toc(CTTimerBypass);

fprintf('   Q rejected     = %.3f MW\n',CTOutputBypass.Q_rejected_W/1e6);
fprintf('   evap loss      = %.5f kg/s\n',CTOutputBypass.mdot_evap_kg_s);
fprintf('   drift loss     = %.5f kg/s\n',CTOutputBypass.mdot_drift_kg_s);
fprintf('   blowdown       = %.5f kg/s\n',CTOutputBypass.mdot_blowdown_kg_s);
fprintf('   makeup         = %.5f kg/s\n',CTOutputBypass.mdot_makeup_kg_s);
fprintf('   Status         = %s / %s\n',CTOutputBypass.status,CTOutputBypass.water_consumption.status);

CTResults = struct();
CTResults.component = 'CT';
CTResults.phase = 3;
CTResults.CTConfig = CTConfig;
CTResults.CTDesign = CTDesign;
CTResults.full_fan = CTOutputFull;
CTResults.target = CTOutputTarget;
CTResults.bypass = CTOutputBypass;

CTTiming.total_s = toc(CTTimerTotal);
CTResults.CTTiming = CTTiming;

fprintf('\nTiming:\n');
fprintf('  Initialization          : %.3f s\n',CTTiming.initialization_s);
fprintf('  Setup                   : %.3f s\n',CTTiming.setup_s);
fprintf('  Full-fan water solve    : %.3f s\n',CTTiming.full_fan_water_s);
fprintf('  Target water solve      : %.3f s\n',CTTiming.target_water_s);
fprintf('  Bypass/no-air check     : %.3f s\n',CTTiming.bypass_s);
fprintf('  Total elapsed time      : %.3f s\n',CTTiming.total_s);

fprintf('\nPhase 3 complete. Next milestone: annual weather-hour test + ORC/preheater coupling interface.\n');
