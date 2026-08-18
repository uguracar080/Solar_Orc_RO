function sys = ro_system_two_stage_px_du2014_fast(Qf_total_m3h, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, age_years, leakage_pressure_unit, Ppxlin_gauge_MPa, max_legacy_iter_override) % Du-2014 iki-stage + PX sistemini ayni fiziksel sabit nokta uzerinde safeguarded secant ile hizli cozer.

%% SABITLER VE MEMBRAN % Legacy fonksiyonla ayni fiziksel parametreleri kullanir.

if nargin < 14 || isempty(max_legacy_iter_override) % Cagiran fonksiyon legacy fallback limitini belirtmediyse kontrol eder.
    max_legacy_iter_override = 200; % Standalone/equivalence kullanimi icin legacy davranisla uyumlu 200 iterasyon fallback limitini korur.
end % Optional fallback-iteration input kontrolunu sonlandirir.

Ppxlout_gauge_MPa = 0.0; % PX low-pressure brine outlet gauge pressure degerini tanimlar.
mem_base = ro_membrane_SW30XLE400(); % Literature membrane parametrelerini yukler.
mem = ro_apply_membrane_age_du2014(mem_base, age_years); % Membrane aging parametrelerini uygular.
P1_abs_MPa = P1_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-1 gauge basincini internal absolute basinca cevirir.
P2_abs_MPa = P2_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-2 gauge basincini internal absolute basinca cevirir.

%% PX MIXING SABIT-NOKTA AYARLARI % Legacy F(C1)=C1 probleminin kokunu daha az membrane evaluation ile arar.

tol_C = 1.0e-8; % Legacy PX-network convergence toleransini aynen korur.
max_secant_iter = 12; % Safeguarded secant icin maksimum hizli iterasyon sayisini tanimlar.
max_legacy_iter = max(0, round(max_legacy_iter_override)); % Cagiran optimizer katmaninin coarse/final amacina gore legacy fallback limitini uygular.
C_lower = max(Cf_kg_m3, 0.0); % PX mixing stage-1 feed salinity icin fiziksel alt siniri raw feed olarak tanimlar.
C_upper = max(90.0, C_lower + 1.0); % Sayisal safeguard icin genis salinity ust siniri tanimlar.
converged = false; % Baslangicta PX-network convergence durumunu false yapar.
solver_method = "secant"; % Kullanilan PX coupling solver yontemini diagnostic olarak baslatir.
map_eval_count = 0; % Membrane+PX map evaluation sayacini sifirlar.

%% ILK IKI NOKTA % Secant solve icin raw-feed ve dogal fixed-point update noktalarini olusturur.

x0 = C_lower; % Ilk stage-1 feed salinity tahminini raw feed degeri yapar.
[m0, g0] = map_at_C1(x0); % F(C1)-C1 residual ve system state degerlerini hesaplar.
if isfinite(g0) && abs(g0) < tol_C % Ilk tahmin zaten legacy tolerance icindeyse kontrol eder.
    C1_feed_kg_m3 = m0.C1_new_kg_m3; % Legacy davranisla ayni sekilde final salinity degerini F(C1) yapar.
    converged = true; % Coupling convergence flag degerini true yapar.
else % Bir secant baslangic noktasi daha gerektigi durumda bu dali kullanir.
    x1 = min(max(m0.C1_new_kg_m3, C_lower), C_upper); % Dogal fixed-point update degerini ikinci secant noktasi yapar.
    if abs(x1 - x0) < 1.0e-10 % Ilk map update sayisal olarak ayni noktaya geldiyse kontrol eder.
        x1 = min(C_upper, x0 + 0.25); % Secant denominator icin kucuk ama fiziksel ikinci nokta olusturur.
    end % Ikinci nokta ayrikligi kontrolunu sonlandirir.
    [m1, g1] = map_at_C1(x1); % Ikinci secant residual degerini hesaplar.

    %% SAFEGUARDED SECANT % Ayni fixed-point kokunu residual g(C)=F(C)-C uzerinde arar.

    for k = 1:max_secant_iter % Hizli scalar secant dongusunu calistirir.
        if isfinite(g1) && abs(g1) < tol_C % Mevcut secant noktasi legacy convergence tolerance icindeyse kontrol eder.
            C1_feed_kg_m3 = m1.C1_new_kg_m3; % Legacy final-update davranisini korur.
            converged = true; % Convergence flag degerini true yapar.
            break; % Secant dongusunden cikar.
        end % Secant convergence kontrolunu sonlandirir.

        denom = g1 - g0; % Secant denominator degerini hesaplar.
        if isfinite(denom) && abs(denom) > 1.0e-12 && isfinite(g0) && isfinite(g1) % Guvenli secant adimi mumkunse kontrol eder.
            x2 = x1 - g1 * (x1 - x0) / denom; % Scalar secant kok tahminini hesaplar.
        else % Secant denominator guvenli degilse bu dali kullanir.
            x2 = 0.5 * (x1 + m1.C1_new_kg_m3); % Legacy under-relaxation benzeri guvenli fallback adimi kullanir.
        end % Secant/fallback adim secimini sonlandirir.

        if ~isfinite(x2) || x2 <= C_lower || x2 >= C_upper || abs(x2 - x1) > 10.0 % Secant tahmini fiziksel safeguard disina cikarsa kontrol eder.
            x2 = 0.5 * (x1 + m1.C1_new_kg_m3); % Guvenli fixed-point relaxation adimina geri doner.
        end % Secant safeguard kosulunu sonlandirir.
        x2 = min(max(x2, C_lower), C_upper); % Yeni salinity tahminini fiziksel bounds icine sinirlar.
        if abs(x2 - x1) < 1.0e-12 % Sayisal stagnation olustuysa kontrol eder.
            x2 = min(max(0.5 * (x1 + m1.C1_new_kg_m3), C_lower), C_upper); % Relaxed map update ile stagnation'i kirar.
        end % Stagnation safeguard kosulunu sonlandirir.

        [m2, g2] = map_at_C1(x2); % Yeni secant noktasinda coupled membrane-PX map degerini hesaplar.
        x0 = x1; % Secant history eski noktasini gunceller.
        g0 = g1; % Secant history eski residual degerini gunceller.
        x1 = x2; % Secant history yeni pressure noktasini gunceller.
        g1 = g2; % Secant history yeni residual degerini gunceller.
        m1 = m2; % Yeni map state struct'ini history icin kaydeder.
    end % Safeguarded secant dongusunu sonlandirir.
end % Ilk-nokta convergence kosulunu sonlandirir.

%% LEGACY FALLBACK % Secant herhangi bir nedenle convergence saglamazsa validated under-relaxed fixed-point dongusune geri doner.

if ~converged && max_legacy_iter > 0 % Hizli secant cozum convergence saglamadi ve fallback izni varsa kontrol eder.
    solver_method = "legacy_fallback"; % Diagnostic solver yontemini fallback olarak gunceller.
    C1_feed_kg_m3 = min(max(x1, C_lower), C_upper); % Legacy fallback'i son finite secant tahmininden baslatir.
    relax = 0.50; % Validated legacy under-relaxation katsayisini aynen kullanir.
    for k = 1:max_legacy_iter % Legacy fixed-point dongusunu calistirir.
        [mf, gf] = map_at_C1(C1_feed_kg_m3); % Mevcut salinity noktasinda coupled map residual degerini hesaplar.
        if ~isfinite(gf) % Map finite degilse kontrol eder.
            break; % Sayisal failure durumunda fallback dongusunden cikar.
        end % Finite-map kosulunu sonlandirir.
        C_error = abs(gf); % Legacy convergence kriteri olan |F(C)-C| degerini hesaplar.
        if C_error < tol_C % Legacy tolerance saglandiysa kontrol eder.
            C1_feed_kg_m3 = mf.C1_new_kg_m3; % Legacy kodla ayni final update davranisini uygular.
            converged = true; % Convergence flag degerini true yapar.
            break; % Legacy fallback dongusunden cikar.
        end % Legacy convergence kosulunu sonlandirir.
        C1_feed_kg_m3 = relax * mf.C1_new_kg_m3 + (1.0 - relax) * C1_feed_kg_m3; % Legacy under-relaxation update degerini uygular.
    end % Legacy fallback dongusunu sonlandirir.
elseif ~converged % Coarse search'te legacy fallback kapaliysa bu dali kullanir.
    solver_method = "secant_failed_no_fallback"; % Noktanin pahali fallback'e girmeden nonconverged birakildigini diagnostic olarak kaydeder.
    C1_feed_kg_m3 = min(max(x1, C_lower), C_upper); % Final diagnostic map icin son finite secant tahminini kullanir.
end % Fallback gereksinimi kontrolunu sonlandirir.

%% FINAL COZUM % Legacy fonksiyon gibi converged salinity ile iki stage ve PX state'ini bir kez daha tutarli hesaplar.

[final_map, ~] = map_at_C1(C1_feed_kg_m3); % Final converged C1 ile membrane ve PX state'lerini yeniden hesaplar.
stage1_PV = final_map.stage1_PV; % Final Stage-1 representative PV sonucunu alir.
stage2_PV = final_map.stage2_PV; % Final Stage-2 representative PV sonucunu alir.
px = final_map.px; % Final PX sonucunu alir.
Qp_stage1_m3h = final_map.Qp_stage1_m3h; % Final Stage-1 toplam permeate debisini alir.
Qb_stage1_m3h = final_map.Qb_stage1_m3h; % Final Stage-1 toplam brine debisini alir.
Qp_stage2_m3h = final_map.Qp_stage2_m3h; % Final Stage-2 toplam permeate debisini alir.
Qb_stage2_m3h = final_map.Qb_stage2_m3h; % Final Stage-2 toplam brine debisini alir.
Qhpp_m3h = final_map.Qhpp_m3h; % Final HPP feed flow degerini alir.

%% SISTEM PERFORMANSI % Legacy fonksiyonla ayni overall outputlari hesaplar.

Qp_total_m3h = Qp_stage1_m3h + Qp_stage2_m3h; % Iki stage permeate debilerini toplar.
Cp_total_kg_m3 = (Qp_stage1_m3h * stage1_PV.Cp_kg_m3 + Qp_stage2_m3h * stage2_PV.Cp_kg_m3) / max(Qp_total_m3h, 1.0e-12); % Debi-agirlikli product salinity degerini hesaplar.
overall_recovery = Qp_total_m3h / Qf_total_m3h; % Raw-feed bazli overall recovery ratio degerini hesaplar.
A_total_m2 = (N_PV_stage1 * n_elements_stage1 + N_PV_stage2 * n_elements_stage2) * mem.active_area_m2; % Toplam aktif membrane alanini hesaplar.
average_flux_LMH = Qp_total_m3h * 1000.0 / A_total_m2; % System-average permeate flux degerini hesaplar.

%% LEGACY MEMBRANE-SIDE FEASIBILITY % Orijinal function ile ayni temel feasibility flag degerini hesaplar.

feed_ok_stage1 = stage1_PV.Qf_m3h <= mem.feed_flow_max_m3h; % Stage-1 feed/PV limitini kontrol eder.
feed_ok_stage2 = stage2_PV.Qf_m3h <= mem.feed_flow_max_m3h; % Stage-2 feed/PV limitini kontrol eder.
brine_ok_stage1 = stage1_PV.Qb_m3h >= mem.min_brine_flow_m3h; % Stage-1 minimum brine/PV limitini kontrol eder.
brine_ok_stage2 = stage2_PV.Qb_m3h >= mem.min_brine_flow_m3h; % Stage-2 minimum brine/PV limitini kontrol eder.
dp_ok_stage1 = stage1_PV.pressure_drop_MPa <= mem.max_PV_pressure_drop_MPa; % Stage-1 pressure-drop limitini kontrol eder.
dp_ok_stage2 = stage2_PV.pressure_drop_MPa <= mem.max_PV_pressure_drop_MPa; % Stage-2 pressure-drop limitini kontrol eder.
cpf_ok_stage1 = stage1_PV.max_CPF <= mem.max_CPF_pass1; % Stage-1 CPF limitini kontrol eder.
cpf_ok_stage2 = stage2_PV.max_CPF <= mem.max_CPF_pass2; % Stage-2 CPF limitini kontrol eder.
flux_ok = average_flux_LMH <= mem.max_system_average_flux_LMH; % System-average flux limitini kontrol eder.
feasible = feed_ok_stage1 && feed_ok_stage2 && brine_ok_stage1 && brine_ok_stage2 && dp_ok_stage1 && dp_ok_stage2 && cpf_ok_stage1 && cpf_ok_stage2 && flux_ok; % Legacy basic feasibility flag degerini hesaplar.

%% OUTPUT STRUCT % Legacy output field'larini ayni isimlerle uretir ve solver diagnostics ekler.

sys.Qf_total_m3h = Qf_total_m3h; % Raw feed flow degerini kaydeder.
sys.Cf_kg_m3 = Cf_kg_m3; % Raw feed concentration degerini kaydeder.
sys.C1_feed_kg_m3 = C1_feed_kg_m3; % PX mixing sonrasi Stage-1 feed concentration degerini kaydeder.
sys.P1_gauge_MPa = P1_gauge_MPa; % Stage-1 operating pressure degerini kaydeder.
sys.P2_gauge_MPa = P2_gauge_MPa; % Stage-2 operating pressure degerini kaydeder.
sys.N_PV_stage1 = N_PV_stage1; % Stage-1 PV sayisini kaydeder.
sys.N_PV_stage2 = N_PV_stage2; % Stage-2 PV sayisini kaydeder.
sys.n_elements_stage1 = n_elements_stage1; % Stage-1 element/PV sayisini kaydeder.
sys.n_elements_stage2 = n_elements_stage2; % Stage-2 element/PV sayisini kaydeder.
sys.Qhpp_m3h = Qhpp_m3h; % HPP feed flow degerini kaydeder.
sys.Qp_stage1_m3h = Qp_stage1_m3h; % Stage-1 permeate flow degerini kaydeder.
sys.Qp_stage2_m3h = Qp_stage2_m3h; % Stage-2 permeate flow degerini kaydeder.
sys.Qp_total_m3h = Qp_total_m3h; % Total permeate flow degerini kaydeder.
sys.Cp_kg_m3 = Cp_total_kg_m3; % Product concentration degerini kaydeder.
sys.overall_recovery = overall_recovery; % Overall recovery degerini kaydeder.
sys.average_flux_LMH = average_flux_LMH; % System-average flux degerini kaydeder.
sys.stage1_PV = stage1_PV; % Final Stage-1 representative PV sonucunu kaydeder.
sys.stage2_PV = stage2_PV; % Final Stage-2 representative PV sonucunu kaydeder.
sys.px = px; % Final PX sonucunu kaydeder.
sys.iterations = map_eval_count; % Diagnostic icin coupled map evaluation sayisini kaydeder.
sys.converged = converged; % PX-network convergence flag degerini kaydeder.
sys.feasible = feasible; % Basic membrane-side feasibility flag degerini kaydeder.
sys.age_years = age_years; % Membrane age degerini kaydeder.
sys.N_segments = N_segments; % Axial grid sayisini kaydeder.
sys.leakage_pressure_unit = leakage_pressure_unit; % Leakage pressure-unit yorumunu kaydeder.
sys.Ppxlin_gauge_MPa = Ppxlin_gauge_MPa; % PX low-side inlet gauge pressure degerini kaydeder.
sys.px_solver_method = solver_method; % Fast/legacy-fallback coupling solver yontemini diagnostic olarak kaydeder.

    function [m, g] = map_at_C1(C1_trial_kg_m3) % Tek Stage-1 feed salinity tahmini icin membrane+PX map F(C1) ve residual g=F-C1 hesaplar.
        map_eval_count = map_eval_count + 1; % Coupled map evaluation sayacini bir arttirir.
        Qf_PV1_m3h = Qf_total_m3h / N_PV_stage1; % Stage-1 representative PV feed flow degerini hesaplar.
        s1 = ro_pv_du2014(Qf_PV1_m3h, C1_trial_kg_m3, P1_abs_MPa, T_C, n_elements_stage1, N_segments, mem); % Stage-1 representative PV detailed cozumunu yapar.
        Qp1 = s1.Qp_m3h * N_PV_stage1; % Stage-1 total permeate flow degerini hesaplar.
        Qb1 = s1.Qb_m3h * N_PV_stage1; % Stage-1 total brine flow degerini hesaplar.
        Qf_PV2_m3h = Qb1 / N_PV_stage2; % Stage-2 representative PV feed flow degerini hesaplar.
        s2 = ro_pv_du2014(Qf_PV2_m3h, s1.Cb_kg_m3, P2_abs_MPa, T_C, n_elements_stage2, N_segments, mem); % Stage-2 representative PV detailed cozumunu yapar.
        Qp2 = s2.Qp_m3h * N_PV_stage2; % Stage-2 total permeate flow degerini hesaplar.
        Qb2 = s2.Qb_m3h * N_PV_stage2; % Stage-2 final high-pressure brine flow degerini hesaplar.
        Ppxhin_gauge_MPa = max(s2.Pout_abs_MPa - mem.permeate_pressure_abs_MPa, 0.0); % PX high-side inlet gauge pressure degerini hesaplar.
        pxx = ro_px_du2014(Qb2, s2.Cb_kg_m3, Ppxhin_gauge_MPa, Cf_kg_m3, 0.95, leakage_pressure_unit, Ppxlin_gauge_MPa, Ppxlout_gauge_MPa); % PX leakage/mixing/pressure transfer modelini cozer.
        Qhpp = max(Qf_total_m3h - pxx.Qpxlin_m3h, 0.0); % HPP feed flow degerini hesaplar.
        C1_new = (Qhpp * Cf_kg_m3 + pxx.Qpxhout_m3h * pxx.Cpxhout_kg_m3) / max(Qhpp + pxx.Qpxhout_m3h, 1.0e-12); % PX-HPP mixing sonrasi yeni Stage-1 feed concentration degerini hesaplar.
        g = C1_new - C1_trial_kg_m3; % Fixed-point residual g(C1)=F(C1)-C1 degerini hesaplar.
        m.stage1_PV = s1; % Stage-1 PV sonucunu map state struct'ina kaydeder.
        m.stage2_PV = s2; % Stage-2 PV sonucunu map state struct'ina kaydeder.
        m.px = pxx; % PX sonucunu map state struct'ina kaydeder.
        m.Qp_stage1_m3h = Qp1; % Stage-1 permeate flow degerini kaydeder.
        m.Qb_stage1_m3h = Qb1; % Stage-1 brine flow degerini kaydeder.
        m.Qp_stage2_m3h = Qp2; % Stage-2 permeate flow degerini kaydeder.
        m.Qb_stage2_m3h = Qb2; % Stage-2 brine flow degerini kaydeder.
        m.Qhpp_m3h = Qhpp; % HPP feed flow degerini kaydeder.
        m.C1_new_kg_m3 = C1_new; % Map output F(C1) degerini kaydeder.
    end % Local membrane+PX map helper fonksiyonunu sonlandirir.

end % Fast PX-coupled two-stage system fonksiyonunu sonlandirir.
