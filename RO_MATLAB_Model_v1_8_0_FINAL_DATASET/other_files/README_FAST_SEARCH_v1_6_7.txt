RO MATLAB MODEL v1.6.7 - FAST PRESSURE SEARCH
==============================================

Bu surum v1.6.6 pressure-domain profiling sonucuna gore hazirlandi.
Profilde 35 N=30 pressure probe noktasinin yalnizca 5'i legacy fallback'e dustu,
ama bu 5 nokta toplam runtime'in yaklasik %97.4'unu tuketti. Bes noktanin tamami
P1=2.5 MPa(g) satirindaydi ve 200-iterasyon legacy fallback limitini tuketti.

Yapilan degisiklikler:
1) Hybrid P1 seed search alt siniri artik sabit 2.5 MPa degil:
      P1_lb_dynamic = max(2.5, pi_feed + 0.50 MPa)
   Buradaki +0.50 MPa teknik hard constraint degildir; yalnizca optimizer search
   lower-bound marjinidir. Final DOE sonrasinda optimumlerin bu sinira yigilip
   yigilmatigi kontrol edilecektir.

2) P1 seed grid yuksek basinçtan dusuge dogru taranir. Coarse N=30 root search'te
   P2=8.3 MPa(g) noktasinda bile hedef recovery ulasilamiyorsa daha dusuk P1
   noktalarina gecilmez.

3) N=30 coarse search'te safeguarded secant PX solver basarisizsa 200 iterasyonluk
   legacy fallback CALISTIRILMAZ. Nokta nonconverged olarak reddedilir.

4) N=150 final/refinement evaluation'larda secant basarisizsa en fazla 40 legacy
   fallback iterasyonu korunur. Böylece coarse search hizlanirken final-gridde
   valid root kurtarma sansi tamamen kaldirilmaz.

5) Validated legacy ro_system_two_stage_px_du2014.m fonksiyonu degistirilmemistir.
   Fast branch yalniz ANN/optimizer evaluation path'inde kullanilir.

ONERILEN TEST
-------------
Current Folder bu klasor iken:

clear functions
rehash
out = test_RO_hybrid_reference_train;

Reference kabul kriterleri:
- DatasetValid = 1
- ExitFlag = 1
- P1* ~= 7.15855 MPa(g)
- P2* ~= 7.68423 MPa(g)
- W ~= 101.05749 kW
- Cp <= 500 mg/L
- Recovery ~= 0.5808

Bu testten sonra runtime ve evaluation sayilari onceki v1.6.6/v1.6.4 ile karsilastirilmalidir.
