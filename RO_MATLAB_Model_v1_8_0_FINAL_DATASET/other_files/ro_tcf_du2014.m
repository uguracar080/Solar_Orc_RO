function TCF = ro_tcf_du2014(T_C, mem) % Du-2014 Eq.21 ile temperature correction factor hesaplar.

%% AKTIVASYON ENERJISI % Sicakliga gore Du-2014 activation energy degerini secer.

if T_C <= 25.0 % Sicaklik 25 C veya daha dusukse bu dali kullanir.
    E_m_J_mol = 25000.0; % Du-2014 dusuk sicaklik activation energy degerini tanimlar.
else % Sicaklik 25 C'nin ustundeyse bu dali kullanir.
    E_m_J_mol = 22000.0; % Du-2014 yuksek sicaklik activation energy degerini tanimlar.
end % Sicaklik kosulunu sonlandirir.

%% TCF HESABI % Arrhenius tipi temperature correction factor degerini hesaplar.

TCF = exp((E_m_J_mol / mem.R_J_mol_K) * (1.0 / 298.0 - 1.0 / (273.0 + T_C))); % Du-2014 Eq.21 TCF degerini hesaplar.

end % Fonksiyonu sonlandirir.
