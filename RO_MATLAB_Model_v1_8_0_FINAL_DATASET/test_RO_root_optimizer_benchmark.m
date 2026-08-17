function Results = test_RO_root_optimizer_benchmark() % Yeni root optimizer'i eski basarili fmincon noktalarina ve secili failure noktalarina karsi benchmark eder.

%% CONFIGURATION % Validation ile sabitlenen truth model ve v1.6.2 root optimizer ayarlarini yukler.

cfg = ro_ann_config(); % Tek train ANN configuration struct'ini yukler.
cfg.optim.method = 'root1d'; % Benchmark boyunca yeni recovery-conditioned root optimizer'i zorunlu olarak secer.

%% TEST CASES % Benchmark, eski pilotun farkli recovery/temperature bolgelerindeki valid noktalarini ve representative failure noktalarini kapsar.

CaseName = [ ...
    "Du_reference_train"; ... % Cf=35 literature reference condition'da daha once basarili smoke-test noktasini tekrar kontrol eder.
    "DOE80_old_valid"; ... % Dusuk recovery / yuksek Qf bolgesindeki eski valid point'i temsil eder.
    "DOE320_old_valid"; ... % Orta recovery ve Cp constraint'inden marjli eski valid point'i temsil eder.
    "DOE12_old_valid"; ... % Orta-yuksek Qf ve sicak feed'deki eski valid point'i temsil eder.
    "DOE95_old_valid"; ... % Product-salinity boundary'deki eski valid point'i temsil eder.
    "DOE319_old_valid"; ... % Dusuk temperature ve P2 upper-bound'a yakin eski valid point'i temsil eder.
    "DOE15_old_valid"; ... % Yuksek recovery ve sicak feed'deki eski valid point'i temsil eder.
    "DOE1_old_Cp_fail"; ... % Recovery hedefini saglayip yalnizca product salinity nedeniyle infeasible eski point'i temsil eder.
    "DOE7_old_Cp_fail"; ... % Yuksek salinity'de product-quality failure point'ini temsil eder.
    "DOE2_old_dP_fail"; ... % Yuksek Qf Stage-1 pressure-drop failure bolgesini temsil eder.
    "DOE3_old_mismatch_Cp"; ... % Legacy fmincon recovery mismatch + product salinity failure point'ini root yontemiyle yeniden sinar.
    "DOE6_analytic_fail"]; % Average-flux/recovery envelope nedeniyle detailed modele gerek kalmadan elenmesi gereken point'i temsil eder.

Qf = [51.6500000000000; 61.4428911538836; 60.9202910105124; 59.2166004257296; 53.8539876157814; 54.4102237819184; 52.8658695387431; 36.1902631800474; 50.5584848212934; 69.7292218155901; 47.9507178128446; 72.3761991260960]; % Test-case feed flow vectorunu m3/h cinsinden tanimlar.
T = [20.0000000000000; 38.3654886146251; 36.7826370213738; 38.8712348423741; 38.4887346576125; 24.7014051254266; 41.7866131182776; 17.2022852195276; 26.7684032431607; 44.2836434064313; 33.7949372687672; 22.2570615838103]; % Test-case RO inlet temperature vectorunu C cinsinden tanimlar.
Cf = [35.0000000000000; 39.6450509127144; 40.1198603184203; 39.0482672502877; 40.2324344230066; 39.2495601567501; 39.6923200496519; 39.8483333534323; 41.2558136303257; 40.8292299390711; 38.7527814169254; 39.1618116637196]; % Test-case feed concentration vectorunu kg/m3 cinsinden tanimlar.
R = [0.580800000000000; 0.435757082196961; 0.465827906186837; 0.494667942281759; 0.504480104882687; 0.533372291269848; 0.545765588761524; 0.473484967109047; 0.515945110136292; 0.412044824127338; 0.399340309335097; 0.553020101907262]; % Test-case recovery target vectorunu tanimlar.

OldValid = logical([1; 1; 1; 1; 1; 1; 1; 0; 0; 0; 0; 0]); % Legacy v1.6.1 sonucunda valid olan reference case'leri isaretler.
OldP1 = [7.15855; 5.66319605627319; 6.03797082670819; 5.90770193615481; 4.92236547902833; 6.00191366165927; 5.22151584066571; NaN; NaN; NaN; NaN; NaN]; % Eski basarili optimizer Stage-1 pressure referanslarini kaydeder.
OldP2 = [7.68423; 5.96467282408921; 6.31777636933937; 6.44695886384221; 7.24310692781194; 8.11829265961530; 7.34491287666492; NaN; NaN; NaN; NaN; NaN]; % Eski basarili optimizer Stage-2 pressure referanslarini kaydeder.
OldW = [101.05749; 81.2007370880945; 87.2544279209762; 90.6669421979966; 107.172723999301; 116.157328110198; 104.858450302474; NaN; NaN; NaN; NaN; NaN]; % Eski basarili optimizer power referanslarini kW cinsinden kaydeder.
OldCp = [500.000; 500.000000000000; 498.586779371517; 484.925632454315; 500.000000000000; 500.000000000000; 500.000000000000; NaN; NaN; NaN; NaN; NaN]; % Eski basarili optimizer product salinity referanslarini mg/L cinsinden kaydeder.

n = numel(CaseName); % Toplam benchmark case sayisini hesaplar.
rows = repmat(ro_dataset_row_template(), n, 1); % Her case icin sabit field'li result struct array'ini preallocate eder.

%% ROOT OPTIMIZER BENCHMARK % Her case'i sirayla cozerek hem sonucu hem point runtime'ini gorunur sekilde raporlar.

fprintf('\n============================================================\n'); % Benchmark baslangic ayiricisini yazdirir.
fprintf('RO ROOT OPTIMIZER v1.6.2 - 12 POINT BENCHMARK\n'); % Benchmark basligini yazdirir.
fprintf('============================================================\n'); % Benchmark baslik ayiricisini yazdirir.
total_timer = tic; % Tum 12-case benchmark wall-clock timer'ini baslatir.

for i = 1:n % Tum test case'leri sirayla cozer.
    fprintf('\n[%02d/%02d] %s\n', i, n, CaseName(i)); % Mevcut case progress bilgisini Command Window'a yazdirir.
    fprintf('Qf=%.4f m3/h | T=%.3f C | Cf=%.4f kg/m3 | Rtarget=%.6f\n', Qf(i), T(i), Cf(i), R(i)); % Mevcut case inputlarini yazdirir.
    rows(i) = ro_optimize_train_point_root(i, "benchmark", Qf(i), T(i), Cf(i), R(i), cfg); % Yeni root optimizer ile mevcut test case'i cozer.
    fprintf('Valid=%d | P1=%.5f | P2=%.5f | W=%.4f kW | Cp=%.3f mg/L | Rerr=%+.3e | %.1f s\n', ...
        rows(i).DatasetValid, rows(i).P1_opt_gauge_MPa, rows(i).P2_opt_gauge_MPa, rows(i).W_RO_train_kW, rows(i).Cp_mg_L, rows(i).Recovery_error, rows(i).Runtime_s); % Ana output ve runtime ozetini yazdirir.
    if strlength(rows(i).FailureReason) > 0 % Case valid degilse veya analitik screened ise kontrol eder.
        fprintf('Failure: %s\n', rows(i).FailureReason); % Failure reason degerini gorunur olarak yazdirir.
    end % Failure reporting kosulunu sonlandirir.
end % Benchmark case dongusunu sonlandirir.

TotalWallTime_s = toc(total_timer); % Tum benchmark toplam wall-clock runtime degerini alir.

%% COMPARISON TABLE % Eski valid optimizer referanslariyla pressure ve power farklarini hesaplar.

New = struct2table(rows); % Root optimizer struct array'ini table object'ine cevirir.
P1_diff_MPa = New.P1_opt_gauge_MPa - OldP1; % Yeni-eski Stage-1 pressure farkini hesaplar.
P2_diff_MPa = New.P2_opt_gauge_MPa - OldP2; % Yeni-eski Stage-2 pressure farkini hesaplar.
W_diff_pct = 100.0 * (New.W_RO_train_kW - OldW) ./ OldW; % Yeni-eski power relative farkini yuzde olarak hesaplar.
Cp_diff_mgL = New.Cp_mg_L - OldCp; % Yeni-eski product salinity farkini mg/L cinsinden hesaplar.

Results = table(CaseName, Qf, T, Cf, R, OldValid, OldP1, OldP2, OldW, OldCp, ...
    New.DatasetValid, New.AnalyticScreenPassed, New.P1_opt_gauge_MPa, New.P2_opt_gauge_MPa, New.W_RO_train_kW, New.Cp_mg_L, New.Recovery_error, ...
    P1_diff_MPa, P2_diff_MPa, W_diff_pct, Cp_diff_mgL, New.RootEvalCountCoarse, New.RootEvalCountFinal, New.Runtime_s, New.ExitFlag, New.FailureReason); % Benchmark comparison tablosunu olusturur.
Results.Properties.VariableNames = {'CaseName','Qf_m3h','T_C','Cf_kg_m3','R_target','OldValid','OldP1_MPa','OldP2_MPa','OldW_kW','OldCp_mgL', ...
    'NewValid','AnalyticScreenPassed','NewP1_MPa','NewP2_MPa','NewW_kW','NewCp_mgL','RecoveryError','P1Diff_MPa','P2Diff_MPa','WDiff_pct','CpDiff_mgL', ...
    'N30_Evals','N150_Evals','Runtime_s','ExitFlag','FailureReason'}; % Okunabilir benchmark kolon adlarini tanimlar.

%% SUMMARY METRICS % Yeni optimizer'in eski valid noktalarini yeniden bulma basarisini ve hizini ozetler.

ref_mask = OldValid; % Eski valid referans case'leri comparison mask'i olarak alir.
ref_recovered = sum(Results.NewValid(ref_mask)); % Eski valid case'lerden kacinin yeni optimizer tarafindan yeniden valid bulundugunu sayar.
finite_wdiff = abs(Results.WDiff_pct(ref_mask & isfinite(Results.WDiff_pct))); % Eski valid case'lerde finite absolute power farklarini secer.
if isempty(finite_wdiff) % Hic finite power comparison sonucu yoksa kontrol eder.
    mean_abs_Wdiff = NaN; % Mean power difference metric'ini NaN yapar.
    max_abs_Wdiff = NaN; % Maximum power difference metric'ini NaN yapar.
else % En az bir finite comparison varsa bu dali kullanir.
    mean_abs_Wdiff = mean(finite_wdiff); % Mean absolute power difference yuzdesini hesaplar.
    max_abs_Wdiff = max(finite_wdiff); % Maximum absolute power difference yuzdesini hesaplar.
end % Power-difference summary kosulunu sonlandirir.

fprintf('\n============================================================\n'); % Summary ayiricisini yazdirir.
fprintf('BENCHMARK OZETI\n'); % Summary basligini yazdirir.
fprintf('Eski valid yeniden bulundu : %d / %d\n', ref_recovered, sum(ref_mask)); % Valid-reference recovery sayisini raporlar.
fprintf('Mean |W farki|            : %.3f %%\n', mean_abs_Wdiff); % Mean absolute power farkini raporlar.
fprintf('Max  |W farki|            : %.3f %%\n', max_abs_Wdiff); % Maximum absolute power farkini raporlar.
fprintf('Toplam wall time          : %.1f s (%.2f min)\n', TotalWallTime_s, TotalWallTime_s / 60.0); % Tum benchmark runtime degerini raporlar.
fprintf('Mean point runtime        : %.1f s\n', mean(Results.Runtime_s)); % Ortalama root optimizer point runtime degerini raporlar.
fprintf('============================================================\n'); % Summary alt ayiricisini yazdirir.

disp(Results(:, {'CaseName','OldValid','NewValid','NewP1_MPa','NewP2_MPa','NewW_kW','NewCp_mgL','RecoveryError','WDiff_pct','N30_Evals','N150_Evals','Runtime_s','FailureReason'})); % En kritik comparison kolonlarini Command Window'da tablo olarak gosterir.

%% DOSYA CIKTISI % Kullanici sonucu geri gonderebilsin diye benchmark table'i CSV olarak kaydeder.

writetable(Results, 'RO_root_optimizer_benchmark.csv'); % Tum comparison sonuclarini CSV dosyasina yazar.
save('RO_root_optimizer_benchmark.mat', 'Results', 'cfg', 'TotalWallTime_s'); % Full precision benchmark sonucunu MAT file olarak kaydeder.

end % Root optimizer benchmark test fonksiyonunu sonlandirir.
