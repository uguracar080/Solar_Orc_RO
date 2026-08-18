function mem = ro_apply_membrane_age_du2014(mem_base, age_years) % Du-2014 membrane aging denklemleri ile FF ve B degerlerini gunceller.

%% GIRDI KONTROLU % Membran yasini fiziksel olarak negatif olmayacak sekilde sinirlar.

age_years = max(age_years, 0.0); % Membran yasini negatif olmayacak sekilde sinirlar.

%% DU-2014 YASLANMA SABITLERI % Case-study aging varsayimlarini tanimlar.

flux_decline_per_year = 0.07; % Du-2014 expected flux decrease per year degerini tanimlar.
salt_passage_increase_per_year = 0.10; % Du-2014 expected salt passage increase per year degerini tanimlar.

%% MEMBRAN KOPYASI % Base membran parametrelerini yeni struct icine kopyalar.

mem = mem_base; % Orijinal membran struct'ini kopyalar.

%% FOULING FACTOR % Du-2014 Eq.22 ile membrane permeability aging etkisini hesaplar.

mem.fouling_factor = (1.0 - flux_decline_per_year)^age_years; % Membran yasina bagli fouling factor degerini hesaplar.

%% SALT TRANSPORT PARAMETRESI % Du-2014 Eq.23 ile salt-passage aging etkisini hesaplar.

mem.B_kg_m2_s = mem_base.B_kg_m2_s * (1.0 + salt_passage_increase_per_year)^age_years; % Membran yasina bagli B degerini hesaplar.

%% YAS BILGISI % Cikti struct'ina aging meta-verilerini ekler.

mem.age_years = age_years; % Kullanilan membrane age degerini kaydeder.
mem.flux_decline_per_year = flux_decline_per_year; % Yillik flux decline varsayimini kaydeder.
mem.salt_passage_increase_per_year = salt_passage_increase_per_year; % Yillik salt-passage increase varsayimini kaydeder.

end % Fonksiyonu sonlandirir.
