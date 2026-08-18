function root = ro_find_P2_for_recovery(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, R_target, P1_gauge_MPa, cfg, N_segments, P2_hint_MPa, recovery_tol_override) % Sabit P1 icin P2'yi recovery target'i saglayacak sekilde bracket+hybrid root solve ile bulur.

%% OPSIYONEL GIRDI % P2 hint verilmediginde tum izinli P2 araligini global probe ile tarar.

if nargin < 8 || isempty(P2_hint_MPa) % P2 hint inputu verilmediyse kontrol eder.
    P2_hint_MPa = NaN; % Hint olmadigini NaN ile temsil eder.
end % Optional hint kontrolunu sonlandirir.
if nargin < 9 || isempty(recovery_tol_override) % Ozel recovery tolerance verilmediyse kontrol eder.
    recovery_tol_override = NaN; % Override olmadigini NaN ile temsil eder.
end % Optional tolerance override kontrolunu sonlandirir.

%% OUTPUT TEMPLATE % Root aramasi basarisiz olsa bile diagnostic bilgileri eksiksiz dondurur.

root.success = false; % Baslangicta recovery root bulunmadigini kabul eder.
root.target_met = false; % Baslangicta recovery target'in saglanmadigini kabul eder.
root.P1_gauge_MPa = P1_gauge_MPa; % Sabit Stage-1 pressure degerini kaydeder.
root.P2_gauge_MPa = NaN; % Root sonucu Stage-2 pressure degerini baslangicta NaN tanimlar.
root.recovery_error = NaN; % Final recovery error degerini baslangicta NaN tanimlar.
root.ev = []; % Final detailed evaluation struct'ini baslangicta bos tanimlar.
root.n_evaluations = 0; % Bu root aramasinda yapilan benzersiz detailed model evaluation sayacini sifirlar.
root.bracket_found = false; % Baslangicta sign-changing recovery bracket bulunmadigini kabul eder.
root.failure_reason = ""; % Baslangicta failure reason alanini bos birakir.
root.bracket_P2_MPa = [NaN, NaN]; % Kullanilan root bracket pressure degerlerini baslangicta NaN tanimlar.
root.bracket_recovery_error = [NaN, NaN]; % Bracket uc recovery error degerlerini baslangicta NaN tanimlar.

%% GRID VE TOLERANS % Coarse ve final cozum icin ayni fizik modelini yalnizca axial resolution farkiyla kullanir.

cfg_eval = cfg; % Configuration struct'ini bu root aramasi icin kopyalar.
cfg_eval.model.N_segments = N_segments; % Istenen axial segment sayisini evaluation modeline uygular.
if isfinite(recovery_tol_override) % Cagiran fonksiyon ozel recovery tolerance verdiyse kontrol eder.
    recovery_tol = recovery_tol_override; % Seed-transfer gibi ara islemlerde override toleransini kullanir.
elseif N_segments >= cfg.root.final_N_segments % Final truth-grid cozumunde hangi recovery toleransinin kullanilacagini kontrol eder.
    recovery_tol = cfg.root.recovery_tol_final; % N=150 final root icin daha siki recovery toleransini kullanir.
else % Coarse root cozumunde bu dali kullanir.
    recovery_tol = cfg.root.recovery_tol_coarse; % N=30 root icin daha gevsek ama yeterli toleransi kullanir.
end % Grid-bazli recovery tolerance secimini sonlandirir.

%% DINAMIK P2 BOUNDS % Feasible bir noktada Stage-1 dP<=0.35 olacagi bilgisini kullanarak gereksiz dusuk P2 bolgesini azaltir.

mem = ro_apply_membrane_age_du2014(ro_membrane_SW30XLE400(), cfg.model.age_years); % Ayni technical-limit membrane struct'ini yukler.
P2_lb = max(cfg.root.P2_lb_MPa, P1_gauge_MPa - mem.max_PV_pressure_drop_MPa); % Feasible interstage booster icin necessary P2 lower bound degerini olusturur.
P2_ub = cfg.root.P2_ub_MPa; % Stage-2 maximum pressure search upper bound degerini alir.
if P2_lb > P2_ub % Dinamik lower bound maximum pressure'i asarsa kontrol eder.
    root.failure_reason = "P2_dynamic_bounds_empty"; % Bos P2 araligini failure reason olarak kaydeder.
    return; % Root aramasini yapmadan fonksiyondan cikar.
end % P2 bound kontrolunu sonlandirir.

%% EVALUATION CACHE % Hint, global probe ve hybrid iterations arasinda ayni P2 noktasini ikinci kez cozmeyi engeller.

cache_P2 = zeros(0, 1); % Daha once cozulmus P2 pressure degerlerini bos vector olarak baslatir.
cache_ev = cell(0, 1); % Daha once cozulmus detailed evaluation struct'larini bos cell array olarak baslatir.
best_ev = []; % Target recovery'ye en yakin finite evaluation'i baslangicta bos tanimlar.
best_P2 = NaN; % Target'a en yakin P2 degerini baslangicta NaN tanimlar.
best_abs_g = inf; % En kucuk absolute recovery mismatch degerini sonsuzla baslatir.

%% COARSE P2-MAX REACHABILITY SCREEN % Hint olmayan N=30 seed aramasinda maksimum P2 bile hedef recovery'ye yetmiyorsa kok aramasini tek evaluation ile sonlandirir.

if ~isfinite(P2_hint_MPa) && N_segments < cfg.root.final_N_segments % Yalnizca coarse global root search'te bu hizli necessary screen'i uygular.
    [ev_ub_screen, g_ub_screen] = evaluate_g(P2_ub); % Manufacturer maximum Stage-2 pressure noktasinda erisilebilen recovery'yi hesaplar.
    numerical_screen_ok = ~isempty(ev_ub_screen) && ev_ub_screen.success && ...
        isfield(ev_ub_screen, 'sys') && ev_ub_screen.sys.converged && ...
        ev_ub_screen.Stage1_all_local_converged && ev_ub_screen.Stage2_all_local_converged && ...
        ~ev_ub_screen.Stage1_flow_clip_active && ~ev_ub_screen.Stage2_flow_clip_active; % Monoton recovery yorumu icin evaluation'in sayisal olarak temiz oldugunu kontrol eder.
    if numerical_screen_ok && isfinite(g_ub_screen) && g_ub_screen < -recovery_tol % Maximum P2'de bile recovery target'in altinda kaliyor ise kontrol eder.
        root.ev = ev_ub_screen; % P2 upper-bound evaluation'ini diagnostic output olarak kaydeder.
        root.P2_gauge_MPa = P2_ub; % Maximum Stage-2 pressure degerini diagnostic olarak kaydeder.
        root.recovery_error = g_ub_screen; % Maximum P2 recovery eksigini kaydeder.
        root.failure_reason = "recovery_unreachable_at_P2_max"; % Daha fazla P2 probe gerektirmeyen reachability failure nedenini tanimlar.
        return; % Tek evaluation sonrasi bu P1 icin root aramasini sonlandirir.
    end % P2-max reachability failure kosulunu sonlandirir.
end % Coarse reachability screen kosulunu sonlandirir.

%% HINT-CENTERED FAST BRACKET % N=30'dan gelen P2 tahmini varsa once yalnizca yakindaki pressure noktalarini genisleterek bracket arar.

bracket_found = false; % Local/global bracket search ortak flag degerini false baslatir.
a = NaN; b = NaN; ga = NaN; gb = NaN; % Root bracket endpoint degerlerini baslangicta NaN tanimlar.

if isfinite(P2_hint_MPa) % Kullanilabilir P2 hint varsa kontrol eder.
    p0 = min(max(P2_hint_MPa, P2_lb), P2_ub); % Hint degerini dynamic pressure bounds icine clip eder.
    [ev0, g0] = evaluate_g(p0); % Hint noktasinda recovery-minus-target degerini hesaplar.
    if isfinite(g0) && abs(g0) <= recovery_tol % N=30 hint N=150'de de target'i zaten sagliyorsa kontrol eder.
        set_success(p0, ev0, g0, [p0, p0], [g0, g0]); % Exact-hint root sonucunu output struct'a aktarir.
        return; % Daha fazla model evaluation yapmadan fonksiyondan cikar.
    end % Exact-hint acceptance kosulunu sonlandirir.

    if isfinite(g0) % Hint evaluation finite ise yonlu bracket expansion uygular.
        if g0 < 0.0 % Actual recovery target'in altindaysa kontrol eder.
            preferred_direction = +1.0; % Genellikle P2 arttikca recovery arttigi icin once yukari pressure yonunu dener.
        else % Actual recovery target'in ustundeyse bu dali kullanir.
            preferred_direction = -1.0; % Genellikle P2 azaltarak recovery'yi dusurmek icin once asagi pressure yonunu dener.
        end % Preferred expansion direction secimini sonlandirir.

        step0 = 0.10; % Hint cevresindeki ilk pressure expansion adimini MPa cinsinden tanimlar.
        [bracket_found, a, b, ga, gb] = expand_from_hint(p0, g0, preferred_direction, step0); % Beklenen monoton yon boyunca geometrik bracket genisletmesi yapar.
        if ~bracket_found % Beklenen yonde bracket bulunamadiysa kontrol eder.
            [bracket_found, a, b, ga, gb] = expand_from_hint(p0, g0, -preferred_direction, step0); % Monotonluk veya hint sapmasina karsi ters yonu da dener.
        end % Opposite-direction fallback kosulunu sonlandirir.
    end % Finite hint evaluation kosulunu sonlandirir.
end % Hint-centered bracket search kosulunu sonlandirir.

%% GLOBAL BRACKET FALLBACK % Hint yoksa veya local expansion target'i bracketleyemezse tum P2 araliginda az sayida deterministic probe kullanir.

if ~bracket_found % Local hint bracket'i bulunmadiysa kontrol eder.
    P2_probe = linspace(P2_lb, P2_ub, cfg.root.n_P2_bracket); % Dynamic search araligini az sayida global probe noktasina boler.
    g_probe = NaN(numel(P2_probe), 1); % Global probe recovery error vectorunu baslatir.
    ev_probe = cell(numel(P2_probe), 1); % Global probe evaluation cell array'ini baslatir.

    for k = 1:numel(P2_probe) % Tum global P2 probe noktalarini sirayla gezer.
        [ev_probe{k}, g_probe(k)] = evaluate_g(P2_probe(k)); % Mevcut probe recovery error degerini hesaplar.
        if isfinite(g_probe(k)) && abs(g_probe(k)) <= recovery_tol % Probe noktasi exact-enough root ise kontrol eder.
            set_success(P2_probe(k), ev_probe{k}, g_probe(k), [P2_probe(k), P2_probe(k)], [g_probe(k), g_probe(k)]); % Probe root'u final sonuc yapar.
            return; % Hybrid root iterations gerekmeksizin fonksiyondan cikar.
        end % Exact global-probe root kosulunu sonlandirir.
    end % Global probe evaluation dongusunu sonlandirir.

    for k = 1:(numel(P2_probe) - 1) % Adjacent global probe ciftlerini sirayla kontrol eder.
        if isfinite(g_probe(k)) && isfinite(g_probe(k + 1)) && g_probe(k) * g_probe(k + 1) < 0.0 % Target recovery iki adjacent pressure arasinda bracketleniyorsa kontrol eder.
            a = P2_probe(k); % Lower pressure bracket endpoint degerini tanimlar.
            b = P2_probe(k + 1); % Upper pressure bracket endpoint degerini tanimlar.
            ga = g_probe(k); % Lower endpoint recovery error degerini tanimlar.
            gb = g_probe(k + 1); % Upper endpoint recovery error degerini tanimlar.
            bracket_found = true; % Sign-changing bracket bulundu flag'ini true yapar.
            break; % Ilk adjacent sign-change bracket'i bulduktan sonra global taramadan cikar.
        end % Global sign-change kosulunu sonlandirir.
    end % Global bracket taramasini sonlandirir.
end % Global-bracket fallback kosulunu sonlandirir.

%% BRACKET YOKSA DIAGNOSTIC FAILURE % Target recovery P2 araliginda bulunamiyorsa en yakin finite pressure noktasini geri dondurur.

if ~bracket_found % Local ve global aramalarda sign-changing bracket bulunamadiysa kontrol eder.
    if isempty(best_ev) % Hicbir finite detailed evaluation uretilmediyse kontrol eder.
        root.failure_reason = "no_finite_P2_probe"; % Sayisal root failure nedenini kaydeder.
    else % Finite evaluations var ancak target bracketlenmiyorsa bu dali kullanir.
        root.ev = best_ev; % Target'a en yakin finite evaluation'i diagnostic olarak kaydeder.
        root.P2_gauge_MPa = best_P2; % En yakin pressure degerini diagnostic olarak kaydeder.
        root.recovery_error = best_ev.Recovery - R_target; % En yakin recovery mismatch degerini kaydeder.
        root.failure_reason = "recovery_not_bracketed_in_P2"; % P2 search araliginda recovery root olmadigini kaydeder.
    end % Finite/nonfinite failure turunu sonlandirir.
    return; % Root failure sonucuyla fonksiyondan cikar.
end % Bracket availability kontrolunu sonlandirir.

root.bracket_found = true; % Root bracket'i bulundu flag degerini output'a kaydeder.
root.bracket_P2_MPa = [a, b]; % Ilk sign-changing bracket pressure endpointlerini kaydeder.
root.bracket_recovery_error = [ga, gb]; % Ilk bracket recovery-error endpointlerini kaydeder.

%% HYBRID SECANT-BISECTION ROOT % Recovery(P2) yaklasik duzgun oldugu icin secant interpolation'i kullanir, bracket guvenligi icin bisection fallback uygular.

for iter = 1:cfg.root.max_bisection_iterations % Maksimum hybrid root iteration sayisina kadar cozum yapar.
    if abs(gb - ga) > 1.0e-14 % Secant denominator yeterince buyukse kontrol eder.
        p_try = (a * gb - b * ga) / (gb - ga); % Bracket endpointlerinden linear-interpolation/secant root tahmini hesaplar.
    else % Recovery slope sayisal olarak sifira yakin ise bu dali kullanir.
        p_try = 0.5 * (a + b); % Guvenli midpoint bisection adimini kullanir.
    end % Secant-vs-midpoint secimini sonlandirir.

    bracket_width = b - a; % Mevcut pressure bracket genisligini hesaplar.
    safe_lo = a + 0.10 * bracket_width; % Secant tahmininin endpoint'e cok yapismasini engelleyen alt guvenli siniri hesaplar.
    safe_hi = b - 0.10 * bracket_width; % Secant tahmininin endpoint'e cok yapismasini engelleyen ust guvenli siniri hesaplar.
    if ~isfinite(p_try) || p_try <= safe_lo || p_try >= safe_hi % Secant tahmini bracket icinde guvenli degilse kontrol eder.
        p_try = 0.5 * (a + b); % Bracket daralmasini garanti etmek icin midpoint kullanir.
    end % Secant safety fallback kosulunu sonlandirir.

    [ev_try, g_try] = evaluate_g(p_try); % Yeni pressure tahmininde detailed recovery error degerini hesaplar.
    if ~isfinite(g_try) % Hybrid iteration noktasinda finite recovery elde edilemezse kontrol eder.
        p_try = 0.5 * (a + b); % Bir kez daha bracket midpoint'ine geri doner.
        [ev_try, g_try] = evaluate_g(p_try); % Midpoint recovery error degerini hesaplar.
        if ~isfinite(g_try) % Midpoint de sayisal olarak basarisizsa kontrol eder.
            root.failure_reason = "nonfinite_during_P2_root"; % Root iteration sayisal failure nedenini kaydeder.
            break; % Hybrid root dongusunden cikar.
        end % Midpoint finite kontrolunu sonlandirir.
    end % First trial finite kontrolunu sonlandirir.

    if abs(g_try) <= recovery_tol || bracket_width <= cfg.root.P2_width_tolerance_MPa % Recovery veya pressure-width criteria saglandiysa kontrol eder.
        set_success(p_try, ev_try, g_try, [a, b], [ga, gb]); % Current root'u final basarili output olarak kaydeder.
        return; % Root solve tamamlandigi icin fonksiyondan cikar.
    end % Hybrid-root acceptance kosulunu sonlandirir.

    if ga * g_try <= 0.0 % Sign change lower endpoint ile trial arasinda ise kontrol eder.
        b = p_try; % Upper bracket pressure degerini trial pressure'a indirir.
        gb = g_try; % Upper bracket recovery error degerini gunceller.
    else % Sign change trial ile upper endpoint arasinda ise bu dali kullanir.
        a = p_try; % Lower bracket pressure degerini trial pressure'a cikarir.
        ga = g_try; % Lower bracket recovery error degerini gunceller.
    end % Hybrid bracket update kosulunu sonlandirir.
end % Hybrid root iteration dongusunu sonlandirir.

%% MAX-ITERATION FALLBACK % Iteration limiti dolduysa target'a en yakin finite evaluation'i tolerance ile son kez degerlendirir.

if ~isempty(best_ev) % En az bir finite evaluation mevcutsa kontrol eder.
    root.ev = best_ev; % Target'a en yakin evaluation'i final diagnostic olarak kaydeder.
    root.P2_gauge_MPa = best_P2; % En yakin P2 degerini kaydeder.
    root.recovery_error = best_ev.Recovery - R_target; % Final recovery mismatch degerini kaydeder.
    root.target_met = abs(root.recovery_error) <= recovery_tol; % Recovery acceptance flag degerini hesaplar.
    root.success = root.target_met; % Target met ise root'u basarili kabul eder.
end % Best finite evaluation kontrolunu sonlandirir.
if ~root.success && strlength(root.failure_reason) == 0 % Henuz acik failure reason yoksa kontrol eder.
    root.failure_reason = "P2_root_tolerance_not_met"; % Iteration/tolerance failure nedenini kaydeder.
end % Final failure reason kosulunu sonlandirir.

    function [ev, g] = evaluate_g(P2_MPa) % Cache destekli detailed evaluation ve recovery-minus-target degerini donduren local helper fonksiyondur.
        P2_MPa = min(max(P2_MPa, P2_lb), P2_ub); % Safety icin pressure degerini dynamic bounds icine clip eder.
        existing = find(abs(cache_P2 - P2_MPa) <= 1.0e-12, 1, 'first'); % Ayni pressure noktasinin daha once cozulup cozulmedigini arar.
        if ~isempty(existing) % Cached evaluation mevcutsa kontrol eder.
            ev = cache_ev{existing}; % Detailed evaluation'i cache'den alir.
        else % Bu P2 ilk kez cozuluyorsa bu dali kullanir.
            root.n_evaluations = root.n_evaluations + 1; % Benzersiz detailed model evaluation sayacini bir arttirir.
            try % Tek pressure noktasindaki model exception'i root solver'i tamamen durdurmasin diye try-catch kullanir.
                ev = ro_evaluate_train_operating_point(Qf_train_m3h, T_RO_in_C, Cf_kg_m3, P1_gauge_MPa, P2_MPa, cfg_eval); % Istenen gridde detailed train operating point'i hesaplar.
            catch % Truth model exception durumunda bu dali kullanir.
                ev = []; % Exception veren evaluation'i bos degerle temsil eder.
            end % Detailed evaluation try-catch blogunu sonlandirir.
            cache_P2(end + 1, 1) = P2_MPa; %#ok<AGROW> % Yeni pressure degerini evaluation cache'e ekler.
            cache_ev{end + 1, 1} = ev; %#ok<AGROW> % Yeni detailed evaluation struct'ini cache'e ekler.
        end % Cache hit/miss kosulunu sonlandirir.

        if ~isempty(ev) && isfield(ev, 'success') && ev.success && isfinite(ev.Recovery) % Evaluation finite recovery uretiyorsa kontrol eder.
            g = ev.Recovery - R_target; % Recovery root function degerini hesaplar.
            if abs(g) < best_abs_g % Mevcut nokta target recovery'ye oncekinden daha yakin ise kontrol eder.
                best_abs_g = abs(g); % En iyi absolute recovery mismatch degerini gunceller.
                best_P2 = P2_MPa; % En iyi P2 pressure degerini gunceller.
                best_ev = ev; % En iyi detailed evaluation struct'ini gunceller.
            end % Best-evaluation update kosulunu sonlandirir.
        else % Evaluation recovery root hesabina uygun degilse bu dali kullanir.
            g = NaN; % Kullanilamayan recovery error degerini NaN yapar.
        end % Finite evaluation kosulunu sonlandirir.
    end % Cache-supported evaluation helper fonksiyonunu sonlandirir.

    function [found, aa, bb, gaa, gbb] = expand_from_hint(p_center, g_center, direction, initial_step) % Hint'ten tek yonlu geometrik pressure expansion ile sign-change bracket arar.
        found = false; % Baslangicta bracket bulunmadigini kabul eder.
        aa = NaN; bb = NaN; gaa = NaN; gbb = NaN; % Bracket outputlarini NaN ile baslatir.
        p_prev = p_center; % Ilk expansion baslangic pressure degerini hint olarak tanimlar.
        g_prev = g_center; % Ilk expansion baslangic recovery error degerini hint error olarak tanimlar.
        step = initial_step; % Ilk pressure expansion adimini tanimlar.

        for jj = 1:5 % En fazla bes geometrik expansion adimi uygular.
            p_new = min(max(p_center + direction * step, P2_lb), P2_ub); % Hint merkezinden ilgili yonde yeni pressure noktasini bounds icinde hesaplar.
            if abs(p_new - p_prev) <= 1.0e-12 % Bound nedeniyle yeni pressure oncekiyle ayni olduysa kontrol eder.
                break; % Bu yonde daha fazla genisleme mumkun olmadigi icin donguden cikar.
            end % Expansion-bound kosulunu sonlandirir.
            [~, g_new] = evaluate_g(p_new); % Yeni expansion pressure noktasinda recovery error degerini hesaplar.
            if isfinite(g_new) && g_prev * g_new < 0.0 % Adjacent expansion noktalarinda sign change olustuysa kontrol eder.
                if p_prev < p_new % Pressure siralamasini lower-upper olarak duzenlemek icin kontrol eder.
                    aa = p_prev; bb = p_new; gaa = g_prev; gbb = g_new; % Artan pressure sirali bracket endpointlerini atar.
                else % Expansion asagi pressure yonundeyse bu dali kullanir.
                    aa = p_new; bb = p_prev; gaa = g_new; gbb = g_prev; % Endpointleri artan pressure sirasi ile yeniden duzenler.
                end % Bracket ordering kosulunu sonlandirir.
                found = true; % Sign-changing bracket bulundu flag'ini true yapar.
                return; % Expansion helper fonksiyonundan hemen cikar.
            end % Expansion sign-change kosulunu sonlandirir.
            if isfinite(g_new) % Yeni recovery error finite ise kontrol eder.
                p_prev = p_new; % Son finite pressure degerini sonraki expansion baslangici yapar.
                g_prev = g_new; % Son finite recovery error degerini sonraki expansion baslangici yapar.
            end % Finite expansion update kosulunu sonlandirir.
            step = 2.0 * step; % Bracket bulunamazsa pressure adimini geometrik olarak iki katina cikarir.
        end % Geometrik expansion dongusunu sonlandirir.
    end % Hint-expansion helper fonksiyonunu sonlandirir.

    function set_success(P2_value, ev_value, g_value, bracket_value, bracket_g_value) % Basarili root sonucunu tek yerde output struct'a aktaran local helper fonksiyondur.
        root.success = true; % Root solve basarili flag degerini true yapar.
        root.target_met = true; % Recovery target acceptance flag degerini true yapar.
        root.P2_gauge_MPa = P2_value; % Final Stage-2 pressure degerini kaydeder.
        root.recovery_error = g_value; % Final recovery mismatch degerini kaydeder.
        root.ev = ev_value; % Final detailed evaluation struct'ini kaydeder.
        root.bracket_found = true; % Basarili root icin bracket flag degerini true yapar.
        root.bracket_P2_MPa = bracket_value; % Final/root-on-probe bracket pressure degerlerini kaydeder.
        root.bracket_recovery_error = bracket_g_value; % Bracket recovery error degerlerini kaydeder.
        root.failure_reason = ""; % Basarili root'ta failure reason alanini temizler.
    end % Root-success helper fonksiyonunu sonlandirir.

end % P2 recovery-root fonksiyonunu sonlandirir.
