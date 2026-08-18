function out = test_RO_ANN_reference_train() % v1.5 validated PX benchmark'in 1/4-scale tek train karsiligini ve yeni ANN wrapper'ini smoke-test eder.

%% VALIDATED REFERENCE-TRAIN INPUTS % Full Du PX benchmark'in geometrik ve debi olarak dortte birini tanimlar.

cfg = ro_ann_config(); % Final train geometry ve v1.5 validated PX settings degerlerini yukler.
Qf_train_m3h = 206.6 / 4.0; % Full benchmark feed flow degerini dort esit train'e boler.
Cf_kg_m3 = 35.0; % Du benchmark feed concentration degerini kullanir.
T_RO_in_C = 20.0; % Du benchmark feed temperature degerini kullanir.
P1_gauge_MPa = 7.14; % Published Stage-1 operating pressure degerini kullanir.
P2_gauge_MPa = 7.49; % Published Stage-2 operating pressure degerini kullanir.
R_target = 0.5808; % Published PX benchmark recovery degerini optimization smoke test target'i yapar.

%% DIRECT REFERENCE-PRESSURE EVALUATION % Yeni extended constraint wrapper ile published pressure noktasini degerlendirir.

ev_ref = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, cfg); % 150-segment tek-train detailed evaluation'i calistirir.

fprintf('\n------------------------------------------------------------\n'); % Smoke-test ayiricisini yazdirir.
fprintf('RO ANN REFERENCE TRAIN / DIRECT PRESSURE CHECK\n'); % Smoke-test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Smoke-test ayiricisini yazdirir.
fprintf('Qf train       : %.4f m3/h\n', Qf_train_m3h); % Train feed flow degerini yazdirir.
fprintf('Recovery       : %.4f %%\n', 100.0 * ev_ref.Recovery); % Detailed model recovery degerini yazdirir.
fprintf('Qp train       : %.4f m3/h\n', ev_ref.Qp_train_m3h); % Train permeate flow degerini yazdirir.
fprintf('Cp             : %.3f mg/L\n', ev_ref.Cp_mg_L); % Product salinity degerini yazdirir.
fprintf('Average flux   : %.4f LMH\n', ev_ref.Javg_LMH); % System average flux degerini yazdirir.
fprintf('Jfirst Stage-1 : %.4f LMH\n', ev_ref.Jfirst_stage1_LMH); % Stage-1 first-element average flux degerini yazdirir.
fprintf('Jfirst Stage-2 : %.4f LMH\n', ev_ref.Jfirst_stage2_LMH); % Stage-2 first-element average flux degerini yazdirir.
fprintf('HPP flow       : %.4f m3/h\n', ev_ref.Qhpp_m3h); % Tek train HPP flow degerini yazdirir.
fprintf('Power          : %.4f kW\n', ev_ref.W_RO_kW); % Tek train total RO electrical power degerini yazdirir.
fprintf('SEC            : %.4f kWh/m3\n', ev_ref.SEC_kWh_m3); % Detailed energy-model SEC degerini yazdirir.
fprintf('Physical feas. : %d\n', ev_ref.physical_feasible); % Extended hard feasibility flag degerini yazdirir.
fprintf('Min margin     : %.6f\n', ev_ref.feasibility_margin_scaled); % En yakin normalized constraint margin degerini yazdirir.
fprintf('PX outlet      : %.5f MPa(g)\n', ev_ref.PXout_gauge_MPa); % PX high-side outlet basincini yazdirir.
fprintf('PX excess dP   : %.5f MPa\n', ev_ref.PX_excess_pressure_MPa); % Stage-1 basincinin ustundeki PX excess pressure'i yazdirir.
fprintf('PX booster dP  : %.5f MPa\n', ev_ref.PX_booster_deltaP_MPa); % Stage-1 basincina ulasmak icin gerekirse PX booster dP degerini yazdirir.
violated_ref = ev_ref.constraint_names(ev_ref.c_scaled > 0.0); % Direct noktada pozitif hard-constraint violation isimlerini secer.
if isempty(violated_ref) % Direct nokta hard-feasible ise kontrol eder.
    fprintf('Violations     : none\n'); % Violation olmadigini yazdirir.
else % Bir veya daha fazla violation varsa bu dali kullanir.
    fprintf('Violations     : %s\n', strjoin(violated_ref, '; ')); % Violation isimlerini tek satirda yazdirir.
end % Direct violation reporting kosulunu sonlandirir.

%% INTERNAL OPTIMIZATION SMOKE TEST % Ayni Qf-T-Cf ve target recovery'de P1-P2 power minimization'i tek kez test eder.

row_opt = ro_optimize_train_point(1, "ReferenceSmokeTest", Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, cfg); % Recovery-conditioned internal P1-P2 optimization'i calistirir.

fprintf('\n------------------------------------------------------------\n'); % Optimizer smoke-test ayiricisini yazdirir.
fprintf('INTERNAL P1-P2 OPTIMIZATION CHECK\n'); % Optimizer smoke-test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Optimizer smoke-test ayiricisini yazdirir.
fprintf('Dataset valid  : %d\n', row_opt.DatasetValid); % Optimized point validity flag degerini yazdirir.
fprintf('P1*            : %.5f MPa(g)\n', row_opt.P1_opt_gauge_MPa); % Optimum Stage-1 pressure degerini yazdirir.
fprintf('P2*            : %.5f MPa(g)\n', row_opt.P2_opt_gauge_MPa); % Optimum Stage-2 pressure degerini yazdirir.
fprintf('Recovery       : %.6f (target %.6f)\n', row_opt.Recovery_actual, R_target); % Actual-target recovery uyumunu yazdirir.
fprintf('Power*         : %.5f kW\n', row_opt.W_RO_train_kW); % Optimum power degerini yazdirir.
fprintf('SEC*           : %.5f kWh/m3\n', row_opt.SEC_kWh_m3); % Optimum SEC degerini yazdirir.
fprintf('Cp*            : %.3f mg/L\n', row_opt.Cp_mg_L); % Optimum product salinity degerini yazdirir.
fprintf('ExitFlag       : %.0f\n', row_opt.ExitFlag); % fmincon exitflag degerini yazdirir.
fprintf('Failure reason : %s\n', row_opt.FailureReason); % Varsa failure reason degerini yazdirir.

%% OUTPUT % Direct benchmark ve optimized row sonuclarini birlikte struct olarak dondurur.

out.direct = ev_ref; % Direct published-pressure train evaluation struct'ini kaydeder.
out.optimized = row_opt; % Recovery-conditioned optimized dataset row struct'ini kaydeder.

end % Reference-train ANN smoke-test fonksiyonunu sonlandirir.
