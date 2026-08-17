function sys = ro_system_two_stage_px_du2014(Qf_total_m3h, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, age_years, leakage_pressure_unit, Ppxlin_gauge_MPa) % Du-2014 Fig.3d two-stage RO + PX sistemini iteratif cozer.

%% FINAL LOW-PRESSURE PX CIKISI % Discharge brine'in atmosfere yakin gauge basincini tanimlar.

Ppxlout_gauge_MPa = 0.0; % PX low-pressure brine outlet basincini 0 MPa(g) kabul eder.

%% MEMBRAN VE AGING PARAMETRELERI % Du-2014 SW30XLE-400 ve membrane-age ayarlarini yukler.

mem_base = ro_membrane_SW30XLE400(); % SW30XLE-400 literature base parametrelerini yukler.
mem = ro_apply_membrane_age_du2014(mem_base, age_years); % Du-2014 Eq.22-23 ile membrane aging parametrelerini uygular.
P1_abs_MPa = P1_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-1 gauge operating pressure degerini internal absolute basinca cevirir.
P2_abs_MPa = P2_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-2 gauge operating pressure degerini internal absolute basinca cevirir.

%% ITERASYON BASLANGICI % PX mixing ile stage-1 feed salinity arasindaki coupled dongu icin ilk tahminleri tanimlar.

C1_feed_kg_m3 = Cf_kg_m3; % Stage-1 feed concentration icin raw seawater degerini ilk tahmin yapar.
relax = 0.50; % PX salinity fixed-point iterasyonu icin under-relaxation katsayisini tanimlar.
tol_C = 1.0e-8; % Stage-1 feed concentration convergence toleransini tanimlar.
max_iter = 200; % Maksimum PX-network iterasyon sayisini tanimlar.
converged = false; % Baslangicta PX-network convergence durumunu false yapar.

%% PX-NETWORK FIXED-POINT DONGUSU % Membran cikisi, PX leakage ve PX mixing etkisini birlikte cozer.

for iter = 1:max_iter % Maksimum iterasyon sayisina kadar coupled system dongusunu calistirir.
    Qf_PV1_m3h = Qf_total_m3h / N_PV_stage1; % Stage-1 representative PV feed debisini hesaplar.
    stage1_PV = ro_pv_du2014(Qf_PV1_m3h, C1_feed_kg_m3, P1_abs_MPa, T_C, n_elements_stage1, N_segments, mem); % Stage-1 representative PV detailed cozumunu yapar.
    Qp_stage1_m3h = stage1_PV.Qp_m3h * N_PV_stage1; % Stage-1 toplam permeate debisini hesaplar.
    Qb_stage1_m3h = stage1_PV.Qb_m3h * N_PV_stage1; % Stage-1 toplam brine debisini hesaplar.
    Qf_PV2_m3h = Qb_stage1_m3h / N_PV_stage2; % Stage-2 representative PV feed debisini hesaplar.
    stage2_PV = ro_pv_du2014(Qf_PV2_m3h, stage1_PV.Cb_kg_m3, P2_abs_MPa, T_C, n_elements_stage2, N_segments, mem); % Stage-2 representative PV detailed cozumunu yapar.
    Qp_stage2_m3h = stage2_PV.Qp_m3h * N_PV_stage2; % Stage-2 toplam permeate debisini hesaplar.
    Qb_stage2_m3h = stage2_PV.Qb_m3h * N_PV_stage2; % Stage-2 final high-pressure brine debisini hesaplar.
    Ppxhin_gauge_MPa = max(stage2_PV.Pout_abs_MPa - mem.permeate_pressure_abs_MPa, 0.0); % Stage-2 PV outlet basincini PX high-side inlet gauge basinci olarak hesaplar.
    px = ro_px_du2014(Qb_stage2_m3h, stage2_PV.Cb_kg_m3, Ppxhin_gauge_MPa, Cf_kg_m3, 0.95, leakage_pressure_unit, Ppxlin_gauge_MPa, Ppxlout_gauge_MPa); % Du-2014 PX-220 leakage, mixing ve pressure-transfer modelini cozer.
    Qhpp_m3h = Qf_total_m3h - px.Qpxlin_m3h; % Raw feed toplamindan PX low-side feed debisini cikararak HPP feed debisini hesaplar.
    Qhpp_m3h = max(Qhpp_m3h, 0.0); % Hesaplanan HPP debisini negatif olmayacak sekilde sinirlar.
    C1_new_kg_m3 = (Qhpp_m3h * Cf_kg_m3 + px.Qpxhout_m3h * px.Cpxhout_kg_m3) / max(Qhpp_m3h + px.Qpxhout_m3h, 1.0e-12); % HPP ve PX high-pressure akimlarini karistirarak stage-1 feed concentration degerini hesaplar.
    C_error = abs(C1_new_kg_m3 - C1_feed_kg_m3); % Stage-1 feed salinity fixed-point hatasini hesaplar.
    C1_feed_kg_m3 = relax * C1_new_kg_m3 + (1.0 - relax) * C1_feed_kg_m3; % Stage-1 feed concentration degerine under-relaxation uygular.
    if C_error < tol_C % Stage-1 feed salinity hatasi toleransin altindaysa kontrol eder.
        C1_feed_kg_m3 = C1_new_kg_m3; % Converged stage-1 feed concentration degerini final deger olarak atar.
        converged = true; % PX-network convergence durumunu true yapar.
        break; % Coupled PX-network iterasyon dongusunden cikar.
    end % Convergence kosulunu sonlandirir.
end % Coupled PX-network fixed-point dongusunu sonlandirir.

%% FINAL COZUMU YENILEME % Converged salinity ile stage sonuclarini bir kez daha tutarli sekilde hesaplar.

Qf_PV1_m3h = Qf_total_m3h / N_PV_stage1; % Final stage-1 representative PV feed debisini hesaplar.
stage1_PV = ro_pv_du2014(Qf_PV1_m3h, C1_feed_kg_m3, P1_abs_MPa, T_C, n_elements_stage1, N_segments, mem); % Converged salinity ile final stage-1 PV cozumunu yapar.
Qp_stage1_m3h = stage1_PV.Qp_m3h * N_PV_stage1; % Final stage-1 toplam permeate debisini hesaplar.
Qb_stage1_m3h = stage1_PV.Qb_m3h * N_PV_stage1; % Final stage-1 toplam brine debisini hesaplar.
Qf_PV2_m3h = Qb_stage1_m3h / N_PV_stage2; % Final stage-2 representative PV feed debisini hesaplar.
stage2_PV = ro_pv_du2014(Qf_PV2_m3h, stage1_PV.Cb_kg_m3, P2_abs_MPa, T_C, n_elements_stage2, N_segments, mem); % Final stage-2 PV cozumunu yapar.
Qp_stage2_m3h = stage2_PV.Qp_m3h * N_PV_stage2; % Final stage-2 toplam permeate debisini hesaplar.
Qb_stage2_m3h = stage2_PV.Qb_m3h * N_PV_stage2; % Final stage-2 high-pressure brine debisini hesaplar.
Ppxhin_gauge_MPa = max(stage2_PV.Pout_abs_MPa - mem.permeate_pressure_abs_MPa, 0.0); % Final PX high-side inlet gauge basincini hesaplar.
px = ro_px_du2014(Qb_stage2_m3h, stage2_PV.Cb_kg_m3, Ppxhin_gauge_MPa, Cf_kg_m3, 0.95, leakage_pressure_unit, Ppxlin_gauge_MPa, Ppxlout_gauge_MPa); % Final PX state degerlerini hesaplar.
Qhpp_m3h = max(Qf_total_m3h - px.Qpxlin_m3h, 0.0); % Final HPP feed debisini hesaplar.

%% SISTEM PERFORMANSI % Iki stage permeate akimlarini birlestirir ve overall performansi hesaplar.

Qp_total_m3h = Qp_stage1_m3h + Qp_stage2_m3h; % Sistem toplam permeate debisini hesaplar.
Cp_total_kg_m3 = (Qp_stage1_m3h * stage1_PV.Cp_kg_m3 + Qp_stage2_m3h * stage2_PV.Cp_kg_m3) / max(Qp_total_m3h, 1.0e-12); % Sistem product concentration degerini debi agirlikli hesaplar.
overall_recovery = Qp_total_m3h / Qf_total_m3h; % Sistem raw-feed bazli overall recovery ratio degerini hesaplar.
A_total_m2 = (N_PV_stage1 * n_elements_stage1 + N_PV_stage2 * n_elements_stage2) * mem.active_area_m2; % Sistem toplam aktif membran alanini hesaplar.
average_flux_LMH = Qp_total_m3h * 1000.0 / A_total_m2; % Sistem average permeate flux degerini LMH cinsinden hesaplar.

%% DU-2014 TEKNIK KISITLARI % Final system feasibility icin temel membrane-side kisitlari kontrol eder.

feed_ok_stage1 = stage1_PV.Qf_m3h <= mem.feed_flow_max_m3h; % Stage-1 PV feed debisinin maksimum limit altinda olup olmadigini kontrol eder.
feed_ok_stage2 = stage2_PV.Qf_m3h <= mem.feed_flow_max_m3h; % Stage-2 PV feed debisinin maksimum limit altinda olup olmadigini kontrol eder.
brine_ok_stage1 = stage1_PV.Qb_m3h >= mem.min_brine_flow_m3h; % Stage-1 PV brine debisinin minimum limit ustunde olup olmadigini kontrol eder.
brine_ok_stage2 = stage2_PV.Qb_m3h >= mem.min_brine_flow_m3h; % Stage-2 PV brine debisinin minimum limit ustunde olup olmadigini kontrol eder.
dp_ok_stage1 = stage1_PV.pressure_drop_MPa <= mem.max_PV_pressure_drop_MPa; % Stage-1 PV pressure drop degerinin maksimum limit altinda olup olmadigini kontrol eder.
dp_ok_stage2 = stage2_PV.pressure_drop_MPa <= mem.max_PV_pressure_drop_MPa; % Stage-2 PV pressure drop degerinin maksimum limit altinda olup olmadigini kontrol eder.
cpf_ok_stage1 = stage1_PV.max_CPF <= mem.max_CPF_pass1; % Stage-1 maximum CPF degerinin pass-1 limitini saglayip saglamadigini kontrol eder.
cpf_ok_stage2 = stage2_PV.max_CPF <= mem.max_CPF_pass2; % Stage-2 maximum CPF degerinin pass-2 limitini saglayip saglamadigini kontrol eder.
flux_ok = average_flux_LMH <= mem.max_system_average_flux_LMH; % Sistem average flux degerinin seawater limitini saglayip saglamadigini kontrol eder.
feasible = feed_ok_stage1 && feed_ok_stage2 && brine_ok_stage1 && brine_ok_stage2 && dp_ok_stage1 && dp_ok_stage2 && cpf_ok_stage1 && cpf_ok_stage2 && flux_ok; % Tum temel membrane-side kisitlardan overall feasibility flag degerini hesaplar.

%% CIKTI YAPISI % Coupled two-stage PX system sonuclarini struct icine toplar.

sys.Qf_total_m3h = Qf_total_m3h; % Sistem raw-feed debisini kaydeder.
sys.Cf_kg_m3 = Cf_kg_m3; % Sistem raw-feed concentration degerini kaydeder.
sys.C1_feed_kg_m3 = C1_feed_kg_m3; % PX mixing sonrasi stage-1 feed concentration degerini kaydeder.
sys.P1_gauge_MPa = P1_gauge_MPa; % Stage-1 operating gauge pressure degerini kaydeder.
sys.P2_gauge_MPa = P2_gauge_MPa; % Stage-2 operating gauge pressure degerini kaydeder.
sys.N_PV_stage1 = N_PV_stage1; % Stage-1 PV sayisini kaydeder.
sys.N_PV_stage2 = N_PV_stage2; % Stage-2 PV sayisini kaydeder.
sys.n_elements_stage1 = n_elements_stage1; % Stage-1 element/PV sayisini kaydeder.
sys.n_elements_stage2 = n_elements_stage2; % Stage-2 element/PV sayisini kaydeder.
sys.Qhpp_m3h = Qhpp_m3h; % Main HPP feed debisini kaydeder.
sys.Qp_stage1_m3h = Qp_stage1_m3h; % Stage-1 permeate debisini kaydeder.
sys.Qp_stage2_m3h = Qp_stage2_m3h; % Stage-2 permeate debisini kaydeder.
sys.Qp_total_m3h = Qp_total_m3h; % Sistem toplam permeate debisini kaydeder.
sys.Cp_kg_m3 = Cp_total_kg_m3; % Sistem product concentration degerini kaydeder.
sys.overall_recovery = overall_recovery; % Sistem overall recovery degerini kaydeder.
sys.average_flux_LMH = average_flux_LMH; % Sistem average flux degerini kaydeder.
sys.stage1_PV = stage1_PV; % Stage-1 representative PV sonucunu kaydeder.
sys.stage2_PV = stage2_PV; % Stage-2 representative PV sonucunu kaydeder.
sys.px = px; % Pressure-exchanger ayrintili sonucunu kaydeder.
sys.iterations = iter; % Coupled PX-network iterasyon sayisini kaydeder.
sys.converged = converged; % Coupled PX-network convergence durumunu kaydeder.
sys.feasible = feasible; % Membrane-side overall feasibility flag degerini kaydeder.
sys.age_years = age_years; % Kullanilan membrane age degerini kaydeder.
sys.N_segments = N_segments; % Kullanilan axial discretization sayisini kaydeder.
sys.leakage_pressure_unit = leakage_pressure_unit; % PX leakage Eq.50 pressure-unit yorumunu kaydeder.
sys.Ppxlin_gauge_MPa = Ppxlin_gauge_MPa; % PX low-side inlet gauge pressure varsayimini kaydeder.

end % Fonksiyonu sonlandirir.
