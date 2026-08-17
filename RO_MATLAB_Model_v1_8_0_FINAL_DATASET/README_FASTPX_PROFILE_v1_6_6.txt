RO MATLAB MODEL v1.6.6 - FASTPX PRESSURE-DOMAIN PROFILING
=========================================================

Amaç:
- v1.6.5 FastPX optimum noktada ~6.7x hizli olmasina ragmen hybrid optimizer runtime'inin ~9.6 dakika kalmasinin nedenini olcmek.
- Fizik, membrane transport, PX correlations ve optimizer mantigi DEGISTIRILMEMISTIR.
- Sadece ro_evaluate_train_operating_point.m icine solver-method/runtime diagnostics eklenmistir.
- Yeni test 7 P1 x 5 P2 = 35 adet N=30 pressure probe calistirir.

Calistirma:
1) Bu klasoru MATLAB Current Folder yapin.
2) clear functions; rehash
3) Results = test_RO_fastPX_pressure_domain_profile;

Beklenen diagnostics:
- PXMethod = secant veya legacy_fallback
- PXMapEvals
- EvalRuntime_s
- Summary'de fallback orani ve secant/fallback ortalama sureleri

Bu testten sonra RO_fastPX_pressure_domain_profile.csv olusur.
