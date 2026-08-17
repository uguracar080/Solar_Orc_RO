function run_all_RO_ANN_figures()
%RUN_ALL_RO_ANN_FIGURES Generate the suggested manuscript figures.
% Put this file and the four figure functions in the same folder. The input
% CSV files may be in the MATLAB Current Folder, or pass full paths directly
% to the individual figure functions if they are stored elsewhere.

fig_RO_ANN_dataset_feasibility('RO_ANN_final_truth_dataset_corrected.csv');
fig_RO_ANN_blind_parity('RO_ANN_blind_test_predictions_v1_9_1.csv');
fig_RO_ANN_classifier_performance('RO_ANN_blind_test_predictions_v1_9_1.csv',0.80);
fig_RO_truth_branch_repair('RO_ANN_truth_branch_repair_scan.csv', ...
                           'RO_ANN_truth_branch_repair_summary.csv');
end
