RO MATLAB MODEL v1.5
==================

AMAÇ
----
Bu klasör, SW30XLE-400 spiral-wound RO membranı için ayrıntılı MATLAB modelinin ilk sürümüdür.
Model önce bağımsız olarak doğrulanmak, daha sonra performance-map / ANN surrogate üretiminde kullanılmak üzere hazırlanmıştır.

ANA KAYNAKLAR
--------------
[1] Mokhtari et al., Desalination 377 (2016) 108-122.
    - İki kademeli RO benchmark.
    - Optimum nokta: Pf=4.68 MPa, Qf=223.27 m3/h, toplam 45 PV, 5 element/PV,
      recovery=76.14%, Cp=183.34 ppm, high-pressure pump power=362.2 kW.
    - Water/salt flux, concentration polarization ve TCF denklemleri.

[2] Jaafari & Rahimi, Energy Reports 7 (2021) 4146-4171.
    - DOW membran parametrelerinin katalogdan türetilmesi.
    - 70 alt-eleman yaklaşımı.

[3] Lu, Liao & Hu, Desalination 307 (2012) 42-50.
    - Solution-diffusion temeli.
    - Reynolds sayısında V = feed-side cross-flow velocity.
    - SW30XLE-400 için A=3.5e-9 kg/(m2 s Pa), B=3.2e-5 kg/(m2 s).
    - 25 C için rho=1020 kg/m3, mu=1.09e-3 Pa.s, Ds=1.35e-9 m2/s.

[4] Du et al., Desalination 333 (2014) 66-81.
    - Eksenel finite-difference RO-PV modeli.
    - Yerel hız, basınç ve konsantrasyon değişimi.
    - Ds(T), mu(T,C), rho(T,C), local mass-transfer ve momentum denklemleri.
    - SW30XLE-400 için Sfcs=0.0150 m2, eps_sp=0.9, de=8.126e-4 m, K_lambda=2.4.

[5] DuPont FilmTec Technical Manual.
    - Manufacturer çalışma sınırları, fouling-factor yaklaşımı ve işletme kısıtları.

ÖNEMLİ MODELLEME NOTLARI
------------------------
1) MATLAB içindeki basınçlar MPa(abs) olarak tutulur.
2) Permeate pressure varsayılan olarak 0.101325 MPa(abs) alınır.
3) Du-2014 ayrıntılı modelinde konsantrasyon kg/m3 olarak tutulur.
4) B katsayısının kaynaklardaki birim gösterimi ile konsantrasyon tanımı tam boyutsal uyumlu değildir.
   Bu sürümde B, tuz kütle akısı katsayısı olarak kullanılır ve salt-flux hesabında konsantrasyon
   farkı kütle kesrine çevrilir: w = C/rho. Bu tercih kodda açıkça işaretlenmiştir.
5) Mokhtari-2016 optimum benchmark için toplam 45 PV'nin stage dağılımı makalede açık verilmemektedir.
   ro_allocate_two_stage_pvs.m, makaledeki stage-ratio fikrine göre 30/15 dağılımını yeniden kurar.
   Bu nedenle Mokhtari testi "reconstruction validation" olarak raporlanır.
6) Mokhtari optimum case için feed salinity, makaledeki maksimum Caspian TDS bilgisine dayanarak
   başlangıçta 13 kg/m3 (=13000 ppm) alınmıştır. Bu değer ayrıca sensitivity ile incelenmelidir.
7) Grid sayısı doğrudan 70 kabul edilmek yerine test_grid_independence.m ile kontrol edilir.

ÇALIŞTIRMA
----------
MATLAB Current Folder'ı bu klasöre ayarlayın ve:

    run_all_RO_tests

komutunu çalıştırın.

DOSYALAR
--------
run_all_RO_tests.m                  : Tüm ilk testleri sırayla çalıştırır.
test_SW30XLE400_datasheet.m         : Tek-element manufacturer consistency testi.
test_Mokhtari2016.m                 : Mokhtari-2016 optimum benchmark reconstruction testi.
test_grid_independence.m            : 10-100 axial segment için grid bağımsızlığı testi.
ro_membrane_SW30XLE400.m            : Membran ve tasarım sabitleri.
ro_properties_du2014.m              : rho(T,C), mu(T,C), Ds(T).
ro_osmotic_pressure_du2014.m        : Du-2014 seawater osmotic pressure korelasyonu.
ro_tcf_du2014.m                     : Du-2014 temperature correction factor.
ro_hydraulics_du2014.m              : Lokal feed velocity, Re, lambda ve dP/dz.
ro_local_transport_du2014.m         : Lokal Jw, Js, Cp, Cmw ve concentration polarization çözümü.
ro_pv_du2014.m                      : Bir pressure vessel için finite-difference çözümü.
ro_system_two_stage.m               : İki-stage, paralel-PV sistem çözümü.
ro_allocate_two_stage_pvs.m         : Toplam PV sayısını iki stage'e dağıtır.
ro_pump_power.m                     : High-pressure pump elektrik gücünü hesaplar.
ro_osmotic_pressure_mokhtari2016.m  : Mokhtari/Lu ppm tabanlı osmotic pressure korelasyonu.
ro_tcf_mokhtari2016.m               : Mokhtari/FilmTec TCF bağıntısı.

SONRAKİ AŞAMA
-------------
Bu sürüm MATLAB'da çalıştırıldıktan sonra:
- çıkan tabloları birlikte değerlendireceğiz,
- gerekiyorsa Mokhtari benchmark için stage allocation / feed salinity / pressure-drop ayrıntısını rafine edeceğiz,
- validasyon kabul edildikten sonra performance-map üretim dosyalarını ekleyeceğiz,
- ardından ANN surrogate modeline geçeceğiz.

V1.1 DUZELTMESI
----------------
- test_Mokhtari2016.m satir 76'daki MATLAB string apostrof syntax hatasi giderildi.
- Datasheet testine feed-flow-range ve sabit-Aref yaklasimi icin aciklayici diagnostik notlar eklendi.
- Fiziksel denklemler ve model parametreleri degistirilmedi.

V1.2 EKLEMELERI
----------------
- Manufacturer standard test noktasindan A/B parameter identification eklendi.
- Bu calibration bagimsiz validation olarak degil, datasheet-based parameter identification olarak etiketlendi.
- Mokhtari reconstruction testi 100 axial segmente cikarildi.
- Makalede raporlanmayan feed salinity ve stage PV split etkisini ayirmak icin diagnostic tarama eklendi.
- Grid independence testi N=200 reference grid'e kadar genisletildi.
- Orijinal Lu/Du A ve B parametreleri literature-reproduction dali icin aynen korunmaktadir.

V1.3 EKLEMELERI
----------------
- Detailed Du solver icin Du-2014 Case Study I without-ERD published verification testi eklendi.
- Stage-2 interstage pump sonrasi bagimsiz pressure inputini destekleyen iki-stage solver eklendi.
- Du-2014 Eq.22-23 aging factors (7%/year flux decline, 10%/year salt-passage increase, 3-year design period) verification testine eklendi.
- Du published operating pressure degerlerinin absolute/gauge belirsizligi iki senaryo halinde test edilmektedir.
- Du published result N=30 grid ile uretilmis oldugundan direct verification N=30 ile yapilmaktadir.
- Final detailed truth-model grid secimi ayri grid-independence testinden N=150 olarak korunmaktadir.
- Mokhtari optimum testi 'secondary cross-model reconstruction benchmark' olarak yeniden siniflandirilmistir.

V1.4 EKLEMELERI
----------------
- Du-2014 v1.3 verification sonucu nedeniyle aged + gauge-pressure yorumu final detailed model convention olarak sabitlendi.
- Final 150-segment truth-model wrapper eklendi: ro_truth_model_two_stage.m.
- Membrane aging ayri fonksiyona tasindi: ro_apply_membrane_age_du2014.m.
- Du-2014 without-ERD pump-energy ve SEC verification testi eklendi.
- Orijinal Lu/Du A/B primary truth-model parametreleri olarak korundu; datasheet-calibrated A/B sensitivity dali olarak birakildi.

V1.5 EKLEMELERI
----------------
- Du-2014 Eq.47-54 ve Eq.94 tabanli ERI PX-220 pressure-exchanger modeli eklendi.
- PX leakage Eq.50 icin kaynakta acik olmayan pressure-unit yorumu MPa ve bar olarak ayri test edilir.
- PX efficiency Eq.94 low-side pressure yorumu 0 ve post-filter 0.2 MPa(g) olarak ayri test edilir.
- Two-stage membrane + PX salinity mixing coupled fixed-point solver eklendi.
- PX case icin published recovery, product concentration, average flux, HPP feed flow ve SEC birlikte karsilastirilir.
- No-ERD enerji hesabina refined physical pressure-rise ve stage-pressure diagnostic testleri eklendi.
- ANN/performance-map uretimi bu PX verification ve sonraki architecture-screening karari tamamlanana kadar eklenmedi.

V1.6 ANN / DATASET EKLEMELERI
-----------------------------
- v1.5 validation physics korunmustur; mevcut benchmark inputlari ve transport denklemleri degistirilmemistir.
- Tek referans train icin 4-input recovery-conditioned surrogate mimarisi eklenmistir:
  [Qf_train, T_RO_in, Cf, R_target] -> optimized [W_RO, Cp, P1*, P2*].
- Internal optimization objective total RO electrical power minimizationidir; actual recovery R_target'a equality constraint ile baglanir.
- Scrambled Sobol + boundary/corner enrichment DOE generatoru eklenmistir.
- First-element average flux, numerical clipping ve solver-convergence diagnostics ro_pv_du2014 ciktilarina eklenmistir.
- Dataset feasibility wrapper'i Cp, Cb, first-element flux, pressure/head ve numerical convergence constraints'ini birlikte kontrol eder.
- TEOS-10 GSW tabanli CMEMS salinity -> Cf [kg/m3] preprocessing fonksiyonu eklenmistir.
- Pilot dataset varsayilan 600 point, full initial dataset varsayilan 4000 point olarak tanimlanmistir.
- ANN training bu dataset kalite kontrolu tamamlanmadan eklenmemistir.
