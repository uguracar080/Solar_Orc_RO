function DOE = test_RO_final_DOE_preflight() % Pahali truth solve baslamadan v1.8.0 2400-point final guided DOE'nin boyut, coverage ve split dagilimini kontrol eder.

%% CONFIG VE DOE % Final config'i yukler ve yalnizca proposal DOE'yi olusturur.
cfg = ro_ann_config(); % Validated truth-model ve v1.8 final DOE settings'ini yukler.
DOE = ro_generate_doe_final_guided(cfg.final.n_truth, cfg, 'RO_feasibility_envelope.csv', 'RO_feasibility_envelope_probes.csv', 'RO_ANN_probe_guided_pilot.csv'); % Truth solve yapmadan final 4-D DOE'yi uretir.

%% ANALYTIC PRECHECK % Final proposal noktalarinin necessary analytic screen'i gecmesini bagimsiz kontrol eder.
AnalyticPass = false(height(DOE),1); % Her DOE row icin analytic pass flag vectorunu preallocate eder.
for i = 1:height(DOE) % Tum final DOE rows'u gezer.
    sc = ro_analytic_screen_train_point(DOE.Qf_train_m3h(i), DOE.T_RO_in_C(i), DOE.Cf_kg_m3(i), DOE.R_target(i), cfg); % Candidate'in analytic necessary-condition screen'ini hesaplar.
    AnalyticPass(i) = sc.pass; % Analytic screen sonucunu kaydeder.
end % Analytic precheck loop'unu sonlandirir.

%% PREFLIGHT RAPORU % Final multi-hour run'dan once sampling coverage'in beklenen aralikta oldugunu gosterir.
fprintf('\nFINAL GUIDED DOE PREFLIGHT: %s\n', ternary(all(AnalyticPass) && height(DOE)==cfg.final.n_truth, 'PASS', 'FAIL')); % Overall preflight sonucunu yazdirir.
fprintf('Qf range      : %.3f - %.3f m3/h\n', min(DOE.Qf_train_m3h), max(DOE.Qf_train_m3h)); % Final Qf coverage range'ini yazdirir.
fprintf('T range       : %.3f - %.3f C\n', min(DOE.T_RO_in_C), max(DOE.T_RO_in_C)); % Final T coverage range'ini yazdirir.
fprintf('Cf range      : %.3f - %.3f kg/m3\n', min(DOE.Cf_kg_m3), max(DOE.Cf_kg_m3)); % Final Cf coverage range'ini yazdirir.
fprintf('R range       : %.5f - %.5f\n', min(DOE.R_target), max(DOE.R_target)); % Final R coverage range'ini yazdirir.
fprintf('Score range   : %.3f - %.3f\n', min(DOE.ProposalFeasibilityScore), max(DOE.ProposalFeasibilityScore)); % Proposal score coverage range'ini yazdirir.
fprintf('Prior distance: %.3f - %.3f\n', min(DOE.NearestPriorDistance), max(DOE.NearestPriorDistance)); % Prior support-distance range'ini yazdirir.
fprintf('Analytic pass : %d / %d\n', sum(AnalyticPass), height(DOE)); % Analytic necessary-condition pass sayisini yazdirir.

end % Final DOE preflight fonksiyonunu sonlandirir.

function y = ternary(cond, a, b) % Basit inline status string secimi icin helper fonksiyonu tanimlar.
if cond, y = a; else, y = b; end % Condition'a gore iki string'den birini dondurur.
end % Ternary helper fonksiyonunu sonlandirir.
