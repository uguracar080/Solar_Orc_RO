ORC_v20
=======

Focus:
- Adds annual/period dispatch infrastructure for the fixed-geometry ORC model.
- Adds warm-start support: each timestep can try the previous feasible operating point immediately after the design candidate.
- Adds a compact synthetic 24-step dispatch profile before coupling to PTC/PCM/cooling-tower data.

New files:
- orc_stage2_annual_dispatch.m
- orc_stage2_synthetic_annual_dispatch_test.m

Modified files:
- orc_default_config.m
- orc_offdesign_dispatch.m
- orc_stage2_annual_offdesign.m
- orc_quickstart.m

Default quickstart behavior:
- Stress dispatch test suite is OFF by default to avoid long runtime.
- Synthetic annual/day dispatch test is ON by default.

Important config flags:
config.orc_run_stage2_dispatch_test_suite = false;
config.orc_run_stage2_synthetic_annual_dispatch_test = true;
config.orc_stage2_dispatch_useWarmStart = true;
config.orc_stage2_dispatch_keepWarmStartAfterOff = true;
config.orc_synthetic_annual_nStep = 24;
config.orc_synthetic_annual_dt_s = 3600;

Notes:
- The synthetic profile is not a solar-field/PCM model. It is a controlled integration test for annual dispatch arrays, warm start, OFF handling, timestep energy integration, and output bookkeeping.
- Heat exchanger geometry remains frozen after Stage-1.
