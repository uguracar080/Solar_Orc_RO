function out = diagnose_Mokhtari2016() % Mokhtari-2016 benchmark icin raporlanmayan feed salinity ve stage PV dagilimi duyarliligini tarar.

%% DIAGNOSTIC BASLIGI % Command Window'da diagnostic basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Diagnostic ust ayiricisini yazdirir.
fprintf('DIAGNOSTIC - MOKHTARI 2016 SALINITY / STAGE-SPLIT SEARCH\n'); % Diagnostic basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Diagnostic alt ayiricisini yazdirir.

%% REFERENCE DEGERLER % Mokhtari optimum benchmark degerlerini tanimlar.

Qf_total_m3h = 223.27; % Makaledeki optimum total feed flow degerini tanimlar.
Pf_abs_MPa = 4.68; % Makaledeki optimum feed pressure degerini tanimlar.
R_ref = 0.7614; % Makaledeki optimum overall recovery fraction degerini tanimlar.
Cp_ref_mgL = 183.34; % Makaledeki optimum permeate concentration degerini tanimlar.
N_PV_total = 45; % Makaledeki toplam PV sayisini tanimlar.
n_elements = 5; % Makaledeki element/PV sayisini tanimlar.
T_C = 25.0; % RO reference temperature olarak 25 C kullanir.
N_segments = 70; % Diagnostic taramanin hesap yukunu azaltmak icin 70 segment kullanir.
mem = ro_membrane_SW30XLE400(); % Literature-reproduction icin Lu/Du A ve B parametrelerini yukler.

%% TARAMA ARALIKLARI % Makaledeki Caspian salinity bandi ve stage split cevresini tanimlar.

Cf_list_kg_m3 = (10.0:0.25:13.0).'; % Makalede belirtilen 10-13 g/L salinity bandini 0.25 g/L adimla tarar.
N1_list = (27:33).'; % Stage-1 PV sayisini 27-33 araliginda tarar.

%% SONUC DIZILERI % Tum kombinasyonlari saklayacak dizileri hazirlar.

n_cases = numel(Cf_list_kg_m3) * numel(N1_list); % Toplam diagnostic case sayisini hesaplar.
Cf_case = zeros(n_cases, 1); % Her case feed salinity degerini saklar.
N1_case = zeros(n_cases, 1); % Her case stage-1 PV sayisini saklar.
N2_case = zeros(n_cases, 1); % Her case stage-2 PV sayisini saklar.
R_model_pct = zeros(n_cases, 1); % Her case model recovery degerini saklar.
Cp_model_mgL = zeros(n_cases, 1); % Her case model permeate concentration degerini saklar.
err_R_pct = zeros(n_cases, 1); % Her case recovery relative error degerini saklar.
err_Cp_pct = zeros(n_cases, 1); % Her case Cp relative error degerini saklar.
score = zeros(n_cases, 1); % Her case combined normalized score degerini saklar.

%% KOMBINASYON TARAMASI % Feed salinity ve stage split kombinasyonlarini cozer.

k = 0; % Case sayacini sifirlar.
for i = 1:numel(Cf_list_kg_m3) % Tum feed salinity degerlerini sirayla tarar.
    for j = 1:numel(N1_list) % Tum stage-1 PV sayilarini sirayla tarar.
        k = k + 1; % Case sayacini bir artirir.
        Cf_now = Cf_list_kg_m3(i); % Mevcut feed salinity degerini alir.
        N1_now = N1_list(j); % Mevcut stage-1 PV sayisini alir.
        N2_now = N_PV_total - N1_now; % Toplam PV kosulundan stage-2 PV sayisini hesaplar.
        sys = ro_system_two_stage(Qf_total_m3h, Cf_now, Pf_abs_MPa, T_C, N1_now, N2_now, n_elements, n_elements, N_segments, mem); % Mevcut kombinasyon icin iki-stage sistemi cozer.
        R_now = sys.overall_recovery; % Mevcut case overall recovery degerini alir.
        Cp_now_mgL = sys.Cp_kg_m3 * 1000.0; % Mevcut case permeate concentration degerini mg/L birimine cevirir.
        eR = 100.0 * (R_now - R_ref) / R_ref; % Recovery relative error degerini hesaplar.
        eCp = 100.0 * (Cp_now_mgL - Cp_ref_mgL) / Cp_ref_mgL; % Permeate concentration relative error degerini hesaplar.
        Cf_case(k) = Cf_now; % Case salinity degerini kaydeder.
        N1_case(k) = N1_now; % Case stage-1 PV sayisini kaydeder.
        N2_case(k) = N2_now; % Case stage-2 PV sayisini kaydeder.
        R_model_pct(k) = 100.0 * R_now; % Case model recovery degerini yuzde olarak kaydeder.
        Cp_model_mgL(k) = Cp_now_mgL; % Case model permeate concentration degerini kaydeder.
        err_R_pct(k) = eR; % Case recovery relative error degerini kaydeder.
        err_Cp_pct(k) = eCp; % Case Cp relative error degerini kaydeder.
        score(k) = sqrt(eR^2 + eCp^2); % Iki relative hatadan combined score degerini hesaplar.
    end % Stage-split dongusunu sonlandirir.
end % Salinity dongusunu sonlandirir.

%% EN IYI CASELER % Combined score degerine gore sonuclari siralar.

result_table = table(Cf_case, N1_case, N2_case, R_model_pct, Cp_model_mgL, err_R_pct, err_Cp_pct, score); % Tum diagnostic case sonuclarini tabloya toplar.
result_table = sortrows(result_table, 'score', 'ascend'); % Combined score degerine gore tabloyu kucukten buyuge siralar.
disp(result_table(1:min(10, height(result_table)), :)); % En iyi ilk on case'i Command Window'da gosterir.

fprintf('Not: Bu tarama eksik raporlanan inputlari tahmin etmek icindir; publication validation yerine gecmez.\n'); % Diagnostic aramanin metodolojik sinirini aciklar.
fprintf('Not: En iyi case, makaledeki exact salinity/stage split olarak iddia edilmeyecektir.\n'); % En iyi kombinasyonun kesin kaynak degeri olmadigini belirtir.

%% CIKTI YAPISI % Diagnostic sonuclarini struct olarak dondurur.

out.result_table = result_table; % Siralanmis diagnostic sonuc tablosunu kaydeder.
out.best_case = result_table(1, :); % En iyi combined-score case'ini kaydeder.

end % Fonksiyonu sonlandirir.
