RO MATLAB MODEL v1.6.8 - FASTSEARCH MULTI-POINT BENCHMARK
=========================================================

Amaç
----
Tek Du reference point'te doğrulanan v1.6.7 FASTSEARCH + FastPX hibrit optimizer'ı,
eski 450-point pilot dataset'te valid bulunan ve farklı Qf-T-Cf-R bölgelerini temsil eden
6 operating point üzerinde yeniden test eder.

Yeni fizik modeli yoktur. v1.6.7 transport/PX/energy/constraint/optimizer kodu aynen korunur.
Bu sürüm yalnızca test_RO_fastsearch_multipoint_benchmark.m benchmark script'ini ekler.

Çalıştırma
---------
clear functions
rehash
Results = test_RO_fastsearch_multipoint_benchmark;

Seçilen bölgeler
----------------
1) yüksek Qf / düşük recovery
2) düşük temperature / yüksek recovery / P2 upper-limit yakını
3) yüksek temperature / product-salinity margin mevcut
4) yüksek salinity / P2 upper-limit yakını
5) yüksek temperature / yüksek recovery
6) orta Qf / düşük recovery

Her case için eski pressure pair mevcut N=150 FastPX truth modelinde tekrar değerlendirilir.
Ardından yeni FASTSEARCH hibrit optimizer çalıştırılır.

Case acceptance
---------------
- New DatasetValid = true
- |Recovery_actual - R_target| <= 1e-4
- Eski pressure pair current truth modelde valid ise yeni optimum power,
  current-old power'dan %1'den fazla yüksek olmamalıdır.
- Yeni çözüm eski power'dan daha düşükse bu failure değildir.

Output
------
RO_fastsearch_multipoint_benchmark.csv
RO_fastsearch_multipoint_benchmark.mat

Overall benchmark pass = 1 olması sonraki feasibility-aware pilot DOE aşamasına geçiş kriteridir.
