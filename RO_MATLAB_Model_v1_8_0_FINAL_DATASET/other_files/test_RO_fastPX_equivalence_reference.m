function report = test_RO_fastPX_equivalence_reference() % Legacy ve fast PX coupling solver'larini ayni N=150 reference pressure noktasinda accuracy/runtime acisindan karsilastirir.

%% REFERENCE INPUT % v1.6.4 hybrid optimum noktasini sabit test girdisi olarak kullanir.

cfg = ro_ann_config(); % ANN configuration parametrelerini yukler.
Qf = 51.65; % Reference single-train feed flow degerini tanimlar.
T = 20.0; % Reference inlet temperature degerini tanimlar.
Cf = 35.0; % Du reference feed concentration degerini tanimlar.
P1 = 7.15855; % v1.6.4 optimum Stage-1 gauge pressure degerini tanimlar.
P2 = 7.68423; % v1.6.4 optimum Stage-2 gauge pressure degerini tanimlar.

fprintf('\n============================================================\n');
fprintf('RO FAST-PX v1.6.5 - LEGACY EQUIVALENCE TEST\n');
fprintf('============================================================\n');
fprintf('Qf=%.4f | T=%.3f | Cf=%.4f | P1=%.5f | P2=%.5f\n\n', Qf, T, Cf, P1, P2);

%% LEGACY EVALUATION % Under-relaxed validated PX fixed-point solver ile baseline sonucunu hesaplar.

cfg_legacy = cfg; % Ana configuration struct'ini kopyalar.
cfg_legacy.compute.fast_px_coupling = false; % Legacy PX coupling solver'ini zorlar.
t0 = tic; % Legacy runtime olcumunu baslatir.
ev_legacy = ro_evaluate_train_operating_point(Qf, T, Cf, P1, P2, cfg_legacy); % Legacy detailed evaluation'i calistirir.
t_legacy = toc(t0); % Legacy runtime degerini kaydeder.

%% FAST EVALUATION % Ayni equations/fixed-point root'u safeguarded secant ile cozer.

cfg_fast = cfg; % Ana configuration struct'ini kopyalar.
cfg_fast.compute.fast_px_coupling = true; % Fast PX coupling solver'ini etkinlestirir.
t0 = tic; % Fast runtime olcumunu baslatir.
ev_fast = ro_evaluate_train_operating_point(Qf, T, Cf, P1, P2, cfg_fast); % Fast detailed evaluation'i calistirir.
t_fast = toc(t0); % Fast runtime degerini kaydeder.

%% REPORT % Critical physics outputs arasindaki farklari ve speedup degerini raporlar.

fprintf('Legacy success       : %d\n', ev_legacy.success);
fprintf('Fast success         : %d\n', ev_fast.success);
fprintf('Legacy PX iterations : %d\n', ev_legacy.PX_iterations);
fprintf('Fast PX map evals    : %d\n', ev_fast.PX_iterations);
fprintf('Legacy runtime       : %.3f s\n', t_legacy);
fprintf('Fast runtime         : %.3f s\n', t_fast);
fprintf('Speedup              : %.2f x\n\n', t_legacy / max(t_fast, eps));

fprintf('Recovery legacy/fast : %.10f / %.10f | diff %+.3e\n', ev_legacy.Recovery, ev_fast.Recovery, ev_fast.Recovery - ev_legacy.Recovery);
fprintf('Qp legacy/fast       : %.8f / %.8f | diff %+.3e m3/h\n', ev_legacy.Qp_train_m3h, ev_fast.Qp_train_m3h, ev_fast.Qp_train_m3h - ev_legacy.Qp_train_m3h);
fprintf('Cp legacy/fast       : %.8f / %.8f | diff %+.3e mg/L\n', ev_legacy.Cp_mg_L, ev_fast.Cp_mg_L, ev_fast.Cp_mg_L - ev_legacy.Cp_mg_L);
fprintf('Power legacy/fast    : %.8f / %.8f | diff %+.3e kW\n', ev_legacy.W_RO_kW, ev_fast.W_RO_kW, ev_fast.W_RO_kW - ev_legacy.W_RO_kW);
fprintf('SEC legacy/fast      : %.8f / %.8f | diff %+.3e\n', ev_legacy.SEC_kWh_m3, ev_fast.SEC_kWh_m3, ev_fast.SEC_kWh_m3 - ev_legacy.SEC_kWh_m3);
fprintf('dP1 legacy/fast      : %.8f / %.8f | diff %+.3e MPa\n', ev_legacy.dP_stage1_MPa, ev_fast.dP_stage1_MPa, ev_fast.dP_stage1_MPa - ev_legacy.dP_stage1_MPa);
fprintf('CPF1 legacy/fast     : %.8f / %.8f | diff %+.3e\n', ev_legacy.CPFmax_stage1, ev_fast.CPFmax_stage1, ev_fast.CPFmax_stage1 - ev_legacy.CPFmax_stage1);
fprintf('Physical feasible    : %d / %d\n', ev_legacy.physical_feasible, ev_fast.physical_feasible);

%% ACCEPTANCE % Fast solver'in legacy result ile numerical equivalence kriterlerini kontrol eder.

report.max_abs_core_diff = max(abs([ev_fast.Recovery - ev_legacy.Recovery, ...
    (ev_fast.Qp_train_m3h - ev_legacy.Qp_train_m3h) / max(abs(ev_legacy.Qp_train_m3h), 1.0), ...
    (ev_fast.Cp_mg_L - ev_legacy.Cp_mg_L) / max(abs(ev_legacy.Cp_mg_L), 1.0), ...
    (ev_fast.W_RO_kW - ev_legacy.W_RO_kW) / max(abs(ev_legacy.W_RO_kW), 1.0)])); % Dimensionless maximum core output difference degerini hesaplar.
report.accepted = ev_legacy.success && ev_fast.success && report.max_abs_core_diff <= 1.0e-7 && ev_legacy.physical_feasible == ev_fast.physical_feasible; % Publication-level equivalence icin tight numerical acceptance flag degerini hesaplar.
report.legacy_runtime_s = t_legacy; % Legacy runtime degerini report struct'a kaydeder.
report.fast_runtime_s = t_fast; % Fast runtime degerini report struct'a kaydeder.
report.speedup = t_legacy / max(t_fast, eps); % Runtime speedup factor degerini kaydeder.
report.ev_legacy = ev_legacy; % Legacy detailed outputu diagnostic icin kaydeder.
report.ev_fast = ev_fast; % Fast detailed outputu diagnostic icin kaydeder.

fprintf('\nEquivalence accepted : %d\n', report.accepted);
fprintf('Max core rel/abs diff: %.3e\n', report.max_abs_core_diff);
fprintf('============================================================\n');

end % Fast-PX equivalence test fonksiyonunu sonlandirir.
