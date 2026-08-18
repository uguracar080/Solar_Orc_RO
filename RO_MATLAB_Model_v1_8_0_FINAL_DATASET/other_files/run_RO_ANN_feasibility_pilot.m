function [Dataset, Summary, DOE] = run_RO_ANN_feasibility_pilot() % FASTSEARCH sonrasi 120-point feasibility-aware pilot dataset run'ini baslatir.

%% BASLANGIC % Configuration'i yukler ve pilot icin checkpoint batch size degerini ayarlar.

cfg = ro_ann_config(); % Validation, FastPX, FASTSEARCH, domain ve DOE configuration degerlerini yukler.
cfg.optim.method = 'hybrid'; % v1.6.7 ile benchmark'i gecen root-seeded single-fmincon optimizer'i kullanir.
cfg.compute.batch_size = 12; % 6-worker sistemde sik checkpoint ve okunabilir progress icin 12-point batch kullanir.

fprintf('\n============================================================\n'); % Run baslangic ayiricisini yazdirir.
fprintf('RO ANN v1.6.9 - FEASIBILITY-AWARE 120-POINT PILOT\n'); % Pilot run basligini yazdirir.
fprintf('============================================================\n'); % Run basligi alt ayiricisini yazdirir.

%% DOE % Qf-T-Cf Sobol coverage'ini conditional recovery sampling, outer-Qf probes ve known-feasible anchors ile birlestirir.

DOE = ro_generate_doe_feasibility_aware(cfg.doe.n_feasibility_pilot, cfg); % 120-point feasibility-aware DOE tablosunu uretir.
writetable(DOE, 'RO_ANN_DOE_feasibility_pilot.csv'); % Optimizer run oncesi tum pilot inputlarini traceability icin CSV olarak kaydeder.

fprintf('Pilot DOE olusturuldu   : %d point\n', height(DOE)); % Toplam pilot sample sayisini yazdirir.
fprintf('Core Qf probe           : %.1f - %.1f m3/h (final hard domain degil)\n', ...
    cfg.doe.feas_Qf_core_min_m3h, cfg.doe.feas_Qf_core_max_m3h); % Core Qf probe bandini kullaniciya yazar.
fprintf('Full T domain           : %.1f - %.1f C\n', cfg.domain.T_min_C, cfg.domain.T_max_C); % Tam temperature sampling zarfini yazdirir.
fprintf('Full Cf domain          : %.1f - %.1f kg/m3\n', cfg.domain.Cf_min_kg_m3, cfg.domain.Cf_max_kg_m3); % Tam concentration sampling zarfini yazdirir.
fprintf('Global R domain         : %.2f - %.2f; R upper limit her pointte analytically conditioned\n', ...
    cfg.domain.R_min, cfg.domain.R_max); % Recovery sampling mantigini aciklar.
fprintf('Analytic precheck pass  : %d / %d\n', sum(DOE.AnalyticScreenExpectedPass), height(DOE)); % DOE construction sonrasi necessary-condition pass sayisini yazdirir.

TypeCounts = groupsummary(DOE, 'DOE_Type'); % Sampling strata sample sayilarini ozetler.
disp(TypeCounts(:, {'DOE_Type','GroupCount'})); % Pilot kompozisyonunu Command Window'da gosterir.

%% OPTIMIZED TRUTH-MODEL DATASET % Her DOE noktasi icin FastPX + FASTSEARCH N=150 optimum operating point'i hesaplar.

Dataset = ro_generate_training_dataset(DOE, cfg, 'RO_ANN_feasibility_pilot'); % Checkpoint destekli optimized truth-model pilot dataset'ini uretir.

%% OTOMATIK PILOT OZETI % Training'e gecmeden once feasibility, failures, runtime ve output-range raporlarini olusturur.

Summary = ro_summarize_feasibility_pilot(Dataset, 'RO_ANN_feasibility_pilot'); % CSV summary dosyalarini olusturur ve Command Window ozetini yazdirir.

fprintf('\nPilot tamamlandi. ANN training henuz baslatilmadi.\n'); % Bu surumun yalniz dataset-domain karar asamasi oldugunu aciklar.
fprintf('Inceleme icin ana dosya: RO_ANN_feasibility_pilot.csv\n'); % Kullaniciya paylasmasi gereken ana dataset file adini bildirir.

end % Feasibility-aware pilot runner fonksiyonunu sonlandirir.
