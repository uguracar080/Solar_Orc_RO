function hyd = ro_hydraulics_du2014(Q_m3h, C_kg_m3, T_C, mem) % Du-2014 lokal feed-side hidrolik parametrelerini hesaplar.

%% AKISKAN OZELLIKLERI % Yerel rho, mu ve Ds degerlerini hesaplar.

props = ro_properties_du2014(T_C, C_kg_m3); % Du-2014 seawater property fonksiyonunu cagirir.

%% SUPERFICIAL FEED VELOCITY % Du-2014 tanimina gore feed-channel velocity hesaplar.

Q_m3h = max(Q_m3h, 1.0e-12); % Debiyi sayisal olarak pozitif tutar.
V_m_s = Q_m3h / (3600.0 * mem.feed_cross_section_m2 * mem.spacer_void_fraction); % Du-2014 superficial feed velocity degerini hesaplar.

%% REYNOLDS SAYISI % Du-2014 Re=rho*V*de/mu tanimini uygular.

Re = props.rho_kg_m3 * V_m_s * mem.equivalent_diameter_m / props.mu_Pa_s; % Yerel Reynolds sayisini hesaplar.
Re = max(Re, 1.0e-12); % Reynolds sayisini sayisal olarak pozitif tutar.

%% FRICTION FACTOR % Du-2014 Eq.4 ve Eq.17 formunu uygular.

lambda = mem.K_lambda * 6.23 * Re^(-0.3); % Du-2014 friction factor degerini hesaplar.

%% BASINC GRADYANI % Du-2014 momentum equation ile dP/dz hesaplar.

dP_dz_Pa_m = -lambda * props.rho_kg_m3 / mem.equivalent_diameter_m * V_m_s^2 / 2.0; % Yerel feed-side pressure gradient degerini hesaplar.
dP_dz_MPa_m = dP_dz_Pa_m / 1.0e6; % Pressure gradient degerini MPa/m birimine cevirir.

%% SCHMIDT SAYISI % Du-2014 Sc=mu/(rho*Ds) tanimini uygular.

Sc = props.mu_Pa_s / (props.rho_kg_m3 * props.Ds_m2_s); % Yerel Schmidt sayisini hesaplar.

%% CIKTI YAPISI % Hesaplanan hidrolik degerleri struct icine toplar.

hyd.V_m_s = V_m_s; % Superficial feed velocity degerini kaydeder.
hyd.Re = Re; % Reynolds sayisini kaydeder.
hyd.Sc = Sc; % Schmidt sayisini kaydeder.
hyd.lambda = lambda; % Friction factor degerini kaydeder.
hyd.dP_dz_MPa_m = dP_dz_MPa_m; % Pressure gradient degerini kaydeder.
hyd.rho_kg_m3 = props.rho_kg_m3; % Yerel density degerini kaydeder.
hyd.mu_Pa_s = props.mu_Pa_s; % Yerel viscosity degerini kaydeder.
hyd.Ds_m2_s = props.Ds_m2_s; % Yerel diffusivity degerini kaydeder.

end % Fonksiyonu sonlandirir.
