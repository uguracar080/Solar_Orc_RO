RO ANN v1.9.0 - BASELINE TRAINING
=================================

Purpose
-------
Train the first publication-grade ANN baseline from RO_ANN_final_truth_dataset.mat
without changing the validated RO truth model or the fixed 70/15/15 DOE split.

Inputs
------
Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target

Models
------
1) Feasibility classifier -> DatasetValid
   - compares FinalOnly and PriorEnriched training
   - architecture/seed/threshold selected on FINAL validation set only
   - threshold is conservative: target invalid specificity >= 0.98
   - blind test remains untouched until final evaluation

2) Separate performance regression ANNs for valid points
   - W_RO_train_kW
   - P1_opt_gauge_MPa
   - P2_opt_gauge_MPa
   Separate networks are used because outputs have different scales/nonlinearities.

3) Hybrid Cp model
   - classifier predicts whether Cp=500 mg/L active quality boundary
   - off-boundary ANN predicts margin = 500-Cp
   - switching threshold selected by validation Cp RMSE
   This avoids forcing a single smooth regressor onto a zero-inflated/active-constraint target.

4) Physics-derived outputs
   Qp = Qf * R
   SEC = W_RO / Qp
   These are not trained ANN outputs.

Model selection
---------------
Architectures: [12], [20], [16 8], [24 12]
Seeds: 3 fixed seeds per architecture
Regression: trainlm, early stopping on fixed validation set
Classification: trainscg + crossentropy, balanced training by minority oversampling
Input/target standardization parameters are fitted on training data only.

Required files in Current Folder
--------------------------------
RO_ANN_final_truth_dataset.mat
RO_feasibility_envelope.csv             (optional but recommended classifier prior)
RO_feasibility_envelope_probes.csv      (optional but recommended classifier prior)
RO_ANN_probe_guided_pilot.csv           (optional but recommended classifier prior)

Required MATLAB capability
--------------------------
Deep Learning Toolbox neural-network functions: fitnet, patternnet, train.
Designed for MATLAB R2023b syntax; no groupsummary is used.

Run order
---------
1) clear functions; rehash
2) Info = test_RO_ANN_training_preflight;
3) Results = run_RO_ANN_train_v1_9_0;

Outputs
-------
RO_ANN_models_v1_9_0.mat
RO_ANN_classifier_architecture_search.csv
RO_ANN_regression_architecture_search.csv
RO_ANN_Cp_active_architecture_search.csv
RO_ANN_Cp_margin_architecture_search.csv
RO_ANN_regression_test_metrics.csv
RO_ANN_classifier_test_metrics.csv
RO_ANN_blind_test_predictions.csv

Annual-model inference
----------------------
Out = ro_predict_ann_surrogate_v1_9_0('RO_ANN_models_v1_9_0.mat', Qf, T, Cf, R);

Important
---------
Do not tune architecture or thresholds using the blind Test metrics after this run.
If accuracy is insufficient, enrichment/model changes must be decided using training/validation
and then evaluated on a newly reserved independent test set or by a documented nested procedure.
