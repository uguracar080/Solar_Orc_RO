function loc = ro_local_transport_du2014(P_feed_abs_MPa, C_bulk_kg_m3, T_C, Q_m3h, mem) % Du-2014 lokal membrane transport denklemlerini iteratif cozer.

%% YEREL HIDROLIK VE TASINIM PARAMETRELERI % Cross-flow ve mass-transfer degerlerini hazirlar.

hyd = ro_hydraulics_du2014(Q_m3h, C_bulk_kg_m3, T_C, mem); % Yerel hidrolik parametreleri hesaplar.
k_m_s = 0.068 * hyd.Re^0.875 * hyd.Sc^0.25 * hyd.Ds_m2_s / mem.equivalent_diameter_m; % Du-2014 Eq.11 mass-transfer coefficient degerini hesaplar.
TCF = ro_tcf_du2014(T_C, mem); % Temperature correction factor degerini hesaplar.
A_kg_m2_s_Pa = mem.Aref_kg_m2_s_Pa * mem.fouling_factor * TCF; % Sicaklik ve fouling etkili water permeability degerini hesaplar.

%% ITERASYON BASLANGICI % Coupled Cp ve Cmw denklemleri icin ilk tahminleri tanimlar.

C_p_kg_m3 = max(0.001 * C_bulk_kg_m3, 1.0e-6); % Permeate concentration icin dusuk bir ilk tahmin tanimlar.
C_mw_kg_m3 = max(1.05 * C_bulk_kg_m3, C_bulk_kg_m3); % Membrane-wall concentration icin ilk tahmin tanimlar.
relax = 0.50; % Fixed-point iterasyonunda under-relaxation katsayisini tanimlar.
tol_Cp = 1.0e-9; % Permeate concentration convergence toleransini tanimlar.
tol_Cmw = 1.0e-8; % Membrane-wall concentration convergence toleransini tanimlar.
max_iter = 500; % Maksimum lokal iterasyon sayisini tanimlar.
converged = false; % Baslangicta convergence durumunu false yapar.

%% COUPLED TRANSPORT ITERASYONU % Water flux, salt flux ve concentration polarization denklemlerini birlikte cozer.

for iter = 1:max_iter % Maksimum iterasyon sayisina kadar cozum dongusunu calistirir.
    pi_mw_MPa = ro_osmotic_pressure_du2014(T_C, C_mw_kg_m3, mem); % Membrane-wall osmotic pressure degerini hesaplar.
    pi_p_MPa = ro_osmotic_pressure_du2014(T_C, C_p_kg_m3, mem); % Permeate-side osmotic pressure degerini hesaplar.
    deltaP_hyd_MPa = max(P_feed_abs_MPa - mem.permeate_pressure_abs_MPa, 0.0); % Feed-permeate hydraulic pressure difference degerini hesaplar.
    NDP_MPa = max(deltaP_hyd_MPa - (pi_mw_MPa - pi_p_MPa), 0.0); % Net driving pressure degerini hesaplar.
    Jw_kg_m2_s = A_kg_m2_s_Pa * NDP_MPa * 1.0e6; % Du-2014 local water mass flux degerini hesaplar.
    w_mw = C_mw_kg_m3 / max(hyd.rho_kg_m3, 1.0e-12); % Membrane-wall konsantrasyonunu solute mass fraction'a cevirir.
    w_p = C_p_kg_m3 / max(mem.permeate_density_kg_m3, 1.0e-12); % Permeate konsantrasyonunu solute mass fraction'a cevirir.
    Js_kg_m2_s = mem.B_kg_m2_s * max(w_mw - w_p, 0.0); % Lu/Du B parametresini mass-fraction farki ile salt flux hesabinda kullanir.
    Vw_m_s = (Jw_kg_m2_s + Js_kg_m2_s) / mem.permeate_density_kg_m3; % Du-2014 Eq.8 permeate velocity degerini hesaplar.
    C_p_new_kg_m3 = Js_kg_m2_s / max(Vw_m_s, 1.0e-15); % Du-2014 Eq.9 local permeate concentration degerini hesaplar.
    exponent_value = min(Vw_m_s / max(k_m_s, 1.0e-15), 50.0); % Exponential overflow riskini sinirlayan polarizasyon ustelini hesaplar.
    C_mw_new_kg_m3 = C_p_new_kg_m3 + (C_bulk_kg_m3 - C_p_new_kg_m3) * exp(exponent_value); % Du-2014 Eq.10 concentration polarization denklemini uygular.
    Cp_error = abs(C_p_new_kg_m3 - C_p_kg_m3); % Permeate concentration iterasyon hatasini hesaplar.
    Cmw_error = abs(C_mw_new_kg_m3 - C_mw_kg_m3); % Membrane-wall concentration iterasyon hatasini hesaplar.
    C_p_kg_m3 = relax * C_p_new_kg_m3 + (1.0 - relax) * C_p_kg_m3; % Permeate concentration degerine under-relaxation uygular.
    C_mw_kg_m3 = relax * C_mw_new_kg_m3 + (1.0 - relax) * C_mw_kg_m3; % Membrane-wall concentration degerine under-relaxation uygular.
    if Cp_error < tol_Cp && Cmw_error < tol_Cmw % Iki concentration hatasi da toleransin altindaysa kontrol eder.
        C_p_kg_m3 = C_p_new_kg_m3; % Son permeate concentration degerini converged degerle gunceller.
        C_mw_kg_m3 = C_mw_new_kg_m3; % Son membrane-wall concentration degerini converged degerle gunceller.
        converged = true; % Lokal cozumun convergence durumunu true yapar.
        break; % Iterasyon dongusunden cikar.
    end % Convergence kosulunu sonlandirir.
end % Lokal fixed-point iterasyonunu sonlandirir.

%% SON DEGERLERIN YENIDEN HESABI % Relaxation sonrasi final akilari tutarli sekilde yeniden hesaplar.

pi_mw_MPa = ro_osmotic_pressure_du2014(T_C, C_mw_kg_m3, mem); % Final membrane-wall osmotic pressure degerini hesaplar.
pi_p_MPa = ro_osmotic_pressure_du2014(T_C, C_p_kg_m3, mem); % Final permeate osmotic pressure degerini hesaplar.
deltaP_hyd_MPa = max(P_feed_abs_MPa - mem.permeate_pressure_abs_MPa, 0.0); % Final hydraulic pressure difference degerini hesaplar.
NDP_MPa = max(deltaP_hyd_MPa - (pi_mw_MPa - pi_p_MPa), 0.0); % Final net driving pressure degerini hesaplar.
Jw_kg_m2_s = A_kg_m2_s_Pa * NDP_MPa * 1.0e6; % Final water mass flux degerini hesaplar.
w_mw = C_mw_kg_m3 / max(hyd.rho_kg_m3, 1.0e-12); % Final membrane-wall mass fraction degerini hesaplar.
w_p = C_p_kg_m3 / max(mem.permeate_density_kg_m3, 1.0e-12); % Final permeate mass fraction degerini hesaplar.
Js_kg_m2_s = mem.B_kg_m2_s * max(w_mw - w_p, 0.0); % Final salt mass flux degerini hesaplar.
Vw_m_s = (Jw_kg_m2_s + Js_kg_m2_s) / mem.permeate_density_kg_m3; % Final permeate velocity degerini hesaplar.
CPF = C_mw_kg_m3 / max(C_bulk_kg_m3, 1.0e-12); % Concentration polarization factor degerini hesaplar.
Jv_LMH = Vw_m_s * 3.6e6; % Volumetric permeate flux degerini LMH birimine cevirir.

%% CIKTI YAPISI % Lokal cozum sonucunu struct icine toplar.

loc.Jw_kg_m2_s = Jw_kg_m2_s; % Water mass flux degerini kaydeder.
loc.Js_kg_m2_s = Js_kg_m2_s; % Salt mass flux degerini kaydeder.
loc.Vw_m_s = Vw_m_s; % Permeate velocity degerini kaydeder.
loc.Jv_LMH = Jv_LMH; % Volumetric permeate flux degerini kaydeder.
loc.Cp_kg_m3 = C_p_kg_m3; % Local permeate concentration degerini kaydeder.
loc.Cmw_kg_m3 = C_mw_kg_m3; % Membrane-wall concentration degerini kaydeder.
loc.CPF = CPF; % Concentration polarization factor degerini kaydeder.
loc.k_m_s = k_m_s; % Mass-transfer coefficient degerini kaydeder.
loc.Re = hyd.Re; % Reynolds sayisini kaydeder.
loc.Sc = hyd.Sc; % Schmidt sayisini kaydeder.
loc.V_feed_m_s = hyd.V_m_s; % Feed superficial velocity degerini kaydeder.
loc.lambda = hyd.lambda; % Friction factor degerini kaydeder.
loc.dP_dz_MPa_m = hyd.dP_dz_MPa_m; % Pressure gradient degerini kaydeder.
loc.rho_kg_m3 = hyd.rho_kg_m3; % Feed density degerini kaydeder.
loc.mu_Pa_s = hyd.mu_Pa_s; % Feed viscosity degerini kaydeder.
loc.Ds_m2_s = hyd.Ds_m2_s; % Solute diffusivity degerini kaydeder.
loc.TCF = TCF; % Temperature correction factor degerini kaydeder.
loc.A_kg_m2_s_Pa = A_kg_m2_s_Pa; % Etkin water permeability degerini kaydeder.
loc.pi_mw_MPa = pi_mw_MPa; % Membrane-wall osmotic pressure degerini kaydeder.
loc.pi_p_MPa = pi_p_MPa; % Permeate osmotic pressure degerini kaydeder.
loc.NDP_MPa = NDP_MPa; % Net driving pressure degerini kaydeder.
loc.iterations = iter; % Kullanilan iterasyon sayisini kaydeder.
loc.converged = converged; % Convergence durumunu kaydeder.

end % Fonksiyonu sonlandirir.
