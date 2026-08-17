function out = test_grid_independence() % Du-2014 PV modelinde axial segment sayisinin sonuc uzerindeki etkisini genis aralikta test eder.

%% TEST BASLIGI % Command Window'da grid test basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 3 - GRID INDEPENDENCE (EXTENDED)\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% TEST NOKTASI % Tipik SWRO pressure-vessel isletme noktasini tanimlar.

mem = ro_membrane_SW30XLE400(); % SW30XLE-400 membran parametrelerini yukler.
Qf_m3h = 8.0; % Representative PV feed debisini tanimlar.
Cf_kg_m3 = 35.0; % Representative seawater feed concentration degerini tanimlar.
Pf_abs_MPa = 6.0; % Representative feed pressure degerini tanimlar.
T_C = 20.0; % Representative seawater temperature degerini tanimlar.
n_elements = 5; % PV icindeki seri element sayisini tanimlar.
N_list = [10 20 30 50 70 100 150 200]; % Genisletilmis axial segment sayilarini tanimlar.

%% COZUM DIZILERI % Her grid icin sonuclari saklayacak dizileri olusturur.

Qp_m3h = zeros(numel(N_list), 1); % Permeate debisi sonuc dizisini olusturur.
Cp_mgL = zeros(numel(N_list), 1); % Permeate concentration sonuc dizisini olusturur.
Pout_MPa = zeros(numel(N_list), 1); % PV cikis pressure sonuc dizisini olusturur.
Recovery_pct = zeros(numel(N_list), 1); % Recovery sonuc dizisini olusturur.

%% GRID TARAMASI % Tum segment sayilari icin PV modelini yeniden cozer.

for i = 1:numel(N_list) % Tum grid seceneklerini sirayla tarar.
    pv = ro_pv_du2014(Qf_m3h, Cf_kg_m3, Pf_abs_MPa, T_C, n_elements, N_list(i), mem); % Mevcut grid sayisi ile PV cozumunu yapar.
    Qp_m3h(i) = pv.Qp_m3h; % Mevcut grid permeate debisini kaydeder.
    Cp_mgL(i) = pv.Cp_kg_m3 * 1000.0; % Mevcut grid permeate concentration degerini mg/L olarak kaydeder.
    Pout_MPa(i) = pv.Pout_abs_MPa; % Mevcut grid PV cikis pressure degerini kaydeder.
    Recovery_pct(i) = 100.0 * pv.recovery; % Mevcut grid recovery degerini yuzde olarak kaydeder.
end % Grid tarama dongusunu sonlandirir.

%% REFERENCE GRID HATALARI % En yuksek grid sayisini reference kabul ederek relative error hesaplar.

Qp_ref = Qp_m3h(end); % N=200 permeate debisini reference olarak alir.
Cp_ref = Cp_mgL(end); % N=200 permeate concentration degerini reference olarak alir.
Qp_error_pct = 100.0 * abs(Qp_m3h - Qp_ref) / max(abs(Qp_ref), 1.0e-12); % Her grid icin permeate flow relative error degerini hesaplar.
Cp_error_pct = 100.0 * abs(Cp_mgL - Cp_ref) / max(abs(Cp_ref), 1.0e-12); % Her grid icin permeate concentration relative error degerini hesaplar.

%% ONERILEN GRID % Hem Qp hem Cp hatasi 0.1%'in altina inen ilk grid sayisini secer.

criterion = Qp_error_pct <= 0.1 & Cp_error_pct <= 0.1; % Grid bagimsizlik kabul kriterini tanimlar.
first_ok = find(criterion, 1, 'first'); % Kriteri saglayan ilk grid indeksini bulur.
if isempty(first_ok) % Hicbir grid kriteri saglamiyorsa kontrol eder.
    recommended_N = N_list(end); % En yuksek grid sayisini onerir.
else % En az bir grid kriteri saglaniyorsa bu dali kullanir.
    recommended_N = N_list(first_ok); % Kriteri ilk saglayan grid sayisini onerir.
end % Grid secim kosulunu sonlandirir.

%% SONUC TABLOSU % Grid bagimsizlik sonuclarini tablo halinde olusturur.

N_segments = N_list(:); % Grid sayilarini sutun vektorune cevirir.
result_table = table(N_segments, Qp_m3h, Cp_mgL, Recovery_pct, Pout_MPa, Qp_error_pct, Cp_error_pct); % Grid sonuclarini tek tabloda toplar.
disp(result_table); % Grid sonuc tablosunu Command Window'da gosterir.

fprintf('Recommended axial segments : %d\n', recommended_N); % Onerilen grid sayisini yazdirir.
fprintf('Criterion                   : |dQp| <= 0.1%% and |dCp| <= 0.1%% relative to N=200\n'); % Grid kabul kriterini yazdirir.

%% CIKTI YAPISI % Grid test sonucunu struct icinde toplar.

out.result_table = result_table; % Grid sonuc tablosunu kaydeder.
out.recommended_N = recommended_N; % Onerilen axial segment sayisini kaydeder.
out.N_list = N_list; % Test edilen grid sayilarini kaydeder.
out.Qp_error_pct = Qp_error_pct; % Permeate flow grid error degerlerini kaydeder.
out.Cp_error_pct = Cp_error_pct; % Permeate concentration grid error degerlerini kaydeder.

end % Fonksiyonu sonlandirir.
