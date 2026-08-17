function props = ro_properties_du2014(T_C, C_kg_m3) % Du-2014 seawater transport properties degerlerini hesaplar.

%% SICAKLIK VE KONSANTRASYON KONTROLU % Sayisal guvenlik icin girdileri sinirlar.

T_C = max(T_C, 0.0); % Sicakligin sifirin altina dusmesini engeller.
C_kg_m3 = max(C_kg_m3, 0.0); % Konsantrasyonun negatif olmasini engeller.

%% YOGUNLUK % Du-2014 Eq.27-28 ile seawater density hesaplar.

M = 1.0069 - 2.757e-4 * T_C; % Du-2014 yardimci M parametresini hesaplar.
rho_kg_m3 = 498.4 * M + sqrt(248400.0 + 752.4 * C_kg_m3 * M); % Du-2014 seawater density korelasyonunu uygular.

%% DINAMIK VISKOZITE % Du-2014 Eq.25 ile viscosity hesaplar.

mu_Pa_s = (1.4757e-3 + 2.4817e-6 * C_kg_m3 + 9.3287e-9 * C_kg_m3^2) * exp(-0.02008 * T_C); % Du-2014 viscosity korelasyonunu uygular.

%% TUZ DIFUZYON KATSAYISI % Du-2014 Eq.26 ile diffusivity hesaplar.

Ds_m2_s = (0.72598 + 0.023087 * T_C + 0.00027657 * T_C^2) * 1.0e-9; % Du-2014 solute diffusivity korelasyonunu uygular.

%% CIKTI YAPISI % Hesaplanan ozellikleri struct icine toplar.

props.rho_kg_m3 = rho_kg_m3; % Hesaplanan seawater density degerini kaydeder.
props.mu_Pa_s = mu_Pa_s; % Hesaplanan dynamic viscosity degerini kaydeder.
props.Ds_m2_s = Ds_m2_s; % Hesaplanan solute diffusivity degerini kaydeder.

end % Fonksiyonu sonlandirir.
