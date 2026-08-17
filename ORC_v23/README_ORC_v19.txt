ORC_v19
=======

Purpose
-------
ORC_v19 keeps the v0.18 physical ORC/STHE/off-design model unchanged and
focuses on dispatch-search speed.

Main changes from v0.18
-----------------------
1. Dispatch candidate cap reduced from 120 to 80 by default.
2. Added an early coverage tier in orc_offdesign_dispatch.m:
   moderate part-load ORC mass-flow candidates are interleaved earlier with
   stress-aware Pevap/Pcond pairs. This prevents source-limited and sink-limited
   cases from spending the whole budget at nominal flow before trying feasible
   lower-load points.
3. Added dispatch timing diagnostics in orc_stage2_dispatch_test_suite.m:
   - Mean/max case time
   - Dispatch cand. cap

Important note
--------------
The heat-exchanger rating correlations, thermodynamic cycle equations,
hydraulic-feedback coupling, and fixed-geometry logic are not changed in v0.19.
Only the dispatch search ordering/budget and diagnostics are changed.
