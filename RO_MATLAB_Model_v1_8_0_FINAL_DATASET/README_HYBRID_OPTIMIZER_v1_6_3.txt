RO MATLAB MODEL v1.6.3 - ROOT-SEEDED HYBRID OPTIMIZER

Amaç
----
v1.6.2 saf root optimizer reference noktada recovery hedefini tam saglamis ancak
minimum power optimumunu yeterince refine edememistir:
P1 = 6.97000 MPa(g), P2 = 7.83772 MPa(g), W = 103.7952 kW, Cp = 494.151 mg/L.
Daha once kabul edilen N=150 fmincon sonucu W = 101.05749 kW oldugu icin v1.6.2
reference noktada yaklasik +2.71% suboptimal kalmistir.

v1.6.3 yaklasimi
-----------------
1) Analitik infeasibility screening.
2) N=30 modelde 7 adet P1 noktasi icin recovery-matched P2 root aramasi.
3) En iyi root seed'in ayni P1 degerinde N=150 recovery root ile tekrar kurulmasi.
4) Bu equality-manifold'a yakin seed'den yalnizca TEK lokal N=150 fmincon/SQP refinement.
5) fmincon root seed'den daha kotu veya gecersiz ise valid root seed fallback olarak korunur.

Bu yontem eski 25-point 2-D coarse grid + 3 fmincon start yapisindan cok daha az local solve
kullanirken, saf root1d yontemindeki P1 coarse-grid bias'ini final SQP ile gidermeyi hedefler.

Ilk test
--------
out = test_RO_hybrid_reference_train;

Reference noktada once accuracy ve runtime kabul edilmeden yeni DOE calistirilmamalidir.
