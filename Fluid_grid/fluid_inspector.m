%% ================================================================
%  FLUID PROPERTY INSPECTOR
%  ---------------------------------------------------------------
%  CoolProp kullanarak bir akışkanın temel termodinamik sınırlarını
%  analiz eder ve grid oluşturma için önerilen aralıkları verir.
%
%  Kullanım:
%  Scripti çalıştırmadan önce sadece fluid adını değiştir.
%
%  Author: Ugur ACAR
% ================================================================

clear
clc

%addpath(genpath(pwd));                                           % mevcut klasör ve alt klasörleri path'e ekle
addpath(genpath('F:\PAPERS\ORC Analisys\MATLAB'));              % istersen kendi ana klasörünü ekle


% ------------------------------------------------
% INPUT
% ------------------------------------------------

fluid = 'R600';      %  akışkanı buraya yaz
%fluid = 'R1233zd(E)';      %  akışkanı buraya yaz
%fluid = 'Toluene';      %  akışkanı buraya yaz
%fluid = 'R245fa';      %  akışkanı buraya yaz


fprintf('\n=====================================\n');
fprintf('FLUID INSPECTION\n');
fprintf('Fluid : %s\n',fluid);
fprintf('=====================================\n\n');


% ------------------------------------------------
% BASIC LIMITS FROM COOLPROP
% ------------------------------------------------

Tcrit = PropsSI('Tcrit',fluid);
Pcrit = PropsSI('Pcrit',fluid);

Tmin  = PropsSI('Tmin',fluid);
Tmax  = PropsSI('Tmax',fluid);


fprintf('Critical properties\n');
fprintf('-------------------\n');

fprintf('Tcrit : %.2f °C\n',Tcrit - 273.15);
fprintf('Pcrit : %.2f bar\n\n',Pcrit/1e5);


fprintf('Library limits\n');
fprintf('--------------\n');

fprintf('Tmin  : %.2f °C\n',Tmin - 273.15);
fprintf('Tmax  : %.2f °C\n\n',Tmax - 273.15);

Tsat_1bar = PropsSI('T','P',1e5,'Q',0,fluid);
fprintf('Reference saturation points\n');
fprintf('--------------------------\n');
fprintf('Tsat @ 1 bar : %.2f °C\n\n', Tsat_1bar - 273.15); % SATURATION TEMPERATURE AT 1 BAR

P_high = 0.9 * Pcrit; % HIGH PRESSURE SATURATION REFERENCE
Tsat_0p9Pcrit = PropsSI('T','P',P_high,'Q',0,fluid);
fprintf('P = 0.9*Pcrit : %.2f bar\n', P_high/1e5);
fprintf('Tsat @ 0.9*Pcrit : %.2f °C\n\n', Tsat_0p9Pcrit - 273.15);

%% ------------------------------------------------
% SATURATION SCAN
% ------------------------------------------------
% Entropy sınırlarını bulmak için doymuş eğri taranır

fprintf('Scanning saturation curve...\n\n');

Tscan = linspace(Tmin+5 , Tcrit-5 , 200);

s_liq = zeros(size(Tscan));
s_vap = zeros(size(Tscan));

h_liq = zeros(size(Tscan));
h_vap = zeros(size(Tscan));

for i = 1:length(Tscan)

    T = Tscan(i);

    s_liq(i) = PropsSI('S','T',T,'Q',0,fluid);
    s_vap(i) = PropsSI('S','T',T,'Q',1,fluid);

    h_liq(i) = PropsSI('H','T',T,'Q',0,fluid);
    h_vap(i) = PropsSI('H','T',T,'Q',1,fluid);

end


%% ------------------------------------------------
% LIMITS FROM SATURATION
% ------------------------------------------------

smin = min(s_liq);
smax = max(s_vap);

hmin = min(h_liq);
hmax = max(h_vap);


fprintf('Saturation scan\n');
fprintf('---------------\n');

fprintf('s_liq_min : %.0f J/kgK\n',smin);
fprintf('s_vap_max : %.0f J/kgK\n',smax);

fprintf('h_liq_min : %.0f J/kg\n',hmin);
fprintf('h_vap_max : %.0f J/kg\n\n',hmax);


%% ------------------------------------------------
% SUGGESTED GRID RANGES
% ------------------------------------------------

fprintf('Suggested grid ranges\n');
fprintf('---------------------\n');

Pmin = 1e5;
Pmax = 0.8*Pcrit;

fprintf('Pressure     : %.2f – %.2f bar\n',Pmin/1e5 , Pmax/1e5);

fprintf('Entropy      : %.0f – %.0f J/kgK\n', ...
        smin*0.9 , smax*1.1);

fprintf('Temperature  : %.1f – %.1f °C\n', ...
        Tmin+20-273.15 , Tcrit-5-273.15);

fprintf('Enthalpy     : %.0f – %.0f J/kgK\n\n', ...
        hmin *0.7 , hmax*1.4);

fprintf('=====================================\n');


%% ------------------------------------------------
% PLOT SATURATION DOME (T-s)
% ------------------------------------------------
fprintf('Generating T-s diagram...\n');
% Kelvin → Celsius dönüşümü
Tscan_C = Tscan - 273.15;

figure

plot(s_liq , Tscan_C , 'b','LineWidth',2)
hold on
plot(s_vap , Tscan_C , 'r','LineWidth',2)

xlabel('Entropy [J/kgK]')
ylabel('Temperature [°C]')

title(['Saturation dome - ',fluid])

grid on
legend('Saturated liquid','Saturated vapor')

%% ------------------------------------------------
% PLOT P-s DIAGRAM
% ------------------------------------------------

fprintf('Generating P-s diagram...\n');

Tscan_ps = linspace(Tmin+5 , Tcrit-5 , 250);

s_liq_ps = zeros(size(Tscan_ps));
s_vap_ps = zeros(size(Tscan_ps));
P_sat_ps = zeros(size(Tscan_ps));

for i = 1:length(Tscan_ps)

    T = Tscan_ps(i);

    s_liq_ps(i) = PropsSI('S','T',T,'Q',0,fluid);
    s_vap_ps(i) = PropsSI('S','T',T,'Q',1,fluid);

    P_sat_ps(i) = PropsSI('P','T',T,'Q',0,fluid);

end


% bar'a çevir
P_sat_bar = P_sat_ps / 1e5;


figure

plot(s_liq_ps , P_sat_bar , 'b','LineWidth',2)
hold on
plot(s_vap_ps , P_sat_bar , 'r','LineWidth',2)

xlabel('Entropy [J/kgK]')
ylabel('Pressure [bar]')

title(['P-s diagram (saturation dome) - ',fluid])

grid on

legend('Saturated liquid','Saturated vapor')

set(gca,'YScale','log')   % log scale daha okunur olur

%% ------------------------------------------------
% PLOT P-h DIAGRAM
% ------------------------------------------------

fprintf('Generating P-h diagram...\n');

Tscan_ph = linspace(Tmin+5 , Tcrit-5 , 250);

h_liq_ph = zeros(size(Tscan_ph));
h_vap_ph = zeros(size(Tscan_ph));
P_sat_ph = zeros(size(Tscan_ph));

for i = 1:length(Tscan_ph)

    T = Tscan_ph(i);

    h_liq_ph(i) = PropsSI('H','T',T,'Q',0,fluid);
    h_vap_ph(i) = PropsSI('H','T',T,'Q',1,fluid);

    P_sat_ph(i) = PropsSI('P','T',T,'Q',0,fluid);

end

% birim dönüşümleri
h_liq_kJ = h_liq_ph / 1000;
h_vap_kJ = h_vap_ph / 1000;
P_bar = P_sat_ph / 1e5;

figure

plot(h_liq_kJ , P_bar , 'b','LineWidth',2)
hold on
plot(h_vap_kJ , P_bar , 'r','LineWidth',2)

xlabel('Enthalpy [kJ/kg]')
ylabel('Pressure [bar]')

title(['P-h diagram (saturation dome) - ',fluid])

grid on
legend('Saturated liquid','Saturated vapor')

set(gca,'YScale','log')   % kritik!