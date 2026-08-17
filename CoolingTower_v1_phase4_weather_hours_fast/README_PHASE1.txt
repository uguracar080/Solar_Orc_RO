COOLING TOWER v1 - PHASE 1 (CT NAMING CONVENTION)
==================================================

Project-wide component naming is now explicit and aligned with the ORC module style:

  CTConfig   -> cooling-tower model configuration
  CTInput    -> cooling-tower calculation inputs
  CTOutput   -> cooling-tower calculation outputs
  CTDesign   -> fixed/rated cooling-tower design (introduced in Phase 2)
  CTAmbient  -> cooling-tower ambient boundary condition
  CTAir      -> psychrometric air state
  CTResults  -> validation / regression result structure

Example:
  CTInput.Me_available
  CTOutput.Me_required
  CTConfig.numerics.merkel_n_intervals

Generic names such as data.Me_available, out.Me_required, config, and result are not used at public component interfaces.
Fields themselves are not redundantly prefixed because the structure already identifies the component.

Phase-1 files:
  CoolingTower/ct_default_config.m
  CoolingTower/ct_psychrometrics.m
  CoolingTower/ct_merkel_number.m
  CoolingTower/ct_validate_old_model_case.m
  CoolingTower/ct_quickstart_phase1.m

Weather/HAPropsSI.m and Weather/read_epw_weather.m remain the existing project infrastructure.
