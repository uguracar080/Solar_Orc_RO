function Results = diagnose_RO_ANN_branch_outliers()
% diagnose_RO_ANN_branch_outliers
% ANN blind-testte ortak buyuk hata uretilen truth noktalarinda recovery-esitlik
% manifoldu boyunca P1 taramasi yaparak tek-seed hibrit optimizerin daha dusuk
% guclu baska bir basinç dali kacirip kacirmadigini kontrol eder.

%% DOSYA VE AYARLAR
truth_file = 'RO_ANN_final_truth_dataset.csv'; % Final 2400-point truth dataset dosyasini tanimlar.
if ~isfile(truth_file) % Truth CSV'nin Current Folder icinde olup olmadigini kontrol eder.
    error('Truth dataset bulunamadi: %s', truth_file); % Dosya yoksa acik hata verir.
end % Dosya kontrolunu sonlandirir.
T = readtable(truth_file, 'TextType', 'string'); % Final truth datasetini tablo olarak okur.
cfg = ro_ann_config(); % Validated RO model ve FASTSEARCH/FastPX ayarlarini yukler.
ids = [955, 2330, 825]; % ANN test outlieri ve ayni davranisi gosteren iki karsilastirma noktasini secer.
n_coarse = 31; % Global recovery-manifold P1 taramasindaki coarse nokta sayisini tanimlar.
n_fine = 17; % En iyi coarse nokta cevresindeki fine P1 nokta sayisini tanimlar.
fine_halfwidth_MPa = 0.20; % Fine refinement'in en iyi coarse P1 etrafindaki yaricapini tanimlar.

%% PARALLEL POOL
try % Parallel Computing Toolbox varsa mevcut pool'u kullanmak veya acmak icin try blogunu baslatir.
    p = gcp('nocreate'); % Mevcut parallel pool'u sorgular.
    if isempty(p) % Acik pool yoksa kontrol eder.
        p = parpool('Processes'); %#ok<NASGU> % Local profile worker sayisiyla process tabanli pool acar.
    end % Pool acma kosulunu sonlandirir.
catch % Parallel toolbox/pool acma basarisizsa seri calismaya izin verir.
    p = []; %#ok<NASGU> % Seri mod icin bos pool placeholder tanimlar.
end % Parallel pool try-catch blogunu sonlandirir.

%% DIAGNOSTIC TARAMA
all_scan = table(); % Tum DOE noktalarinin coarse+fine probe kayitlarini birlestirecek tabloyu baslatir.
summary_rows = cell(numel(ids), 1); % Her DOE ID icin ozet satirini cell array olarak baslatir.

fprintf('\n============================================================\n'); % Baslik ayiracini yazdirir.
fprintf('RO ANN v1.9.1 - TRUTH BRANCH OUTLIER DIAGNOSTIC\n'); % Diagnostic basligini yazdirir.
fprintf('============================================================\n'); % Baslik ayiracini yazdirir.

for ii = 1:numel(ids) % Secilen truth noktalarini sirayla inceler.
    id = ids(ii); % Mevcut DOE ID degerini alir.
    idx = find(T.DOE_ID == id, 1, 'first'); % Dataset icinde DOE ID satirini bulur.
    if isempty(idx) % DOE ID bulunamazsa kontrol eder.
        warning('DOE_ID %d truth datasetinde bulunamadi; atlaniyor.', id); % Eksik ID icin uyari verir.
        continue; % Sonraki ID'ye gecer.
    end % ID bulunabilirlik kosulunu sonlandirir.

    Qf = T.Qf_train_m3h(idx); % Mevcut noktanin train feed flow inputunu alir.
    Tin = T.T_RO_in_C(idx); % Mevcut noktanin RO inlet temperature inputunu alir.
    Cf = T.Cf_kg_m3(idx); % Mevcut noktanin feed salt concentration inputunu alir.
    Rt = T.R_target(idx); % Mevcut noktanin target recovery inputunu alir.
    W_saved = T.W_RO_train_kW(idx); % Dataset'e kayitli optimized power degerini alir.
    P1_saved = T.P1_opt_gauge_MPa(idx); % Dataset'e kayitli Stage-1 pressure degerini alir.
    P2_saved = T.P2_opt_gauge_MPa(idx); % Dataset'e kayitli Stage-2 pressure degerini alir.
    Cp_saved = T.Cp_mg_L(idx); % Dataset'e kayitli product salinity degerini alir.

    mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Aged membrane parametrelerini yukler.
    pi_feed_MPa = ro_osmotic_pressure_du2014(Tin, Cf, mem); % Feed osmotic pressure degerini hesaplar.
    P1_lb = max(cfg.hybrid.P1_lb_MPa, pi_feed_MPa + cfg.hybrid.P1_osmotic_margin_MPa); % FASTSEARCH ile ayni dinamik P1 lower bound degerini hesaplar.
    P1_lb = min(P1_lb, cfg.hybrid.P1_ub_MPa); % Dinamik lower bound'u maximum pressure altinda tutar.
    P1_coarse = linspace(P1_lb, cfg.hybrid.P1_ub_MPa, n_coarse); % Tum izinli P1 araligini kapsayan coarse grid olusturur.

    fprintf('\nDOE_ID %d | Qf=%.5f | T=%.4f | Cf=%.5f | R=%.6f\n', id, Qf, Tin, Cf, Rt); % Mevcut input state'i yazdirir.
    fprintf('Saved truth : P1=%.5f | P2=%.5f | W=%.5f kW | Cp=%.3f mg/L\n', P1_saved, P2_saved, W_saved, Cp_saved); % Kayitli truth sonucunu yazdirir.
    fprintf('P1 scan     : %.4f - %.4f MPa(g) | %d coarse points\n', P1_lb, cfg.hybrid.P1_ub_MPa, n_coarse); % Coarse scan domainini yazdirir.

    ScanCoarse = scan_p1_grid(P1_coarse, id, "coarse", Qf, Tin, Cf, Rt, cfg); % N=150 recovery manifold coarse taramasini calistirir.
    feasible_coarse = ScanCoarse.TargetMet & ScanCoarse.PhysicalFeasible & isfinite(ScanCoarse.W_kW); % Regression-valid coarse probe maskesini olusturur.

    if any(feasible_coarse) % En az bir fiziksel feasible coarse root bulunduysa kontrol eder.
        feasible_idx = find(feasible_coarse); % Feasible coarse satir indexlerini alir.
        [~, jbest_local] = min(ScanCoarse.W_kW(feasible_idx)); % Feasible coarse probe'lar icinde minimum power indexini bulur.
        jbest = feasible_idx(jbest_local); % Minimum power coarse satirinin mutlak indexini alir.
        P1_best_coarse = ScanCoarse.P1_MPa(jbest); % Minimum-power coarse P1 degerini alir.
        fine_lb = max(P1_lb, P1_best_coarse - fine_halfwidth_MPa); % Fine scan lower bound degerini hesaplar.
        fine_ub = min(cfg.hybrid.P1_ub_MPa, P1_best_coarse + fine_halfwidth_MPa); % Fine scan upper bound degerini hesaplar.
        P1_fine = linspace(fine_lb, fine_ub, n_fine); % Minimum coarse nokta etrafinda fine P1 grid olusturur.
        ScanFine = scan_p1_grid(P1_fine, id, "fine", Qf, Tin, Cf, Rt, cfg); % N=150 recovery manifold fine taramasini calistirir.
    else % Hic feasible coarse root bulunmadiysa bu dali kullanir.
        ScanFine = ScanCoarse([],:); % Ayni kolonlara sahip bos fine tablo olusturur.
    end % Fine scan kosulunu sonlandirir.

    Scan = [ScanCoarse; ScanFine]; % Coarse ve fine probe tablolarini birlestirir.
    Scan = sortrows(Scan, {'P1_MPa','ScanLevel'}); % Sonuclari P1 ve scan seviyesine gore siralar.
    feasible = Scan.TargetMet & Scan.PhysicalFeasible & isfinite(Scan.W_kW); % Tum probe'larda final feasible maskesini olusturur.

    if any(feasible) % En az bir feasible manifold noktasi varsa kontrol eder.
        feasible_idx = find(feasible); % Feasible probe indexlerini alir.
        [W_best, jlocal] = min(Scan.W_kW(feasible_idx)); % Tum coarse+fine probe'lar icinde minimum power degerini bulur.
        j = feasible_idx(jlocal); % Minimum-power probe satir indexini alir.
        P1_best = Scan.P1_MPa(j); % Minimum-power scan P1 degerini alir.
        P2_best = Scan.P2_MPa(j); % Minimum-power scan P2 degerini alir.
        Cp_best = Scan.Cp_mg_L(j); % Minimum-power scan product salinity degerini alir.
        dW = W_saved - W_best; % Kayitli truth power ile scan minimumu arasindaki farki hesaplar.
        dW_pct = 100.0 * dW / W_saved; % Kayitli power'a gore yuzde iyilesme miktarini hesaplar.
        suspicious = dW > max(0.50, 0.005 * W_saved); % 0.5 kW veya %0.5'ten buyuk iyilesmeyi local-branch suphe flag'i yapar.
        fprintf('Best scan   : P1=%.5f | P2=%.5f | W=%.5f kW | Cp=%.3f mg/L\n', P1_best, P2_best, W_best, Cp_best); % Bulunan en iyi manifold noktasini yazdirir.
        fprintf('Saved-best  : %.5f kW (%.3f %%) | suspicious local branch = %d\n', dW, dW_pct, suspicious); % Saved truth ile global scan farkini yazdirir.
    else % Hic feasible recovery-root probe yoksa bu dali kullanir.
        W_best = NaN; P1_best = NaN; P2_best = NaN; Cp_best = NaN; dW = NaN; dW_pct = NaN; suspicious = true; % Bos diagnostic degerleri tanimlar.
        fprintf('Best scan   : feasible N=150 recovery-manifold point bulunamadi.\n'); % Feasible scan bulunamadigini bildirir.
    end % Feasible scan ozet kosulunu sonlandirir.

    Scan.Saved_P1_MPa = repmat(P1_saved, height(Scan), 1); % Her probe satirina dataset P1 referansini ekler.
    Scan.Saved_P2_MPa = repmat(P2_saved, height(Scan), 1); % Her probe satirina dataset P2 referansini ekler.
    Scan.Saved_W_kW = repmat(W_saved, height(Scan), 1); % Her probe satirina dataset power referansini ekler.
    all_scan = [all_scan; Scan]; %#ok<AGROW> % Mevcut ID probe sonuclarini global scan tablosuna ekler.

    summary_rows{ii} = table(id, Qf, Tin, Cf, Rt, P1_saved, P2_saved, W_saved, Cp_saved, P1_best, P2_best, W_best, Cp_best, dW, dW_pct, suspicious, ... % Mevcut DOE ID diagnostic ozet satirini olusturur.
        'VariableNames', {'DOE_ID','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target','Saved_P1_MPa','Saved_P2_MPa','Saved_W_kW','Saved_Cp_mg_L','ScanBest_P1_MPa','ScanBest_P2_MPa','ScanBest_W_kW','ScanBest_Cp_mg_L','SavedMinusBest_kW','SavedMinusBest_pct','SuspiciousLocalBranch'}); % Ozet tablo kolon adlarini tanimlar.
end % Tum DOE ID diagnostic dongusunu sonlandirir.

%% OZET VE DOSYA CIKTILARI
summary_rows = summary_rows(~cellfun(@isempty, summary_rows)); % Eksik DOE ID nedeniyle bos kalan ozet cell'lerini temizler.
if isempty(summary_rows) % Hic ozet satiri olusmadiysa kontrol eder.
    Results = table(); % Bos result tablo dondurur.
else % En az bir ozet satiri varsa bu dali kullanir.
    Results = vertcat(summary_rows{:}); % Tum DOE ID ozet satirlarini tek tablo halinde birlestirir.
end % Ozet tablo olusturma kosulunu sonlandirir.
writetable(all_scan, 'RO_ANN_truth_branch_scan.csv'); % Tum recovery-manifold probe sonuclarini CSV'ye kaydeder.
writetable(Results, 'RO_ANN_truth_branch_scan_summary.csv'); % DOE bazli branch diagnostic ozetini CSV'ye kaydeder.

fprintf('\n============================================================\n'); % Final ozet ayiracini yazdirir.
fprintf('TRUTH BRANCH DIAGNOSTIC SUMMARY\n'); % Final ozet basligini yazdirir.
fprintf('============================================================\n'); % Final ozet ayiracini yazdirir.
disp(Results); % DOE bazli branch diagnostic ozet tablosunu Command Window'da gosterir.
fprintf('Probe CSV   : RO_ANN_truth_branch_scan.csv\n'); % Probe CSV adini yazdirir.
fprintf('Summary CSV : RO_ANN_truth_branch_scan_summary.csv\n'); % Summary CSV adini yazdirir.
fprintf('============================================================\n'); % Final ozet ayiracini yazdirir.
end % Ana diagnostic fonksiyonunu sonlandirir.

function S = scan_p1_grid(P1_grid, DOE_ID, scan_level, Qf, Tin, Cf, Rt, cfg)
% Sabit input state icin P1 gridindeki her noktada N=150 P2 recovery root'u bulur.

n = numel(P1_grid); % Tarama nokta sayisini alir.
P2 = NaN(n,1); % Root sonucu P2 vectorunu baslatir.
W = NaN(n,1); % RO power vectorunu baslatir.
Cp = NaN(n,1); % Product salinity vectorunu baslatir.
Rec = NaN(n,1); % Actual recovery vectorunu baslatir.
Rerr = NaN(n,1); % Recovery residual vectorunu baslatir.
dP1 = NaN(n,1); % Stage-1 pressure-drop vectorunu baslatir.
J1 = NaN(n,1); % Stage-1 first-element flux vectorunu baslatir.
PXex = NaN(n,1); % PX excess pressure vectorunu baslatir.
Qhpp = NaN(n,1); % HPP flow vectorunu baslatir.
TargetMet = false(n,1); % Recovery target flag vectorunu baslatir.
Physical = false(n,1); % Physical feasibility flag vectorunu baslatir.
Success = false(n,1); % Numerical success flag vectorunu baslatir.
EvalCount = zeros(n,1); % Root model evaluation sayaci vectorunu baslatir.
Failure = strings(n,1); % Root failure reason string vectorunu baslatir.
Runtime = NaN(n,1); % Her P1 root wall-clock runtime vectorunu baslatir.

parfor k = 1:n % P1 root problemlerini worker'lar arasinda paralel cozer.
    tk = tic; % Mevcut P1 root runtime olcumunu baslatir.
    rr = ro_find_P2_for_recovery(Qf, Tin, Cf, Rt, P1_grid(k), cfg, cfg.hybrid.final_N_segments, NaN); % Sabit P1 icin full N=150 recovery root P2'yi bulur.
    Runtime(k) = toc(tk); % Root wall-clock runtime degerini kaydeder.
    EvalCount(k) = rr.n_evaluations; % Root solve detailed evaluation sayisini kaydeder.
    Failure(k) = string(rr.failure_reason); % Root failure reason degerini kaydeder.
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success % Kullanilabilir recovery-matched truth evaluation bulunduysa kontrol eder.
        ev = rr.ev; % Root detailed evaluation struct'ini yerel degiskene alir.
        P2(k) = rr.P2_gauge_MPa; % Root P2 degerini kaydeder.
        W(k) = ev.W_RO_kW; % Total RO power degerini kaydeder.
        Cp(k) = ev.Cp_mg_L; % Product salinity degerini kaydeder.
        Rec(k) = ev.Recovery; % Actual recovery degerini kaydeder.
        Rerr(k) = ev.Recovery - Rt; % Recovery residual degerini kaydeder.
        dP1(k) = ev.dP_stage1_MPa; % Stage-1 pressure drop degerini kaydeder.
        J1(k) = ev.Jfirst_stage1_LMH; % Stage-1 first-element average flux degerini kaydeder.
        PXex(k) = ev.PX_excess_pressure_MPa; % PX excess pressure diagnostic degerini kaydeder.
        Qhpp(k) = ev.Qhpp_m3h; % HPP flow degerini kaydeder.
        TargetMet(k) = abs(Rerr(k)) <= cfg.optim.recovery_accept_tolerance; % Final recovery acceptance flag degerini hesaplar.
        Physical(k) = ev.physical_feasible; % Physical feasibility flag degerini kaydeder.
        Success(k) = true; % Numerical-success flag degerini true yapar.
    end % Root acceptance kosulunu sonlandirir.
end % Parallel P1 scan dongusunu sonlandirir.

S = table(repmat(DOE_ID,n,1), repmat(string(scan_level),n,1), P1_grid(:), P2, W, Cp, Rec, Rerr, TargetMet, Physical, Success, dP1, J1, PXex, Qhpp, EvalCount, Runtime, Failure, ... % Scan output tablosunu olusturur.
    'VariableNames', {'DOE_ID','ScanLevel','P1_MPa','P2_MPa','W_kW','Cp_mg_L','Recovery','RecoveryError','TargetMet','PhysicalFeasible','Success','dP1_MPa','Jfirst1_LMH','PX_excess_MPa','Qhpp_m3h','RootEvalCount','Runtime_s','FailureReason'}); % Scan output kolon adlarini tanimlar.
end % P1 scan helper fonksiyonunu sonlandirir.
