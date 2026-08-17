ORC_v12 - Modular ORC + STHE sizing/off-design package
======================================================

Main workflow
-------------
1) orc_validate_kaska.m
   R245fa thermodynamic validation against Kaska Case-1.

2) orc_stage1_sizing.m
   Stage-1 nominal ORC sizing. The thermodynamic cycle, evaporator and
   condenser are solved with hydraulic feedback. STHE geometries are frozen
   after sizing.

3) orc_stage2_annual_offdesign.m
   Stage-2 fixed-geometry off-design loop for one or many timesteps.

4) orc_stage2_test_suite.m
   Comprehensive fixed-geometry stress test suite. It perturbs hot-stream,
   cooling-stream, ORC mass flow and pressure inputs. Some extreme cases are
   expected to be infeasible; caught errors are reported instead of stopping
   the full test.

Naming standard
---------------
All shared variables use subsystem prefixes such as orc_, solar_, pcm_, ro_.
Local ORC structures use names such as orcHotStream, orcColdStream, orcDesign,
orcThermo and orcAnnual.

Important v12 additions
-----------------------
- Added config.orc_run_stage2_test_suite.
- Added config.orc_stage2_test_printSummary.
- Added config.orc_stage2_test_printCaseTable.
- Added config.orc_stage2_test_exportCsv.
- Added orc_stage2_test_suite.m.
- Updated orc_quickstart.m to run the comprehensive test suite after the
  design-point Stage-2 check.

Notes
-----
The current shell-side two-phase pressure-drop model is a preliminary
homogeneous-equilibrium layer. It is useful for code coupling and stress
checking, but it should be documented as preliminary until replaced or
benchmarked against the final selected STHE two-phase pressure-drop method.

Run
---
From MATLAB, run:

    orc_quickstart

To skip the stress-test suite:

    config = orc_default_config(struct());
    config.orc_run_stage2_test_suite = false;
