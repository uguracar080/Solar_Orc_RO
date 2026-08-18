function Results = test_RO_fastPX_pressure_domain_profile() % FastPX solver'in optimizer pressure-domain boyunca secant/fallback davranisini hizli bir grid ile profiller.

%% CONFIGURATION % Mevcut v1.6.5 physics ve optimizer ayarlarini yukler.

cfg = ro_ann_config(); % ANN/optimizer configuration struct'ini yukler.
cfg.compute.fast_px_coupling = true; % Profil testinde accelerated PX coupling solver'i zorunlu olarak etkinlestirir.
cfg.model.N_segments = 30; % Root seed asamasinda kullanilan hizli N=30 gridini profiller.

%% REFERENCE CONDITION % Daha once dogrulanan recovery-conditioned reference train noktasini kullanir.

Qf = 51.6500; % Tek-train feed flow degerini m3/h olarak tanimlar.
T = 20.000; % Reference feed temperature degerini C olarak tanimlar.
Cf = 35.0000; % Du reference feed concentration degerini kg/m3 olarak tanimlar.
Rtarget = 0.580800; % Reference recovery target degerini tanimlar.

%% PRESSURE PROBE GRID % Hybrid optimizer'in 7 P1 seed noktasi ve root solver'in 5 P2 global probe mantigini taklit eder.

P1_grid = linspace(cfg.hybrid.P1_lb_MPa, cfg.hybrid.P1_ub_MPa, cfg.hybrid.n_P1_seed); % Hybrid seed Stage-1 pressure gridini olusturur.
mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Dynamic P2 lower bound icin membrane technical limits struct'ini yukler.
nP2 = cfg.root.n_P2_bracket; % Root solver global bracket probe sayisini kullanir.
nRows = numel(P1_grid) * nP2; % Toplam profil evaluation sayisini hesaplar.

P1_MPa = NaN(nRows,1); % Result Stage-1 pressure kolonunu olusturur.
P2_MPa = NaN(nRows,1); % Result Stage-2 pressure kolonunu olusturur.
Recovery = NaN(nRows,1); % Actual recovery kolonunu olusturur.
Rerr = NaN(nRows,1); % Recovery-minus-target kolonunu olusturur.
Cp_mgL = NaN(nRows,1); % Product salinity kolonunu olusturur.
Power_kW = NaN(nRows,1); % RO power kolonunu olusturur.
PhysicalFeasible = false(nRows,1); % Physical feasibility kolonunu olusturur.
Success = false(nRows,1); % Numerical success kolonunu olusturur.
PXMethod = strings(nRows,1); % PX coupling method kolonunu olusturur.
PXMapEvals = NaN(nRows,1); % PX map evaluation count kolonunu olusturur.
EvalRuntime_s = NaN(nRows,1); % Tek evaluation runtime kolonunu olusturur.

fprintf('\n============================================================\n'); % Test basligini baslatir.
fprintf('FAST PX PRESSURE-DOMAIN PROFILE - N=30\n'); % Test adini yazdirir.
fprintf('============================================================\n'); % Baslik ayiracini yazdirir.
fprintf('Qf=%.4f | T=%.3f | Cf=%.4f | Rtarget=%.6f\n\n', Qf, T, Cf, Rtarget); % Reference condition'i yazdirir.

row = 0; % Flat result row sayacini sifirlar.
t_total = tic; % Tum 35-probe profil testinin toplam runtime olcumunu baslatir.

for i = 1:numel(P1_grid) % Yedi hybrid Stage-1 seed pressure noktasini sirayla gezer.
    P1 = P1_grid(i); % Mevcut Stage-1 pressure degerini alir.
    P2_lb = max(cfg.root.P2_lb_MPa, P1 - mem.max_PV_pressure_drop_MPa); % Root solver ile ayni dynamic Stage-2 lower bound degerini hesaplar.
    P2_grid = linspace(P2_lb, cfg.root.P2_ub_MPa, nP2); % Root solver global P2 probe gridini olusturur.

    for j = 1:numel(P2_grid) % Mevcut P1 icin bes P2 pressure probe noktasini gezer.
        row = row + 1; % Flat result row sayacini arttirir.
        P2 = P2_grid(j); % Mevcut Stage-2 pressure probe degerini alir.
        ev = ro_evaluate_train_operating_point(Qf, T, Cf, P1, P2, cfg); % Tek N=30 detailed operating-point evaluation'i calistirir.

        P1_MPa(row) = P1; % Stage-1 pressure degerini kaydeder.
        P2_MPa(row) = P2; % Stage-2 pressure degerini kaydeder.
        Success(row) = ev.success; % Numerical success flag degerini kaydeder.
        PXMethod(row) = string(ev.PX_solver_method); % Secant/fallback method degerini kaydeder.
        PXMapEvals(row) = ev.PX_map_evals; % Coupled map evaluation count degerini kaydeder.
        EvalRuntime_s(row) = ev.EvalRuntime_s; % Wall-clock evaluation runtime degerini kaydeder.

        if ev.success % Finite physical outputs mevcutsa kontrol eder.
            Recovery(row) = ev.Recovery; % Actual recovery degerini kaydeder.
            Rerr(row) = ev.Recovery - Rtarget; % Recovery target residual degerini kaydeder.
            Cp_mgL(row) = ev.Cp_mg_L; % Product salinity degerini kaydeder.
            Power_kW(row) = ev.W_RO_kW; % RO train power degerini kaydeder.
            PhysicalFeasible(row) = ev.physical_feasible; % Physical feasibility flag degerini kaydeder.
        end % Successful evaluation output assignment kosulunu sonlandirir.

        fprintf('P1=%6.3f P2=%6.3f | %-15s | maps=%3.0f | %7.3f s | R=%7.4f\n', ...
            P1, P2, char(PXMethod(row)), PXMapEvals(row), EvalRuntime_s(row), Recovery(row)); % Her pressure probe sonucunu anlik yazdirir.
    end % P2 probe dongusunu sonlandirir.
end % P1 seed dongusunu sonlandirir.

TotalRuntime_s = toc(t_total); % Tum profil probe setinin toplam wall-clock runtime degerini hesaplar.

%% RESULTS TABLE % Tum probe sonuclarini analiz ve paylasim icin tabloya cevirir.

Results = table(P1_MPa, P2_MPa, Recovery, Rerr, Cp_mgL, Power_kW, PhysicalFeasible, Success, PXMethod, PXMapEvals, EvalRuntime_s); % Flat profiling table olusturur.
writetable(Results, 'RO_fastPX_pressure_domain_profile.csv'); % Profil sonuclarini CSV dosyasina kaydeder.

%% SUMMARY % Fast secant ve legacy fallback frekans/runtime ozetlerini yazdirir.

isFast = PXMethod == "secant"; % Safeguarded secant ile tamamlanan evaluation flag'lerini hesaplar.
isFallback = PXMethod == "legacy_fallback"; % Legacy fixed-point fallback kullanan evaluation flag'lerini hesaplar.

fprintf('\n------------------------------------------------------------\n'); % Summary ayiracini yazdirir.
fprintf('SUMMARY\n'); % Summary basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Summary ayiracini yazdirir.
fprintf('Total probes          : %d\n', height(Results)); % Toplam pressure probe sayisini yazdirir.
fprintf('Fast secant           : %d (%.1f %%)\n', sum(isFast), 100*mean(isFast)); % Fast secant sayi ve oranini yazdirir.
fprintf('Legacy fallback       : %d (%.1f %%)\n', sum(isFallback), 100*mean(isFallback)); % Legacy fallback sayi ve oranini yazdirir.
fprintf('Total runtime         : %.2f s (%.2f min)\n', TotalRuntime_s, TotalRuntime_s/60); % Tum profil runtime degerini yazdirir.
if any(isFast) % En az bir secant evaluation mevcutsa kontrol eder.
    fprintf('Secant mean runtime   : %.3f s\n', mean(EvalRuntime_s(isFast), 'omitnan')); % Secant evaluation ortalama runtime degerini yazdirir.
    fprintf('Secant mean map evals : %.2f\n', mean(PXMapEvals(isFast), 'omitnan')); % Secant evaluation ortalama map count degerini yazdirir.
end % Secant summary kosulunu sonlandirir.
if any(isFallback) % En az bir fallback evaluation mevcutsa kontrol eder.
    fprintf('Fallback mean runtime : %.3f s\n', mean(EvalRuntime_s(isFallback), 'omitnan')); % Fallback evaluation ortalama runtime degerini yazdirir.
    fprintf('Fallback mean maps    : %.2f\n', mean(PXMapEvals(isFallback), 'omitnan')); % Fallback evaluation ortalama map count degerini yazdirir.
    fprintf('Fallback max runtime  : %.3f s\n', max(EvalRuntime_s(isFallback), [], 'omitnan')); % En yavas fallback evaluation runtime degerini yazdirir.
end % Fallback summary kosulunu sonlandirir.
fprintf('CSV                   : RO_fastPX_pressure_domain_profile.csv\n'); % Olusan CSV dosya adini yazdirir.
fprintf('============================================================\n\n'); % Test kapanis ayiracini yazdirir.

end % FastPX pressure-domain profiling test fonksiyonunu sonlandirir.
