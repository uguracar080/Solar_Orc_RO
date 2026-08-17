function [Dataset, Summary, DOE] = run_RO_ANN_probe_guided_pilot() % v1.7.0 labeled probe logundan ogrenilen proposal gate ile 120-point truth-model pilot dataset uretir.

%% CONFIG % Validated truth-model/FASTSEARCH ayarlarini aynen yukler ve yalnizca pilot checkpoint boyutunu override eder.
cfg = ro_ann_config(); % v1.6.7 FASTSEARCH + FastPX truth configuration'ini yukler.
cfg.compute.batch_size = 12; % 4 ve 6 worker sistemlerde checkpoint ve load balancing icin 12-point batch kullanir.

%% DOE % Package icine dahil edilen v1.7.0 final envelope/probe CSV'lerini sampling proposal prior'i olarak kullanir.
DOE = ro_generate_doe_probe_guided(cfg.guided.n_pilot, cfg, 'RO_feasibility_envelope.csv', 'RO_feasibility_envelope_probes.csv'); % 120-point probe-guided adaptive DOE olusturur.
writetable(DOE, 'RO_ANN_DOE_probe_guided_pilot.csv'); % Truth run oncesi DOE inputlarini reproducibility icin CSV olarak yazar.

%% TRUTH DATASET % Her proposed point'i yine ayni N=150 validated truth-model + FASTSEARCH optimizer ile gercekten dogrular.
Dataset = ro_generate_training_dataset(DOE, cfg, 'RO_ANN_probe_guided_pilot'); % Proposal modeline guvenmeden tum noktalar icin detailed truth-model result uretir.

%% SUMMARY % Proposal score'un gercek precision'ini ve full-Dataset stratejisine gecis kriterlerini hesaplar.
Summary = ro_summarize_probe_guided_pilot(Dataset, DOE, 'RO_ANN_probe_guided_pilot'); % Overall/type/score/failure diagnostics CSV'lerini ve Command Window ozetini uretir.
fprintf('\nPilot tamamlandi. Bu kNN score final ANN/classifier degildir; yalnizca truth-model sampling gate''idir.\n'); % Proposal modelinin bilimsel rolunu aciklar.
fprintf('Inceleme icin ana dosya: RO_ANN_probe_guided_pilot.csv\n'); % Kullaniciya paylasmasi gereken ana truth-dataset dosyasini bildirir.

end % Probe-guided pilot runner fonksiyonunu sonlandirir.
