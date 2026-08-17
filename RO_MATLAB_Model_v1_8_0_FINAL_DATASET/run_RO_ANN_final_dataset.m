function [Dataset, Summary, DOE] = run_RO_ANN_final_dataset() % v1.8.0 probe+pilot-guided 2400-point final N=150 truth datasetini checkpoint ve fixed train/validation/test splitleriyle uretir.

%% CONFIG % Validated FastPX + FASTSEARCH truth-model ayarlarini yukler ve production checkpoint batch boyutunu ayarlar.
cfg = ro_ann_config(); % Tum validated RO physics/optimizer/final DOE settings'ini yukler.
cfg.compute.batch_size = cfg.final.batch_size; % 4 ve 6 worker sistemlerde dengeli production checkpoint batch boyutunu uygular.

%% FINAL DOE % 622 envelope probe + 120 successful pilot labels'i yalnizca sampling proposal prior'i olarak kullanir.
DOE = ro_generate_doe_final_guided(cfg.final.n_truth, cfg, 'RO_feasibility_envelope.csv', 'RO_feasibility_envelope_probes.csv', 'RO_ANN_probe_guided_pilot.csv'); % 2400-point reproducible final DOE'yi olusturur.
writetable(DOE, 'RO_ANN_DOE_final_truth_dataset.csv'); % Truth run oncesi final inputs, proposal metadata ve fixed split labels'i CSV'ye yazar.

%% TRUTH DATASET % Her DOE point'i yine N=150 validated truth model + FastPX + FASTSEARCH ile gercekten dogrular.
Dataset = ro_generate_training_dataset(DOE, cfg, 'RO_ANN_final_truth_dataset'); % Checkpoint/resume destekli final detailed truth datasetini uretir.

%% SUMMARY % Final production dataset validity, split ve classifier-sampling diagnostics tablolarini olusturur.
Summary = ro_summarize_final_dataset(Dataset, DOE, 'RO_ANN_final_truth_dataset'); % R2023b-compatible final summary CSV ve Command Window raporlarini uretir.
fprintf('\nFinal truth dataset tamamlandi. ANN/classifier training bu runner icinde baslatilmaz.\n'); % Physics dataset uretimi ile ML egitimini bilimsel olarak ayri tutar.
fprintf('Ana truth dataset : RO_ANN_final_truth_dataset.csv\n'); % Ana final truth CSV adini bildirir.
fprintf('DOE + split file  : RO_ANN_DOE_final_truth_dataset.csv\n'); % Fixed train-validation-test metadata dosyasini bildirir.

end % Final truth dataset runner fonksiyonunu sonlandirir.
