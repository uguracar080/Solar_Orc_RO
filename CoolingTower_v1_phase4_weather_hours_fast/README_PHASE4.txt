CoolingTower v1 - Phase 4 weather-hour validation with timing
=============================================================

This package contains the Phase-4 cooling-tower model files.

Main updates relative to Phase 4 fixed3:
  1) All clickable quickstart files are scripts.
  2) Timing blocks were added to Phase 1, Phase 2, Phase 3, and Phase 4 quickstarts.
  3) ct_quickstart_phase4_weather_hours.m reports timing for:
       - initialization
       - weather cache loading
       - CT model setup
       - representative weather-hour selection
       - selected-hour CT loop
       - per-case full-fan and target-solve runtimes
  4) Optional full-year runtime test added:
       ct_quickstart_phase4_annual_timing.m

Weather file handling
---------------------
The EPW file name is changed inside:

  CoolingTower/ct_quickstart_phase4_weather_hours.m
  CoolingTower/ct_quickstart_phase4_annual_timing.m

at the line:

  CTWeatherEPWFileName = 'TUR_IC_Mersin.173400_TMYx.2009-2023.epw';

The script finds the sibling Weather folder automatically:

  Project/
    Weather/
    CoolingTower/

The cache file name is not written in the CT scripts. read_epw_weather.m
creates/loads the matching *_weather_cache.mat automatically.

Recommended run sequence
------------------------
From the project root or after addpath(genpath(pwd)):

  ct_quickstart_phase1
  ct_quickstart_phase2
  ct_quickstart_phase3
  ct_quickstart_phase4_weather_hours

Optional full-year timing test:

  ct_quickstart_phase4_annual_timing

Workspace variables
-------------------
The scripts leave useful variables in the MATLAB workspace:

  CTConfig
  CTDesign
  WeatherData
  CTTiming
  CTCaseTiming
  CTWeatherSummary
  CTWeatherResults

For the annual timing script:

  CTAnnualSummary
  CTTiming

