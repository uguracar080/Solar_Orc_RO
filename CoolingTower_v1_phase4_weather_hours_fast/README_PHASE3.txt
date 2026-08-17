CoolingTower v1 Phase 3 - Air outlet + water consumption
========================================================

Run from MATLAB after adding the project folder to path:

    clear functions
    rehash
    addpath(genpath(pwd))
    ct_quickstart_phase1
    ct_quickstart_phase2
    ct_quickstart_phase3

New Phase-3 files:

CoolingTower/ct_air_outlet_state.m
    Uses the air-side energy balance h_out = h_in + Q/mdot_da and the
    saturated-exit runtime assumption to estimate T_air_out and omega_out.

CoolingTower/ct_water_consumption.m
    Calculates evaporation from mdot_da*(omega_out-omega_in), then applies
    user/project inputs for drift fraction and cycles of concentration to
    calculate blowdown and makeup.

Updated:

CoolingTower/ct_offdesign_merkel.m
    Now attaches CTOutput.air_out, CTOutput.water_consumption, and convenient
    scalar fields such as CTOutput.mdot_evap_kg_s and CTOutput.V_makeup_m3_h.

CoolingTower/ct_default_config.m
    Adds CTConfig.water.rho_kgm3, CTConfig.air_outlet.model, and explicit
    water-consumption configuration fields.

Notes:

- Evaporation is based on the dry-air humidity balance.
- Drift fraction and cycles of concentration are modelling inputs. The
  quickstart sets drift_fraction=2e-5 and COC=5 only to demonstrate the
  calculation. Use project-appropriate values in final simulations.
- Weather remains a project-wide service outside the CoolingTower component.
