function cfg = ro_ann_config() % RO ANN dataset uretimi icin tek noktadan kullanilan configuration struct'ini olusturur.

%% REFERANS TRAIN GEOMETRISI % Du-2014 PX benchmark geometrisinin dortte biri olan tek train'i tanimlar.

cfg.geometry.N_PV_stage1 = 5; % Tek train Stage-1 pressure-vessel sayisini tanimlar.
cfg.geometry.N_PV_stage2 = 4; % Tek train Stage-2 pressure-vessel sayisini tanimlar.
cfg.geometry.n_elements_stage1 = 5; % Stage-1 element/PV sayisini tanimlar.
cfg.geometry.n_elements_stage2 = 4; % Stage-2 element/PV sayisini tanimlar.

%% TRUTH-MODEL AYARLARI % Validation sonrasi sabitlenen Du detailed model ayarlarini tanimlar.

cfg.model.N_segments = 150; % Final truth model icin 150 axial segment kullanir.
cfg.model.age_years = 3.0; % Du design-period ana membran durumunu 3 yil olarak tanimlar.
cfg.model.leakage_pressure_unit = 'bar'; % Validation'da kabul edilen PX Eq.50 pressure-unit yorumunu tanimlar.
cfg.model.Ppxlin_gauge_MPa = 0.2; % Validation'da kabul edilen PX low-pressure inlet basincini tanimlar.

%% ENERJI MODELI % Du-2014 Table 3 pump ve pretreatment parametrelerini tanimlar.

cfg.energy.P_SWIP_MPa = 0.5; % SWIP outlet gauge pressure degerini tanimlar.
cfg.energy.filter_loss_MPa = 0.3; % Filter ve diger pretreatment pressure loss degerini tanimlar.
cfg.energy.eta_SWIP = 0.65; % SWIP pump efficiency degerini tanimlar.
cfg.energy.eta_HPP = 0.75; % High-pressure pump efficiency degerini tanimlar.
cfg.energy.eta_BP = 0.65; % Booster pump efficiency degerini tanimlar.
cfg.energy.eta_motor = 0.98; % Electric motor efficiency degerini tanimlar.

%% ANN TRAINING DOMAIN % Dört-boyutlu recovery-conditioned surrogate training zarfini tanimlar.

cfg.domain.Qf_min_m3h = 35.0; % Tek aktif train icin minimum feed flow training degerini tanimlar.
cfg.domain.Qf_max_m3h = 75.0; % Tek aktif train icin maksimum feed flow training degerini tanimlar.
cfg.domain.T_min_C = 15.0; % Sea-water profilinin biraz altina uzanan minimum RO inlet temperature degerini tanimlar.
cfg.domain.T_max_C = 45.0; % Membrane manufacturer maximum operating temperature limitini training ust siniri yapar.
cfg.domain.Cf_min_kg_m3 = 38.5; % CMEMS-derived feed concentration araliginin alt buffer degerini tanimlar.
cfg.domain.Cf_max_kg_m3 = 41.5; % CMEMS-derived feed concentration araliginin ust buffer degerini tanimlar.
cfg.domain.R_min = 0.34; % Energy-optimum dusuk-recovery bolgesini kapsayan minimum recovery target degerini tanimlar.
cfg.domain.R_max = 0.60; % Yuksek-recovery bolgesini kapsayan maksimum recovery target degerini tanimlar.

%% HARD CONSTRAINT PARAMETRELERI % Dataset feasibility hesabinda kullanilan teknik limitleri tanimlar.

cfg.constraints.Cp_max_kg_m3 = 0.500; % Maximum product salinity degerini 500 mg/L olarak tanimlar.
cfg.constraints.Cb_max_kg_m3 = 90.0; % Du-2014 maximum brine/bulk concentration limitini tanimlar.
cfg.constraints.T_max_C = 45.0; % SW30XLE-400i maximum continuous operating temperature limitini tanimlar.
cfg.constraints.P_max_gauge_MPa = 8.3; % Maximum membrane operating gauge pressure limitini tanimlar.

%% P1-P2 INTERNAL OPTIMIZATION % Her DOE noktasi icin pressure optimization ayarlarini tanimlar.

cfg.optim.method = 'hybrid'; % v1.6.3 sonrasinda recovery-root seed + tek lokal fmincon refinement yontemini ana optimizer olarak secer.

cfg.optim.P1_lb_MPa = 4.0; % Stage-1 pressure search lower bound degerini tanimlar.
cfg.optim.P1_ub_MPa = 8.3; % Stage-1 pressure search upper bound degerini tanimlar.
cfg.optim.P2_lb_MPa = 4.0; % Stage-2 pressure search lower bound degerini tanimlar.
cfg.optim.P2_ub_MPa = 8.3; % Stage-2 pressure search upper bound degerini tanimlar.
cfg.optim.coarse_N_segments = 30; % Sadece initial-seed taramasinda kullanilan hizli axial grid sayisini tanimlar.
cfg.optim.coarse_points_per_axis = 5; % P1-P2 seed taramasinda her pressure eksenindeki nokta sayisini tanimlar.
cfg.optim.n_local_starts = 3; % En iyi coarse seed'lerden kac adet fmincon calistirilacagini tanimlar.
cfg.optim.max_iterations = 120; % Her local optimization icin maksimum iteration sayisini tanimlar.
cfg.optim.max_function_evaluations = 350; % Her local optimization icin maksimum truth-model evaluation sayisini tanimlar.
cfg.optim.constraint_tolerance = 1.0e-6; % fmincon nonlinear constraint toleransini tanimlar.
cfg.optim.step_tolerance = 1.0e-8; % fmincon step toleransini tanimlar.
cfg.optim.optimality_tolerance = 1.0e-7; % fmincon optimality toleransini tanimlar.
cfg.optim.recovery_accept_tolerance = 1.0e-4; % Final dataset row icin kabul edilen absolute recovery mismatch degerini tanimlar.


%% ROOT-BASED FAST OPTIMIZER % Recovery equality manifoldunu dogrudan izleyen hizli optimizer ayarlarini tanimlar.

cfg.root.P1_lb_MPa = 2.5; % Keyfi 4 MPa alt sinirini kaldirip dusuk-recovery noktalarini dislamayan Stage-1 search alt sinirini tanimlar.
cfg.root.P1_ub_MPa = 8.3; % Manufacturer maximum operating pressure degerini Stage-1 search ust siniri yapar.
cfg.root.P2_lb_MPa = 2.5; % Stage-2 root search icin genis fiziksel alt basinç sinirini tanimlar.
cfg.root.P2_ub_MPa = 8.3; % Manufacturer maximum operating pressure degerini Stage-2 root search ust siniri yapar.
cfg.root.coarse_N_segments = 30; % P1 taramasi ve recovery-root aramasinda hizli Du gridini kullanir.
cfg.root.final_N_segments = 150; % Dataset'e yazilan final sonucu validation ile secilen truth gridinde dogrular.
cfg.root.n_P1_coarse = 9; % Tum P1 araligini ilk geciste tarayan coarse P1 nokta sayisini tanimlar.
cfg.root.n_P1_refine = 5; % En iyi coarse P1 bolgesini ikinci kez tarayan local nokta sayisini tanimlar.
cfg.root.n_final_seeds = 2; % N=150 final dogrulamaya tasinacak en iyi coarse P1 aday sayisini tanimlar.
cfg.root.final_P1_offsets_MPa = [-0.12, -0.04, 0.04, 0.12]; % N=150 cozum etrafinda hem kaba hem ince iki-yonlu P1 refinement offsetlerini tanimlar.
cfg.root.n_P2_bracket = 5; % Her P1 icin recovery root bracket'i ararken kullanilan P2 probe sayisini tanimlar.
cfg.root.P2_hint_halfwidth_MPa = 0.35; % N=150 root aramasinda N=30 P2 tahmini etrafindaki hizli bracket yaricapini tanimlar.
cfg.root.recovery_tol_coarse = 2.0e-4; % N=30 root aramasinda kabul edilen absolute recovery hata toleransini tanimlar.
cfg.root.recovery_tol_final = 2.0e-5; % N=150 final root aramasinda kullanilan daha siki absolute recovery toleransini tanimlar.
cfg.root.max_bisection_iterations = 18; % P2 recovery root bisection dongusunun maksimum iteration sayisini tanimlar.
cfg.root.P2_width_tolerance_MPa = 2.0e-5; % P2 bracket genisligi bu degerin altina indiginde bisection'i sonlandirir.
cfg.root.coarse_constraint_penalty = 2.0e4; % Coarse P1 ranking'de normalized hard-constraint violation'larini power'dan daha onemli yapan katsayiyi tanimlar.
cfg.root.analytic_tolerance = 1.0e-10; % Analitik necessary-condition screening icin sayisal toleransi tanimlar.
cfg.root.physical_constraint_accept_tolerance = 1.0e-6; % Final normalized hard constraints icin yalnizca round-off seviyesinde kabul toleransi tanimlar.



%% ROOT-SEEDED HYBRID OPTIMIZER % Hızli recovery-root seed ile tek lokal N=150 fmincon refinement ayarlarini tanimlar.

cfg.hybrid.P1_lb_MPa = 2.5; % Mutlak global safeguard lower bound; actual seed lower bound osmotic-pressure margin ile dinamik hesaplanir.
cfg.hybrid.P1_osmotic_margin_MPa = 0.50; % Feed osmotic pressure uzerinde coarse P1 aramasinin baslayacagi minimum net-driving-pressure search marjini tanimlar; teknik hard constraint degildir.
cfg.hybrid.P1_ub_MPa = 8.3; % Stage-1 global search upper bound degerini tanimlar.
cfg.hybrid.P2_lb_MPa = 2.5; % Stage-2 global search lower bound degerini tanimlar.
cfg.hybrid.P2_ub_MPa = 8.3; % Stage-2 global search upper bound degerini tanimlar.
cfg.hybrid.seed_N_segments = 30; % Yalnizca recovery-matched initial seed aramasinda hizli N=30 gridini kullanir.
cfg.hybrid.final_N_segments = 150; % Final optimizer ve dataset outputunu validation ile secilen N=150 truth gridinde hesaplar.
cfg.hybrid.n_P1_seed = 7; % Dinamik P1 araliginda yuksek basinctan asagiya recovery-root seed arayan coarse P1 nokta sayisini tanimlar.
cfg.hybrid.break_after_recovery_unreachable = true; % Azalan P1 taramasinda P2=8.3 MPa'da hedef recovery artik ulasilamiyorsa daha dusuk P1 noktalarini taramayi durdurur.
cfg.hybrid.n_N150_seed_trials = 4; % N=30 adaylari arasindan N=150 truth-grid'e aktarilacak en iyi seed sayisini tanimlar.
cfg.hybrid.seed_transfer_recovery_tol = 1.0e-4; % N=150 seed transferinde fmincon baslangici icin yeterli recovery toleransini tanimlar.
cfg.hybrid.enable_root_fallback = true; % Dogrudan seed transferleri basarisiz olursa robust root optimizer sonucunu fmincon seed'i olarak kullanir.
cfg.hybrid.seed_constraint_penalty = 2.0e4; % Seed ranking'de physical constraint violation'larini power'dan daha onemli yapan katsayiyi tanimlar.
cfg.hybrid.P1_halfwidth_MPa = 0.80; % Root seed etrafindaki lokal fmincon Stage-1 pressure yaricapini tanimlar.
cfg.hybrid.P2_halfwidth_MPa = 1.00; % Root seed etrafindaki lokal fmincon Stage-2 pressure yaricapini tanimlar.
cfg.hybrid.max_iterations = 40; % Tek local SQP refinement icin maximum iteration sayisini tanimlar.
cfg.hybrid.max_function_evaluations = 90; % Tek local SQP refinement icin maximum truth-model evaluation sayisini tanimlar.
cfg.hybrid.constraint_tolerance = 1.0e-6; % Hibrit fmincon nonlinear constraint toleransini tanimlar.
cfg.hybrid.step_tolerance = 1.0e-7; % Hibrit fmincon step toleransini tanimlar.
cfg.hybrid.optimality_tolerance = 1.0e-6; % Hibrit fmincon first-order optimality toleransini tanimlar.

%% SOBOL DOE AYARLARI % Space-filling sampling ve boundary enrichment ayarlarini tanimlar.

cfg.doe.n_pilot = 600; % Legacy v1.6 pilot DOE boyutunu geriye donuk uyumluluk icin korur.
cfg.doe.n_root_pilot = 120; % Legacy root-pilot boyutunu geriye donuk uyumluluk icin korur.
cfg.doe.n_feasibility_pilot = 120; % FASTSEARCH dogrulandiktan sonra calistirilacak feasibility-aware pilot DOE boyutunu tanimlar.
cfg.doe.feas_core_fraction = 0.60; % Pilot generated noktalarinin core Qf-recovery bolgesine ayrilan oranini tanimlar.
cfg.doe.feas_lowR_fraction = 0.15; % Dusuk-recovery feasibility probe noktalarinin oranini tanimlar.
cfg.doe.feas_outerQ_fraction = 0.15; % Core Qf disindaki turndown/yuksek-debi probe noktalarinin oranini tanimlar.
cfg.doe.feas_upperR_fraction = 0.10; % Analitik recovery upper-envelope yakinini probe eden noktalarin oranini tanimlar.
cfg.doe.feas_Qf_core_min_m3h = 47.0; % Eski pilot ve multi-region benchmark sonrasi core feed-flow probe alt sinirini tanimlar; final hard domain degildir.
cfg.doe.feas_Qf_core_max_m3h = 64.0; % Eski pilot ve multi-region benchmark sonrasi core feed-flow probe ust sinirini tanimlar; final hard domain degildir.
cfg.doe.feas_R_core_min = 0.40; % Core pilotta recovery conditional sampling icin kullanilan alt probe degerini tanimlar; final feasible Rmin degildir.
cfg.doe.feas_R_low_probe_max = 0.42; % Dusuk-recovery probe bandinin nominal ust degerini tanimlar.
cfg.doe.feas_R_upper_margin = 0.005; % Analitik recovery upper-envelope'in hemen altinda birakilan sayisal/physical sampling marjini tanimlar.
cfg.doe.feas_n_known_anchors = 6; % v1.6.8'de yeniden dogrulanan alti feasible operating point'i pilot anchor olarak ekler.
cfg.doe.n_full = 4000; % Pilot basarili olduktan sonra onerilen ilk full dataset nokta sayisini tanimlar.
cfg.doe.boundary_fraction = 0.20; % Exact domain face noktalarinin toplam DOE icindeki hedef oranini tanimlar.
cfg.doe.include_corners = true; % Dört-boyutlu domain'in 16 kosesini DOE'ye eklemeyi etkinlestirir.
cfg.doe.skip = 2048; % Sobol sequence'in ilk noktalarini atlamak icin kullanilan Skip degerini tanimlar.
cfg.doe.leap = 0; % Sobol sequence icin Leap degerini tanimlar.
cfg.doe.scramble_method = 'MatousekAffineOwen'; % Reproducible low-discrepancy scrambling yontemini tanimlar.


%% FEASIBILITY ENVELOPE MAPPING % v1.7.0 ile Qf-T-Cf state basina fiziksel feasible recovery bandini haritalar.

cfg.envelope.n_states = 48; % Ilk envelope map icin toplam Qf-T-Cf base-state sayisini tanimlar.
cfg.envelope.n_R_coarse = 9; % Her base state'te recovery bandini bulmak icin kullanilan ilk coarse recovery probe sayisini tanimlar.
cfg.envelope.n_bisection = 6; % Alt ve ust feasible recovery sinirlarini refine etmek icin maximum bisection iteration sayisini tanimlar.
cfg.envelope.R_boundary_tolerance = 1.0e-3; % Recovery boundary bracket genisligi bu degerin altina indiginde refinement'i sonlandirir.
cfg.envelope.R_upper_guard = 2.0e-4; % Exact analytic upper bound uzerinde round-off kaynakli gereksiz failure'i onlemek icin kucuk recovery guard degerini tanimlar.
cfg.envelope.batch_states = 8; % State-level parfor checkpoint batch boyutunu tanimlar; 4 ve 6 worker sistemlerde dengeli calisir.
cfg.envelope.Qf_core_min_m3h = 49.0; % Envelope core-state feed-flow alt probe degerini tanimlar; final hard limit degildir.
cfg.envelope.Qf_core_max_m3h = 61.0; % Envelope core-state feed-flow ust probe degerini tanimlar; final hard limit degildir.
cfg.envelope.Qf_low_min_m3h = 46.0; % Dusuk-flow feasibility boundary probe alt degerini tanimlar.
cfg.envelope.Qf_low_max_m3h = 50.0; % Dusuk-flow feasibility boundary probe ust degerini tanimlar.
cfg.envelope.Qf_high_min_m3h = 61.0; % Yuksek-flow feasibility boundary probe alt degerini tanimlar.
cfg.envelope.Qf_high_max_m3h = 64.0; % Yuksek-flow feasibility boundary probe ust degerini tanimlar.
cfg.envelope.T_low_max_C = 24.0; % Ozellikle low-temperature feasibility boundary'sini zenginlestiren probe ust degerini tanimlar.
cfg.envelope.T_high_min_C = 39.0; % Yuksek-temperature feasibility bolgesini zenginlestiren probe alt degerini tanimlar.
cfg.envelope.resume_if_checkpoint_exists = true; % Yarida kesilen envelope run'inda mevcut checkpoint varsa tamamlanan state'lerden devam etmeyi etkinlestirir.

%% PROBE-GUIDED ADAPTIVE DOE % v1.7.0 probe logunu final classifier yerine yalnizca truth-model sampling proposal gate'i olarak kullanir.

cfg.guided.n_pilot = 120; % Proposal stratejisinin truth-valid precision'ini olcmek icin yeni pilot boyutunu tanimlar.
cfg.guided.candidate_pool_size = 12000; % Space-filling secimden once score verilecek Sobol candidate pool buyuklugunu tanimlar.
cfg.guided.knn_k = 24; % Leave-one-state diagnostic'te dengeli precision veren kNN komsu sayisini tanimlar.
cfg.guided.knn_weight_power = 2.0; % Feasibility proposal score icin inverse-distance-squared agirlik kullanir.
cfg.guided.knn_chunk_size = 500; % Candidate scoring sırasında memory kullanimi icin chunk boyutunu tanimlar.
cfg.guided.norm_lb = [46.0, 15.0, 38.5, 0.34]; % [Qf,T,Cf,R] normalized-distance lower reference vectorunu tanimlar.
cfg.guided.norm_ub = [64.0, 45.0, 41.5, 0.60]; % [Qf,T,Cf,R] normalized-distance upper reference vectorunu tanimlar.
cfg.guided.Qf_min_m3h = 47.5; % Adaptive pilot candidate feed-flow alt sinirini tanimlar; final hard train limit degildir.
cfg.guided.Qf_max_m3h = 63.0; % Adaptive pilot candidate feed-flow ust sinirini tanimlar; final hard train limit degildir.
cfg.guided.T_min_C = 20.0; % Adaptive pilot candidate inlet-temperature alt sinirini tanimlar; classifier negative data low-T probe logunda korunur.
cfg.guided.T_max_C = 45.0; % Adaptive pilot candidate inlet-temperature ust sinirini membrane max temperature ile sinirlar.
cfg.guided.Cf_min_kg_m3 = 38.5; % Mersin feed-concentration lower domain degerini korur.
cfg.guided.Cf_max_kg_m3 = 41.5; % Mersin feed-concentration upper domain degerini korur.
cfg.guided.R_candidate_floor = 0.39; % Envelope mappingde gozlenen Rmin>0.40 sonucuna gore tamamen verimsiz 0.34-0.39 proposal bandini dislar; final physics constraint degildir.
cfg.guided.R_analytic_guard = 0.003; % Candidate recovery'yi exact analytic upper cap'tan az miktarda iceri alir.
cfg.guided.R_min_span = 0.010; % Candidate state'in proposal icin en az sahip olmasi gereken necessary recovery span degerini tanimlar.
cfg.guided.core_score_min = 0.65; % High-confidence performance-sampling pool'u icin minimum kNN proposal score degerini tanimlar.
cfg.guided.boundary_score_low = 0.50; % Classifier-enrichment score-boundary pool'unun alt score degerini tanimlar.
cfg.guided.challenge_score_min = 0.55; % Low-T ve flow-edge challenge pool'larinda kullanilan minimum proposal support degerini tanimlar.
cfg.guided.fallback_score_min = 0.55; % Stratum pool yetersizliginde pilot boyutunu tamamlayacak fallback minimum score degerini tanimlar.
cfg.guided.max_nearest_distance = 0.55; % 4-D normalized uzayda prior probe'lardan asiri uzak extrapolative candidate'lari eler.
cfg.guided.lowT_max_C = 27.0; % Low-temperature challenge sampling'in ust temperature degerini tanimlar.
cfg.guided.Qf_low_edge_max_m3h = 50.0; % Low-flow edge challenge bolgesinin ust feed-flow degerini tanimlar.
cfg.guided.Qf_high_edge_min_m3h = 61.0; % High-flow edge challenge bolgesinin alt feed-flow degerini tanimlar.
cfg.guided.frac_lowT = 10.0 / 120.0; % Pilotun yaklasik 10 noktasini low-temperature challenge'a ayirir.
cfg.guided.frac_flow_edge = 10.0 / 120.0; % Pilotun yaklasik 10 noktasini flow-edge challenge'a ayirir.
cfg.guided.frac_score_boundary = 20.0 / 120.0; % Pilotun yaklasik 20 noktasini score-boundary enrichment'a ayirir.

%% FINAL GUIDED TRUTH DATASET % v1.8.0 production dataset boyutu, scalable sampling ve fixed ML split ayarlarini tanimlar.

cfg.final.n_truth = 2400; % Final truth production run icin toplam DOE point sayisini tanimlar.
cfg.final.candidate_pool_size = 60000; % 2400-point scalable maximin secimden once score verilecek Sobol candidate pool boyutunu tanimlar.
cfg.final.frac_lowT = 200.0 / 2400.0; % Final datasetin 200 noktasini low-temperature challenge stratumuna ayirir.
cfg.final.frac_flow_edge = 200.0 / 2400.0; % Final datasetin 200 noktasini low/high train-flow edge stratumuna ayirir.
cfg.final.frac_score_boundary = 400.0 / 2400.0; % Final datasetin 400 noktasini feasibility-score boundary enrichment stratumuna ayirir.
cfg.final.rng_seed = 20260812; % Final candidate scramble ve split assignment icin reproducibility RNG seed degerini tanimlar.
cfg.final.min_prior_distance = 0.015; % Mevcut probe/pilot noktalarina neredeyse duplicate candidates'i elemek icin minimum normalized prior distance degerini tanimlar.
cfg.final.train_fraction = 0.70; % Preassigned ML train split fraction'ini tanimlar.
cfg.final.validation_fraction = 0.15; % Preassigned ML validation split fraction'ini tanimlar.
cfg.final.test_fraction = 0.15; % Preassigned blind ML test split fraction'ini tanimlar.
cfg.final.batch_size = 24; % Production truth run checkpoint batch boyutunu 4 ve 6 worker ile tam bolunebilir 24 point olarak tanimlar.

%% HESAPLAMA VE CHECKPOINT % Uzun dataset run'larinda paralellik ve ara kayit ayarlarini tanimlar.

cfg.compute.use_parallel = true; % Parallel Computing Toolbox varsa DOE noktalarini parfor ile cozmek ister.
cfg.compute.fast_px_coupling = true; % ANN/optimizer evaluation'larinda ayni PX salinity fixed-point kokunu safeguarded secant ile hizli cozen solver'i etkinlestirir.
cfg.compute.fast_px_legacy_fallback_max_iter_coarse = 0; % N<150 coarse search'te secant basarisizsa pahali legacy 200-iterasyon dongusune girmeden noktayi nonconverged olarak reddeder.
cfg.compute.fast_px_legacy_fallback_max_iter_final = 40; % N=150 final/refinement'ta secant basarisizsa yalnizca sinirli legacy fallback ile valid kok kurtarma sansi verir.
cfg.compute.batch_size = 25; % Genel dataset run'lari icin varsayilan checkpoint batch size degerini tanimlar; feasibility pilot runner bunu 12'ye override eder.

%% CMEMS / MERSIN KONUMU % Salinity conversion ve EPW alignment icin sabit konum bilgilerini tanimlar.

cfg.site.latitude_deg = 36.729168; % Ortak CMEMS temperature-salinity grid latitude degerini tanimlar.
cfg.site.longitude_deg = 34.583336; % Ortak CMEMS temperature-salinity grid longitude degerini tanimlar.
cfg.site.depth_m = 10.536604; % CMEMS seawater profile depth degerini tanimlar.
cfg.site.epw_latitude_deg = 36.78083; % Mersin TMY/EPW latitude degerini tanimlar.
cfg.site.epw_longitude_deg = 34.60305; % Mersin TMY/EPW longitude degerini tanimlar.
cfg.site.timezone_UTC = 3.0; % Mersin EPW timezone degerini UTC+3 olarak tanimlar.

end % Configuration fonksiyonunu sonlandirir.
