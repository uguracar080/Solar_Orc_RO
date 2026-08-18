function cal = ro_calibrate_AB_datasheet(N_segments) % SW30XLE-400 A ve B degerlerini standard datasheet noktasina sayisal olarak kalibre eder.

%% VARSAYILAN GRID % Kullanici grid sayisi vermezse calibration gridini tanimlar.

if nargin < 1 % Segment sayisi verilmediyse kontrol eder.
    N_segments = 100; % Calibration icin varsayilan 100 axial segment kullanir.
end % Varsayilan grid kosulunu sonlandirir.

%% MEMBRAN VE REFERENCE DEGERLERI % Manufacturer standard test noktasini tanimlar.

mem0 = ro_membrane_SW30XLE400(); % Orijinal Lu/Du membran parametrelerini yukler.
Qp_ref_m3h = mem0.nominal_permeate_m3_day / 24.0; % Nominal permeate debisini m3/h birimine cevirir.
Qf_test_m3h = Qp_ref_m3h / mem0.standard_test_recovery; % Nominal recovery kullanarak standard test feed debisini hesaplar.
Cf_test_kg_m3 = mem0.standard_test_feed_kg_m3; % Standard feed salinity degerini tanimlar.
Pf_test_abs_MPa = mem0.standard_test_pressure_abs_MPa; % Standard feed pressure degerini tanimlar.
T_test_C = mem0.standard_test_temperature_C; % Standard feed temperature degerini tanimlar.
Rj_ref = mem0.nominal_rejection_fraction; % Nominal stabilized salt rejection fraction degerini tanimlar.

%% OPTIMIZASYON DEGISKENLERI % Pozitif A ve B icin logaritmik parametreleri tanimlar.

x0 = log([mem0.Aref_kg_m2_s_Pa, mem0.B_kg_m2_s]); % Lu/Du A ve B degerlerini log uzayinda ilk tahmin yapar.
objective = @(x) local_objective(x, mem0, Qf_test_m3h, Cf_test_kg_m3, Pf_test_abs_MPa, T_test_C, N_segments, Qp_ref_m3h, Rj_ref); % Kalibrasyon objective fonksiyonunu tanimlar.

%% FMINSEARCH AYARLARI % Base MATLAB ile calisan Nelder-Mead optimizer ayarlarini tanimlar.

options = optimset('Display', 'off', 'TolX', 1.0e-7, 'TolFun', 1.0e-10, 'MaxIter', 120, 'MaxFunEvals', 300); % fminsearch convergence ayarlarini tanimlar.
[x_opt, fval, exitflag, output] = fminsearch(objective, x0, options); % A ve B logaritmalarini standard test noktasina gore optimize eder.

%% KALIBRE MEMBRAN % Optimum A ve B degerleri ile yeni membran struct'i olusturur.

mem_cal = mem0; % Orijinal membran struct'ini kopyalar.
mem_cal.Aref_kg_m2_s_Pa = exp(x_opt(1)); % Kalibre water permeability A degerini atar.
mem_cal.B_kg_m2_s = exp(x_opt(2)); % Kalibre salt transport B degerini atar.

%% FINAL STANDARD TEST COZUMU % Kalibre parametrelerle standard test noktasini yeniden cozer.

pv = ro_pv_du2014(Qf_test_m3h, Cf_test_kg_m3, Pf_test_abs_MPa, T_test_C, 1, N_segments, mem_cal); % Kalibre parametrelerle tek-element modelini cozer.
Qp_model_m3h = pv.Qp_m3h; % Kalibre model permeate debisini kaydeder.
Rj_model = 1.0 - pv.Cp_kg_m3 / Cf_test_kg_m3; % Kalibre model salt rejection fraction degerini hesaplar.

%% CIKTI YAPISI % Calibration sonuclarini struct icinde toplar.

cal.A_original = mem0.Aref_kg_m2_s_Pa; % Orijinal Lu/Du A degerini kaydeder.
cal.B_original = mem0.B_kg_m2_s; % Orijinal Lu/Du B degerini kaydeder.
cal.A_calibrated = mem_cal.Aref_kg_m2_s_Pa; % Kalibre A degerini kaydeder.
cal.B_calibrated = mem_cal.B_kg_m2_s; % Kalibre B degerini kaydeder.
cal.A_ratio = cal.A_calibrated / cal.A_original; % Kalibre/orijinal A oranini hesaplar.
cal.B_ratio = cal.B_calibrated / cal.B_original; % Kalibre/orijinal B oranini hesaplar.
cal.Qp_ref_m3_day = mem0.nominal_permeate_m3_day; % Reference permeate debisini m3/day olarak kaydeder.
cal.Qp_model_m3_day = Qp_model_m3h * 24.0; % Kalibre model permeate debisini m3/day olarak kaydeder.
cal.rejection_ref_pct = 100.0 * Rj_ref; % Reference salt rejection degerini yuzde olarak kaydeder.
cal.rejection_model_pct = 100.0 * Rj_model; % Kalibre model salt rejection degerini yuzde olarak kaydeder.
cal.objective_value = fval; % Final objective function degerini kaydeder.
cal.exitflag = exitflag; % fminsearch exit flag degerini kaydeder.
cal.optimizer_output = output; % fminsearch ayrintili cikti yapisini kaydeder.
cal.mem_calibrated = mem_cal; % Kalibre membran struct'ini kaydeder.
cal.pv = pv; % Kalibre tek-element PV sonucunu kaydeder.

end % Ana calibration fonksiyonunu sonlandirir.

function f = local_objective(x, mem0, Qf_m3h, Cf_kg_m3, Pf_MPa, T_C, N_segments, Qp_ref_m3h, Rj_ref) % Calibration objective fonksiyonunu hesaplar.

%% ADAY A VE B % Log-parametreleri fiziksel A ve B degerlerine cevirir.

mem = mem0; % Orijinal membran struct'ini kopyalar.
mem.Aref_kg_m2_s_Pa = exp(x(1)); % Aday water permeability A degerini tanimlar.
mem.B_kg_m2_s = exp(x(2)); % Aday salt transport B degerini tanimlar.

%% ADAY MODEL COZUMU % Standard test noktasini aday A ve B ile cozer.

pv = ro_pv_du2014(Qf_m3h, Cf_kg_m3, Pf_MPa, T_C, 1, N_segments, mem); % Aday tek-element PV cozumunu yapar.
Qp_model_m3h = pv.Qp_m3h; % Aday permeate debisini alir.
Rj_model = 1.0 - pv.Cp_kg_m3 / Cf_kg_m3; % Aday salt rejection fraction degerini hesaplar.

%% NORMALIZE HATALAR % Debi ve salt-passage hatalarini normalize eder.

flow_error = (Qp_model_m3h - Qp_ref_m3h) / Qp_ref_m3h; % Permeate debisi relative error degerini hesaplar.
SP_ref = max(1.0 - Rj_ref, 1.0e-8); % Reference salt passage fraction degerini hesaplar.
SP_model = max(1.0 - Rj_model, 1.0e-8); % Model salt passage fraction degerini hesaplar.
salt_error = (SP_model - SP_ref) / SP_ref; % Salt passage relative error degerini hesaplar.

%% OBJECTIVE % Iki normalize hata karesini birlikte minimize eder.

f = flow_error^2 + salt_error^2; % Calibration objective function degerini hesaplar.

end % Local objective fonksiyonunu sonlandirir.
