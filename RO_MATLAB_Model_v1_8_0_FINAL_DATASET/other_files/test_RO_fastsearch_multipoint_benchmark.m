function Results = test_RO_fastsearch_multipoint_benchmark() % v1.6.7 FASTSEARCH hibrit optimizer'i farkli feasible operating-point bolgelerinde eski N=150 cozumlerle karsilastirir.

%% CONFIGURATION % FastPX + dynamic-pressure-search kullanan mevcut ANN configuration struct'ini yukler.

cfg = ro_ann_config(); % RO ANN/truth-model configuration struct'ini yukler.
cfg.optim.method = 'hybrid'; % Benchmark boyunca root-seeded single-fmincon hibrit optimizer'i kullanir.

%% BENCHMARK CASES % Eski 450-point pilotta valid bulunan ve domain'in farkli bolgelerini temsil eden alti noktayi tanimlar.

CaseName = [ ...
    "DOE80_highQ_lowR"; ... % Yuksek train debisi ve dusuk recovery bolgesini temsil eder.
    "DOE319_lowT_highR"; ... % Dusuk sicaklik ve yuksek recovery / P2-limit yakini bolgeyi temsil eder.
    "DOE172_highT_quality_margin"; ... % Yuksek sicaklikta Cp constraint'inin aktif olmadigi feasible bolgeyi temsil eder.
    "DOE23_highSalinity_P2limit"; ... % Yuksek salinity ve Stage-2 maximum pressure'a yakin bolgeyi temsil eder.
    "DOE15_highT_highR"; ... % Yuksek sicaklik ve yuksek recovery bolgesini temsil eder.
    "DOE447_lowR_midQ" ... % Orta debi ve dusuk recovery bolgesini temsil eder.
    ];

Qf = [61.442891; 54.410224; 59.628889; 51.854958; 52.865870; 54.638007]; % Feed-flow inputlarini m3/h olarak tanimlar.
T = [38.365489; 24.701405; 44.503512; 30.033322; 41.786613; 40.666479]; % RO inlet temperature inputlarini C olarak tanimlar.
Cf = [39.645051; 39.249560; 40.543472; 40.521768; 39.692320; 39.441435]; % Feed concentration inputlarini kg/m3 olarak tanimlar.
Rtarget = [0.435757; 0.533372; 0.508160; 0.493386; 0.545766; 0.439749]; % Recovery target inputlarini tanimlar.

OldP1 = [5.663196; 6.001914; 5.662854; 4.240584; 5.221516; 4.212287]; % Eski valid N=150 Stage-1 optimum basinclarini MPa(g) olarak saklar.
OldP2 = [5.964673; 8.118293; 6.803689; 8.266191; 7.344913; 6.577898]; % Eski valid N=150 Stage-2 optimum basinclarini MPa(g) olarak saklar.
OldW = [81.200737; 116.157328; 100.867673; 136.458169; 104.858450; 102.616232]; % Eski valid train-power cozumlerini kW olarak saklar.
OldCp = [500.000000; 500.000000; 482.079446; 500.000000; 500.000000; 500.000000]; % Eski product-salinity cozumlerini mg/L olarak saklar.

nCase = numel(Qf); % Benchmark case sayisini hesaplar.
Row = repmat(struct(), nCase, 1); % Her case icin benchmark sonucunu saklayacak struct array'i olusturur.

fprintf('\n============================================================\n'); % Benchmark baslangic ayiricisini yazdirir.
fprintf('RO FASTSEARCH v1.6.8 - 6 POINT MULTI-REGION BENCHMARK\n'); % Benchmark basligini yazdirir.
fprintf('============================================================\n'); % Baslik alt ayiricisini yazdirir.

%% CASE LOOP % Her operating point'te once eski pressure pair'ini yeniden degerlendirir, sonra yeni optimizer'i calistirir.

for i = 1:nCase % Tum benchmark noktalarini sirayla gezer.

    fprintf('\n[%02d/%02d] %s\n', i, nCase, CaseName(i)); % Mevcut benchmark case adini yazdirir.
    fprintf('Qf=%.4f m3/h | T=%.3f C | Cf=%.4f kg/m3 | Rtarget=%.6f\n', Qf(i), T(i), Cf(i), Rtarget(i)); % Case inputlarini yazdirir.

    t_old = tic; % Eski pressure pair'inin current FastPX truth-model evaluation runtime olcumunu baslatir.
    ev_old = ro_evaluate_train_operating_point(Qf(i), T(i), Cf(i), OldP1(i), OldP2(i), cfg); % Eski optimum pressure pair'ini mevcut N=150 FastPX truth modelde yeniden hesaplar.
    old_eval_runtime = toc(t_old); % Eski pressure-pair tek evaluation runtime degerini saniye olarak kaydeder.

    old_recovery_error = ev_old.Recovery - Rtarget(i); % Eski pressure pair'inin current truth-model recovery residual degerini hesaplar.
    old_valid_now = ev_old.success && ev_old.physical_feasible && abs(old_recovery_error) <= cfg.optim.recovery_accept_tolerance; % Eski cozumun mevcut truth modelde halen valid olup olmadigini hesaplar.

    out = ro_optimize_train_point_hybrid(i, CaseName(i), Qf(i), T(i), Cf(i), Rtarget(i), cfg); % Yeni FASTSEARCH hibrit optimizer'i mevcut case icin calistirir.

    power_diff_vs_old_eval_pct = 100.0 * (out.W_RO_train_kW - ev_old.W_RO_kW) / ev_old.W_RO_kW; % Yeni power sonucunun current truth-modelde yeniden hesaplanan eski cozumden yuzde farkini hesaplar.
    power_diff_vs_saved_pct = 100.0 * (out.W_RO_train_kW - OldW(i)) / OldW(i); % Yeni power sonucunun eski CSV'de saklanan degerden yuzde farkini hesaplar.
    p1_diff = out.P1_opt_gauge_MPa - OldP1(i); % Yeni ve eski Stage-1 pressure farkini hesaplar.
    p2_diff = out.P2_opt_gauge_MPa - OldP2(i); % Yeni ve eski Stage-2 pressure farkini hesaplar.
    cp_diff = out.Cp_mg_L - ev_old.Cp_mg_L; % Yeni ve current-old product salinity farkini mg/L olarak hesaplar.

    accepted = out.DatasetValid && abs(out.Recovery_error) <= cfg.optim.recovery_accept_tolerance && ... % Yeni cozumun valid ve recovery-matched olmasini zorunlu tutar.
        (~old_valid_now || out.W_RO_train_kW <= 1.01 * ev_old.W_RO_kW); % Eski cozum current truth modelde valid ise yeni power'in %1'den fazla kotulesmemesini ister; daha dusuk power'i kabul eder.

    fprintf('Old valid now   : %d | Rerr=%+.2e | W=%.4f kW | Cp=%.3f | eval %.3f s\n', old_valid_now, old_recovery_error, ev_old.W_RO_kW, ev_old.Cp_mg_L, old_eval_runtime); % Eski pressure pair yeniden-degerlendirme sonucunu yazdirir.
    fprintf('New valid       : %d | ExitFlag=%g | Rerr=%+.2e\n', out.DatasetValid, out.ExitFlag, out.Recovery_error); % Yeni optimizer validity ve recovery sonucunu yazdirir.
    fprintf('P1 old/new      : %.5f / %.5f MPa(g) | diff %+.5f\n', OldP1(i), out.P1_opt_gauge_MPa, p1_diff); % Stage-1 pressure comparison sonucunu yazdirir.
    fprintf('P2 old/new      : %.5f / %.5f MPa(g) | diff %+.5f\n', OldP2(i), out.P2_opt_gauge_MPa, p2_diff); % Stage-2 pressure comparison sonucunu yazdirir.
    fprintf('W  old/new      : %.5f / %.5f kW | diff current-old %+.3f %% | saved-old %+.3f %%\n', ev_old.W_RO_kW, out.W_RO_train_kW, power_diff_vs_old_eval_pct, power_diff_vs_saved_pct); % Power comparison sonucunu yazdirir.
    fprintf('Cp old/new      : %.3f / %.3f mg/L | diff %+.3f\n', ev_old.Cp_mg_L, out.Cp_mg_L, cp_diff); % Product salinity comparison sonucunu yazdirir.
    fprintf('Runtime         : %.2f s | N30=%g | N150seed=%g | fmincon=%g\n', out.Runtime_s, out.RootEvalCountCoarse, out.RootEvalCountFinal, out.FminconFunctionCount); % Yeni optimizer runtime ve evaluation sayilarini yazdirir.
    fprintf('Accepted        : %d\n', accepted); % Case-level acceptance flag degerini yazdirir.

    Row(i).CaseName = CaseName(i); % Case adini output struct'a kaydeder.
    Row(i).Qf_train_m3h = Qf(i); % Feed flow inputunu output struct'a kaydeder.
    Row(i).T_RO_in_C = T(i); % Temperature inputunu output struct'a kaydeder.
    Row(i).Cf_kg_m3 = Cf(i); % Feed concentration inputunu output struct'a kaydeder.
    Row(i).R_target = Rtarget(i); % Recovery target inputunu output struct'a kaydeder.
    Row(i).OldSavedP1_MPa = OldP1(i); % Eski kayitli P1 degerini output struct'a kaydeder.
    Row(i).OldSavedP2_MPa = OldP2(i); % Eski kayitli P2 degerini output struct'a kaydeder.
    Row(i).OldSavedW_kW = OldW(i); % Eski kayitli power degerini output struct'a kaydeder.
    Row(i).OldSavedCp_mgL = OldCp(i); % Eski kayitli Cp degerini output struct'a kaydeder.
    Row(i).OldCurrentValid = old_valid_now; % Eski pressure pair current truth-model validity flag degerini output struct'a kaydeder.
    Row(i).OldCurrentRecovery = ev_old.Recovery; % Eski pressure pair current recovery degerini output struct'a kaydeder.
    Row(i).OldCurrentRecoveryError = old_recovery_error; % Eski pressure pair current recovery residual degerini output struct'a kaydeder.
    Row(i).OldCurrentW_kW = ev_old.W_RO_kW; % Eski pressure pair current power degerini output struct'a kaydeder.
    Row(i).OldCurrentCp_mgL = ev_old.Cp_mg_L; % Eski pressure pair current Cp degerini output struct'a kaydeder.
    Row(i).NewValid = out.DatasetValid; % Yeni optimizer validity flag degerini output struct'a kaydeder.
    Row(i).NewP1_MPa = out.P1_opt_gauge_MPa; % Yeni optimum P1 degerini output struct'a kaydeder.
    Row(i).NewP2_MPa = out.P2_opt_gauge_MPa; % Yeni optimum P2 degerini output struct'a kaydeder.
    Row(i).NewW_kW = out.W_RO_train_kW; % Yeni optimum power degerini output struct'a kaydeder.
    Row(i).NewCp_mgL = out.Cp_mg_L; % Yeni optimum Cp degerini output struct'a kaydeder.
    Row(i).NewRecovery = out.Recovery_actual; % Yeni optimum recovery degerini output struct'a kaydeder.
    Row(i).NewRecoveryError = out.Recovery_error; % Yeni optimum recovery residual degerini output struct'a kaydeder.
    Row(i).PowerDiffVsOldCurrent_pct = power_diff_vs_old_eval_pct; % Current-old power farkini output struct'a kaydeder.
    Row(i).PowerDiffVsOldSaved_pct = power_diff_vs_saved_pct; % Saved-old power farkini output struct'a kaydeder.
    Row(i).P1Diff_MPa = p1_diff; % Stage-1 pressure farkini output struct'a kaydeder.
    Row(i).P2Diff_MPa = p2_diff; % Stage-2 pressure farkini output struct'a kaydeder.
    Row(i).CpDiff_mgL = cp_diff; % Cp farkini output struct'a kaydeder.
    Row(i).Runtime_s = out.Runtime_s; % Yeni optimizer runtime degerini output struct'a kaydeder.
    Row(i).N30Evals = out.RootEvalCountCoarse; % N=30 evaluation sayisini output struct'a kaydeder.
    Row(i).N150SeedEvals = out.RootEvalCountFinal; % N=150 seed evaluation sayisini output struct'a kaydeder.
    Row(i).FminconEvals = out.FminconFunctionCount; % fmincon evaluation sayisini output struct'a kaydeder.
    Row(i).ExitFlag = out.ExitFlag; % Yeni optimizer exit flag degerini output struct'a kaydeder.
    Row(i).Accepted = accepted; % Case-level acceptance flag degerini output struct'a kaydeder.
    Row(i).FailureReason = out.FailureReason; % Yeni optimizer failure reason degerini output struct'a kaydeder.

end % Benchmark case loop'unu sonlandirir.

%% SUMMARY % Tum benchmark case'lerinin validity, accuracy ve runtime ozetini hesaplar.

Results = struct2table(Row); % Case struct array'ini analiz ve CSV export icin table'a cevirir.

nAccepted = sum(Results.Accepted); % Kabul kriterini gecen case sayisini hesaplar.
nNewValid = sum(Results.NewValid); % Yeni optimizer'in valid buldugu case sayisini hesaplar.
meanRuntime = mean(Results.Runtime_s, 'omitnan'); % Ortalama per-point runtime degerini hesaplar.
maxRuntime = max(Results.Runtime_s, [], 'omitnan'); % Maximum per-point runtime degerini hesaplar.
meanAbsPowerDiff = mean(abs(Results.PowerDiffVsOldCurrent_pct), 'omitnan'); % Ortalama absolute power farkini hesaplar.
maxPositivePowerDiff = max(Results.PowerDiffVsOldCurrent_pct, [], 'omitnan'); % Yeni optimizer'in eski valid current cozumden en buyuk power kotulesmesini hesaplar.

fprintf('\n============================================================\n'); % Summary baslangic ayiricisini yazdirir.
fprintf('SUMMARY\n'); % Summary basligini yazdirir.
fprintf('New valid             : %d / %d\n', nNewValid, nCase); % Yeni optimizer validity sayisini yazdirir.
fprintf('Accepted              : %d / %d\n', nAccepted, nCase); % Kabul edilen case sayisini yazdirir.
fprintf('Mean runtime          : %.2f s/point\n', meanRuntime); % Ortalama runtime degerini yazdirir.
fprintf('Max runtime           : %.2f s\n', maxRuntime); % Maximum runtime degerini yazdirir.
fprintf('Mean |power diff|     : %.3f %%\n', meanAbsPowerDiff); % Ortalama absolute power farkini yazdirir.
fprintf('Max power degradation : %+.3f %%\n', maxPositivePowerDiff); % En buyuk power kotulesmesini yazdirir.
fprintf('Overall benchmark pass: %d\n', nAccepted == nCase); % Tum caseler kabul edildiyse overall pass flag degerini yazdirir.
fprintf('============================================================\n'); % Summary sonu ayiricisini yazdirir.

%% EXPORT % Benchmark sonuclarini CSV ve MAT dosyalarina kaydeder.

writetable(Results, 'RO_fastsearch_multipoint_benchmark.csv'); % Kullanici incelemesi icin benchmark table'ini CSV olarak kaydeder.
save('RO_fastsearch_multipoint_benchmark.mat', 'Results', 'cfg'); % MATLAB-side traceability icin benchmark table ve configuration struct'ini MAT dosyasina kaydeder.

end % Multi-region FASTSEARCH benchmark fonksiyonunu sonlandirir.
