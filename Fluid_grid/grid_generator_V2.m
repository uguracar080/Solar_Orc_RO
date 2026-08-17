%% ========================================================================
% GENERATE_THERMO_DATABASE
% ------------------------------------------------------------------------
% Bu script CoolProp kullanarak geniş kapsamlı bir termodinamik
% veri tabanı üretir ve .mat dosyasına kaydeder.
%
% Amaç:
% Simülasyon sırasında CoolProp çağrılarını tamamen kaldırmak
%
% Oluşturulan tablolar:
%
% 1) Saturation table
%       P  -> Tsat hf hg sf sg rho_f rho_g
%
% 2) (P,s) grid
%       (P,s) -> h T rho
%
% 3) (P,h) grid
%       (P,h) -> T s
%
% 4) Isentropic grid
%       (P2,s1) -> h2s
%
% Tüm gridler yüksek çözünürlüklüdür ve parfor ile hesaplanır.
%
% Author: Ugur Acar, 2026
% ========================================================================

clear
clc
close all

tic

%% ========================================================================
% USER PATHS
% ========================================================================
%addpath(genpath(pwd));
addpath(genpath('F:\PAPERS\ORC Analisys\MATLAB')); % MATLAB çalışma klasörünü ve alt klasörleri path'e ekler

%% --------------------------------------------------
% Simulation start time
% --------------------------------------------------
startTime = datetime('now');
fprintf('Generator started at: %s\n', datestr(startTime,'yyyy-mm-dd HH:MM:SS'));
fprintf('Grid Generation Order: GRID_1_(P,s)--GRID_2_(P,h)--GRID_3_Saturation--GRID_4_ Isentropic_Enthalpy\n');

%% ========================================================================
% INPUT PARAMETERS
% ========================================================================

fluid = 'R245fa';              % çalışılacak akışkan

% -------------------------------
% Pressure range
% -------------------------------

Pmin_bar = 0.3;                % minimum pressure
Pmax_bar = 40;                 % maximum pressure

% -------------------------------
% Entropy range
% -------------------------------

smin = 400;                    % J/kgK
smax = 2500;                   % J/kgK

% -------------------------------
% Enthalpy range
% -------------------------------

hmin = 1e5;                    % J/kg
hmax = 8e5;                    % J/kg

% -------------------------------
% GRID RESOLUTION
% -------------------------------

Np = 600;                      % pressure resolution
Ns = 600;                      % entropy resolution
Nh = 600;                      % enthalpy resolution
Nsat = 1000;                   % saturation resolution

%% ========================================================================
% UNIT CONVERSION
% ========================================================================

Pmin = Pmin_bar*1e5;
Pmax = Pmax_bar*1e5;

%% ========================================================================
% GRID VECTORS
% ========================================================================

P_vec = linspace(Pmin,Pmax,Np);      % pressure grid

s_vec = linspace(smin,smax,Ns);      % entropy grid

h_vec = linspace(hmin,hmax,Nh);      % enthalpy grid

%% ========================================================================
% PARALLEL POOL
% ========================================================================

if isempty(gcp('nocreate'))
    parpool;
end

%% ========================================================================
% PREALLOCATE ARRAYS
% ========================================================================

H_ps   = nan(Np,Ns);          % h(P,s)
T_ps   = nan(Np,Ns);          % T(P,s)
rho_ps = nan(Np,Ns);          % rho(P,s)

T_ph   = nan(Np,Nh);          % T(P,h)
s_ph   = nan(Np,Nh);          % s(P,h)

%% ========================================================================
% GRID 1
% (P,s) THERMODYNAMIC TABLE
% ========================================================================

fprintf('Generating GRID 1 (P,s) table...\n')

parfor i = 1:Np
    
    P = P_vec(i);              % pressure
    
    H_row = nan(1,Ns);
    T_row = nan(1,Ns);
    rho_row = nan(1,Ns);
    
    for j = 1:Ns
        
        s = s_vec(j);
        
        try
            
            H_row(j) = PropsSI('H','P',P,'S',s,fluid);
            
            T_row(j) = PropsSI('T','P',P,'S',s,fluid);
            
            rho_row(j) = PropsSI('D','P',P,'S',s,fluid);
            
        catch
            
            H_row(j) = NaN;
            T_row(j) = NaN;
            rho_row(j) = NaN;
            
        end
        
    end
    
    H_ps(i,:) = H_row;
    T_ps(i,:) = T_row;
    rho_ps(i,:) = rho_row;
    
end

t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('GRID_1 (P,s) finished: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);

%% ========================================================================
% GRID 2
% (P,h) INVERSION TABLE
% ========================================================================

fprintf('Generating GRID_2 (P,h) table...\n')

parfor i = 1:Np
    
    P = P_vec(i);
    
    T_row = nan(1,Nh);
    s_row = nan(1,Nh);
    
    for j = 1:Nh
        
        h = h_vec(j);
        
        try
            
            T_row(j) = PropsSI('T','P',P,'H',h,fluid);
            
            s_row(j) = PropsSI('S','P',P,'H',h,fluid);
            
        catch
            
            T_row(j) = NaN;
            s_row(j) = NaN;
            
        end
        
    end
    
    T_ph(i,:) = T_row;
    s_ph(i,:) = s_row;
    
end
t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('GRID_2 (P,h) finished: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);


%% ========================================================================
% GRID 3
% SATURATION TABLE
% ========================================================================

fprintf('Generating GRID-3, Saturation Table...\n')

P_sat_vec = linspace(Pmin,Pmax,Nsat);

hf = nan(size(P_sat_vec));
hg = nan(size(P_sat_vec));
sf = nan(size(P_sat_vec));
sg = nan(size(P_sat_vec));
Tf = nan(size(P_sat_vec));

rho_f = nan(size(P_sat_vec));
rho_g = nan(size(P_sat_vec));

parfor i = 1:Nsat
    
    P = P_sat_vec(i);
    
    try
        
        hf(i) = PropsSI('H','P',P,'Q',0,fluid);
        hg(i) = PropsSI('H','P',P,'Q',1,fluid);
        
        sf(i) = PropsSI('S','P',P,'Q',0,fluid);
        sg(i) = PropsSI('S','P',P,'Q',1,fluid);
        
        Tf(i) = PropsSI('T','P',P,'Q',0,fluid);
        
        rho_f(i) = PropsSI('D','P',P,'Q',0,fluid);
        rho_g(i) = PropsSI('D','P',P,'Q',1,fluid);
        
    catch
        
    end
    
end
t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('GRID_3 Saturation Table finished: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);

%% ========================================================================
% GRID 4
% ISENTROPIC ENTHALPY TABLE
% ========================================================================

fprintf('Generating GRID_4, isentropic enthalpy grid...\n')

Pc_vec = P_vec;

h2s_grid = nan(Ns,Np);

parfor is = 1:Ns
    
    s = s_vec(is);
    
    row = nan(1,Np);
    
    for ip = 1:Np
        
        Pc = Pc_vec(ip);
        
        try
            
            row(ip) = PropsSI('H','P',Pc,'S',s,fluid);
            
        catch
            
            row(ip) = NaN;
            
        end
        
    end
    
    h2s_grid(is,:) = row;
    
end

t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('GRID_4 Isentropic Enthalpy Table finished: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);

%% ========================================================================
% CREATE DATABASE STRUCT
% ========================================================================

thermoDB = struct();

thermoDB.fluid = fluid;

% saturation
thermoDB.sat.P = P_sat_vec;
thermoDB.sat.hf = hf;
thermoDB.sat.hg = hg;
thermoDB.sat.sf = sf;
thermoDB.sat.sg = sg;
thermoDB.sat.T = Tf;
thermoDB.sat.rho_f = rho_f;
thermoDB.sat.rho_g = rho_g;

% P,s grid
thermoDB.Ps.P = P_vec;
thermoDB.Ps.s = s_vec;
thermoDB.Ps.H = H_ps;
thermoDB.Ps.T = T_ps;
thermoDB.Ps.rho = rho_ps;

% P,h grid
thermoDB.Ph.P = P_vec;
thermoDB.Ph.h = h_vec;
thermoDB.Ph.T = T_ph;
thermoDB.Ph.s = s_ph;

% isentropic
thermoDB.iso.P = Pc_vec;
thermoDB.iso.s = s_vec;
thermoDB.iso.h2s = h2s_grid;

%% ========================================================================
% SAVE DATABASE
% ========================================================================

filename = ['thermoDB_',fluid,'.mat'];
save(filename,'thermoDB','-v7.3')

fprintf('\nDatabase saved: %s\n',filename)

% --------------------------------------------------
% Simulation end time
% --------------------------------------------------
endTime = datetime('now');
fprintf('Generation finished at: %s\n', datestr(endTime,'yyyy-mm-dd HH:MM:SS'));

t = toc;
h = floor(t/3600);
m = floor(mod(t,3600)/60);
s = mod(t,60);
fprintf('Simulation duration: %02d:%02d:%05.2f (hh:mm:ss)\n',h,m,s);