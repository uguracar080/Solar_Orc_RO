ORC_v22
=======

Changes relative to ORC_v21:

1) Stage-2 progress display now supports a MATLAB GUI waitbar window.
   Default:
       config.orc_stage2_progressEnabled = true;
       config.orc_stage2_progressMode = 'waitbar';   % 'waitbar','command','none'

   The command-window progress line is no longer the default. To disable:
       config.orc_stage2_progressMode = 'none';

   To use the old text progress line:
       config.orc_stage2_progressMode = 'command';

2) Annual warm-start promotion is now guarded by external-stream similarity.
   The previous feasible operating point is promoted early only when the next
   timestep has similar HTF/CW inlet temperatures and mass flow rates.
   This prevents a stale low-load warm-start from locking the annual dispatch
   into low power during improving solar/source conditions.

   New defaults:
       config.orc_stage2_dispatch_warmStartSimilarityOnly = true;
       config.orc_stage2_dispatch_warmStart_Ttol_K = 3.0;
       config.orc_stage2_dispatch_warmStart_mdotRelTol = 0.10;

3) Physical ORC/STHE models are unchanged. Only progress display and annual
   dispatch warm-start ordering were modified.
