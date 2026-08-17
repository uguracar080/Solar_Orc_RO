RO MATLAB Model v1.7.1 - PROBE-GUIDED ADAPTIVE DOE PILOT
=========================================================

Bu surum v1.7.0 feasibility-envelope run'inda uretilen 622 labeled optimizer probe'unu
yalnizca yeni DOE noktalarini daha verimli ONERMEK icin kullanir.

Degismeyen kisimlar:
- N=150 truth model
- FastPX solver
- v1.6.7 FASTSEARCH hybrid pressure optimizer
- fiziksel constraint seti

Yeni kisimlar:
- ro_knn_probe_feasibility_score.m
- ro_generate_doe_probe_guided.m
- ro_summarize_probe_guided_pilot.m
- run_RO_ANN_probe_guided_pilot.m

Package icinde kullanicinin v1.7.0 run'undan gelen iki prior artifact de vardir:
- RO_feasibility_envelope.csv
- RO_feasibility_envelope_probes.csv

KNN ONEMLI NOT:
Bu kNN nihai feasibility classifier degildir ve annual simulation'da kullanilmayacaktir.
Yalnizca expensive truth-model dataset generation'da invalid point oranini azaltmak icin
proposal gate olarak kullanilir. Her selected point tekrar validated truth-model ile cozulur.

Pilot tasarimi (120 point):
- 80 civari HighConfidenceCore
- 20 civari ScoreBoundaryProbe
- 10 civari LowTemperatureChallenge
- 10 civari FlowEdgeChallenge
Pool yetersizliginde sayilar GuidedFallback ile otomatik tamamlanabilir.

Calistirma:
clear functions
rehash
[Dataset, Summary, DOE] = run_RO_ANN_probe_guided_pilot;

Gecis kriterleri:
- overall valid >= 70%
- proposal score >= 0.65 bolgesinde valid >= 75%
- explicit recovery-root failure <= 3%

Bu pilot gecerse bir sonraki asama full adaptive truth dataset uretimidir.
ANN training bu surumde baslatilmaz.
