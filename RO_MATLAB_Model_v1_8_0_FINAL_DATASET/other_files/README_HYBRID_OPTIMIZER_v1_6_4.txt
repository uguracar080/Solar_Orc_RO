RO HYBRID OPTIMIZER v1.6.4

Amaç:
- v1.6.3'te N=30 gridde tek en iyi seed secilip N=150'ye aktariliyordu.
- Reference testte bu tek seed N=150 recovery root'a sahip olmadigi icin optimizer fmincon'a gecemeden ExitFlag=-12 ile durdu.

Duzeltme:
1) N=30 recovery-root adaylari score'a gore siralanir.
2) En iyi 4 aday sirayla N=150 truth-grid'e aktarilir.
3) Ilk fiziksel-feasible N=150 seed bulunduğunda gereksiz transferler durdurulur.
4) N=150 seed-transfer tolerance final dataset acceptance ile uyumlu 1e-4 olarak kullanilir; fmincon daha sonra refine eder.
5) Kullanilan seed rank ve N=30 P1/P2 degerleri diagnostic output olarak kaydedilir.
6) Tum transferler basarisizsa her seed icin P1, P2 hint, failure reason ve recovery error ErrorMessage alanina yazilir.

Truth model:
- Final fiziksel/model sonucu hala N_segments=150 ile hesaplanir.
- Membran, PX, enerji ve validation denklemlerinde degisiklik yoktur.

Ilk test:
    out = test_RO_hybrid_reference_train;

600-point veya full DOE'ye bu test dogrulanmadan gecilmemelidir.
