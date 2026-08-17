function Dataset = run_RO_ANN_pilot_dataset() % 4-D surrogate pipeline icin ilk 600-point Sobol pilot dataset run'ini baslatir.

%% BASLANGIC % Configuration'i yukler ve run basligini yazdirir.

cfg = ro_ann_config(); % Tek train geometry, truth model, domain ve optimizer ayarlarini yukler.
fprintf('\n============================================================\n'); % Command Window ayiricisini yazdirir.
fprintf('RO ANN PILOT DATASET - RECOVERY-CONDITIONED 4-D SURROGATE\n'); % Run basligini yazdirir.
fprintf('============================================================\n'); % Command Window ayiricisini yazdirir.

%% DOE % Scrambled Sobol interior + domain-face + corner sample tablosunu olusturur.

DOE = ro_generate_doe_sobol(cfg.doe.n_pilot, cfg); % Varsayilan 600-point pilot DOE tablosunu uretir.
writetable(DOE, 'RO_ANN_DOE_pilot.csv'); % Pilot DOE inputs degerlerini optimizer run'dan once ayri CSV olarak kaydeder.

fprintf('Pilot DOE olusturuldu: %d point.\n', height(DOE)); % Pilot sample sayisini yazdirir.
fprintf('Qf domain: %.1f - %.1f m3/h\n', cfg.domain.Qf_min_m3h, cfg.domain.Qf_max_m3h); % Feed-flow domain degerini yazdirir.
fprintf('T  domain: %.1f - %.1f C\n', cfg.domain.T_min_C, cfg.domain.T_max_C); % Temperature domain degerini yazdirir.
fprintf('Cf domain: %.1f - %.1f kg/m3\n', cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Feed concentration domain degerini yazdirir.
fprintf('R  domain: %.2f - %.2f\n', cfg.domain.R_min, cfg.domain.R_max); % Recovery-target domain degerini yazdirir.

%% OPTIMIZED TRUTH-MODEL DATASET % Her DOE noktasinda P1-P2 internal power minimization yapar.

Dataset = ro_generate_training_dataset(DOE, cfg, 'RO_ANN_pilot_dataset'); % Checkpoint destekli detailed optimized pilot dataset'i uretir.

%% VALIDITY QUICK CHECK % Sonraki full DOE kararindan once pilot kalite gostergelerini yazdirir.

valid = Dataset.DatasetValid; % Regression ANN icin valid point flag vectorunu alir.
fprintf('\nPilot valid fraction: %.1f %%\n', 100.0 * mean(valid)); % Pilot feasible/optimized fraction degerini yazdirir.
fprintf('Sonraki adim: RO_ANN_pilot_dataset.csv dosyasinda feasibility, optimizer exitflag ve output range kontrollerini yapin.\n'); % Pilot sonrasi kalite-kontrol adimini aciklar.

end % Pilot dataset run fonksiyonunu sonlandirir.
