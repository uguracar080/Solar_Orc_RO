RO MATLAB MODEL v1.6 - ANN / SURROGATE DATASET PREPARATION
==========================================================

AMAÇ
----
Bu sürüm v1.5 doğrulama paketini korur ve tek bir referans PX'li RO train için
recovery-conditioned optimal operating policy surrogate dataset üretim altyapısını ekler.

SURROGATE TANIMI
----------------
Inputs:
  Qf_train [m3/h]
  T_RO_in [degC]
  Cf [kg/m3]
  R_target [-]

Truth-model internal decision variables:
  P1 [MPa(g)]
  P2 [MPa(g)]

Internal objective:
  minimize W_RO,total [kW]

Equality constraint:
  Recovery_actual = R_target

Primary ANN targets önerisi:
  W_RO_train [kW]
  Cp [mg/L]
  P1_opt [MPa(g)]
  P2_opt [MPa(g)]

Qp, Recovery ve SEC physical consistency için yıllık modelde input/outputlardan hesaplanabilir.
Dataset içinde gerçek Qp, Recovery ve SEC ayrıca diagnostic olarak saklanır.

TRAIN GEOMETRISI
----------------
Stage 1 = 5 PV x 5 element/PV
Stage 2 = 4 PV x 4 element/PV
Age = 3 years
N_segments final = 150
PX leakage correlation pressure unit = bar
PX low-pressure inlet = 0.2 MPa(g)
PX efficiency = 95% (mevcut validated PX model içinde)

TRAINING DOMAIN
---------------
Qf_train = 35-75 m3/h
T_RO_in = 15-45 degC
Cf = 38.5-41.5 kg/m3
R_target = 0.34-0.60

DOE
---
Scrambled Sobol kullanılır.
- Interior low-discrepancy samples
- %20 exact domain-face enrichment
- 16 exact 4-D corners

Pilot: 600 points
Full initial dataset: 4000 points

ÖNEMLİ FEASIBILITY EKLERI
-------------------------
Dataset wrapper mevcut v1.5 sys.feasible flag'i yerine daha kapsamlı constraint seti kullanır:
- feed flow/PV <= 16 m3/h
- brine flow/PV >= 3.6 m3/h
- system average flux <= 20 LMH
- Stage-1 first-element average flux <= 35 LMH
- Stage-2 first-element average flux <= 48 LMH
- CPFmax Stage 1 <= 1.2
- CPFmax Stage 2 <= 1.4
- dP/PV <= 0.35 MPa
- Cp <= 500 mg/L
- maximum bulk/brine concentration <= 90 kg/m3
- P1,P2 <= 8.3 MPa(g)
- T <= 45 degC
- P2 >= Stage-1 outlet pressure (negative interstage pump head yasak)
- P1 >= PX high-side outlet pressure (negative PX booster head yasak)
- PX fixed-point convergence
- all local transport solves converged
- numerical 95% segment flow clipping inactive

FIRST-ELEMENT FLUX DÜZELTMESI
-----------------------------
v1.5 ro_pv_du2014.m yalnızca maximum local segment flux raporluyordu.
Du constraint'i first membrane element permeate flux ile ilgilidir.
v1.6, first element uzunluğu ile segment overlap alanını kullanarak area-weighted
first-element average flux hesaplar. Mevcut transport çözümü veya validation outputs değiştirilmez.

SALINITY PREPROCESSING
----------------------
Final annual profile için:
  Practical Salinity SP
  -> TEOS-10 Absolute Salinity SA [g/kg]
  -> TEOS-10 density rho [kg/m3]
  -> Cf = rho * SA / 1000 [kg/m3]

MEDSEA variable sea-water potential temperature olduğundan TEOS-10 pipeline:
  p = gsw_p_from_z(...)
  SA = gsw_SA_from_SP(...)
  CT = gsw_CT_from_pt(...)
  rho = gsw_rho(...)

Final conversion için resmi TEOS-10 GSW MATLAB Toolbox gerekir.
ro_preprocess_seawater_profile_teos10.m toolbox yoksa sessiz approximate fallback yapmaz.
ro_cmems_salinity_reference_approx.m sadece domain/sensitivity kontrolü için ayrıca verilmiştir.

ÖNERİLEN ÇALIŞTIRMA SIRASI
--------------------------
1) Önce mevcut validation'ın değişmediğini kontrol edin:
       run_all_RO_tests

2) GSW toolbox kuruluysa seawater profile dönüştürün:
       cfg = ro_ann_config;
       Profile = ro_preprocess_seawater_profile_teos10('seawater_profile(1).csv', 'seawater_profile_RO_ready.csv', cfg);

3) EPW / seawater hour mapping kontrolü:
       check_Mersin_EPW_seawater_alignment('TUR_IC_Mersin.173400_TMYx.2009-2023(2).epw', 'seawater_profile(1).csv');

4) ANN wrapper ve internal optimizer için tek-train smoke test çalıştırın:
       out = test_RO_ANN_reference_train;

5) Smoke test sorunsuzsa pilot optimized truth-model dataset üretin:
       Dataset = run_RO_ANN_pilot_dataset;

6) Pilot CSV'yi paylaşın / inceleyin:
       RO_ANN_pilot_dataset.csv

7) Feasible fraction, constraint-boundary coverage, optimizer failures ve outlier kontrolleri kabul edilirse:
       Dataset = run_RO_ANN_full_dataset;

ANN training kodu bu pilot/full dataset kalite kontrolünden sonra eklenmelidir.


V1.6.1 PATCH NOTE
-----------------
PX high-side outlet pressure can be slightly higher than Stage-1 operating pressure under the validated Du Eq.94 implementation. Therefore P1 >= Ppxhout is not enforced as a hard feasibility constraint. Positive PX outlet excess is retained as PX_excess_pressure_MPa and interpreted as pressure to be dissipated by throttling/mixing; when Ppxhout < P1, PX_booster_deltaP_MPa is retained and electrical booster power is calculated by ro_energy_du2014.m. This change prevents the validated Du PX benchmark from being rejected by a newly introduced pressure-order constraint.
