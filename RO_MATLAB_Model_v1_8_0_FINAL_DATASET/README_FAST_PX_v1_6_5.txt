RO MATLAB MODEL v1.6.5 FAST-PX
==============================

AMAC
----
v1.6.4 hybrid optimizer reference point'te eski optimumu tam olarak yeniden uretmistir,
ancak tek nokta 243 s surmustur. Profil analizi, tek bir truth-model evaluation icinde PX
salinity coupling fixed-point dongusunun tipik olarak ~29 iteration yaptigini gostermistir.

Bu surum optimizer fiziğini veya membrane denklemlerini DEGISTIRMEZ. Yalnizca scalar
PX mixing fixed-point equation F(C1)=C1 ayni 1e-8 tolerance ile safeguarded secant
method kullanilarak daha az membrane solve ile cozulur. Secant convergence saglamazsa
validated legacy 0.5 under-relaxation loop otomatik fallback olarak calisir.

ONCE CALISTIRILACAK TEST
------------------------
report = test_RO_fastPX_equivalence_reference;

KABUL KRITERI
-------------
Equivalence accepted = 1
Recovery, Qp, Cp, Power ve SEC farklari numerical round-off seviyesinde olmali.
Fast runtime legacy runtime'dan belirgin sekilde dusuk olmali.

Bu equivalence testi gecmeden hybrid optimizer veya DOE calistirilMAMALIDIR.

NOT
---
run_all_RO_tests legacy ro_system_two_stage_px_du2014.m yolunu kullanmaya devam eder.
Dolayisiyla validation reproduction branch aynen korunmustur.
