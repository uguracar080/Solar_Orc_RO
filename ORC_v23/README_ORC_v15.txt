ORC_v15 - fixed-geometry off-design dispatch layer

Main additions relative to ORC_v14:

1) New dispatch solver
   - orc_offdesign_dispatch.m
   - Searches a compact ordered candidate set of ORC mass flow, evaporation
     pressure and condensation pressure.
   - Keeps evaporator/condenser geometry frozen.
   - Returns dispatch-on if a feasible fixed-geometry point is found.
   - Returns dispatch-off if no feasible point is found.

2) Stage-2 annual mode support
   - orc_stage2_annual_offdesign.m can now run either forced-command mode or
     dispatch mode.
   - Default remains forced for the one-point design check.
   - Use orcAnnualInput.orc_useDispatch = true or
     config.orc_stage2_operatingMode = 'dispatch' for dispatched annual runs.

3) Dispatch stress-test suite
   - orc_stage2_dispatch_test_suite.m
   - quickstart runs this by default.
   - The old forced comprehensive test suite remains available but is disabled
     by default to avoid running both long suites in every quickstart.

Important config fields:

config.orc_run_stage2_test_suite = false;
config.orc_run_stage2_dispatch_test_suite = true;
config.orc_stage2_operatingMode = 'forced';
config.orc_dispatch_maxCandidates = 48;
config.orc_dispatch_stopAtFirstFeasible = true;
config.orc_dispatch_mdotFactors = [1.00 0.95 0.90 0.85 0.80 0.70 0.60 0.50 0.40 0.30 0.20 0.10];
config.orc_dispatch_pevapFactors = [1.00 0.97 0.95 0.90 0.85];
config.orc_dispatch_pcondFactors = [1.00 1.10 1.20 1.35 1.50];

Expected quickstart flow:
- Kaşka validation
- thermodynamic design example
- STHE core check
- Stage-1 sizing
- one-point Stage-2 fixed-geometry check
- Stage-2 dispatch test suite

