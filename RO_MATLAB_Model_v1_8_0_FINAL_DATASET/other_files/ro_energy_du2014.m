function energy = ro_energy_du2014(sys, P_SWIP_MPa, filter_loss_MPa, eta_SWIP, eta_HPP, eta_BP, eta_motor, use_px) % Du-2014 iki-stage RO sisteminde pump power ve SEC degerlerini hesaplar.

%% LOW-PRESSURE FEED STATE % SWIP ve filter sonrasi HPP/PX inlet basincini hesaplar.

P_pre_gauge_MPa = max(P_SWIP_MPa - filter_loss_MPa, 0.0); % SWIP outlet basinçtan filter loss degerini cikararak pretreated-feed gauge basincini hesaplar.

%% SWIP PUMP POWER % Raw seawater intake ve pretreatment pressurization gucunu hesaplar.

W_SWIP_kW = P_SWIP_MPa * sys.Qf_total_m3h / (3.6 * eta_SWIP * eta_motor); % Du-2014 energy accounting ile SWIP pump elektrik gucunu hesaplar.

%% MAIN HIGH-PRESSURE PUMP % PX durumuna gore HPP'den gecen feed debisini belirler.

if use_px % Pressure exchanger aktifse bu dali kullanir.
    Q_HPP_m3h = sys.Qhpp_m3h; % HPP debisini PX system sonucundan alir.
else % Pressure exchanger yoksa bu dali kullanir.
    Q_HPP_m3h = sys.Qf_total_m3h; % Tum raw-feed debisini HPP debisi olarak kullanir.
end % PX/HPP debi kosulunu sonlandirir.

deltaP_HPP_MPa = max(sys.P1_gauge_MPa - P_pre_gauge_MPa, 0.0); % Main HPP physical pressure-rise degerini hesaplar.
W_HPP_kW = deltaP_HPP_MPa * Q_HPP_m3h / (3.6 * eta_HPP * eta_motor); % Main HPP elektrik gucunu hesaplar.

%% INTERSTAGE BOOSTER PUMP % Stage-1 PV outlet basincindan stage-2 inlet basincina gereken boost gucunu hesaplar.

P1out_gauge_MPa = max(sys.stage1_PV.Pout_abs_MPa - 0.101325, 0.0); % Stage-1 representative PV outlet basincini gauge MPa birimine cevirir.
deltaP_interstage_MPa = max(sys.P2_gauge_MPa - P1out_gauge_MPa, 0.0); % Stage-2 inlet icin gereken physical interstage pressure rise degerini hesaplar.
Q_interstage_m3h = sys.stage1_PV.Qb_m3h * sys.N_PV_stage1; % Interstage booster pump'tan gecen toplam stage-1 brine debisini hesaplar.
W_interstage_kW = deltaP_interstage_MPa * Q_interstage_m3h / (3.6 * eta_BP * eta_motor); % Interstage booster pump elektrik gucunu hesaplar.

%% PX HIGH-PRESSURE OUTLET BOOSTER % PX high-side outlet stage-1 pressure altindaysa ek booster gucunu hesaplar.

if use_px % Pressure exchanger aktifse PX booster ihtiyacini hesaplar.
    deltaP_PXbooster_MPa = max(sys.P1_gauge_MPa - sys.px.Ppxhout_gauge_MPa, 0.0); % PX high-pressure outlet ile stage-1 pressure arasindaki farki hesaplar.
    Q_PXbooster_m3h = sys.px.Qpxhout_m3h; % PX booster pump debisini high-pressure seawater outlet debisine esitler.
    W_PXbooster_kW = deltaP_PXbooster_MPa * Q_PXbooster_m3h / (3.6 * eta_BP * eta_motor); % PX high-side booster elektrik gucunu hesaplar.
else % Pressure exchanger yoksa bu dali kullanir.
    deltaP_PXbooster_MPa = 0.0; % PX booster pressure rise degerini sifir yapar.
    Q_PXbooster_m3h = 0.0; % PX booster debisini sifir yapar.
    W_PXbooster_kW = 0.0; % PX booster power degerini sifir yapar.
end % PX booster kosulunu sonlandirir.

%% TOPLAM POWER VE SEC % Tum pump elektriklerini toplar ve specific energy consumption degerini hesaplar.

W_total_kW = W_SWIP_kW + W_HPP_kW + W_interstage_kW + W_PXbooster_kW; % Sistem toplam pump elektrik gucunu hesaplar.
SEC_kWh_m3 = W_total_kW / max(sys.Qp_total_m3h, 1.0e-12); % Sistem specific energy consumption degerini hesaplar.

%% CIKTI YAPISI % Energy model sonuclarini struct icine toplar.

energy.P_pre_gauge_MPa = P_pre_gauge_MPa; % Pretreated-feed gauge pressure degerini kaydeder.
energy.W_SWIP_kW = W_SWIP_kW; % SWIP pump power degerini kaydeder.
energy.deltaP_HPP_MPa = deltaP_HPP_MPa; % HPP pressure-rise degerini kaydeder.
energy.Q_HPP_m3h = Q_HPP_m3h; % HPP debisini kaydeder.
energy.W_HPP_kW = W_HPP_kW; % HPP elektrik gucunu kaydeder.
energy.P1out_gauge_MPa = P1out_gauge_MPa; % Stage-1 PV outlet gauge pressure degerini kaydeder.
energy.deltaP_interstage_MPa = deltaP_interstage_MPa; % Interstage booster pressure-rise degerini kaydeder.
energy.Q_interstage_m3h = Q_interstage_m3h; % Interstage booster debisini kaydeder.
energy.W_interstage_kW = W_interstage_kW; % Interstage booster power degerini kaydeder.
energy.deltaP_PXbooster_MPa = deltaP_PXbooster_MPa; % PX booster pressure-rise degerini kaydeder.
energy.Q_PXbooster_m3h = Q_PXbooster_m3h; % PX booster debisini kaydeder.
energy.W_PXbooster_kW = W_PXbooster_kW; % PX booster power degerini kaydeder.
energy.W_total_kW = W_total_kW; % Sistem toplam pump power degerini kaydeder.
energy.SEC_kWh_m3 = SEC_kWh_m3; % Sistem SEC degerini kaydeder.

end % Fonksiyonu sonlandirir.
