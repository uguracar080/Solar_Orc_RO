function pi_MPa = ro_osmotic_pressure_mokhtari2016(C_ppm, T_C) % Mokhtari-2016 / Lu-2012 ppm tabanli osmotic pressure korelasyonunu uygular.

%% GIRDI KONTROLU % Ppm konsantrasyonunu fiziksel aralikta tutar.

C_ppm = min(max(C_ppm, 0.0), 999999.0); % Denklem paydasinin sifir olmamasi icin konsantrasyonu sinirlar.

%% OSMOTIK BASINC % Lu-2012 Eq.3 ve Mokhtari-2016 Eq.19 formunu uygular.

pi_MPa = 0.2641 * C_ppm * (T_C + 273.0) / (1.0e6 - C_ppm); % Ppm tabanli osmotic pressure degerini MPa olarak hesaplar.

end % Fonksiyonu sonlandirir.
