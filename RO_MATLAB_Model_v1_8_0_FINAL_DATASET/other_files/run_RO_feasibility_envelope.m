function [Envelope, ProbeLog, BaseStates, Summary] = run_RO_feasibility_envelope() % v1.7.0 48-state Qf-T-Cf recovery-envelope mapping run'ini parallel checkpoint destegiyle baslatir.

%% BASLANGIC % Configuration, output isimleri ve deterministic base-state tablosunu yukler.

cfg = ro_ann_config(); % Validation, FastPX, FASTSEARCH ve envelope mapping configuration degerlerini yukler.
prefix = "RO_feasibility_envelope"; % Tum output/checkpoint dosyalari icin ortak prefix tanimlar.
checkpoint_file = prefix + "_partial.mat"; % State-level checkpoint MAT dosya adini tanimlar.
BaseStates = ro_generate_envelope_base_states(cfg.envelope.n_states, cfg); % 48 adet stratified Qf-T-Cf base state'i olusturur.
writetable(BaseStates, prefix + "_base_states.csv"); % Optimizer run oncesi base-state inputlarini traceability icin kaydeder.

fprintf('\n============================================================\n'); % Run baslangic ayiricisini yazdirir.
fprintf('RO v1.7.0 - FEASIBILITY ENVELOPE MAP\n'); % Run basligini yazdirir.
fprintf('============================================================\n'); % Run basligi alt ayiricisini yazdirir.
fprintf('Base states             : %d\n', height(BaseStates)); % Toplam Qf-T-Cf state sayisini yazdirir.
fprintf('Recovery coarse probes  : %d/state\n', cfg.envelope.n_R_coarse); % State basina coarse recovery probe sayisini yazdirir.
fprintf('Boundary bisection max  : %d/side\n', cfg.envelope.n_bisection); % Boundary basina maximum bisection iteration sayisini yazdirir.
fprintf('Boundary R tolerance    : %.4g\n', cfg.envelope.R_boundary_tolerance); % Recovery boundary tolerance degerini yazdirir.
fprintf('Parallelism             : state-level parfor; local profile worker sayisi kullanilir\n'); % Parallelization stratejisini aciklar.

%% CHECKPOINT / RESUME % Onceki ayni-state run yarida kaldiysa tamamlanan state'leri yukler; aksi halde bos result cell'leri olusturur.

n_states = height(BaseStates); % Toplam base-state sayisini alir.
EnvelopeCells = cell(n_states, 1); % Her state'in envelope struct sonucunu tutacak cell array'i olusturur.
ProbeCells = cell(n_states, 1); % Her state'in probe table sonucunu tutacak cell array'i olusturur.
Completed = false(n_states, 1); % Tamamlanan state flag vectorunu baslatir.
if cfg.envelope.resume_if_checkpoint_exists && isfile(checkpoint_file) % Resume acik ve checkpoint mevcutsa kontrol eder.
    S = load(checkpoint_file, 'BaseStates', 'EnvelopeCells', 'ProbeCells', 'Completed'); % Onceki checkpoint'in gerekli alanlarini yukler.
    if isfield(S, 'BaseStates') && height(S.BaseStates) == n_states && ...
            all(abs(S.BaseStates.Qf_train_m3h - BaseStates.Qf_train_m3h) < 1.0e-10) && ...
            all(abs(S.BaseStates.T_RO_in_C - BaseStates.T_RO_in_C) < 1.0e-10) && ...
            all(abs(S.BaseStates.Cf_kg_m3 - BaseStates.Cf_kg_m3) < 1.0e-10) % Checkpoint'in ayni deterministic state setine ait olup olmadigini kontrol eder.
        EnvelopeCells = S.EnvelopeCells; % Onceki state envelope sonuclarini geri yukler.
        ProbeCells = S.ProbeCells; % Onceki probe loglarini geri yukler.
        Completed = S.Completed; % Tamamlanan state flag'lerini geri yukler.
        fprintf('Checkpoint bulundu       : %d / %d state tamamlanmis, devam ediliyor.\n', sum(Completed), n_states); % Resume durumunu kullaniciya bildirir.
    else % Checkpoint state seti mevcut run ile uyusmuyorsa bu dali kullanir.
        fprintf('Checkpoint state seti farkli; temiz run baslatiliyor.\n'); % Eski checkpoint'in kullanilmadigini aciklar.
    end % Checkpoint compatibility kontrolunu sonlandirir.
end % Checkpoint-exists kosulunu sonlandirir.

%% PARALLEL POOL % Toolbox varsa kullanicinin local profile'inda tanimli worker sayisi ile pool'u baslatir.

use_parallel = cfg.compute.use_parallel && license('test', 'Distrib_Computing_Toolbox'); % Parallel Computing Toolbox lisans ve config durumunu kontrol eder.
if use_parallel % Parallel run etkinse kontrol eder.
    pool = gcp('nocreate'); % Mevcut parallel pool varsa alir.
    if isempty(pool) % Aktif pool yoksa kontrol eder.
        pool = parpool('Processes'); % Local Processes profile'ini varsayilan worker sayisi ile baslatir.
    end % Pool creation kosulunu sonlandirir.
    fprintf('Parallel pool           : %d workers\n', pool.NumWorkers); % Aktif worker sayisini yazdirir.
else % Parallel toolbox/config kullanilmiyorsa bu dali kullanir.
    fprintf('Parallel pool           : kapali, serial run\n'); % Serial run durumunu yazdirir.
end % Parallel setup branch'ini sonlandirir.

%% STATE BATCH LOOP % Tamamlanmamis base state'leri checkpoint batch'leri halinde cozer.

pending = find(~Completed); % Henuz tamamlanmamis state indexlerini bulur.
batch_size = cfg.envelope.batch_states; % State-level checkpoint batch boyutunu configuration'dan alir.
for ib0 = 1:batch_size:numel(pending) % Pending state'leri fixed-size batch'ler halinde gezer.
    batch_idx = pending(ib0:min(ib0 + batch_size - 1, numel(pending))); % Bu batch'te cozulacak global state indexlerini alir.
    fprintf('\nState batch %d-%d / %d basliyor...\n', batch_idx(1), batch_idx(end), n_states); % Batch progress mesajini yazdirir.
    t_batch = tic; % Batch wall-clock timer'ini baslatir.
    EnvBatch = cell(numel(batch_idx), 1); % Batch envelope outputs icin temporary cell array olusturur.
    ProbeBatch = cell(numel(batch_idx), 1); % Batch probe logs icin temporary cell array olusturur.
    if use_parallel % State-level parfor etkinse kontrol eder.
        parfor jb = 1:numel(batch_idx) % Batch state'lerini workers arasinda paralel dagitir.
            i = batch_idx(jb); % Global state indexini alir.
            [EnvBatch{jb}, ProbeBatch{jb}] = ro_map_recovery_envelope_state( ...
                BaseStates.State_ID(i), BaseStates.State_Type(i), BaseStates.Qf_train_m3h(i), ...
                BaseStates.T_RO_in_C(i), BaseStates.Cf_kg_m3(i), cfg); % Tek Qf-T-Cf state'in recovery envelope'unu haritalar.
        end % State-level parfor loop'unu sonlandirir.
    else % Serial execution secildiyse bu dali kullanir.
        for jb = 1:numel(batch_idx) % Batch state'lerini seri gezer.
            i = batch_idx(jb); % Global state indexini alir.
            [EnvBatch{jb}, ProbeBatch{jb}] = ro_map_recovery_envelope_state( ...
                BaseStates.State_ID(i), BaseStates.State_Type(i), BaseStates.Qf_train_m3h(i), ...
                BaseStates.T_RO_in_C(i), BaseStates.Cf_kg_m3(i), cfg); % Tek Qf-T-Cf state'in recovery envelope'unu haritalar.
        end % Serial state loop'unu sonlandirir.
    end % Parallel/serial branch'ini sonlandirir.
    for jb = 1:numel(batch_idx) % Batch sonu temporary outputs'u global checkpoint cell arrays'e aktarir.
        i = batch_idx(jb); % Global state indexini alir.
        EnvelopeCells{i} = EnvBatch{jb}; % State envelope struct sonucunu kaydeder.
        ProbeCells{i} = ProbeBatch{jb}; % State probe table sonucunu kaydeder.
        Completed(i) = true; % State'i tamamlanmis olarak isaretler.
    end % Batch-output merge loop'unu sonlandirir.
    save(checkpoint_file, 'BaseStates', 'EnvelopeCells', 'ProbeCells', 'Completed', 'cfg', '-v7.3'); % Her batch sonunda resumable MAT checkpoint yazar.
    [EnvelopePartial, ProbePartial] = assemble_results(EnvelopeCells, ProbeCells, Completed); % Tamamlanan state'leri partial tables haline getirir.
    writetable(EnvelopePartial, prefix + "_partial.csv"); % Partial state-level envelope CSV dosyasini gunceller.
    writetable(ProbePartial, prefix + "_probes_partial.csv"); % Partial probe-log CSV dosyasini gunceller.
    fprintf('Batch tamamlandi         : %.1f s | feasible band %d/%d | total complete %d/%d\n', ...
        toc(t_batch), sum(EnvBatch_has_band(EnvBatch)), numel(batch_idx), sum(Completed), n_states); % Batch runtime ve feasibility progress bilgisini yazdirir.
end % State-batch loop'unu sonlandirir.

%% FINAL ASSEMBLY % Tum completed state/probe sonuclarini final tables haline getirir ve CSV/MAT outputlarini yazar.

[Envelope, ProbeLog] = assemble_results(EnvelopeCells, ProbeCells, Completed); % Tum state-level ve probe-level results tablolarini birlestirir.
writetable(Envelope, prefix + ".csv"); % Final feasible recovery-envelope table'ini CSV olarak yazar.
writetable(ProbeLog, prefix + "_probes.csv"); % Tum recovery probe diagnostics table'ini CSV olarak yazar.
save(prefix + ".mat", 'Envelope', 'ProbeLog', 'BaseStates', 'cfg', '-v7.3'); % Final MATLAB artifact'ini reproducibility icin kaydeder.

%% SUMMARY % ANN dataset domainini secmeden once envelope results'i otomatik olarak raporlar.

Summary = ro_summarize_feasibility_envelope(Envelope, ProbeLog, prefix); % State types, boundaries, failures ve runtime ozetlerini hesaplar/yazar.
fprintf('\nEnvelope mapping tamamlandi. ANN training henuz baslatilmadi.\n'); % Bu surumun hala domain-mapping asamasi oldugunu aciklar.
fprintf('Ana dosya               : %s.csv\n', prefix); % Kullaniciya paylasmasi gereken state-level envelope dosyasini bildirir.
fprintf('Probe diagnostics        : %s_probes.csv\n', prefix); % Gerekirse paylasilacak detailed probe log dosyasini bildirir.

end % Feasibility-envelope runner fonksiyonunu sonlandirir.

function [Envelope, ProbeLog] = assemble_results(EnvelopeCells, ProbeCells, Completed) % Tamamlanan cell outputs'u iki standard table halinde birlestirir.
idx = find(Completed); % Tamamlanan state indexlerini alir.
if isempty(idx) % Hic state tamamlanmadiysa kontrol eder.
    Envelope = table(); % Bos envelope table dondurur.
    ProbeLog = table(); % Bos probe table dondurur.
    return; % Helper fonksiyonundan cikar.
end % Empty-completion kontrolunu sonlandirir.
env_structs = vertcat(EnvelopeCells{idx}); % Tamamlanan envelope struct'larini tek struct array halinde birlestirir.
Envelope = struct2table(env_structs); % State-level struct array'ini table'a cevirir.
ProbeLog = ProbeCells{idx(1)}; % Probe table birlestirmesini ilk completed state ile baslatir.
for k = 2:numel(idx) % Kalan completed state probe tablolarini gezer.
    ProbeLog = [ProbeLog; ProbeCells{idx(k)}]; %#ok<AGROW> % Ayni kolonlu probe tablolarini dikey birlestirir.
end % Probe-table concatenation loop'unu sonlandirir.
end % Result-assembly helper fonksiyonunu sonlandirir.

function n = EnvBatch_has_band(EnvBatch) % Batch cell array icinde feasible-band flag sayisini hesaplar.
n = 0; % Feasible-band sayacini sifirdan baslatir.
for k = 1:numel(EnvBatch) % Batch envelope cell'lerini gezer.
    if ~isempty(EnvBatch{k}) && isfield(EnvBatch{k}, 'HasFeasibleBand') && EnvBatch{k}.HasFeasibleBand % State result'i mevcut ve feasible band ise kontrol eder.
        n = n + 1; % Feasible-band sayacini bir arttirir.
    end % State feasibility kosulunu sonlandirir.
end % Batch-cell loop'unu sonlandirir.
end % Batch feasible-count helper fonksiyonunu sonlandirir.
