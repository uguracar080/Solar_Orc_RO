%% ========================================================================
% CP_SURROGATE_MODEL_T_ONLY.m
% ========================================================================

clear; clc; close all;

addpath(genpath('F:\PAPERS\SOLAR-ORC Optimizasyon\System_Mode'));

fluid = 'Water';

%% ------------------------------------------------------------------------
% 1) SICAKLIK ARALIĞI
% ------------------------------------------------------------------------
T_C = linspace(0, 150, 200);   % 0–120°C (güvenli aralık)
T_K = T_C + 273.15;

%% ------------------------------------------------------------------------
% 2) REFERANS BASINÇ (önemsiz ama gerekli)
% ------------------------------------------------------------------------
P_ref = 1e5;   % 5 bar (liquid garanti)

%% ------------------------------------------------------------------------
% 3) COOLPROP DATA
% ------------------------------------------------------------------------
cp_real = PropsSI('C','T',T_K,'P',P_ref,'Water');

% Güvenlik kontrolü
assert(all(isfinite(cp_real)), 'CoolProp NaN/Inf döndürdü!');

%% ------------------------------------------------------------------------
% 4) POLYNOMIAL FIT (cubic)
% ------------------------------------------------------------------------
% cp = a0 + a1*T + a2*T^2 + a3*T^3

X = [ ...
    ones(length(T_K),1), ...
    T_K(:), ...
    T_K(:).^2, ...
    T_K(:).^3 ];

coeff = X \ cp_real(:);

%% ------------------------------------------------------------------------
% 5) DOĞRULAMA
% ------------------------------------------------------------------------
cp_pred = X * coeff;

error = abs((cp_pred - cp_real(:)) ./ cp_real(:)) * 100;

fprintf('Mean error  : %.4f %%\n', mean(error));
fprintf('Max error   : %.4f %%\n', max(error));

%% ------------------------------------------------------------------------
% 6) MODELİ KAYDET
% ------------------------------------------------------------------------
%% ------------------------------------------------------------------------
% 6.5) MODEL DENKLEMİNİ YAZDIR
% ------------------------------------------------------------------------

a = coeff;   % katsayılar

fprintf('\n==============================================\n');
fprintf('        CP SURROGATE MODEL (Water)\n');
fprintf('==============================================\n');

fprintf('Model type: cp(T) polynomial (cubic)\n\n');

fprintf('cp(T) = a0 + a1*T + a2*T^2 + a3*T^3\n\n');

fprintf('a0 = %.6e\n', a(1));
fprintf('a1 = %.6e\n', a(2));
fprintf('a2 = %.6e\n', a(3));
fprintf('a3 = %.6e\n', a(4));

fprintf('\nTemperature range: %.2f K – %.2f K\n', ...
    min(T_K), max(T_K));

fprintf('==============================================\n\n');
cp_model.coeff = coeff;
cp_model.type = 'cp(T)';
cp_model.T_range = [min(T_K), max(T_K)];



save('cp_model_water_T_only.mat', 'cp_model')

fprintf('Model saved.\n');
%% ------------------------------------------------------------------------
% 7) GRAFİK: GERÇEK vs MODEL
% ------------------------------------------------------------------------

figure('Name','cp Model Validation','Color','w');

% --- 1) cp vs Temperature ---
subplot(2,1,1);

plot(T_C, cp_real, 'b-', 'LineWidth', 2); hold on;
plot(T_C, cp_pred, 'r--', 'LineWidth', 2);

grid on;
xlabel('Temperature [°C]');
ylabel('cp [J/kg-K]');
title('Water cp: CoolProp vs Surrogate Model');

legend('CoolProp (Real)', 'Model (Polynomial)', 'Location','best');

% --- 2) Error plot ---
subplot(2,1,2);

plot(T_C, error, 'k-', 'LineWidth', 2);

grid on;
xlabel('Temperature [°C]');
ylabel('Error [%]');
title('Relative Error');

% --- layout iyileştirme
set(gcf,'Position',[200 200 800 600]);