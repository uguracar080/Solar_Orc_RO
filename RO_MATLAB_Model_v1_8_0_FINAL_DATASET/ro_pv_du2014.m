function result = ro_pv_du2014(Qf_m3h, Cf_kg_m3, Pf_abs_MPa, T_C, n_elements, N_segments, mem) % Bir pressure vessel'i Du-2014 finite-difference modeli ile cozer.

%% GIRDI KONTROLLERI % Fiziksel ve sayisal girdileri kontrol eder.

if nargin < 7 % Membran struct'i verilmediyse kontrol eder.
    mem = ro_membrane_SW30XLE400(); % Varsayilan SW30XLE-400 membran verilerini yukler.
end % Membran giris kontrolunu sonlandirir.

Qf_m3h = max(Qf_m3h, 1.0e-9); % Feed debisini pozitif bir degere sinirlar.
Cf_kg_m3 = max(Cf_kg_m3, 0.0); % Feed konsantrasyonunu negatif olmayacak sekilde sinirlar.
n_elements = max(round(n_elements), 1); % Seri element sayisini pozitif tam sayiya cevirir.
N_segments = max(round(N_segments), 2); % Axial segment sayisini en az iki olacak sekilde ayarlar.

%% GRID VE ALAN TANIMI % PV uzunlugu ve segment membran alanini hesaplar.

L_PV_m = n_elements * mem.effective_length_m; % PV aktif hidrolik uzunlugunu hesaplar.
dz_m = L_PV_m / N_segments; % Axial finite-difference adim uzunlugunu hesaplar.
S_total_m2 = n_elements * mem.active_area_m2; % PV toplam aktif membran alanini hesaplar.
S_segment_m2 = S_total_m2 / N_segments; % Her axial segmentin aktif membran alanini hesaplar.

%% PROFIL DIZILERI % Feed, permeate ve lokal transport profillerini saklayacak dizileri olusturur.

z_m = zeros(N_segments + 1, 1); % Axial konum dizisini olusturur.
Q_m3h = zeros(N_segments + 1, 1); % Feed/brine debi profil dizisini olusturur.
C_kg_m3 = zeros(N_segments + 1, 1); % Bulk concentration profil dizisini olusturur.
P_abs_MPa = zeros(N_segments + 1, 1); % Feed pressure profil dizisini olusturur.
dQp_m3h = zeros(N_segments, 1); % Her segment permeate debisi dizisini olusturur.
dQ_candidate_m3h = zeros(N_segments, 1); % Clipping oncesi teorik segment permeate debisi dizisini diagnostic icin olusturur.
flow_clip_active = false(N_segments, 1); % Her segmentte numerical 95% feed-flow clip durumunu saklayacak logical dizi olusturur.
Cp_local_kg_m3 = zeros(N_segments, 1); % Her segment permeate concentration dizisini olusturur.
Cmw_kg_m3 = zeros(N_segments, 1); % Membrane-wall concentration dizisini olusturur.
Jv_LMH = zeros(N_segments, 1); % Local volumetric flux dizisini olusturur.
CPF = zeros(N_segments, 1); % Concentration polarization factor dizisini olusturur.
Re = zeros(N_segments, 1); % Reynolds sayisi dizisini olusturur.
Sc = zeros(N_segments, 1); % Schmidt sayisi dizisini olusturur.
NDP_MPa = zeros(N_segments, 1); % Net driving pressure dizisini olusturur.
local_converged = false(N_segments, 1); % Lokal convergence durum dizisini olusturur.

%% BASLANGIC SINIR KOSULLARI % PV giris kosullarini ilk grid noktasina atar.

Q_m3h(1) = Qf_m3h; % PV feed debisini ilk grid noktasina atar.
C_kg_m3(1) = Cf_kg_m3; % PV feed concentration degerini ilk grid noktasina atar.
P_abs_MPa(1) = Pf_abs_MPa; % PV feed pressure degerini ilk grid noktasina atar.

%% FINITE-DIFFERENCE DONGUSU % Her axial segmentte transport ve momentum denklemlerini cozer.

for l = 1:N_segments % PV boyunca tum axial segmentleri sirayla cozer.
    z_m(l) = (l - 1) * dz_m; % Mevcut segment baslangic konumunu kaydeder.
    loc = ro_local_transport_du2014(P_abs_MPa(l), C_kg_m3(l), T_C, Q_m3h(l), mem); % Mevcut segmentin lokal membrane transport cozumunu yapar.
    dQ_candidate_m3h(l) = 3600.0 * loc.Vw_m_s * S_segment_m2; % Du-2014 Eq.12 formuna gore clipping-oncesi segment permeate debisini hesaplar.
    flow_clip_active(l) = dQ_candidate_m3h(l) > 0.95 * Q_m3h(l); % Numerical 95% feed-flow clip'in bu segmentte devreye girip girmedigini kaydeder.
    dQp_m3h(l) = min(dQ_candidate_m3h(l), 0.95 * Q_m3h(l)); % Segmentin feed debisinin tamamini tuketmesini engeller.
    Q_m3h(l + 1) = Q_m3h(l) - dQp_m3h(l); % Sonraki grid noktasindaki brine debisini hesaplar.
    Cp_local_kg_m3(l) = loc.Cp_kg_m3; % Lokal permeate concentration degerini kaydeder.
    C_kg_m3(l + 1) = (Q_m3h(l) * C_kg_m3(l) - dQp_m3h(l) * Cp_local_kg_m3(l)) / max(Q_m3h(l + 1), 1.0e-12); % Du-2014 Eq.13 salt balance ile sonraki bulk concentration degerini hesaplar.
    hyd_now = ro_hydraulics_du2014(Q_m3h(l), C_kg_m3(l), T_C, mem); % Segment baslangic pressure gradient degerini hesaplar.
    hyd_next = ro_hydraulics_du2014(Q_m3h(l + 1), C_kg_m3(l + 1), T_C, mem); % Segment sonu pressure gradient degerini tahmin eder.
    P_abs_MPa(l + 1) = P_abs_MPa(l) + 0.5 * dz_m * (hyd_now.dP_dz_MPa_m + hyd_next.dP_dz_MPa_m); % Trapezoidal finite-difference ile sonraki pressure degerini hesaplar.
    Cmw_kg_m3(l) = loc.Cmw_kg_m3; % Membrane-wall concentration degerini profile kaydeder.
    Jv_LMH(l) = loc.Jv_LMH; % Local permeate flux degerini profile kaydeder.
    CPF(l) = loc.CPF; % Concentration polarization factor degerini profile kaydeder.
    Re(l) = loc.Re; % Reynolds sayisini profile kaydeder.
    Sc(l) = loc.Sc; % Schmidt sayisini profile kaydeder.
    NDP_MPa(l) = loc.NDP_MPa; % Net driving pressure degerini profile kaydeder.
    local_converged(l) = loc.converged; % Lokal solver convergence durumunu profile kaydeder.
end % Axial finite-difference dongusunu sonlandirir.

z_m(end) = L_PV_m; % Son grid noktasinin axial konumunu PV uzunluguna esitler.

%% TOPLAM PERMEATE SONUCLARI % PV toplam permeate debisi ve ortalama kalitesini hesaplar.

Qp_total_m3h = sum(dQp_m3h); % Tum segment permeate debilerini toplayarak PV permeate debisini hesaplar.
Qb_m3h = Q_m3h(end); % PV cikis brine debisini alir.
Cb_kg_m3 = C_kg_m3(end); % PV cikis brine concentration degerini alir.
Cp_avg_kg_m3 = sum(dQp_m3h .* Cp_local_kg_m3) / max(Qp_total_m3h, 1.0e-12); % Debi-agirlikli ortalama permeate concentration degerini hesaplar.
recovery = Qp_total_m3h / Qf_m3h; % PV recovery ratio degerini hesaplar.
pressure_drop_MPa = Pf_abs_MPa - P_abs_MPa(end); % PV toplam feed-side pressure drop degerini hesaplar.
avg_flux_LMH = (Qp_total_m3h * 1000.0) / S_total_m2; % PV ortalama permeate flux degerini LMH cinsinden hesaplar.

%% FIRST-ELEMENT FLUX DIAGNOSTIGI % Du-2014 first membrane element flux constraint'i icin area-weighted ilk-element average flux hesaplar.

segment_start_m = z_m(1:end-1); % Her axial segmentin baslangic konum vectorunu tanimlar.
segment_end_m = segment_start_m + dz_m; % Her axial segmentin bitis konum vectorunu tanimlar.
first_element_end_m = mem.effective_length_m; % Ilk membrane element'in aktif hidrolik bitis konumunu tanimlar.
overlap_first_m = max(min(segment_end_m, first_element_end_m) - segment_start_m, 0.0); % Her segmentin ilk element ile olan axial overlap uzunlugunu hesaplar.
if sum(overlap_first_m) > 0.0 % Ilk element ile en az bir segment overlap'i varsa kontrol eder.
    first_element_average_flux_LMH = sum(Jv_LMH .* overlap_first_m) / sum(overlap_first_m); % Uniform membrane-area/length varsayimi ile area-weighted first-element average flux degerini hesaplar.
    first_element_max_CPF = max(CPF(overlap_first_m > 0.0)); % Ilk element icindeki maximum CPF degerini diagnostic olarak hesaplar.
else % Sayisal olarak ilk element overlap'i olusmazsa bu dali kullanir.
    first_element_average_flux_LMH = NaN; % Gecersiz grid durumunu NaN ile acikca isaretler.
    first_element_max_CPF = NaN; % Gecersiz grid durumunda first-element CPF degerini NaN yapar.
end % First-element overlap kosulunu sonlandirir.

%% PROFIL TABLOSU % Analiz ve grafik icin ayrintili axial profil tablosunu olusturur.

profile = table(z_m(1:end-1), Q_m3h(1:end-1), C_kg_m3(1:end-1), P_abs_MPa(1:end-1), dQp_m3h, Cp_local_kg_m3, Cmw_kg_m3, Jv_LMH, CPF, Re, Sc, NDP_MPa, local_converged); % Axial profile tablosunu olusturur.
profile.Properties.VariableNames = {'z_m','Q_m3h','Cbulk_kg_m3','Pabs_MPa','dQp_m3h','Cp_kg_m3','Cmw_kg_m3','Jv_LMH','CPF','Re','Sc','NDP_MPa','Converged'}; % Profil tablosunun sutun adlarini tanimlar.

%% CIKTI YAPISI % PV sonucunu tek bir struct icinde toplar.

result.Qf_m3h = Qf_m3h; % PV feed debisini kaydeder.
result.Cf_kg_m3 = Cf_kg_m3; % PV feed concentration degerini kaydeder.
result.Pf_abs_MPa = Pf_abs_MPa; % PV feed pressure degerini kaydeder.
result.T_C = T_C; % PV feed temperature degerini kaydeder.
result.n_elements = n_elements; % PV seri element sayisini kaydeder.
result.N_segments = N_segments; % PV axial segment sayisini kaydeder.
result.Qp_m3h = Qp_total_m3h; % PV toplam permeate debisini kaydeder.
result.Qb_m3h = Qb_m3h; % PV cikis brine debisini kaydeder.
result.Cp_kg_m3 = Cp_avg_kg_m3; % PV ortalama permeate concentration degerini kaydeder.
result.Cb_kg_m3 = Cb_kg_m3; % PV cikis brine concentration degerini kaydeder.
result.Pout_abs_MPa = P_abs_MPa(end); % PV cikis pressure degerini kaydeder.
result.recovery = recovery; % PV recovery ratio degerini kaydeder.
result.pressure_drop_MPa = pressure_drop_MPa; % PV toplam pressure drop degerini kaydeder.
result.average_flux_LMH = avg_flux_LMH; % PV average permeate flux degerini kaydeder.
result.max_flux_LMH = max(Jv_LMH); % PV maximum local permeate flux degerini kaydeder.
result.first_element_average_flux_LMH = first_element_average_flux_LMH; % Du first-element constraint'i icin area-weighted ilk element average flux degerini kaydeder.
result.first_element_max_CPF = first_element_max_CPF; % Ilk element icindeki maximum CPF degerini diagnostic olarak kaydeder.
result.numerical_flow_clip_active = any(flow_clip_active); % PV boyunca 95% numerical segment flow clipping herhangi bir yerde aktif olduysa true kaydeder.
result.numerical_flow_clip_count = sum(flow_clip_active); % Clipping aktif olan segment sayisini diagnostic olarak kaydeder.
result.dQ_candidate_m3h = dQ_candidate_m3h; % Clipping oncesi teorik segment permeate debilerini diagnostic olarak kaydeder.
result.flow_clip_profile = flow_clip_active; % Segment-bazli clipping logical profilini diagnostic olarak kaydeder.
result.max_CPF = max(CPF); % PV maximum concentration polarization factor degerini kaydeder.
result.all_local_converged = all(local_converged); % Tum lokal transport cozumlerinin convergence durumunu kaydeder.
result.profile = profile; % Ayrintili axial profil tablosunu kaydeder.

end % Fonksiyonu sonlandirir.
