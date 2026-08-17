CoolingTower v1 Phase 2 - CTDesign + off-design Merkel
======================================================

Run from MATLAB after adding the project folder to path:

    clear functions
    rehash
    addpath(genpath(pwd))
    ct_quickstart_phase1
    ct_quickstart_phase2

Main Phase-2 files:

CoolingTower/ct_rate_design_point.m
    Builds CTDesign from a rated point. The default example is the old-model
    rating point: Q=4.434 MW, Tdb/Twb=35/24 C, approach=4 C, range=5 C,
    L/G=1.0.

CoolingTower/ct_transfer_characteristic.m
    Computes the off-design available Merkel characteristic. Phase 2 uses a
    normalized Kloppers-Kroger trickle-fill style correlation:
        Me/Me_r = rw^(0.43177-1) * ra^0.641400 * (Twi/Twi,r)^0.178670.
    This is a modelling choice and should be kept explicit in CTConfig.

CoolingTower/ct_fan_power.m
    Uses Wfan = Wfan_rated * fan_ratio^3, where fan_ratio is interpreted as
    mdot_air/mdot_air_rated.

CoolingTower/ct_offdesign_merkel.m
    Solves fixed-tower off-design at a specified fan_ratio.

CoolingTower/ct_solve_fan_for_target.m
    Finds the minimum fan_ratio needed to meet a target cold-water temperature.

Naming convention:
    CTConfig, CTInput, CTAmbient, CTDesign, CTOutput are used consistently.

Weather remains project-wide and independent of CoolingTower.
