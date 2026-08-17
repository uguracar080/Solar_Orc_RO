RO MATLAB MODEL v1.6.2 - RECOVERY ROOT OPTIMIZER
=================================================

AMAÇ
----
v1.6.1 pilot DOE'de 450 noktanin yalnizca 19'u valid cikti ve legacy 2-D fmincon
algoritmasi batch basina yaklasik 50 dakika surdu. v1.6.2 transport / PX / energy
truth-model denklemlerini degistirmez. Yalnizca ANN dataset pressure-optimization
katmanini yeniden duzenler.

ANA DEGISIKLIK
--------------
Legacy:
    min W(P1,P2)
    subject to Recovery(P1,P2) = Rtarget + technical constraints

v1.6.2:
    1) Analitik necessary-condition screening
    2) Sabit P1 icin P2, Recovery(P1,P2)=Rtarget root'u ile bulunur
    3) P1 boyunca yalnız recovery-manifold'u uzerinde power/feasibility aranir
    4) Search N=30 ile yapilir
    5) Dataset'e yazilan final point N=150 truth model ile yeniden root edilir

Bu nedenle optimizer artik 2-D pressure duzleminde recovery equality manifoldunu
fmincon ile aramaz.

ANALITIK SCREENING
------------------
Detailed model cagrisindan once pressure'dan bagimsiz kesin necessary conditions
kontrol edilir:

- Stage-1 feed/PV <= 16 m3/h
- T <= 45 C
- Target average flux <= 20 LMH
- Target final Stage-2 brine/PV >= 3.6 m3/h
- Raw-feed salt-balance iyimser lower bound ile Cb <= 90 kg/m3 gerekliligi

Bu screening sufficient feasibility testi degildir. Sadece kesin imkansiz noktalari
pahali truth-model optimization'ina girmeden eler.

YENI DOSYALAR
-------------
ro_analytic_screen_train_point.m
    Pressure optimization'dan once necessary-condition screening yapar.

ro_find_P2_for_recovery.m
    Sabit P1 icin P2 recovery root'unu hint-centered bracket + hybrid
    secant/bisection ile bulur. Evaluation cache kullanir.

ro_optimize_train_point_root.m
    P1 coarse/refined search + final N=150 verification yapar.

 test_RO_root_optimizer_benchmark.m
    12 secili point ile yeni optimizer'i v1.6.1 basarili sonuclara ve
    representative failure noktalarina karsi test eder.

DEGISTIRILEN DOSYALAR
---------------------
ro_ann_config.m
    cfg.optim.method='root1d' ve cfg.root.* ayarlari eklendi.

ro_evaluate_train_operating_point.m
    Fizik denklemleri degismedi. Yalniz normalized hard constraint'lerde
    1e-6 round-off acceptance toleransi eklendi.

ro_dataset_row_template.m
    Root optimizer diagnostics kolonlari eklendi.

ro_generate_training_dataset.m
    cfg.optim.method='root1d' ise yeni optimizer'i cagiracak dispatcher eklendi.

ILK CALISTIRILACAK TEST
-----------------------
MATLAB Current Folder'i bu klasore ayarlayin ve:

    Results = test_RO_root_optimizer_benchmark;

calistirin.

Test bittiginde:

    RO_root_optimizer_benchmark.csv
    RO_root_optimizer_benchmark.mat

olusur.

KABUL KRITERLERI - ILK BENCHMARK
--------------------------------
Kesin karar benchmark sonucuna gore verilecektir; baslangic hedefleri:

1) Eski valid reference case'lerin 7/7'sinin yeniden valid bulunmasi.
2) Power farkinin tercihen mean < 1%, max < 2% olmasi.
3) Recovery residual'in final acceptance toleransi icinde kalmasi.
4) Representative physical failure case'lerin hata nedenlerinin korunmasi.
5) Point runtime'in legacy yaklasimdan belirgin bicimde dusmesi.

NOT
---
Bu benchmark basarili olmadan 600 veya 4000 point dataset run'i baslatmayin.
Sonraki adim 100-120 point feasibility-aware pilot olacaktir.
