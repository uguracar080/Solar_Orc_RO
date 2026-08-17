RO MATLAB MODEL v1.8.0 - FINAL GUIDED TRUTH DATASET
==================================================

Bu surum v1.6.7 ile dogrulanan N=150 truth model, FastPX ve FASTSEARCH optimizer'i DEGISTIRMEZ.
Yalnizca final ANN/classifier truth dataset uretim katmanini ekler.

Neden 2400 point?
- 4 inputlu smooth recovery-conditioned policy surrogate icin 120-point guided pilot %90.8 valid verdi.
- 2400 truth point, pilot precision korunursa yaklasik 2150-2200 valid performance sample verir.
- Daha pahali 4000-point run'i pesinen yapmak yerine, final blind-test hatalari yuksekse adaptive enrichment yapilacaktir.

Final stratum hedefleri (2400):
- HighConfidenceCore      : 1600
- ScoreBoundaryProbe     : 400
- LowTemperatureChallenge: 200
- FlowEdgeChallenge      : 200

Proposal prior:
- 622 v1.7.0 envelope probes
- 120 v1.7.1 guided pilot truth rows
Proposal score final classifier DEGILDIR; sadece truth-model sampling gate'idir.

Preassigned split:
- Train      ~70%
- Validation ~15%
- Test       ~15%
Split truth solve ONCESINDE DOE_Type icinde fixed RNG seed ile atanir.
Test rows ML training/model-selection sirasinda kullanilmamalidir.

Once hizli preflight:
  clear functions
  rehash
  DOE = test_RO_final_DOE_preflight;

PASS ise production run:
  [Dataset, Summary, DOE] = run_RO_ANN_final_dataset;

Checkpoint/resume:
- Batch size = 24 (4 ve 6 worker ile bolunebilir)
- RO_ANN_final_truth_dataset_partial.mat olusur.
- Run kesilirse AYNI Current Folder ve AYNI DOE ile komut tekrar verilerek devam edilir.
- Reproducible DOE generator fixed RNG seed ve final Sobol skip kullanir.

Ana ciktilar:
- RO_ANN_DOE_final_truth_dataset.csv
- RO_ANN_final_truth_dataset.csv
- RO_ANN_final_truth_dataset.mat
- RO_ANN_final_truth_dataset_overall_summary.csv
- RO_ANN_final_truth_dataset_type_summary.csv
- RO_ANN_final_truth_dataset_split_summary.csv
- RO_ANN_final_truth_dataset_score_calibration.csv
- RO_ANN_final_truth_dataset_failure_summary.csv
- RO_ANN_final_truth_dataset_valid_ranges.csv

Sonraki asama:
1) Feasibility classifier: prior probes + pilot + final TRAIN labels; class weighting.
2) Performance ANN: yalniz DatasetValid=1 TRAIN rows; outputs W_RO, Cp, P1*, P2*.
3) Validation split: model selection/early stopping.
4) Test split: tamamen blind final metrics.
5) Qp=Qf*R ve SEC=W/Qp fiziksel olarak hesaplanir; gereksiz ANN output yapilmaz.
