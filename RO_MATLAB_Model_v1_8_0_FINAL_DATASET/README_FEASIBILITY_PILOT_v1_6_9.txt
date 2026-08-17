RO MATLAB MODEL v1.6.9 - FEASIBILITY-AWARE PILOT
=================================================

AMAÇ
----
v1.6.8 multi-region benchmark 6/6 accepted ve ortalama 14.67 s/point sonucundan sonra,
ANN training'e gecmeden once 120-point kucuk bir feasibility-aware pilot dataset uretmek.

BU SURUMDE FIZIK/OPTIMIZER DEGISIKLIGI YOK
-----------------------------------------
- Validated Du transport model ayni.
- N_segments = 150 final truth model ayni.
- FastPX safeguarded secant solver ayni.
- v1.6.7 FASTSEARCH hybrid optimizer ayni.
- P1/P2 objective ve hard constraints ayni.

YENI DOE MANTIGI
----------------
Eski 600-point pilotta Rtarget, Qf'den bagimsiz dikdortgen Sobol ile seciliyordu.
Yeni pilotta recovery, her Qf-Cf sample icin analitik necessary Rmax envelope'ine kosullu secilir.

120 point kompozisyonu yaklaşık olarak:
- CoreConditional        : generated noktalarin %60'i; Qf 47-64 m3/h, T ve Cf tam domain.
- LowRecoveryProbe       : %15; R=0.34-0.42 bolgesini robust optimizer ile yeniden test eder.
- OuterQfLow/HighProbe   : %15; Qf 35-47 ve 64-75 m3/h dis zarfini probe eder.
- UpperRecoveryProbe     : %10; analytic Rmax envelope yakinini probe eder.
- KnownFeasibleAnchor    : v1.6.8'de tekrar dogrulanan 6 nokta.

47-64 m3/h core araligi final hard training domain DEGILDIR. Pilot efficiency icin kullanilan probe bandidir.
Outer-Qf samples sayesinde turndown ve high-flow feasibility boundaries korunur.
T=15-45 C ve Cf=38.5-41.5 kg/m3 zarfı pilot boyunca tam olarak probe edilir.

CALISTIRMA
----------
Yeni klasoru MATLAB Current Folder yapin:

clear functions
rehash

[Dataset, Summary, DOE] = run_RO_ANN_feasibility_pilot;

Parallel Computing Toolbox varsa outer DOE loop parfor ile calisir.
Runner checkpoint batch size = 12 kullanir.

OLUSAN ANA DOSYALAR
-------------------
RO_ANN_DOE_feasibility_pilot.csv
RO_ANN_feasibility_pilot_partial.mat
RO_ANN_feasibility_pilot.mat
RO_ANN_feasibility_pilot.csv
RO_ANN_feasibility_pilot_overall_summary.csv
RO_ANN_feasibility_pilot_type_summary.csv
RO_ANN_feasibility_pilot_failure_summary.csv
RO_ANN_feasibility_pilot_valid_ranges.csv
RO_ANN_feasibility_pilot_active_constraint_summary.csv

NOT
---
Bu run ANN egitmez. Once valid/infeasible dagilimi, failure reasons, actual feasible input-output ranges,
constraint boundary coverage ve runtime incelenecek; daha sonra full DOE ve ANN architecture karari verilecek.
