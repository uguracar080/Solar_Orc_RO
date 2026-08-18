function Dataset = ro_generate_training_dataset(DOE, cfg, output_stem) % DOE tablosundaki her nokta icin optimized detailed truth-model dataset'i checkpoint'lerle uretir.

%% GIRDI KONTROLLERI % Configuration ve output name girdilerini varsayilan degerlerle tamamlar.

if nargin < 2 || isempty(cfg) % Configuration struct verilmemisse kontrol eder.
    cfg = ro_ann_config(); % Varsayilan ANN configuration degerlerini yukler.
end % Configuration input kontrolunu sonlandirir.
if nargin < 3 || strlength(string(output_stem)) == 0 % Output stem verilmemisse kontrol eder.
    output_stem = 'RO_ANN_dataset'; % Varsayilan dataset file stem degerini tanimlar.
end % Output-stem input kontrolunu sonlandirir.

output_stem = char(output_stem); % File path islemleri icin output stem degerini char tipine cevirir.
partial_mat = [output_stem '_partial.mat']; % Resume/checkpoint MAT file adini olusturur.
final_mat = [output_stem '.mat']; % Final MAT dataset file adini olusturur.
final_csv = [output_stem '.csv']; % Final CSV dataset file adini olusturur.

%% RESUME / PREALLOCATION % Onceki partial run varsa kaldigi yerden devam eder, yoksa bos result struct dizisi olusturur.

template = ro_dataset_row_template(); % parfor ve struct-array preallocation icin bos row template'ini yukler.
n_total = height(DOE); % Toplam DOE point sayisini alir.
Results = repmat(template, n_total, 1); % Tum DOE satirlari icin sabit boyutlu result struct array olusturur.
last_completed = 0; % Yeni run icin tamamlanan son index degerini sifirlar.

if isfile(partial_mat) % Ayni output stem'e ait checkpoint file mevcutsa kontrol eder.
    S = load(partial_mat, 'Results', 'last_completed', 'DOE_saved'); % Onceki result array ve resume index degerini yukler.
    if isfield(S, 'DOE_saved') && height(S.DOE_saved) == n_total % Checkpoint DOE boyutu mevcut run ile uyumluysa kontrol eder.
        Results = S.Results; % Onceki hesaplanmis result array degerlerini geri yukler.
        last_completed = S.last_completed; % Son tamamlanan DOE index degerini geri yukler.
        fprintf('Checkpoint bulundu. DOE %d sonrasindan devam ediliyor.\n', last_completed); % Resume bilgisini kullaniciya yazdirir.
    else % Checkpoint mevcut ancak DOE ile uyumsuzsa bu dali kullanir.
        error('Mevcut partial MAT dosyasi bu DOE ile uyumlu degil. Output stem''i degistirin veya eski partial dosyayi kaldirin.'); % Yanlis resume riskini onler.
    end % Checkpoint-compatibility kosulunu sonlandirir.
end % Checkpoint-existence kosulunu sonlandirir.

%% PARALLEL MODE % Outer DOE noktalarini bagimsiz process workers uzerinde calistirmayi hazirlar.

use_parallel = false; % Varsayilan hesaplama modunu sequential tanimlar.
if cfg.compute.use_parallel && license('test', 'Distrib_Computing_Toolbox') % Kullanici paralellik istediyse ve toolbox license mevcutsa kontrol eder.
    use_parallel = true; % Dataset loop'unu parfor moduna alir.
    if isempty(gcp('nocreate')) % Mevcut parallel pool olup olmadigini kontrol eder.
        parpool('local'); % Varsayilan local process-based parallel pool'u baslatir.
    end % Parallel-pool kosulunu sonlandirir.
end % Parallel-mode kosulunu sonlandirir.

%% BATCHED DATASET GENERATION % Uzun run boyunca belirli araliklarla checkpoint kaydederek DOE noktalarini cozer.

batch_size = max(round(cfg.compute.batch_size), 1); % Checkpoint batch size degerini pozitif tam sayiya cevirir.
first_index = last_completed + 1; % Bu run'da ilk cozulacak DOE index degerini hesaplar.

for batch_start = first_index:batch_size:n_total % Tum kalan DOE noktalarini batch'ler halinde gezer.
    batch_end = min(batch_start + batch_size - 1, n_total); % Mevcut batch'in son index degerini hesaplar.
    idx = batch_start:batch_end; % Mevcut batch DOE index vectorunu olusturur.
    batch_rows = repmat(template, numel(idx), 1); % Batch result struct array'ini preallocate eder.

    fprintf('DOE batch %d-%d / %d basliyor...\n', batch_start, batch_end, n_total); % Batch progress bilgisini yazdirir.
    tic; % Batch execution time olcumunu baslatir.

    if use_parallel % Parallel mode etkinse bu dali kullanir.
        parfor k = 1:numel(idx) % Batch DOE noktalarini process workers arasinda parallel cozer.
            ii = idx(k); % Global DOE row index degerini alir.
            if isfield(cfg.optim, 'method') && strcmpi(cfg.optim.method, 'hybrid') % Root-seeded hybrid optimizer ana yontem olarak seciliyse kontrol eder.
                batch_rows(k) = ro_optimize_train_point_hybrid(DOE.DOE_ID(ii), DOE.DOE_Type(ii), DOE.Qf_train_m3h(ii), DOE.T_RO_in_C(ii), DOE.Cf_kg_m3(ii), DOE.R_target(ii), cfg); % Recovery-root seed ve tek lokal fmincon ile pressure optimization yapar.
            elseif isfield(cfg.optim, 'method') && strcmpi(cfg.optim.method, 'root1d') % Saf root-based optimizer isteniyorsa kontrol eder.
                batch_rows(k) = ro_optimize_train_point_root(DOE.DOE_ID(ii), DOE.DOE_Type(ii), DOE.Qf_train_m3h(ii), DOE.T_RO_in_C(ii), DOE.Cf_kg_m3(ii), DOE.R_target(ii), cfg); % Recovery-manifold uzerinde root-based pressure optimization yapar.
            else % Legacy fmincon optimizer isteniyorsa bu dali kullanir.
                batch_rows(k) = ro_optimize_train_point(DOE.DOE_ID(ii), DOE.DOE_Type(ii), DOE.Qf_train_m3h(ii), DOE.T_RO_in_C(ii), DOE.Cf_kg_m3(ii), DOE.R_target(ii), cfg); % Legacy iki-degiskenli fmincon pressure optimization sonucunu hesaplar.
            end % Optimizer-method secimini sonlandirir.
        end % Parallel batch loop'unu sonlandirir.
    else % Parallel toolbox yoksa sequential mode kullanir.
        for k = 1:numel(idx) % Batch DOE noktalarini sirayla cozer.
            ii = idx(k); % Global DOE row index degerini alir.
            if isfield(cfg.optim, 'method') && strcmpi(cfg.optim.method, 'hybrid') % Root-seeded hybrid optimizer ana yontem olarak seciliyse kontrol eder.
                batch_rows(k) = ro_optimize_train_point_hybrid(DOE.DOE_ID(ii), DOE.DOE_Type(ii), DOE.Qf_train_m3h(ii), DOE.T_RO_in_C(ii), DOE.Cf_kg_m3(ii), DOE.R_target(ii), cfg); % Recovery-root seed ve tek lokal fmincon ile pressure optimization yapar.
            elseif isfield(cfg.optim, 'method') && strcmpi(cfg.optim.method, 'root1d') % Saf root-based optimizer isteniyorsa kontrol eder.
                batch_rows(k) = ro_optimize_train_point_root(DOE.DOE_ID(ii), DOE.DOE_Type(ii), DOE.Qf_train_m3h(ii), DOE.T_RO_in_C(ii), DOE.Cf_kg_m3(ii), DOE.R_target(ii), cfg); % Recovery-manifold uzerinde root-based pressure optimization yapar.
            else % Legacy fmincon optimizer isteniyorsa bu dali kullanir.
                batch_rows(k) = ro_optimize_train_point(DOE.DOE_ID(ii), DOE.DOE_Type(ii), DOE.Qf_train_m3h(ii), DOE.T_RO_in_C(ii), DOE.Cf_kg_m3(ii), DOE.R_target(ii), cfg); % Legacy iki-degiskenli fmincon pressure optimization sonucunu hesaplar.
            end % Optimizer-method secimini sonlandirir.
        end % Sequential batch loop'unu sonlandirir.
    end % Parallel/sequential execution kosulunu sonlandirir.

    Results(idx) = batch_rows; % Tamamlanan batch result satirlarini global struct array'e aktarir.
    last_completed = batch_end; % Resume index degerini mevcut batch sonuna gunceller.
    DOE_saved = DOE; %#ok<NASGU> % Checkpoint ile birlikte input DOE tablosunu kaydetmek icin alias olusturur.
    save(partial_mat, 'Results', 'last_completed', 'DOE_saved', 'cfg', '-v7.3'); % Her batch sonunda crash-safe checkpoint MAT file yazar.

    elapsed_s = toc; % Mevcut batch execution time degerini saniye olarak alir.
    valid_batch = sum([batch_rows.DatasetValid]); % Batch icindeki valid regression-point sayisini hesaplar.
    fprintf('Batch tamamlandi: %.1f s | Valid %d/%d\n', elapsed_s, valid_batch, numel(batch_rows)); % Batch runtime ve feasibility ozetini yazdirir.
end % Batched dataset-generation loop'unu sonlandirir.

%% FINAL TABLE VE DOSYALAR % Flat struct array'i MATLAB table ve CSV/MAT dosyalarina donusturur.

Dataset = struct2table(Results); % Tum result struct satirlarini MATLAB table object'ine cevirir.
save(final_mat, 'Dataset', 'DOE', 'cfg', '-v7.3'); % Full-precision final dataset ve configuration'i MAT file olarak kaydeder.
writetable(Dataset, final_csv); % Inceleme ve Python/Excel islemleri icin flat CSV dataset yazar.

%% RUN OZETI % Dataset validity ve en sik failure nedenlerini Command Window'da raporlar.

n_valid = sum(Dataset.DatasetValid); % Regression ANN icin valid sample sayisini hesaplar.
fprintf('\nDataset tamamlandi: %d / %d valid point (%.1f%%).\n', n_valid, n_total, 100.0 * n_valid / n_total); % Overall valid fraction degerini yazdirir.
if n_valid > 0 % En az bir valid point varsa basic output ranges raporlar.
    Dv = Dataset(Dataset.DatasetValid, :); % Sadece valid regression rows'u secer.
    fprintf('Valid Qp range : %.3f - %.3f m3/h\n', min(Dv.Qp_train_m3h), max(Dv.Qp_train_m3h)); % Valid permeate production range degerini yazdirir.
    fprintf('Valid W range  : %.3f - %.3f kW\n', min(Dv.W_RO_train_kW), max(Dv.W_RO_train_kW)); % Valid RO power range degerini yazdirir.
    fprintf('Valid Cp range : %.2f - %.2f mg/L\n', min(Dv.Cp_mg_L), max(Dv.Cp_mg_L)); % Valid product salinity range degerini yazdirir.
    fprintf('Valid SEC range: %.3f - %.3f kWh/m3\n', min(Dv.SEC_kWh_m3), max(Dv.SEC_kWh_m3)); % Valid SEC range degerini yazdirir.
end % Valid-range reporting kosulunu sonlandirir.

end % Batched training-dataset generator fonksiyonunu sonlandirir.
