RO MATLAB Model v1.7.0 - FEASIBILITY ENVELOPE
============================================================

Bu surum RO truth modelini, FastPX fizik cozumunu veya v1.6.7 FASTSEARCH optimizer'ini degistirmez.
Yeni katman yalnizca Qf-T-Cf base state basina feasible recovery bandini haritalar:

    Rmin_feasible(Qf,T,Cf) <= R <= Rmax_feasible(Qf,T,Cf)

Neden:
- v1.6.9 pilotta 120/120 analytic upper-screen pass olmasina ragmen sadece 31/120 valid cikti.
- LowRecoveryProbe 0/17 ve OuterQfLow/High 0 valid cikti.
- Bu, yalniz analytic Rmax kullanmanin yeterli olmadigini ve state-dependent Rmin gerektigini gosterdi.

Yontem:
1) 48 adet stratified Qf-T-Cf base state.
2) Her state icin 9 coarse recovery probe.
3) En uzun contiguous valid recovery adasi secilir.
4) Lower invalid->valid boundary ve upper valid->invalid boundary 6 adima kadar bisection ile refine edilir.
5) Exact analytic Rmax uzerinde 2e-4 guard kullanilir.
6) State-level parfor ve 8-state checkpoint batch kullanilir.
7) Yarida kesilirse RO_feasibility_envelope_partial.mat checkpoint'inden ayni deterministic state seti icin devam eder.

ONCE SMOKE TEST:
    clear functions
    rehash
    [env, probes] = test_RO_feasibility_envelope_smoke;

Smoke test PASS ise FULL MAP:
    [Envelope, ProbeLog, BaseStates, Summary] = run_RO_feasibility_envelope;

Ana outputs:
- RO_feasibility_envelope_base_states.csv
- RO_feasibility_envelope.csv
- RO_feasibility_envelope_probes.csv
- RO_feasibility_envelope.mat
- RO_feasibility_envelope_overall_summary.csv
- RO_feasibility_envelope_type_summary.csv
- RO_feasibility_envelope_lower_boundary_failures.csv
- RO_feasibility_envelope_upper_boundary_failures.csv
- RO_feasibility_envelope_probe_summary.csv

Not:
- Qf=46-64 m3/h burada final hard ANN domain degildir; boundary mapping probe zarfidir.
- T=15-45 C ve Cf=38.5-41.5 kg/m3 korunur.
- NonContiguousCoarse=true cikan state'ler full ANN DOE'den once tek tek incelenmelidir.
- ANN training bu surumde baslatilmaz.
