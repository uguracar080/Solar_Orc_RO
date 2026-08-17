function [score, nearest_dist] = ro_knn_probe_feasibility_score(Xquery, Xprior, yprior, cfg) % Existing envelope probe log'unu yalnizca DOE proposal gate'i olarak kullanan toolbox-free kNN feasibility score hesaplar.

%% GIRDI SEKILLERI % Tum inputlari double matrix/vector formatina getirir.
Xquery = double(Xquery); % Query [Qf,T,Cf,R] matrix'ini double tipine cevirir.
Xprior = double(Xprior); % Prior probe [Qf,T,Cf,R] matrix'ini double tipine cevirir.
yprior = double(yprior(:)); % Prior DatasetValid flag'lerini column double vector haline getirir.

%% NORMALIZASYON % Dort boyutun mesafe hesabinda benzer olcekte katkida bulunmasini saglar.
lb = double(cfg.guided.norm_lb(:).'); % Normalization lower-bound vectorunu row vector olarak alir.
ub = double(cfg.guided.norm_ub(:).'); % Normalization upper-bound vectorunu row vector olarak alir.
span = max(ub - lb, 1.0e-12); % Sifir aralik riskini onleyen normalization span vectorunu hesaplar.
Xq = (Xquery - lb) ./ span; % Query noktalarini normalize eder.
Xp = (Xprior - lb) ./ span; % Prior probe noktalarini ayni olcekte normalize eder.

%% KNN AYARLARI % Cross-state diagnostic sonuclariyla secilen komsu sayisi ve agirlik kuvvetini yukler.
k = min(max(round(cfg.guided.knn_k), 1), size(Xp, 1)); % Kullanilabilir prior sayisini asmayan k degerini belirler.
power = cfg.guided.knn_weight_power; % Inverse-distance weighting kuvvetini alir.
chunk_size = max(round(cfg.guided.knn_chunk_size), 1); % Bellek kullanimi icin query chunk boyutunu belirler.
score = NaN(size(Xq, 1), 1); % Her query icin feasibility proposal score vectorunu preallocate eder.
nearest_dist = NaN(size(Xq, 1), 1); % Her query icin en yakin prior normalized distance vectorunu preallocate eder.

%% CHUNKED DISTANCE HESABI % Buyuk candidate pool'da tum distance matrixini tek seferde bellekte tutmadan score hesaplar.
prior_norm2 = sum(Xp.^2, 2).'; % Matrix-distance identity icin prior squared norm row vectorunu hesaplar.
for i0 = 1:chunk_size:size(Xq, 1) % Query noktalarini chunk'lar halinde gezer.
    i1 = min(i0 + chunk_size - 1, size(Xq, 1)); % Mevcut chunk'in son indexini hesaplar.
    Xc = Xq(i0:i1, :); % Mevcut query chunk'ini alir.
    D2 = sum(Xc.^2, 2) + prior_norm2 - 2.0 * (Xc * Xp.'); % Tum query-prior squared Euclidean distance'lerini hesaplar.
    D2 = max(D2, 0.0); % Floating-point round-off kaynakli cok kucuk negatif distance degerlerini sifira clip eder.
    [D2k, Ik] = mink(D2, k, 2); % Her query icin k en yakin prior probe'u bulur.
    W = 1.0 ./ (D2k.^(0.5 * power) + 1.0e-8); % Inverse-distance agirliklarini hesaplar.
    Yk = yprior(Ik); % Komsu probe'larin valid/infeasible label'larini alir.
    score(i0:i1) = sum(W .* Yk, 2) ./ sum(W, 2); % Weighted valid fraction'i proposal feasibility score olarak hesaplar.
    nearest_dist(i0:i1) = sqrt(D2k(:, 1)); % En yakin prior probe distance'ini diagnostic olarak kaydeder.
end % Chunk loop'unu sonlandirir.

end % kNN proposal-score fonksiyonunu sonlandirir.
