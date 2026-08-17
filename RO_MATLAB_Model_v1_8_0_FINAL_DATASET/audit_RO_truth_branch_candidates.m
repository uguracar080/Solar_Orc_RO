function Results = audit_RO_truth_branch_candidates()
% audit_RO_truth_branch_candidates
% Final truth datasetinde hibrit optimizerin N=30 seed'den hic ayrilmadan
% function-evaluation limitine ulasma imzasi tasiyan valid noktalarini bulur.
% Daha once RO_ANN_truth_branch_scan_summary.csv ile taranmis ID'leri yeniden
% hesaplamaz; yalniz yeni adaylarda N=150 recovery-manifold global P1 taramasi yapar.
% Bu dosya truth datasetini DEGISTIRMEZ.

%% DOSYALAR VE MODEL AYARLARI
truth_file = 'RO_ANN_final_truth_dataset.csv';
prior_summary_file = 'RO_ANN_truth_branch_scan_summary.csv';
if ~isfile(truth_file)
    error('Truth dataset bulunamadi: %s', truth_file);
end
T = readtable(truth_file, 'TextType', 'string');
cfg = ro_ann_config();

%% OTOMATIK BRANCH-RISK SCREEN
% Confirmed 955/2330 vakalarinda ortak imza:
% 1) dataset valid,
% 2) fmincon function-evaluation limitine ulasmis,
% 3) final P1, N=30 seed P1'den hic ayrilmamis.
seed_tol = 1.0e-8;
func_limit = cfg.hybrid.max_function_evaluations;
mask = logical(T.DatasetValid) & ...
       isfinite(T.FminconFunctionCount) & T.FminconFunctionCount >= func_limit & ...
       isfinite(T.P1_opt_gauge_MPa) & isfinite(T.HybridSeedP1_N30_MPa) & ...
       abs(T.P1_opt_gauge_MPa - T.HybridSeedP1_N30_MPa) <= seed_tol;
C = T(mask, {'DOE_ID','DOE_Type','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
             'W_RO_train_kW','Cp_mg_L','P1_opt_gauge_MPa','P2_opt_gauge_MPa', ...
             'PX_excess_pressure_MPa','FminconIterations','FminconFunctionCount', ...
             'HybridSeedRankUsed','HybridSeedP1_N30_MPa','HybridSeedP2_N30_MPa'});

fprintf('\n============================================================\n');
fprintf('RO TRUTH BRANCH-RISK AUDIT\n');
fprintf('============================================================\n');
fprintf('Valid truth rows                 : %d\n', sum(logical(T.DatasetValid)));
fprintf('fmincon function limit           : %d\n', func_limit);
fprintf('Seed-stagnation branch candidates: %d\n', height(C));
disp(C);

if isempty(C)
    Results = table();
    fprintf('Branch-risk candidate bulunmadi.\n');
    return;
end

%% DAHA ONCE TARANAN NOKTALARI OKU
Prior = table();
if isfile(prior_summary_file)
    Prior = readtable(prior_summary_file, 'TextType', 'string');
end

%% PARALLEL POOL
try
    p = gcp('nocreate');
    if isempty(p)
        parpool('Processes');
    end
catch
    % Pool acilamazsa parfor MATLAB tarafindan seri fallback ile calisabilir.
end

%% YALNIZ DAHA ONCE TARANMAMIS ADAYLARI GLOBAL MANIFOLD SCAN ILE DENETLE
n_coarse = 31;
n_fine = 17;
fine_halfwidth_MPa = 0.20;
new_results = cell(height(C),1);
new_scans = cell(height(C),1);

for i = 1:height(C)
    id = C.DOE_ID(i);
    if ~isempty(Prior) && any(Prior.DOE_ID == id)
        fprintf('\nDOE_ID %d daha once taranmis; mevcut summary kullaniliyor.\n', id);
        continue;
    end

    idx = find(T.DOE_ID == id, 1, 'first');
    Qf = T.Qf_train_m3h(idx);
    Tin = T.T_RO_in_C(idx);
    Cf = T.Cf_kg_m3(idx);
    Rt = T.R_target(idx);
    W_saved = T.W_RO_train_kW(idx);
    P1_saved = T.P1_opt_gauge_MPa(idx);
    P2_saved = T.P2_opt_gauge_MPa(idx);
    Cp_saved = T.Cp_mg_L(idx);

    mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years);
    pi_feed_MPa = ro_osmotic_pressure_du2014(Tin, Cf, mem);
    P1_lb = max(cfg.hybrid.P1_lb_MPa, pi_feed_MPa + cfg.hybrid.P1_osmotic_margin_MPa);
    P1_lb = min(P1_lb, cfg.hybrid.P1_ub_MPa);
    P1_coarse = linspace(P1_lb, cfg.hybrid.P1_ub_MPa, n_coarse);

    fprintf('\nDOE_ID %d | Qf=%.5f | T=%.4f | Cf=%.5f | R=%.6f\n', id, Qf, Tin, Cf, Rt);
    fprintf('Saved truth : P1=%.5f | P2=%.5f | W=%.5f kW | Cp=%.3f mg/L\n', P1_saved, P2_saved, W_saved, Cp_saved);

    S1 = scan_p1_grid(P1_coarse, id, "coarse", Qf, Tin, Cf, Rt, cfg);
    ok1 = S1.TargetMet & S1.PhysicalFeasible & isfinite(S1.W_kW);

    if any(ok1)
        jj = find(ok1);
        [~, kk] = min(S1.W_kW(jj));
        jbest = jj(kk);
        pbest = S1.P1_MPa(jbest);
        P1_fine = linspace(max(P1_lb,pbest-fine_halfwidth_MPa), ...
                           min(cfg.hybrid.P1_ub_MPa,pbest+fine_halfwidth_MPa), n_fine);
        S2 = scan_p1_grid(P1_fine, id, "fine", Qf, Tin, Cf, Rt, cfg);
    else
        S2 = S1([],:);
    end

    S = [S1; S2];
    ok = S.TargetMet & S.PhysicalFeasible & isfinite(S.W_kW);
    if any(ok)
        jj = find(ok);
        [W_best, kk] = min(S.W_kW(jj));
        j = jj(kk);
        P1_best = S.P1_MPa(j);
        P2_best = S.P2_MPa(j);
        Cp_best = S.Cp_mg_L(j);
        dW = W_saved - W_best;
        dW_pct = 100*dW/W_saved;
        suspicious = dW > max(0.50, 0.005*W_saved);
        fprintf('Best scan   : P1=%.5f | P2=%.5f | W=%.5f kW | Cp=%.3f mg/L\n', P1_best, P2_best, W_best, Cp_best);
        fprintf('Saved-best  : %.5f kW (%.3f %%) | suspicious local branch = %d\n', dW, dW_pct, suspicious);
    else
        W_best=NaN; P1_best=NaN; P2_best=NaN; Cp_best=NaN; dW=NaN; dW_pct=NaN; suspicious=true;
        fprintf('Feasible recovery-manifold point bulunamadi.\n');
    end

    new_results{i} = table(id,Qf,Tin,Cf,Rt,P1_saved,P2_saved,W_saved,Cp_saved, ...
        P1_best,P2_best,W_best,Cp_best,dW,dW_pct,suspicious, ...
        'VariableNames', {'DOE_ID','Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target', ...
        'Saved_P1_MPa','Saved_P2_MPa','Saved_W_kW','Saved_Cp_mg_L', ...
        'ScanBest_P1_MPa','ScanBest_P2_MPa','ScanBest_W_kW','ScanBest_Cp_mg_L', ...
        'SavedMinusBest_kW','SavedMinusBest_pct','SuspiciousLocalBranch'});
    S.Saved_P1_MPa = repmat(P1_saved,height(S),1);
    S.Saved_P2_MPa = repmat(P2_saved,height(S),1);
    S.Saved_W_kW = repmat(W_saved,height(S),1);
    new_scans{i} = S;
end

new_results = new_results(~cellfun(@isempty,new_results));
new_scans = new_scans(~cellfun(@isempty,new_scans));
if isempty(new_results)
    New = table();
else
    New = vertcat(new_results{:});
end

%% PRIOR + YENI SONUCLARI BIRLESTIR
if isempty(Prior)
    Results = New;
elseif isempty(New)
    Results = Prior;
else
    Results = [Prior; New];
    [~, ia] = unique(Results.DOE_ID, 'last');
    Results = Results(sort(ia),:);
end

% Yalniz otomatik screen'den gecen candidate ID'lerini final tabloda tut.
Results = Results(ismember(Results.DOE_ID,C.DOE_ID),:);
Results = sortrows(Results,'DOE_ID');

if ~isempty(new_scans)
    ScanNew = vertcat(new_scans{:});
    writetable(ScanNew,'RO_ANN_truth_branch_audit_new_scans.csv');
end
writetable(C,'RO_ANN_truth_branch_risk_candidates.csv');
writetable(Results,'RO_ANN_truth_branch_audit_summary.csv');

fprintf('\n============================================================\n');
fprintf('BRANCH-RISK AUDIT SUMMARY\n');
fprintf('============================================================\n');
disp(Results);
fprintf('Candidate CSV : RO_ANN_truth_branch_risk_candidates.csv\n');
fprintf('Audit summary : RO_ANN_truth_branch_audit_summary.csv\n');
fprintf('NOTE: Truth dataset bu fonksiyon tarafindan DEGISTIRILMEDI.\n');
fprintf('============================================================\n');
end

function S = scan_p1_grid(P1_grid, DOE_ID, scan_level, Qf, Tin, Cf, Rt, cfg)
% Sabit input state icin P1 gridindeki her noktada N=150 P2 recovery root'u bulur.
n = numel(P1_grid);
P2=NaN(n,1); W=NaN(n,1); Cp=NaN(n,1); Rec=NaN(n,1); Rerr=NaN(n,1);
dP1=NaN(n,1); J1=NaN(n,1); PXex=NaN(n,1); Qhpp=NaN(n,1);
TargetMet=false(n,1); Physical=false(n,1); Success=false(n,1);
EvalCount=zeros(n,1); Failure=strings(n,1); Runtime=NaN(n,1);

parfor k=1:n
    tk=tic;
    rr=ro_find_P2_for_recovery(Qf,Tin,Cf,Rt,P1_grid(k),cfg,cfg.hybrid.final_N_segments,NaN);
    Runtime(k)=toc(tk);
    EvalCount(k)=rr.n_evaluations;
    Failure(k)=string(rr.failure_reason);
    if rr.target_met && ~isempty(rr.ev) && rr.ev.success
        ev=rr.ev;
        P2(k)=rr.P2_gauge_MPa;
        W(k)=ev.W_RO_kW;
        Cp(k)=ev.Cp_mg_L;
        Rec(k)=ev.Recovery;
        Rerr(k)=ev.Recovery-Rt;
        dP1(k)=ev.dP_stage1_MPa;
        J1(k)=ev.Jfirst_stage1_LMH;
        PXex(k)=ev.PX_excess_pressure_MPa;
        Qhpp(k)=ev.Qhpp_m3h;
        TargetMet(k)=abs(Rerr(k))<=cfg.optim.recovery_accept_tolerance;
        Physical(k)=ev.physical_feasible;
        Success(k)=true;
    end
end

S=table(repmat(DOE_ID,n,1),repmat(string(scan_level),n,1),P1_grid(:),P2,W,Cp,Rec,Rerr,TargetMet,Physical,Success,dP1,J1,PXex,Qhpp,EvalCount,Runtime,Failure, ...
    'VariableNames',{'DOE_ID','ScanLevel','P1_MPa','P2_MPa','W_kW','Cp_mg_L','Recovery','RecoveryError','TargetMet','PhysicalFeasible','Success','dP1_MPa','Jfirst1_LMH','PX_excess_MPa','Qhpp_m3h','RootEvalCount','Runtime_s','FailureReason'});
end
