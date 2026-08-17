function out = test_Du2014_caseI_noERD() % Du-2014 Case Study I no-ERD konfigürasyonunu published Table 4'e karsi dogrular.

%% TEST BASLIGI % Command Window'da Du-2014 verification basligini yazdirir.

fprintf('\n------------------------------------------------------------\n'); % Test ust ayiricisini yazdirir.
fprintf('TEST 4 - DU 2014 CASE I / WITHOUT ERD VERIFICATION\n'); % Test basligini yazdirir.
fprintf('------------------------------------------------------------\n'); % Test alt ayiricisini yazdirir.

%% DU-2014 PUBLISHED INPUTLARI % Table 2-4 ve case-study specifications degerlerini tanimlar.

Qf_total_m3h = 195.3; % Du-2014 without-ERD system feed flow degerini tanimlar.
Cf_kg_m3 = 35.0; % Du-2014 feed seawater salinity degerini tanimlar.
T_C = 20.0; % Du-2014 feed water temperature degerini tanimlar.
P1_source_MPa = 6.55; % Du-2014 stage-1 operating pressure degerini tanimlar.
P2_source_MPa = 7.79; % Du-2014 stage-2 operating pressure degerini tanimlar.
N_PV_stage1 = 22; % Du-2014 stage-1 PV sayisini tanimlar.
N_PV_stage2 = 14; % Du-2014 stage-2 PV sayisini tanimlar.
n_elements_stage1 = 3; % Du-2014 stage-1 element/PV sayisini tanimlar.
n_elements_stage2 = 7; % Du-2014 stage-2 element/PV sayisini tanimlar.
N_segments = 30; % Du-2014 published resultte kullanilan axial integration grid sayisini tanimlar.

%% DU-2014 PUBLISHED OUTPUTLARI % Table 4 reference performans degerlerini tanimlar.

R_ref = 0.6145; % Du-2014 published overall recovery fraction degerini tanimlar.
Cp_ref_mgL = 500.0; % Du-2014 published product concentration degerini tanimlar.
Javg_ref_LMH = 19.67; % Du-2014 published system average flux degerini tanimlar.
Qp_ref_m3h = Qf_total_m3h * R_ref; % Published recovery ve feed debisinden permeate debisini hesaplar.

%% MEMBRAN BASE PARAMETRELERI % Du-2014 Table 2 SW30XLE-400 parametrelerini yukler.

mem_base = ro_membrane_SW30XLE400(); % SW30XLE-400 base membran parametrelerini yukler.

%% DU-2014 YASLANMA PARAMETRELERI % Case-study specifications ve Eq.22-23 ile 3-yillik tasarim parametrelerini hesaplar.

FFd = 0.07; % Du-2014 expected decrease in flux per year degerini tanimlar.
Bspin = 0.10; % Du-2014 expected salt passage increase per year degerini tanimlar.
Nmlp = 3.0; % Du-2014 design period degerini yil olarak tanimlar.
FF_aged = (1.0 - FFd)^Nmlp; % Du-2014 Eq.22 fouling factor degerini hesaplar.
B_aged = mem_base.B_kg_m2_s * (1.0 + Bspin)^Nmlp; % Du-2014 Eq.23 aged salt transport coefficient degerini hesaplar.

%% SENARYO TANIMLARI % Basinç konvansiyonu ve membrane-aging etkisini ayirmak icin dort varyant tanimlar.

Scenario = {'Clean / source P as absolute'; 'Aged / source P as absolute'; 'Clean / source P as gauge'; 'Aged / source P as gauge'}; % Diagnostic senaryo adlarini tanimlar.
UseAging = [false; true; false; true]; % Her senaryoda aging uygulanip uygulanmadigini tanimlar.
UseGauge = [false; false; true; true]; % Her senaryoda source pressure degerinin gauge kabul edilip edilmedigini tanimlar.

%% SONUC DIZILERI % Dort senaryonun sonuclarini saklayacak dizileri olusturur.

Recovery_pct = zeros(4, 1); % Model recovery sonuc dizisini olusturur.
Cp_mgL = zeros(4, 1); % Model product concentration sonuc dizisini olusturur.
AverageFlux_LMH = zeros(4, 1); % Model average flux sonuc dizisini olusturur.
Qp_m3h = zeros(4, 1); % Model permeate debisi sonuc dizisini olusturur.
Error_R_pct = zeros(4, 1); % Recovery relative error sonuc dizisini olusturur.
Error_Cp_pct = zeros(4, 1); % Product concentration relative error sonuc dizisini olusturur.
Error_J_pct = zeros(4, 1); % Average flux relative error sonuc dizisini olusturur.
Score = zeros(4, 1); % Combined verification score sonuc dizisini olusturur.

%% SENARYO COZUMLERI % Dort fiziksel yorum secenegini ayri ayri cozer.

for i = 1:4 % Dort diagnostic senaryoyu sirayla cozer.
    mem = mem_base; % Her senaryo icin base membran struct'ini kopyalar.
    if UseAging(i) % Mevcut senaryoda Du-2014 aging uygulanacaksa kontrol eder.
        mem.fouling_factor = FF_aged; % Du-2014 aged fouling factor degerini uygular.
        mem.B_kg_m2_s = B_aged; % Du-2014 aged salt transport coefficient degerini uygular.
    end % Aging kosulunu sonlandirir.
    if UseGauge(i) % Source pressure degerleri gauge kabul edilecekse kontrol eder.
        P1_abs_MPa = P1_source_MPa + mem.permeate_pressure_abs_MPa; % Stage-1 source gauge basincini absolute basinca cevirir.
        P2_abs_MPa = P2_source_MPa + mem.permeate_pressure_abs_MPa; % Stage-2 source gauge basincini absolute basinca cevirir.
    else % Source pressure degerleri absolute kabul edilecekse bu dali kullanir.
        P1_abs_MPa = P1_source_MPa; % Stage-1 source pressure degerini absolute olarak dogrudan kullanir.
        P2_abs_MPa = P2_source_MPa; % Stage-2 source pressure degerini absolute olarak dogrudan kullanir.
    end % Basinç konvansiyonu kosulunu sonlandirir.
    sys = ro_system_two_stage_interstage_pressure(Qf_total_m3h, Cf_kg_m3, P1_abs_MPa, P2_abs_MPa, T_C, N_PV_stage1, N_PV_stage2, n_elements_stage1, n_elements_stage2, N_segments, mem); % Mevcut senaryo icin published iki-stage konfigürasyonu cozer.
    Recovery_pct(i) = 100.0 * sys.overall_recovery; % Model overall recovery degerini yuzde olarak kaydeder.
    Cp_mgL(i) = sys.Cp_kg_m3 * 1000.0; % Model product concentration degerini mg/L olarak kaydeder.
    AverageFlux_LMH(i) = sys.average_flux_LMH; % Model system average flux degerini kaydeder.
    Qp_m3h(i) = sys.Qp_total_m3h; % Model total permeate debisini kaydeder.
    Error_R_pct(i) = 100.0 * (sys.overall_recovery - R_ref) / R_ref; % Recovery relative error degerini hesaplar.
    Error_Cp_pct(i) = 100.0 * (Cp_mgL(i) - Cp_ref_mgL) / Cp_ref_mgL; % Product concentration relative error degerini hesaplar.
    Error_J_pct(i) = 100.0 * (AverageFlux_LMH(i) - Javg_ref_LMH) / Javg_ref_LMH; % Average flux relative error degerini hesaplar.
    Score(i) = sqrt(Error_R_pct(i)^2 + Error_Cp_pct(i)^2 + Error_J_pct(i)^2); % Uc relative hatadan combined verification score degerini hesaplar.
end % Senaryo cozum dongusunu sonlandirir.

%% SONUC TABLOSU % Published reference ile tum senaryolari karsilastirir.

result_table = table(Scenario, UseAging, UseGauge, Recovery_pct, Cp_mgL, AverageFlux_LMH, Qp_m3h, Error_R_pct, Error_Cp_pct, Error_J_pct, Score); % Du verification sonuc tablosunu olusturur.
result_table = sortrows(result_table, 'Score', 'ascend'); % En iyi combined-score senaryosunu en uste tasir.
disp(result_table); % Du verification sonuc tablosunu Command Window'da gosterir.

fprintf('Published reference : Recovery = %.2f %%, Cp = %.1f mg/L, Javg = %.2f LMH, Qp = %.3f m3/h\n', 100.0 * R_ref, Cp_ref_mgL, Javg_ref_LMH, Qp_ref_m3h); % Published reference degerlerini yazdirir.
fprintf('Du aging factors    : FF = %.6f, B/Bref = %.6f\n', FF_aged, B_aged / mem_base.B_kg_m2_s); % Du-2014 aging factors degerlerini yazdirir.
fprintf('Not: Published Du sonucu 30 axial grid ile uretilmistir; bu verification testinde de N=30 kullanilmistir.\n'); % Published grid secimini aciklar.
fprintf('Not: Basinç konvansiyonu makalede absolute/gauge olarak acik etiketlenmedigi icin iki yorum da raporlanmistir.\n'); % Pressure-convention belirsizligini aciklar.

%% CIKTI YAPISI % Test sonucunu struct olarak dondurur.

out.result_table = result_table; % Siralanmis Du verification sonuc tablosunu kaydeder.
out.best_case = result_table(1, :); % En dusuk combined-score senaryosunu kaydeder.
out.reference_recovery_pct = 100.0 * R_ref; % Published recovery degerini kaydeder.
out.reference_Cp_mgL = Cp_ref_mgL; % Published product concentration degerini kaydeder.
out.reference_flux_LMH = Javg_ref_LMH; % Published average flux degerini kaydeder.
out.reference_Qp_m3h = Qp_ref_m3h; % Published permeate debisini kaydeder.

end % Fonksiyonu sonlandirir.
