ORC_v14
=======

This package is a robustness patch after ORC_v13.

Main fix
--------
- orc_stage2_test_suite.m: localBlankResult() now includes guardedFlag and status fields.
  This prevents MATLAB's 'Subscripted assignment between dissimilar structures' error
  when a normal/guarded case row is stored in the preallocated caseResult array.

Model status
------------
- Thermodynamic core unchanged from v0.13.
- Stage-1 sizing model unchanged from v0.13.
- Stage-2 fixed-geometry rating model unchanged from v0.13.
- Only the comprehensive test-suite result-struct preallocation was corrected.

Expected behavior
-----------------
Run: orc_quickstart

Expected comprehensive test-suite behavior:
- Caught errors should be 0 if all extreme cases are guarded correctly.
- Previously thrown extreme cases should appear as GRD instead of ERR.
- Stage-1 and Stage-2 design-point results should match v0.13 within numerical noise.
