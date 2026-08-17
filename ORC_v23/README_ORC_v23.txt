ORC_v23
=======

Changes relative to ORC_v22:
- Simplified MATLAB waitbar text for Stage-2 progress.
- Waitbar now shows the started/completed timestep and total elapsed time only.
- ETA, power, candidate count, and status details are no longer shown in waitbar by default.
- Detailed GUI text is still available with:
    config.orc_stage2_progressWaitbarText = 'detailed';
- Command-window progress mode is still available with:
    config.orc_stage2_progressMode = 'command';

Physical ORC, STHE, hydraulic, off-design rating, dispatch, and synthetic annual test logic are unchanged from ORC_v22.
