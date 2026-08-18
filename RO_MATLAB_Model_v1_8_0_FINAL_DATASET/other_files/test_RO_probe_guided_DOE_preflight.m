function DOE = test_RO_probe_guided_DOE_preflight() % Heavy truth-model run'dan once v1.7.1 proposal DOE generator'unun input ve score diagnostics'ini kontrol eder.

%% CONFIG VE DOE % Package icindeki v1.7.0 prior artifacts ile 120-point adaptive DOE olusturur.
cfg = ro_ann_config(); % v1.7.1 configuration struct'ini yukler.
DOE = ro_generate_doe_probe_guided(cfg.guided.n_pilot, cfg, 'RO_feasibility_envelope.csv', 'RO_feasibility_envelope_probes.csv'); % Proposal-guided DOE'yi truth solve yapmadan uretir.

%% BASIC CHECKS % Boyut, finite inputs ve analytic necessary-condition pass durumunu kontrol eder.
assert(height(DOE) == cfg.guided.n_pilot, 'DOE point sayisi beklenen %d degil.', cfg.guided.n_pilot); % Pilot row count'unu dogrular.
assert(all(isfinite(DOE.Qf_train_m3h)) && all(isfinite(DOE.T_RO_in_C)) && all(isfinite(DOE.Cf_kg_m3)) && all(isfinite(DOE.R_target)), 'DOE inputlarinda NaN/Inf var.'); % Tum model inputlarinin finite oldugunu dogrular.
assert(all(DOE.ProposalFeasibilityScore >= 0 & DOE.ProposalFeasibilityScore <= 1), 'Proposal score [0,1] disinda.'); % kNN score range'ini dogrular.
analytic_pass = false(height(DOE), 1); % Her DOE point icin analytic necessary-condition flag vectorunu baslatir.
for i = 1:height(DOE) % Tum selected DOE rows'u gezer.
    sc = ro_analytic_screen_train_point(DOE.Qf_train_m3h(i), DOE.T_RO_in_C(i), DOE.Cf_kg_m3(i), DOE.R_target(i), cfg); % Aynı analytic screening fonksiyonunu selected point'e uygular.
    analytic_pass(i) = sc.pass; % Pass flag degerini kaydeder.
end % Analytic-check loop'unu sonlandirir.
assert(all(analytic_pass), 'Selected DOE icinde analytic necessary-condition fail noktasi var.'); % Tum proposal point'lerin analytic necessary conditions'i gectigini dogrular.

%% OZET % Heavy truth run'a gecmeden once input coverage ve sampling stratum bilgilerini yazdirir.
fprintf('\nPROBE-GUIDED DOE PREFLIGHT: PASS\n'); % Preflight acceptance mesajini yazdirir.
fprintf('Qf range    : %.3f - %.3f m3/h\n', min(DOE.Qf_train_m3h), max(DOE.Qf_train_m3h)); % Selected feed-flow coverage range'ini yazdirir.
fprintf('T range     : %.3f - %.3f C\n', min(DOE.T_RO_in_C), max(DOE.T_RO_in_C)); % Selected temperature coverage range'ini yazdirir.
fprintf('Cf range    : %.3f - %.3f kg/m3\n', min(DOE.Cf_kg_m3), max(DOE.Cf_kg_m3)); % Selected concentration coverage range'ini yazdirir.
fprintf('R range     : %.5f - %.5f\n', min(DOE.R_target), max(DOE.R_target)); % Selected recovery coverage range'ini yazdirir.
fprintf('Score range : %.3f - %.3f\n', min(DOE.ProposalFeasibilityScore), max(DOE.ProposalFeasibilityScore)); % Selected proposal-score coverage range'ini yazdirir.
fprintf('Analytic pass: %d / %d\n', sum(analytic_pass), height(DOE)); % Analytic necessary-condition pass count'unu yazdirir.

end % Preflight test fonksiyonunu sonlandirir.
