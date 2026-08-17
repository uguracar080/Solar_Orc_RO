%% ========================================================================
% THERMODYNAMIC GRID GENERATOR
% ------------------------------------------------------------------------
% Bu script CoolProp kullanarak bir akışkan için termodinamik özellik
% gridlerini oluşturur ve .mat dosyasına kaydeder.
%
% Üretilen veri tabanı:
%   1) thermoGrid (P,s)  → h, T, rho, cp
%   2) satGrid   (P)     → hf, hg, sf, sg, Tf
%
% Amaç:
%   Simülasyon sırasında CoolProp çağrılarını kaldırmak
%
% Kullanım:
%   Script başındaki INPUT bölümünü düzenle
%
% Author: Ugur ACAR
% ========================================================================

clear
clc
close all
tic

startTime = datetime('now');
fprintf('Calculation started at: %s\n', datestr(startTime,'yyyy-mm-dd HH:MM:SS'));

%% ------------------------------------------------------------------------
% INPUT PARAMETERS
% ------------------------------------------------------------------------

fluid = 'R410a';           % akışkan adı

% Pressure grid limits
Pmin_bar = 0.5;             % minimum pressure [bar]
Pmax_bar = 28;              % maximum pressure [bar]

% Entropy grid limits
smin = 850;                 % minimum entropy [J/kgK]
smax = 1750;                % maximum entropy [J/kgK]

% Grid resolution
Np = 200;                   % pressure grid size
Ns = 200;                   % entropy grid size

% Saturation grid resolution
Nsat = 300;                 % saturation pressure grid

%% ------------------------------------------------------------------------
% UNIT CONVERSION
% ------------------------------------------------------------------------

Pmin = Pmin_bar * 1e5;      % bar → Pa
Pmax = Pmax_bar * 1e5;

%% ------------------------------------------------------------------------
% CREATE PRESSURE AND ENTROPY VECTORS
% ------------------------------------------------------------------------

P_vec = linspace(Pmin , Pmax , Np);     % pressure grid
s_vec = linspace(smin , smax , Ns);     % entropy grid

%% ------------------------------------------------------------------------
% PREALLOCATE PROPERTY MATRICES
% ------------------------------------------------------------------------

H   = zeros(Np,Ns);         % enthalpy
T   = zeros(Np,Ns);         % temperature
rho = zeros(Np,Ns);         % density
cp  = zeros(Np,Ns);         % specific heat

%% ------------------------------------------------------------------------
% START PARALLEL POOL (IF NOT RUNNING)
% ------------------------------------------------------------------------

if isempty(gcp('nocreate'))
    parpool;                % available core sayısı kadar worker açılır
end

%% ------------------------------------------------------------------------
% GENERATE (P,s) THERMODYNAMIC GRID
% ------------------------------------------------------------------------
tic
fprintf('\nGenerating thermodynamic grid (P,s)...\n')

% her pressure için paralel döngü
parfor i = 1:Np

    % local arrays oluşturulur (parfor için gerekli)
    H_row   = zeros(1,Ns);
    T_row   = zeros(1,Ns);
    rho_row = zeros(1,Ns);
    cp_row  = zeros(1,Ns);

    % pressure değeri
    P = P_vec(i);

    for j = 1:Ns

        % entropy değeri
        s = s_vec(j);

        try

            % enthalpy hesapla
            h = PropsSI('H','P',P,'S',s,fluid);

            % temperature
            T_row(j) = PropsSI('T','P',P,'S',s,fluid);

            % density
            rho_row(j) = PropsSI('D','P',P,'S',s,fluid);

            % cp
            cp_row(j) = PropsSI('C','P',P,'S',s,fluid);

            H_row(j) = h;

        catch

            % iki faz bölgesi veya hatalı noktalar
            H_row(j)   = NaN;
            T_row(j)   = NaN;
            rho_row(j) = NaN;
            cp_row(j)  = NaN;

        end

    end

    % sonuçları ana matrise yaz
    H(i,:)   = H_row;
    T(i,:)   = T_row;
    rho(i,:) = rho_row;
    cp(i,:)  = cp_row;

end

fprintf('Thermo grid completed.\n')

t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('Thermo grid completed: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);

%% ------------------------------------------------------------------------
% GENERATE SATURATION GRID
% ------------------------------------------------------------------------

fprintf('Generating saturation grid...\n')

P_sat_vec = linspace(Pmin , Pmax , Nsat);

hf = zeros(size(P_sat_vec));
hg = zeros(size(P_sat_vec));
sf = zeros(size(P_sat_vec));
sg = zeros(size(P_sat_vec));
Tf = zeros(size(P_sat_vec));

for i = 1:Nsat

    P = P_sat_vec(i);

    try

        hf(i) = PropsSI('H','P',P,'Q',0,fluid);
        hg(i) = PropsSI('H','P',P,'Q',1,fluid);

        sf(i) = PropsSI('S','P',P,'Q',0,fluid);
        sg(i) = PropsSI('S','P',P,'Q',1,fluid);

        Tf(i) = PropsSI('T','P',P,'Q',0,fluid);

    catch

        hf(i) = NaN;
        hg(i) = NaN;
        sf(i) = NaN;
        sg(i) = NaN;
        Tf(i) = NaN;

    end

end

fprintf('Saturation grid completed.\n')

t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('Saturation grid completed: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);

%% ------------------------------------------------------------------------
% STORE DATA STRUCTURE
% ------------------------------------------------------------------------

thermoData = struct();

thermoData.fluid = fluid;

% thermo grid
thermoData.thermoGrid.P_vec = P_vec;
thermoData.thermoGrid.s_vec = s_vec;

thermoData.thermoGrid.H   = H;
thermoData.thermoGrid.T   = T;
thermoData.thermoGrid.rho = rho;
thermoData.thermoGrid.cp  = cp;

% saturation grid
thermoData.satGrid.P_vec = P_sat_vec;

thermoData.satGrid.hf = hf;
thermoData.satGrid.hg = hg;

thermoData.satGrid.sf = sf;
thermoData.satGrid.sg = sg;

thermoData.satGrid.Tf = Tf;

%% ------------------------------------------------------------------------
% SAVE .MAT FILE
% ------------------------------------------------------------------------

filename = ['thermo_',fluid,'.mat'];

save(filename,'thermoData','-v7.3')

fprintf('\nThermodynamic database saved as:\n')
fprintf('%s\n',filename)



t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('Calculation duration: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);

endTime = datetime('now');
fprintf('Calculation finished at: %s\n', datestr(endTime,'yyyy-mm-dd HH:MM:SS'));


%% ------------------------------------------------------------------------
% OPTIONAL: QUICK VISUAL CHECK
% ------------------------------------------------------------------------

figure

plot(s_vec , T(:,round(Ns/2))-273.15)

xlabel('Entropy [J/kgK]')
ylabel('Temperature [°C]')

title(['Sample T-s slice - ',fluid])

grid on