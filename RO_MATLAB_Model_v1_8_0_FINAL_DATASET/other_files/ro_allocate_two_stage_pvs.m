function allocation = ro_allocate_two_stage_pvs(N_total, overall_recovery) % Toplam PV sayisini stage-ratio fikrine gore iki kademeye dagitir.

%% GIRDI KONTROLU % Toplam PV ve recovery degerlerini fiziksel araliga getirir.

N_total = max(round(N_total), 2); % Toplam PV sayisini en az iki olacak sekilde tam sayiya cevirir.
overall_recovery = min(max(overall_recovery, 1.0e-6), 0.999999); % Recovery degerini sifir ile bir arasinda tutar.

%% STAGE RATIO % Mokhtari Eq.3 fikrine gore stage ratio degerini hesaplar.

n_stages = 2.0; % Bu fonksiyonun iki-stage sistem icin oldugunu tanimlar.
RR = (1.0 / (1.0 - overall_recovery))^(1.0 / n_stages); % Mokhtari stage-ratio ifadesini hesaplar.

%% INTEGER PV DAGILIMI % N1+N2=Ntotal kosulunda N1/N2 oranini RR'ye en yakin yapan dagilimi bulur.

best_error = inf; % Baslangicta en iyi oran hatasini sonsuz yapar.
best_N1 = 1; % Baslangic stage-1 PV sayisini tanimlar.
best_N2 = N_total - 1; % Baslangic stage-2 PV sayisini tanimlar.

for N1 = 1:(N_total - 1) % Tum olasi stage-1 PV sayilarini tarar.
    N2 = N_total - N1; % Toplam PV kosulundan stage-2 PV sayisini hesaplar.
    ratio_now = N1 / N2; % Mevcut integer dagilimin stage PV oranini hesaplar.
    ratio_error = abs(ratio_now - RR); % Mevcut oranin hedef RR'den mutlak farkini hesaplar.
    if ratio_error < best_error % Mevcut dagilim daha iyi ise kontrol eder.
        best_error = ratio_error; % En iyi oran hatasini gunceller.
        best_N1 = N1; % En iyi stage-1 PV sayisini kaydeder.
        best_N2 = N2; % En iyi stage-2 PV sayisini kaydeder.
    end % En iyi dagilim kosulunu sonlandirir.
end % Integer PV taramasini sonlandirir.

%% CIKTI YAPISI % Yeniden kurulan stage dagilimini struct olarak dondurur.

allocation.N_total = N_total; % Toplam PV sayisini kaydeder.
allocation.N_stage1 = best_N1; % Stage-1 PV sayisini kaydeder.
allocation.N_stage2 = best_N2; % Stage-2 PV sayisini kaydeder.
allocation.RR_target = RR; % Hedef stage ratio degerini kaydeder.
allocation.RR_integer = best_N1 / best_N2; % Integer dagilimda gerceklesen stage ratio degerini kaydeder.
allocation.ratio_error = best_error; % Integer stage ratio hata degerini kaydeder.
allocation.is_reconstructed = true; % Bu dagilimin makaleden dogrudan alinmadigini isaretler.

end % Fonksiyonu sonlandirir.
