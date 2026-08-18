function W_kW = ro_pump_power(Q_m3h, P_in_abs_MPa, P_out_abs_MPa, eta_pump, eta_motor) % High-pressure pump elektrik gucunu hesaplar.

%% GIRDI KONTROLU % Debi, basinc ve verimleri fiziksel aralikta tutar.

Q_m3h = max(Q_m3h, 0.0); % Debinin negatif olmasini engeller.
eta_pump = min(max(eta_pump, 1.0e-6), 1.0); % Pump efficiency degerini sifir-bir araliginda tutar.
eta_motor = min(max(eta_motor, 1.0e-6), 1.0); % Motor efficiency degerini sifir-bir araliginda tutar.
deltaP_Pa = max(P_out_abs_MPa - P_in_abs_MPa, 0.0) * 1.0e6; % Pump pressure rise degerini Pa cinsinden hesaplar.

%% PUMP GUC HESABI % Q*DeltaP/(eta_pump*eta_motor) ile elektrik gucunu hesaplar.

Q_m3_s = Q_m3h / 3600.0; % Volumetric flow rate degerini m3/s birimine cevirir.
W_W = Q_m3_s * deltaP_Pa / (eta_pump * eta_motor); % Pump elektrik gucunu W cinsinden hesaplar.
W_kW = W_W / 1000.0; % Pump elektrik gucunu kW birimine cevirir.

end % Fonksiyonu sonlandirir.
