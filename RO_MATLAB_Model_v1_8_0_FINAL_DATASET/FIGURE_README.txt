RO ANN manuscript figure scripts
================================

Main-text recommendations
-------------------------
1) fig_RO_ANN_dataset_feasibility.m
   Input: RO_ANN_final_truth_dataset_corrected.csv
   Output: Fig_ANN1_final_DOE_feasibility.pdf/.png
   Suggested placement: after the guided DOE / dataset-generation subsection.

2) fig_RO_ANN_blind_parity.m
   Input: RO_ANN_blind_test_predictions_v1_9_1.csv
   Output: Fig_ANN2_blind_test_parity.pdf/.png
   Suggested placement: surrogate validation subsection.

3) fig_RO_ANN_classifier_performance.m
   Input: RO_ANN_blind_test_predictions_v1_9_1.csv
   Output: Fig_ANN3_classifier_performance.pdf/.png
   Suggested placement: feasibility-classifier subsection or surrogate validation subsection.

Optional supplementary figure
-----------------------------
4) fig_RO_truth_branch_repair.m
   Inputs: RO_ANN_truth_branch_repair_scan.csv and RO_ANN_truth_branch_repair_summary.csv
   Output: Fig_S_ANN_truth_branch_repair.pdf/.png
   Purpose: documents the three targeted local-branch repairs in the high-fidelity optimizer.

All scripts are MATLAB R2023b-compatible and save vector PDF plus 600-dpi PNG to a "figures" subfolder.
