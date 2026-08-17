function out = ro_cmems_salinity_reference_approx(SP, T_C) % TEOS-10 toolbox olmadan sadece sensitivity/domain check icin Reference-Salinity + Du-density approximate Cf hesaplar.

%% REFERENCE SALINITY % Practical Salinity'yi TEOS-10 constant ratio ile Reference Salinity [g/kg] degerine cevirir.

SR_g_kg = (35.16504 / 35.0) .* SP; % SR = uPS * SP standard conversion degerini hesaplar.

%% DU-DENSITY FIXED POINT % C = rho_Du(T,C)*SR/1000 implicit iliskisini iteratif cozer.

Cf_kg_m3 = SR_g_kg; % Fixed-point iteration icin ilk Cf tahminini g/L benzeri sayisal degerle baslatir.
for iter = 1:100 % Maximum 100 fixed-point iteration uygular.
    rho_kg_m3 = zeros(size(Cf_kg_m3)); % Mevcut iteration density vectorunu olusturur.
    for k = 1:numel(Cf_kg_m3) % ro_properties_du2014 scalar input yapisini korumak icin tum samples uzerinde dongu kurar.
        props = ro_properties_du2014(T_C(k), Cf_kg_m3(k)); % Mevcut temperature ve concentration icin Du density hesaplar.
        rho_kg_m3(k) = props.rho_kg_m3; % Hesaplanan density degerini kaydeder.
    end % Sample density dongusunu sonlandirir.
    Cf_new = rho_kg_m3 .* SR_g_kg / 1000.0; % Reference Salinity mass fraction ile Du density'den yeni concentration tahmini hesaplar.
    if max(abs(Cf_new(:) - Cf_kg_m3(:))) < 1.0e-10 % Fixed-point convergence saglandiysa kontrol eder.
        Cf_kg_m3 = Cf_new; % Final converged concentration degerini gunceller.
        break; % Iteration dongusunden cikar.
    end % Fixed-point convergence kosulunu sonlandirir.
    Cf_kg_m3 = Cf_new; % Bir sonraki iteration icin concentration degerini gunceller.
end % Fixed-point iteration dongusunu sonlandirir.

%% OUTPUT % Bu yontemin final ANN dataset icin degil sadece approximate sensitivity oldugunu metadata ile kaydeder.

out.Reference_Salinity_g_kg = SR_g_kg; % Reference Salinity vectorunu output'a kaydeder.
out.Cf_kg_m3 = Cf_kg_m3; % Approximate physical concentration vectorunu output'a kaydeder.
out.rho_kg_m3 = rho_kg_m3; % Son Du-density vectorunu output'a kaydeder.
out.method = 'ReferenceSalinity_plus_DuDensity_APPROX_ONLY'; % Yontemin final TEOS-10 preprocessing yerine kullanilmamasi gerektigini acik etiketler.

end % Approximate salinity conversion fonksiyonunu sonlandirir.
