% ========================================================================
% GENERATE_THERMO_DATABASE
% ------------------------------------------------------------------------
% Bu script CoolProp kullanarak geniş kapsamlı bir termodinamik
% veri tabanı üretir ve .mat dosyasına kaydeder.
%
% Oluşturulan tablolar:
%   1) Saturation table     : P -> Tsat hf hg sf sg rho_f rho_g
%   2) (P,s) grid           : (P,s) -> h T rho
%   3) (P,h) grid           : (P,h) -> T s
%   4) Isentropic grid      : (P2,s1) -> h2s
%
% Not:
%   GRID 4, GRID 1'de hesaplanan h(P,s) tablosunun transpozudur.
%
% Author: Ugur Acar, 2026
% Revised: SmartMATLAB code review
% ========================================================================

clearvars
clc
close all

tStart = tic;

%% ========================================================================
% PATH SETUP
% ========================================================================
% Script'in bulunduğu klasörü ve alt klasörlerini path'e ekle
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
addpath(genpath(scriptDir));

%% ========================================================================
% COOLPROP AVAILABILITY CHECK
% ========================================================================
% Direct PropsSI wrapper varsa kullan.
% Yoksa kullanıcıya açık hata ver.
if exist('PropsSI', 'file') ~= 2 && exist('PropsSI', 'builtin') ~= 5
    error(['CoolProp function "PropsSI" not found on MATLAB path. ' ...
           'CoolProp must be installed and accessible before running this script.']);
end

%% ========================================================================
% SIMULATION START INFO
% ========================================================================
startTime = datetime('now');
fprintf('Generator started at: %s\n', datestr(startTime,'yyyy-mm-dd HH:MM:SS'));
fprintf(['Grid Generation Order: GRID_1_(P,s) -> GRID_2_(P,h) -> ', ...
         'GRID_3_Saturation -> GRID_4_Isentropic_Enthalpy\n']);

%% ========================================================================
% INPUT PARAMETERS
% ========================================================================
%fluid = 'R245fa';
%fluid = 'R410a';
%fluid = 'R1233zd(E)';
fluid = 'R600';
fluid = strtrim(fluid);

try
    PropsSI('TCRIT', fluid);
catch ME
    error('Invalid or unavailable fluid "%s": %s', fluid, ME.message);
end

fprintf('Selected fluid: "%s"\n', fluid);

% Pressure range
Pmin_bar = 0.5;
Pmax_bar = 35;

% Entropy range [J/kg/K]
smin = 840;
smax = 2600;

% Enthalpy range [J/kg]
hmin = 150e3;
hmax = 750e3;

% GRID RESOLUTION 
Np   = 600;
Ns   = 600;
Nh   = 600;
Nsat = 1000;


%% ========================================================================
% UNIT CONVERSION
% ========================================================================
Pmin = Pmin_bar * 1e5;
Pmax = Pmax_bar * 1e5;

%% ========================================================================
% GRID VECTORS
% ========================================================================
P_vec = linspace(Pmin, Pmax, Np);
s_vec = linspace(smin, smax, Ns);
h_vec = linspace(hmin, hmax, Nh);

%% ========================================================================
% PARALLEL POOL
% ========================================================================
poolObj = gcp('nocreate');
if isempty(poolObj)
    parpool;
end

%% ========================================================================
% PREALLOCATE ARRAYS
% ========================================================================
H_ps   = nan(Np, Ns);   % h(P,s)
T_ps   = nan(Np, Ns);   % T(P,s)
rho_ps = nan(Np, Ns);   % rho(P,s)

T_ph   = nan(Np, Nh);   % T(P,h)
s_ph   = nan(Np, Nh);   % s(P,h)

%% ========================================================================
% MASTER PROGRESS BAR SETUP
% ========================================================================

% total iteration count across all grids
totalIterations = Np + Np + Nsat; 
% GRID1 + GRID2 + GRID3

progressCount = 0;

wb = waitbar(0,'Initializing thermodynamic database generation...');

progressStart = tic;

dq = parallel.pool.DataQueue;

%afterEach(dq,@updateProgress);
%afterEach(dq,@(~)updateProgress(totalIterations,progressStart,wb));
afterEach(dq,@(data)updateProgress(data,totalIterations,progressStart,wb,Np,Nsat));



%% ========================================================================
% GRID 1 : (P,s) THERMODYNAMIC TABLE
% ========================================================================
fprintf('Generating GRID 1 (P,s) table...\n');
waitbar(progressCount/totalIterations,wb,'GRID 1 (P,s) generating...')

parfor i = 1:Np
    P = P_vec(i);

    H_row   = nan(1, Ns);
    T_row   = nan(1, Ns);
    rho_row = nan(1, Ns);

    % Fast path: evaluate the full entropy row in vector form.
    try
        H_row   = PropsSI('H', 'P', P, 'S', s_vec, fluid).';
        T_row   = PropsSI('T', 'P', P, 'S', s_vec, fluid).';
        rho_row = PropsSI('D', 'P', P, 'S', s_vec, fluid).';
    catch
        % Fallback keeps partially valid points as NaN.
        for j = 1:Ns
            sVal = s_vec(j);

            try
                H_row(j)   = PropsSI('H', 'P', P, 'S', sVal, fluid);
                T_row(j)   = PropsSI('T', 'P', P, 'S', sVal, fluid);
                rho_row(j) = PropsSI('D', 'P', P, 'S', sVal, fluid);
            catch
                % NaN kalacak
            end
        end
    end

    H_ps(i, :)   = H_row;
    T_ps(i, :)   = T_row;
    rho_ps(i, :) = rho_row;

    %send(dq,1); %waitbar sinyali
    send(dq, struct('grid',1,'i',i)); %grid 1 için
    

end


printElapsedTime('GRID_1 (P,s) finished', tStart);

%% ========================================================================
% GRID 2 : (P,h) INVERSION TABLE
% ========================================================================
fprintf('Generating GRID 2 (P,h) table...\n');
waitbar(progressCount/totalIterations,wb,'GRID 2 (P,h) generating...')

parfor i = 1:Np
    P = P_vec(i);

    T_row = nan(1, Nh);
    s_row = nan(1, Nh);

    % Fast path: evaluate the full enthalpy row in vector form.
    try
        T_row = PropsSI('T', 'P', P, 'H', h_vec, fluid).';
        s_row = PropsSI('S', 'P', P, 'H', h_vec, fluid).';
    catch
        % Fallback keeps partially valid points as NaN.
        for j = 1:Nh
            hVal = h_vec(j);

            try
                T_row(j) = PropsSI('T', 'P', P, 'H', hVal, fluid);
                s_row(j) = PropsSI('S', 'P', P, 'H', hVal, fluid);
            catch
                % NaN kalacak
            end
        end
    end

    T_ph(i, :) = T_row;
    s_ph(i, :) = s_row;

    %send(dq,1); %waitbar sinyali
    send(dq, struct('grid',2,'i',i)); %grid 2 için
end

printElapsedTime('GRID_2 (P,h) finished', tStart);

%% ========================================================================
% GRID 3 : SATURATION TABLE
% ========================================================================
fprintf('Generating GRID 3 Saturation Table...\n');
waitbar(progressCount/totalIterations,wb,'GRID 3 Saturation Table generating...')

% Not:
% Saturation çağrıları kritik basınç üzerindeki noktalarda başarısız olabilir.
% Bu nedenle try/catch ile NaN bırakıyoruz.
% P_sat_vec = linspace(Pmin, Pmax, Nsat);

Pcrit = PropsSI('PCRIT',fluid);
Pmax_sat = min(Pmax,0.99*Pcrit);
P_sat_vec = linspace(Pmin, Pmax_sat, Nsat);


hf    = nan(size(P_sat_vec));
hg    = nan(size(P_sat_vec));
sf    = nan(size(P_sat_vec));
sg    = nan(size(P_sat_vec));
Tf    = nan(size(P_sat_vec));
rho_f = nan(size(P_sat_vec));
rho_g = nan(size(P_sat_vec));

try
    hf    = PropsSI('H', 'P', P_sat_vec, 'Q', 0, fluid);
    hg    = PropsSI('H', 'P', P_sat_vec, 'Q', 1, fluid);
    sf    = PropsSI('S', 'P', P_sat_vec, 'Q', 0, fluid);
    sg    = PropsSI('S', 'P', P_sat_vec, 'Q', 1, fluid);
    Tf    = PropsSI('T', 'P', P_sat_vec, 'Q', 0, fluid);
    rho_f = PropsSI('D', 'P', P_sat_vec, 'Q', 0, fluid);
    rho_g = PropsSI('D', 'P', P_sat_vec, 'Q', 1, fluid);

    for i = 1:Nsat
        send(dq, struct('grid',3,'i',i));
    end
catch
    parfor i = 1:Nsat
        P = P_sat_vec(i);

        try
            hf(i)    = PropsSI('H', 'P', P, 'Q', 0, fluid);
            hg(i)    = PropsSI('H', 'P', P, 'Q', 1, fluid);
            sf(i)    = PropsSI('S', 'P', P, 'Q', 0, fluid);
            sg(i)    = PropsSI('S', 'P', P, 'Q', 1, fluid);
            Tf(i)    = PropsSI('T', 'P', P, 'Q', 0, fluid);
            rho_f(i) = PropsSI('D', 'P', P, 'Q', 0, fluid);
            rho_g(i) = PropsSI('D', 'P', P, 'Q', 1, fluid);
        catch
            % NaN kalacak
        end

        %send(dq,1); %waitbar sinyali
        send(dq, struct('grid',3,'i',i)); %grid 3
    end
end

printElapsedTime('GRID_3 Saturation Table finished', tStart);

%% ========================================================================
% GRID 4 : ISENTROPIC ENTHALPY TABLE
% ========================================================================
fprintf('Generating GRID 4 isentropic enthalpy grid...\n');

% GRID 4, GRID 1'de hesaplanan H_ps tablosunun transpozudur:
% H_ps(i,j) = h(P_vec(i), s_vec(j))
% h2s_grid(is,ip) = h(Pc_vec(ip), s_vec(is))
Pc_vec   = P_vec;
h2s_grid = H_ps.';

printElapsedTime('GRID_4 Isentropic Enthalpy Table finished', tStart);

%% ========================================================================
% CREATE DATABASE STRUCT
% ========================================================================
thermoDB = struct();

thermoDB.fluid = fluid;

% Saturation
thermoDB.sat.P     = P_sat_vec;
thermoDB.sat.hf    = hf;
thermoDB.sat.hg    = hg;
thermoDB.sat.sf    = sf;
thermoDB.sat.sg    = sg;
thermoDB.sat.T     = Tf;
thermoDB.sat.rho_f = rho_f;
thermoDB.sat.rho_g = rho_g;

% (P,s) grid
thermoDB.Ps.P   = P_vec;
thermoDB.Ps.s   = s_vec;
thermoDB.Ps.H   = H_ps;
thermoDB.Ps.T   = T_ps;
thermoDB.Ps.rho = rho_ps;

% (P,h) grid
thermoDB.Ph.P = P_vec;
thermoDB.Ph.h = h_vec;
thermoDB.Ph.T = T_ph;
thermoDB.Ph.s = s_ph;

% Isentropic
thermoDB.iso.P   = Pc_vec;
thermoDB.iso.s   = s_vec;
thermoDB.iso.h2s = h2s_grid;

%% ========================================================================
% SAVE DATABASE
% ========================================================================
filename = ['thermoDB_', fluid, '.mat'];
save(filename, 'thermoDB', '-v7.3');

fprintf('\nDatabase saved: %s\n', filename);

close(wb) %waitbar kapat


%% ========================================================================
% SIMULATION END INFO
% ========================================================================
endTime = datetime('now');
fprintf('Generation finished at: %s\n', datestr(endTime,'yyyy-mm-dd HH:MM:SS'));
printElapsedTime('Simulation duration', tStart);

%% ========================================================================
% LOCAL FUNCTION
% ========================================================================
function printElapsedTime(labelText, tStartHandle)
    elapsedSec = toc(tStartHandle);
    hh = floor(elapsedSec / 3600);
    mm = floor(mod(elapsedSec, 3600) / 60);
    ss = mod(elapsedSec, 60);
    fprintf('%s: %02d:%02d:%05.2f (hh:mm:ss)\n', labelText, hh, mm, ss);
end


function updateProgress(data,totalIterations,progressStart,wb,Np,Nsat)

    persistent progressCount

    if isempty(progressCount)
        progressCount = 0;
    end

    progressCount = progressCount + 1;

    % -------- GLOBAL --------
    global_frac = progressCount / totalIterations;

    % -------- LOCAL --------
    switch data.grid
        case 1
            local_frac = data.i / Np;
            gridName = 'GRID 1 (P,s)';
        case 2
            local_frac = data.i / Np;
            gridName = 'GRID 2 (P,h)';
        case 3
            local_frac = data.i / Nsat;
            gridName = 'GRID 3 (SAT)';
    end

    % -------- TIME --------
    elapsed = toc(progressStart);

    if progressCount > 0
        remaining = elapsed*(totalIterations/progressCount - 1);
    else
        remaining = NaN;
    end

    % format
    e_h = floor(elapsed/3600);
    e_m = floor(mod(elapsed,3600)/60);
    e_s = mod(elapsed,60);

    r_h = floor(remaining/3600);
    r_m = floor(mod(remaining,3600)/60);
    r_s = mod(remaining,60);

    % -------- MESSAGE --------
    msg = sprintf([ ...
        '%s\n', ...
        'Local Progress : %.1f %%\n', ...
        'Global Progress: %.1f %%\n', ...
        'Elapsed  : %02d:%02d:%04.1f\n', ...
        'Remaining: %02d:%02d:%04.1f'], ...
        gridName, ...
        local_frac*100, ...
        global_frac*100, ...
        e_h,e_m,e_s, ...
        r_h,r_m,r_s);

    waitbar(global_frac,wb,msg);
    drawnow

end
