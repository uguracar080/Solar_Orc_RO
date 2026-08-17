function pi_MPa = ro_osmotic_pressure_du2014(T_C, C_kg_m3, mem) % Du-2014 Eq.24 ile osmotic pressure hesaplar.

%% GIRDI KONTROLU % Konsantrasyon ve yogunlugu guvenli aralikta tutar.

C_kg_m3 = max(C_kg_m3, 0.0); % Negatif konsantrasyonu sifira sinirlar.
props = ro_properties_du2014(T_C, C_kg_m3); % Yerel seawater density degerini hesaplar.

%% OSMOTIK BASINC % Du-2014 nonlinear seawater osmotic-pressure korelasyonunu uygular.

molar_term = 1.0e3 * C_kg_m3 / (mem.solute_molar_mass * props.rho_kg_m3); % Osmotic korelasyondaki boyutsuz konsantrasyon terimini hesaplar.
pi_MPa = 4.54047 * max(molar_term, 0.0)^0.987; % Du-2014 Eq.24 osmotic pressure degerini MPa olarak hesaplar.

end % Fonksiyonu sonlandirir.
