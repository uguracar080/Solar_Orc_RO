function px = ro_px_du2014(Qpxhin_m3h, Cpxhin_kg_m3, Ppxhin_gauge_MPa, Cf_kg_m3, eta_px, leakage_pressure_unit, Ppxlin_gauge_MPa, Ppxlout_gauge_MPa) % Du-2014 ERI PX-220 pressure-exchanger denklemlerini hesaplar.

%% GIRDI KONTROLLERI % PX model girdilerini fiziksel ve sayisal aralikta tutar.

Qpxhin_m3h = max(Qpxhin_m3h, 1.0e-12); % High-pressure brine inlet debisini pozitif tutar.
Cpxhin_kg_m3 = max(Cpxhin_kg_m3, 0.0); % High-pressure brine inlet konsantrasyonunu negatif olmayacak sekilde sinirlar.
Ppxhin_gauge_MPa = max(Ppxhin_gauge_MPa, 0.0); % High-pressure brine inlet gauge basincini negatif olmayacak sekilde sinirlar.
Cf_kg_m3 = max(Cf_kg_m3, 0.0); % Low-pressure seawater concentration degerini negatif olmayacak sekilde sinirlar.
eta_px = min(max(eta_px, 1.0e-6), 1.0); % Pressure-exchanger efficiency degerini sifir-bir araliginda tutar.
Ppxlin_gauge_MPa = max(Ppxlin_gauge_MPa, 0.0); % PX low-pressure inlet basincini negatif olmayacak sekilde sinirlar.
Ppxlout_gauge_MPa = max(Ppxlout_gauge_MPa, 0.0); % PX low-pressure outlet basincini negatif olmayacak sekilde sinirlar.

%% LUBRICATION / LEAKAGE KORELASYONU % Du-2014 Eq.50 icin pressure-unit yorumunu secer.

if strcmpi(leakage_pressure_unit, 'bar') % Empirik Eq.50 basincinin bar olarak yorumlandigi senaryoyu kontrol eder.
    P_corr = 10.0 * Ppxhin_gauge_MPa; % Gauge MPa degerini bar birimine cevirir.
elseif strcmpi(leakage_pressure_unit, 'MPa') % Empirik Eq.50 basincinin MPa olarak yorumlandigi senaryoyu kontrol eder.
    P_corr = Ppxhin_gauge_MPa; % Gauge MPa degerini korelasyonda dogrudan kullanir.
else % Tanimlanmamis pressure-unit etiketi verildiyse bu dali kullanir.
    error('leakage_pressure_unit yalnizca ''bar'' veya ''MPa'' olabilir.'); % Hatali pressure-unit etiketi icin acik hata mesaji verir.
end % Leakage pressure-unit kosulunu sonlandirir.

Lpx_pct = 0.3924 + 0.01238 * P_corr; % Du-2014 Eq.50 ERI PX-220 lubrication/leakage yuzdesini hesaplar.
Lpx_pct = min(max(Lpx_pct, 0.0), 15.0); % Empirik leakage yuzdesini sayisal olarak makul aralikta tutar.

%% PX DEBI DENGELERI % Du-2014 Eq.47-49 ile high/low-side debilerini hesaplar.

Qpxhout_m3h = Qpxhin_m3h * (1.0 - Lpx_pct / 100.0); % Du-2014 Eq.49 ile high-pressure seawater outlet debisini hesaplar.
Qpxlin_m3h = Qpxhout_m3h; % Du-2014 Eq.47 ile low-pressure seawater inlet debisini high-pressure outlet debisine esitler.
Qpxlout_m3h = Qpxhin_m3h; % Du-2014 Eq.48 ile low-pressure brine outlet debisini high-pressure brine inlet debisine esitler.

%% OVERFLUSH VE VOLUMETRIK MIXING % Du-2014 Eq.52-53 ile PX mixing parametrelerini hesaplar.

OF_pct = 100.0 * (Qpxhin_m3h - Qpxhout_m3h) / Qpxhin_m3h; % Du-2014 Eq.53 overflush yuzdesini hesaplar.
Mix_pct = 6.0057 - 0.3559 * OF_pct + 0.0084 * OF_pct^2; % Du-2014 Eq.52 ERI PX-220 volumetric mixing yuzdesini hesaplar.
Mix_fraction = Mix_pct / 100.0; % Mixing yuzdesini concentration equation icin fraction degerine cevirir.

%% PX CIKIS KONSANTRASYONLARI % Du-2014 Eq.51 ve Eq.54 ile iki PX outlet salinitesini hesaplar.

Cpxlin_kg_m3 = Cf_kg_m3; % PX low-pressure seawater inlet konsantrasyonunu raw-feed concentration degerine esitler.
Cpxhout_kg_m3 = Cpxlin_kg_m3 + Mix_fraction * (Cpxhin_kg_m3 - Cpxlin_kg_m3); % Du-2014 Eq.51 ile high-pressure seawater outlet concentration degerini hesaplar.
Cpxlout_kg_m3 = (Qpxlin_m3h * Cpxlin_kg_m3 + Qpxhin_m3h * Cpxhin_kg_m3 - Qpxhout_m3h * Cpxhout_kg_m3) / max(Qpxlout_m3h, 1.0e-12); % Du-2014 Eq.54 ile low-pressure brine outlet concentration degerini hesaplar.

%% PX PRESSURE EFFICIENCY % Du-2014 Eq.94 ile high-pressure seawater outlet basincini hesaplar.

numerator_MPa_m3h = eta_px * (Ppxhin_gauge_MPa * Qpxhin_m3h + Ppxlin_gauge_MPa * Qpxlin_m3h) - Ppxlout_gauge_MPa * Qpxlout_m3h; % Eq.94 yeniden duzenlenmis pay degerini hesaplar.
Ppxhout_gauge_MPa = numerator_MPa_m3h / max(Qpxhout_m3h, 1.0e-12); % Eq.94 yeniden duzenlenmis formu ile PX high-pressure outlet gauge basincini hesaplar.
Ppxhout_gauge_MPa = max(Ppxhout_gauge_MPa, 0.0); % Hesaplanan PX outlet basincini negatif olmayacak sekilde sinirlar.

%% EFFICIENCY BACK-CHECK % Hesaplanan outlet basinci ile Eq.94 efficiency degerini tekrar kontrol eder.

eta_back = (Ppxhout_gauge_MPa * Qpxhout_m3h + Ppxlout_gauge_MPa * Qpxlout_m3h) / max(Ppxhin_gauge_MPa * Qpxhin_m3h + Ppxlin_gauge_MPa * Qpxlin_m3h, 1.0e-12); % PX pressure efficiency degerini outlet sonuclarindan yeniden hesaplar.

%% CIKTI YAPISI % PX model sonuclarini tek struct icinde toplar.

px.Qpxhin_m3h = Qpxhin_m3h; % High-pressure brine inlet debisini kaydeder.
px.Qpxhout_m3h = Qpxhout_m3h; % High-pressure seawater outlet debisini kaydeder.
px.Qpxlin_m3h = Qpxlin_m3h; % Low-pressure seawater inlet debisini kaydeder.
px.Qpxlout_m3h = Qpxlout_m3h; % Low-pressure brine outlet debisini kaydeder.
px.Cpxhin_kg_m3 = Cpxhin_kg_m3; % High-pressure brine inlet concentration degerini kaydeder.
px.Cpxhout_kg_m3 = Cpxhout_kg_m3; % High-pressure seawater outlet concentration degerini kaydeder.
px.Cpxlin_kg_m3 = Cpxlin_kg_m3; % Low-pressure seawater inlet concentration degerini kaydeder.
px.Cpxlout_kg_m3 = Cpxlout_kg_m3; % Low-pressure brine outlet concentration degerini kaydeder.
px.Ppxhin_gauge_MPa = Ppxhin_gauge_MPa; % High-pressure brine inlet gauge basincini kaydeder.
px.Ppxhout_gauge_MPa = Ppxhout_gauge_MPa; % High-pressure seawater outlet gauge basincini kaydeder.
px.Ppxlin_gauge_MPa = Ppxlin_gauge_MPa; % Low-pressure seawater inlet gauge basincini kaydeder.
px.Ppxlout_gauge_MPa = Ppxlout_gauge_MPa; % Low-pressure brine outlet gauge basincini kaydeder.
px.Lpx_pct = Lpx_pct; % Du lubrication/leakage yuzdesini kaydeder.
px.OF_pct = OF_pct; % Overflush yuzdesini kaydeder.
px.Mix_pct = Mix_pct; % Volumetric mixing yuzdesini kaydeder.
px.eta_px = eta_px; % Girilen PX efficiency degerini kaydeder.
px.eta_back = eta_back; % Eq.94 back-check efficiency degerini kaydeder.
px.leakage_pressure_unit = leakage_pressure_unit; % Eq.50 pressure-unit yorumunu kaydeder.

end % Fonksiyonu sonlandirir.
