function mem = ro_membrane_SW30XLE400() % SW30XLE-400 membran ve model sabitlerini dondurur.

%% MEMBRAN KIMLIGI % Membranin temel kimlik bilgilerini tanimlar.

mem.name = 'SW30XLE-400'; % Membran model adini kaydeder.
mem.active_area_m2 = 37.2; % Lu-2012 ve Du-2014 aktif membran alanini tanimlar.
mem.element_length_m = 1.016; % Lu-2012 toplam element uzunlugunu tanimlar.
mem.effective_length_m = 0.88; % Du-2014 aktif hidrolik uzunlugu tanimlar.
mem.element_diameter_m = 0.201; % Du-2014 element capini tanimlar.

%% FEED KANALI GEOMETRISI % Feed-side hidrolik geometriyi tanimlar.

mem.feed_spacer_mil = 28.0; % Lu-2012 ve Du-2014 feed spacer kalinligini mil cinsinden tanimlar.
mem.feed_channel_h_m = mem.feed_spacer_mil * 0.0254e-3; % Spacer kalinligini metreye cevirir.
mem.feed_cross_section_m2 = 0.0150; % Du-2014 feed cross-section open area degerini tanimlar.
mem.spacer_void_fraction = 0.90; % Du-2014 spacer void fraction degerini tanimlar.
mem.equivalent_diameter_m = 8.126e-4; % Du-2014 equivalent hydraulic diameter degerini tanimlar.
mem.K_lambda = 2.4; % Du-2014 friction-factor correction parameter degerini tanimlar.

%% MEMBRAN TASINIM PARAMETRELERI % Water ve salt permeability parametrelerini tanimlar.

mem.Aref_kg_m2_s_Pa = 3.5e-9; % Lu-2012 ve Du-2014 pure-water permeability sabitini tanimlar.
mem.B_kg_m2_s = 3.2e-5; % Lu-2012 ve Du-2014 salt transport parameter degerini tanimlar.
mem.fouling_factor = 1.00; % Yeni ve temiz membran icin fouling factor degerini tanimlar.
mem.permeate_density_kg_m3 = 1000.0; % Permeate yogunlugu icin baslangic degerini tanimlar.
mem.solute_molar_mass = 58.5; % Du-2014 NaCl benzeri solute molecular weight degerini tanimlar.
mem.R_J_mol_K = 8.314; % Evrensel gaz sabitini tanimlar.

%% BASINC VE DEBI SINIRLARI % Kaynaklardaki teknik isletme sinirlarini tanimlar.

mem.permeate_pressure_abs_MPa = 0.101325; % Atmospheric permeate pressure varsayimini tanimlar.
mem.max_operating_pressure_MPa = 8.3; % SW30XLE-400 maksimum operating pressure degerini tanimlar.
mem.feed_flow_min_m3h = 0.8; % Lu-2012 minimum element feed flow degerini tanimlar.
mem.feed_flow_max_m3h = 16.0; % Lu-2012 maksimum element feed flow degerini tanimlar.
mem.max_PV_pressure_drop_MPa = 0.35; % Lu-2012 ve Du-2014 maksimum PV pressure drop sinirini tanimlar.
mem.min_brine_flow_m3h = 3.6; % Du-2014 minimum brine flow constraint degerini tanimlar.

%% FLUX VE POLARIZASYON SINIRLARI % Du-2014 tarafindan kullanilan tasarim kisitlarini tanimlar.

mem.max_system_average_flux_LMH = 20.0; % Du-2014 seawater average permeate flux sinirini tanimlar.
mem.max_first_element_flux_pass1_LMH = 35.0; % Du-2014 pass-1 ilk element flux sinirini tanimlar.
mem.max_first_element_flux_pass2_LMH = 48.0; % Du-2014 pass-2 ilk element flux sinirini tanimlar.
mem.max_CPF_pass1 = 1.2; % Du-2014 pass-1 maximum concentration polarization factor degerini tanimlar.
mem.max_CPF_pass2 = 1.4; % Du-2014 pass-2 maximum concentration polarization factor degerini tanimlar.

%% NOMINAL DATASHEET DEGERLERI % Manufacturer consistency testi icin nominal degerleri tanimlar.

mem.nominal_area_ft2 = 400.0; % Datasheet aktif alan degerini ft2 cinsinden tanimlar.
mem.nominal_permeate_m3_day = 34.1; % Lu-2012 tablosundaki nominal permeate flow degerini tanimlar.
mem.nominal_rejection_fraction = 0.9970; % Lu-2012 tablosundaki stabilized salt rejection degerini tanimlar.
mem.standard_test_feed_kg_m3 = 32.0; % FilmTec standard test feed salinity degerini kg/m3 olarak tanimlar.
mem.standard_test_pressure_abs_MPa = 5.5; % Standard test pressure icin yaklasik 800 psi degerini tanimlar.
mem.standard_test_temperature_C = 25.0; % Standard test temperature degerini tanimlar.
mem.standard_test_recovery = 0.08; % FilmTec standard element recovery degerini tanimlar.

end % Fonksiyonu sonlandirir.
