function out = test_RO_hybrid_reference_train() % v1.6.7 hizlandirilmis hibrit optimizer'i bilinen Du reference-train noktasinda hiz ve optimum dogrulugu acisindan test eder.

%% CONFIGURATION % Yeni root-seeded hybrid optimizer ayarlarini yukler.

cfg = ro_ann_config(); % ANN/truth-model configuration struct'ini yukler.
cfg.optim.method = 'hybrid'; % Bu smoke testte hibrit optimizer'i zorunlu olarak secer.

%% REFERENCE CONDITION % Daha once N=150 legacy fmincon ile basarili bulunan reference operating point girdilerini tanimlar.

Qf = 51.6500; % Tek train feed flow degerini m3/h olarak tanimlar.
T = 20.0; % Reference feed temperature degerini C olarak tanimlar.
Cf = 35.0; % Du benchmark feed concentration degerini kg/m3 olarak tanimlar.
Rtarget = 0.5808; % Reference recovery target degerini tanimlar.
OldP1 = 7.15855; % Daha once basarili N=150 optimizer ile bulunan Stage-1 pressure referansini MPa(g) olarak tanimlar.
OldP2 = 7.68423; % Daha once basarili N=150 optimizer ile bulunan Stage-2 pressure referansini MPa(g) olarak tanimlar.
OldW = 101.05749; % Daha once basarili N=150 optimizer ile bulunan train power referansini kW olarak tanimlar.
OldCp = 500.000; % Daha once basarili N=150 optimizer ile bulunan product salinity referansini mg/L olarak tanimlar.

%% RUN % Tek reference noktayi hibrit optimizer ile cozer.

fprintf('\n============================================================\n'); % Test baslangic ayiricisini yazdirir.
fprintf('RO HYBRID OPTIMIZER v1.6.7 - REFERENCE TRAIN TEST\n'); % Test basligini yazdirir.
fprintf('============================================================\n'); % Baslik alt ayiricisini yazdirir.
fprintf('Qf=%.4f m3/h | T=%.3f C | Cf=%.4f kg/m3 | Rtarget=%.6f\n', Qf, T, Cf, Rtarget); % Test inputlarini Command Window'a yazdirir.
mem_search = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Dynamic P1 search bound diagnostic icin aged membrane struct'ini yukler.
pi_feed = ro_osmotic_pressure_du2014(T, Cf, mem_search); % Reference feed osmotic pressure degerini hesaplar.
P1_lb_dynamic = max(cfg.hybrid.P1_lb_MPa, pi_feed + cfg.hybrid.P1_osmotic_margin_MPa); % Dynamic Stage-1 search lower bound degerini hesaplar.
fprintf('Feed osmotic P  : %.4f MPa | dynamic P1 lb %.4f MPa(g)\n', pi_feed, P1_lb_dynamic); % Yeni dynamic pressure bound diagnostic degerlerini yazdirir.

out = ro_optimize_train_point_hybrid(1, "reference", Qf, T, Cf, Rtarget, cfg); % Yeni hibrit optimizer'i reference noktada calistirir.

%% COMPARISON % Yeni sonucu daha once kabul edilen N=150 optimum ile karsilastirir.

Wdiff_pct = 100.0 * (out.W_RO_train_kW - OldW) / OldW; % Yeni-eski power relative farkini yuzde olarak hesaplar.
P1diff = out.P1_opt_gauge_MPa - OldP1; % Stage-1 pressure farkini hesaplar.
P2diff = out.P2_opt_gauge_MPa - OldP2; % Stage-2 pressure farkini hesaplar.
Cpdiff = out.Cp_mg_L - OldCp; % Product salinity farkini mg/L cinsinden hesaplar.

fprintf('\nValid           : %d\n', out.DatasetValid); % Dataset-valid flag degerini yazdirir.
fprintf('P1*             : %.5f MPa(g) | old %.5f | diff %+.5f\n', out.P1_opt_gauge_MPa, OldP1, P1diff); % Stage-1 pressure comparison sonucunu yazdirir.
fprintf('P2*             : %.5f MPa(g) | old %.5f | diff %+.5f\n', out.P2_opt_gauge_MPa, OldP2, P2diff); % Stage-2 pressure comparison sonucunu yazdirir.
fprintf('Power*          : %.5f kW | old %.5f | diff %+.3f %%\n', out.W_RO_train_kW, OldW, Wdiff_pct); % Power comparison sonucunu yazdirir.
fprintf('Cp*             : %.3f mg/L | old %.3f | diff %+.3f\n', out.Cp_mg_L, OldCp, Cpdiff); % Product salinity comparison sonucunu yazdirir.
fprintf('Recovery        : %.8f | target %.8f | err %+.3e\n', out.Recovery_actual, Rtarget, out.Recovery_error); % Recovery equality sonucunu yazdirir.
fprintf('ExitFlag        : %g\n', out.ExitFlag); % Final optimizer exit flag degerini yazdirir.
fprintf('N30 evals       : %g\n', out.RootEvalCountCoarse); % N=30 seed-search evaluation sayisini yazdirir.
fprintf('N150 seed evals : %g\n', out.RootEvalCountFinal); % N=150 root-seed evaluation sayisini yazdirir.
fprintf('Seed rank used  : %g\n', out.HybridSeedRankUsed); % N=30 aday siralamasinda hangi seed'in truth-grid'e aktarildigini yazdirir.
fprintf('N30 seed P1/P2  : %.5f / %.5f MPa(g)\n', out.HybridSeedP1_N30_MPa, out.HybridSeedP2_N30_MPa); % Kullanilan N=30 seed pressure degerlerini yazdirir.
fprintf('N150 trials     : %g\n', out.HybridN150SeedTrials); % N=150 transfer icin planlanan seed trial sayisini yazdirir.
fprintf('fmincon evals   : %g\n', out.FminconFunctionCount); % Tek local fmincon function-count degerini yazdirir.
fprintf('Runtime         : %.1f s (%.2f min)\n', out.Runtime_s, out.Runtime_s / 60.0); % Tek point runtime sonucunu yazdirir.
if strlength(out.FailureReason) > 0 % Failure reason mevcutsa kontrol eder.
    fprintf('Failure         : %s\n', out.FailureReason); % Failure reason degerini yazdirir.
end % Failure reporting kosulunu sonlandirir.
if strlength(out.ErrorMessage) > 0 % Ek seed-transfer diagnostic mesaji mevcutsa kontrol eder.
    fprintf('Diagnostic      : %s\n', out.ErrorMessage); % Ek diagnostic mesaji Command Window'a yazdirir.
end % Diagnostic reporting kosulunu sonlandirir.
fprintf('============================================================\n'); % Test sonu ayiricisini yazdirir.

end % Hibrit reference-train smoke test fonksiyonunu sonlandirir.
