function TCF = ro_tcf_mokhtari2016(T_C) % Mokhtari-2016 / FilmTec temperature correction factor degerini hesaplar.

%% SICAKLIK DALI % 25 C sinirina gore uygun katsayiyi secer.

if T_C >= 25.0 % Sicaklik 25 C veya daha yuksekse bu dali kullanir.
    exponent_value = 2640.0 * (1.0 / 298.0 - 1.0 / (273.0 + T_C)); % Mokhtari yuksek sicaklik TCF ustelini hesaplar.
else % Sicaklik 25 C'nin altindaysa bu dali kullanir.
    exponent_value = 3020.0 * (1.0 / 298.0 - 1.0 / (273.0 + T_C)); % Mokhtari dusuk sicaklik TCF ustelini hesaplar.
end % Sicaklik kosulunu sonlandirir.

%% TCF HESABI % Secilen ustel ile temperature correction factor hesaplar.

TCF = exp(exponent_value); % Temperature correction factor degerini hesaplar.

end % Fonksiyonu sonlandirir.
