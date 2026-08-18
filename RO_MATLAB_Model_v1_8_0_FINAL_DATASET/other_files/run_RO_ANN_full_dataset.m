function Dataset = run_RO_ANN_full_dataset() % Pilot kalite kontrolleri kabul edildikten sonra 4000-point full Sobol dataset run'ini baslatir.

%% CONFIGURATION VE DOE % Pilot ile ayni physics/optimization ayarlarinda daha yogun 4-D sample seti olusturur.

cfg = ro_ann_config(); % Final ANN dataset configuration degerlerini yukler.
DOE = ro_generate_doe_sobol(cfg.doe.n_full, cfg); % Varsayilan 4000-point full Sobol + boundary/corner DOE tablosunu uretir.
writetable(DOE, 'RO_ANN_DOE_full.csv'); % Full DOE input tablosunu traceability icin ayri CSV file olarak kaydeder.

%% OPTIMIZED TRUTH-MODEL DATASET % Tum full DOE noktalarini batched checkpoint sistemi ile cozer.

Dataset = ro_generate_training_dataset(DOE, cfg, 'RO_ANN_full_dataset'); % Final optimized detailed training dataset'i uretir.

end % Full dataset run fonksiyonunu sonlandirir.
