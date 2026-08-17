function sys = ro_truth_model_two_stage(Qf_total_m3h, Cf_kg_m3, P1_gauge_MPa, P2_gauge_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, age_years) % Final detailed two-stage RO truth model wrapper fonksiyonudur.

%% FINAL MODEL SABITLERI % Verification ve grid-independence sonucunda secilen model ayarlarini tanimlar.

N_segments = 150; % N=200 referansa gore Qp ve Cp icin %0.1 altinda hata veren 150 axial segment kullanir.
mem_base = ro_membrane_SW30XLE400(); % Lu/Du literature SW30XLE-400 base parametrelerini yukler.
mem = ro_apply_membrane_age_du2014(mem_base, age_years); % Du-2014 aging denklemleri ile membrane yasini uygular.

%% BASINC DONUSUMU % RO operating pressure girdilerini gauge MPa'dan internal absolute MPa'ya cevirir.

P1_abs_MPa = P1_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-1 gauge operating pressure degerini absolute basinca cevirir.
P2_abs_MPa = P2_gauge_MPa + mem.permeate_pressure_abs_MPa; % Stage-2 gauge operating pressure degerini absolute basinca cevirir.

%% DETAILED TWO-STAGE COZUM % Du-2014 local finite-difference modeli ile sistemi cozer.

sys = ro_system_two_stage_interstage_pressure(Qf_total_m3h, Cf_kg_m3, P1_abs_MPa, P2_abs_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, mem); % Final detailed two-stage RO cozumunu calistirir.

%% MODEL META-VERILERI % Surrogate dataset ve publication raporlama icin model secimlerini ciktida saklar.

sys.model_name = 'Du2014_detailed_truth_model'; % Truth model adini kaydeder.
sys.pressure_input_convention = 'gauge_MPa'; % Dis kullanicinin pressure input convention degerini kaydeder.
sys.internal_pressure_convention = 'absolute_MPa'; % Internal solver pressure convention degerini kaydeder.
sys.N_segments_truth = N_segments; % Final truth-model axial segment sayisini kaydeder.
sys.membrane_age_years = age_years; % Kullanilan membrane age degerini kaydeder.
sys.fouling_factor = mem.fouling_factor; % Kullanilan fouling factor degerini kaydeder.
sys.B_kg_m2_s = mem.B_kg_m2_s; % Kullanilan aged B degerini kaydeder.
sys.Aref_kg_m2_s_Pa = mem.Aref_kg_m2_s_Pa; % Kullanilan Lu/Du Aref degerini kaydeder.

end % Fonksiyonu sonlandirir.
