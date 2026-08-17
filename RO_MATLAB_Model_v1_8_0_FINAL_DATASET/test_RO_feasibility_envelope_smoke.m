function [env, probes] = test_RO_feasibility_envelope_smoke() % v1.7.0 mapper'i bilinen feasible benchmark state'te tek-state smoke test ile dogrular.

%% REFERANS STATE % v1.6.8 benchmark'ta accepted olan DOE15 high-T/high-R state'ini kullanir.

cfg = ro_ann_config(); % Merkezi configuration'i yukler.
Qf = 52.865870; % Known-feasible anchor feed-flow degerini tanimlar.
T = 41.786613; % Known-feasible anchor temperature degerini tanimlar.
Cf = 39.692320; % Known-feasible anchor concentration degerini tanimlar.

fprintf('\n============================================================\n'); % Smoke-test baslangic ayiricisini yazdirir.
fprintf('RO v1.7.0 - FEASIBILITY ENVELOPE SMOKE TEST\n'); % Smoke-test basligini yazdirir.
fprintf('============================================================\n'); % Baslik alt ayiricisini yazdirir.
fprintf('Qf=%.6f | T=%.6f | Cf=%.6f\n', Qf, T, Cf); % Test state inputlarini yazdirir.

%% ENVELOPE MAP % Tek state'in recovery bandini coarse scan + bisection ile haritalar.

[env, probes] = ro_map_recovery_envelope_state(999, "SmokeKnownFeasible", Qf, T, Cf, cfg); % Tek-state mapper'i cagirir.
fprintf('Has feasible band : %d\n', env.HasFeasibleBand); % Feasible-band flag degerini yazdirir.
fprintf('Rmin / Rmax       : %.6f / %.6f\n', env.Rmin_feasible, env.Rmax_feasible); % Refined recovery envelope degerlerini yazdirir.
fprintf('Band width        : %.6f\n', env.FeasibleBandWidth); % Recovery-band genisligini yazdirir.
fprintf('Coarse valid      : %d / %d\n', env.CoarseValidCount, env.CoarseProbeCount); % Coarse valid count degerlerini yazdirir.
fprintf('Total probes      : %d\n', env.TotalProbeCount); % Toplam optimizer probe sayisini yazdirir.
fprintf('Runtime           : %.2f s\n', env.Runtime_s); % Tek-state total runtime degerini yazdirir.
fprintf('Lower fail side   : %s\n', env.Rmin_lower_invalid_reason); % Lower boundary invalid-side reason'ini yazdirir.
fprintf('Upper fail side   : %s\n', env.Rmax_upper_invalid_reason); % Upper boundary invalid-side reason'ini yazdirir.
fprintf('Non-contiguous    : %d\n', env.NonContiguousCoarse); % Coarse valid island diagnostic flag degerini yazdirir.

%% MINIMUM ACCEPTANCE % Known-feasible state'te en az bir nonzero recovery band bulunmasini zorunlu tutar.

if ~env.HasFeasibleBand || ~isfinite(env.Rmin_feasible) || ~isfinite(env.Rmax_feasible) || env.Rmax_feasible < env.Rmin_feasible % Temel mapper acceptance kosullarini kontrol eder.
    error('v1.7.0 smoke test FAILED: known-feasible state icin recovery band bulunamadi.'); % Problem varsa full 48-state run'i baslatmadan acik hata verir.
end % Smoke-test acceptance kontrolunu sonlandirir.
fprintf('Smoke test        : PASS\n'); % Basarili mapper smoke-test sonucunu yazdirir.

end % Smoke-test fonksiyonunu sonlandirir.
