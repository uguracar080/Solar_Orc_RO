ORC_v16 - faster and broader fixed-geometry dispatch test layer

Main changes relative to ORC_v15:
- Dispatch candidate ordering was revised so reduced ORC mass-flow candidates are not starved by pressure sweeps.
- Candidate grid was expanded for Pevap/Pcond search.
- A thermodynamic pre-screen skips candidates with impossible source/sink terminal temperatures before HX rating.
- Candidate screening uses a one-pass fixed-geometry rating; only promising candidates are validated with the normal hydraulic iteration.
- Physical design/sizing model is unchanged from v0.14/v0.15.

Run:
    orc_quickstart

Key output block:
    ORC STAGE-2 DISPATCH TEST SUITE - V0.16

The expected improvement is a much lower dispatch-test time than v0.15 and more ON cases for low-source/part-load points that were previously missed because maxCandidates was consumed by high-load pressure candidates.
