function humidAirDB = humid_air_grid_generator_V1(opts)
% HUMID_AIR_GRID_GENERATOR_V1 Build a humid-air lookup database for CT use.
%
% The database is generated with HAPropsSI once, then can be copied into the
% CoolingTower folder and used later without runtime CoolProp calls.
%
% Default use:
%   humid_air_grid_generator_V1
%
% Small test use:
%   opts = struct('N_Tdb',10,'N_Twb',10,'N_RH',9,'N_P',4,'N_Tsat',20, ...
%       'fileSuffix','SMALL');
%   humid_air_grid_generator_V1(opts)

if nargin < 1 || isempty(opts)
    opts = struct();
end

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
addpath(scriptDir);

opts = localDefaults(opts,scriptDir);

if exist('HAPropsSI','file') ~= 2
    error('humid_air_grid_generator_V1:HAPropsSIMissing', ...
        'HAPropsSI.m is not on the MATLAB path.');
end

tStart = tic;
fprintf('\nHumid-air DB generation started: %s\n',datestr(datetime('now')));

weatherSummary = localWeatherSummary(opts.weatherCacheFile,opts.epwFile);
opts = localApplyWeatherRanges(opts,weatherSummary);

Tdb_C = linspace(opts.Tdb_min_C,opts.Tdb_max_C,opts.N_Tdb);
Twb_C = linspace(opts.Twb_min_C,opts.Twb_max_C,opts.N_Twb);
RH = linspace(opts.RH_min,opts.RH_max,opts.N_RH);
P_Pa = linspace(opts.P_min_Pa,opts.P_max_Pa,opts.N_P);
Tsat_C = linspace(opts.Tsat_min_C,opts.Tsat_max_C,opts.N_Tsat);

fprintf('Tdb range  : %.3f to %.3f C (%d)\n',Tdb_C(1),Tdb_C(end),numel(Tdb_C));
fprintf('Twb range  : %.3f to %.3f C (%d)\n',Twb_C(1),Twb_C(end),numel(Twb_C));
fprintf('RH range   : %.3f to %.3f %% (%d)\n',100*RH(1),100*RH(end),numel(RH));
fprintf('P range    : %.3f to %.3f kPa (%d)\n',P_Pa(1)/1000,P_Pa(end)/1000,numel(P_Pa));
fprintf('Tsat range : %.3f to %.3f C (%d)\n',Tsat_C(1),Tsat_C(end),numel(Tsat_C));

dbrh = localBuildDbRh(Tdb_C,RH,P_Pa,opts);
sat = localBuildSat(Tsat_C,P_Pa,opts);
if opts.generateDbWb
    dbwb = localBuildDbWb(Tdb_C,Twb_C,P_Pa,opts);
else
    dbwb = localBlankDbWb(Tdb_C,Twb_C,P_Pa);
end

humidAirDB = struct();
humidAirDB.schema = 'humidAirDB_v1';
humidAirDB.fluid = 'HumidAir';
humidAirDB.meta = struct();
humidAirDB.meta.generator = 'humid_air_grid_generator_V1';
humidAirDB.meta.source = 'CoolProp HumidAirProp.HAPropsSI';
humidAirDB.meta.weatherCacheFile = opts.weatherCacheFile;
humidAirDB.meta.epwFile = opts.epwFile;
humidAirDB.meta.createdAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
humidAirDB.meta.weatherSummary = weatherSummary;
humidAirDB.ranges = opts;
humidAirDB.dbwb = dbwb;
humidAirDB.dbrh = dbrh;
humidAirDB.sat = sat;
humidAirDB.units = struct( ...
    'T','degC', ...
    'P','Pa', ...
    'RH','fraction', ...
    'omega','kg_water_per_kg_dry_air', ...
    'h','J_per_kg_dry_air', ...
    'v','m3_per_kg_dry_air', ...
    'rho_da','kg_dry_air_per_m3_moist_air', ...
    'rho_ma','kg_moist_air_per_m3_moist_air');

localPrintFiniteSummary(humidAirDB);

if opts.saveFile
    if ~exist(opts.outputDir,'dir')
        mkdir(opts.outputDir);
    end
    filename = fullfile(opts.outputDir,localOutputName(opts));
    save(filename,'humidAirDB','-v7.3');
    fprintf('Saved: %s\n',filename);
end

fprintf('Humid-air DB generation finished in %.2f s.\n',toc(tStart));

end

function opts = localDefaults(opts,scriptDir)
projectDir = fileparts(scriptDir);
opts = localSetDefault(opts,'epwFile',fullfile(scriptDir,'TUR_IC_Mersin.173400_TMYx.2009-2023.epw'));
opts = localSetDefault(opts,'weatherCacheFile',fullfile(scriptDir,'TUR_IC_Mersin.173400_TMYx.2009-2023_weather_cache.mat'));
opts = localSetDefault(opts,'outputDir',fullfile(projectDir,'CoolingTower'));
opts = localSetDefault(opts,'fileSuffix','V1');
opts = localSetDefault(opts,'saveFile',true);
opts = localSetDefault(opts,'useWeatherRanges',true);
opts = localSetDefault(opts,'weatherMargin_Tdb_C',5.0);
opts = localSetDefault(opts,'weatherMargin_Twb_C',3.0);
opts = localSetDefault(opts,'weatherMargin_RH_pct',5.0);
opts = localSetDefault(opts,'weatherMargin_P_Pa',1000.0);
opts = localSetDefault(opts,'Tdb_min_C',-5.0);
opts = localSetDefault(opts,'Tdb_max_C',45.0);
opts = localSetDefault(opts,'Twb_min_C',-5.0);
opts = localSetDefault(opts,'Twb_max_C',35.0);
opts = localSetDefault(opts,'RH_min',0.05);
opts = localSetDefault(opts,'RH_max',1.0);
opts = localSetDefault(opts,'P_min_Pa',98000.0);
opts = localSetDefault(opts,'P_max_Pa',104000.0);
opts = localSetDefault(opts,'Tsat_min_C',-10.0);
opts = localSetDefault(opts,'Tsat_max_C',95.0);
opts = localSetDefault(opts,'N_Tdb',81);
opts = localSetDefault(opts,'N_Twb',81);
opts = localSetDefault(opts,'N_RH',81);
opts = localSetDefault(opts,'N_P',21);
opts = localSetDefault(opts,'N_Tsat',221);
opts = localSetDefault(opts,'generateDbWb',false);
opts = localSetDefault(opts,'showProgress',true);
opts = localSetDefault(opts,'progressEvery',10);
end

function opts = localSetDefault(opts,fieldName,defaultValue)
if ~isfield(opts,fieldName) || isempty(opts.(fieldName))
    opts.(fieldName) = defaultValue;
end
end

function opts = localApplyWeatherRanges(opts,summary)
if ~opts.useWeatherRanges || isempty(summary)
    return
end
opts.Tdb_min_C = floor(summary.Tdb_min_C - opts.weatherMargin_Tdb_C);
opts.Tdb_max_C = ceil(summary.Tdb_max_C + opts.weatherMargin_Tdb_C);
opts.Twb_min_C = floor(summary.Twb_min_C - opts.weatherMargin_Twb_C);
opts.Twb_max_C = ceil(summary.Twb_max_C + opts.weatherMargin_Twb_C);
opts.RH_min = max(0.01,(summary.RH_min_pct - opts.weatherMargin_RH_pct)/100);
opts.RH_max = min(1.0,(summary.RH_max_pct + opts.weatherMargin_RH_pct)/100);
opts.P_min_Pa = floor(summary.P_min_Pa - opts.weatherMargin_P_Pa);
opts.P_max_Pa = ceil(summary.P_max_Pa + opts.weatherMargin_P_Pa);
opts.Tsat_min_C = min(opts.Tsat_min_C,floor(opts.Twb_min_C - 5));
opts.Tsat_max_C = max(opts.Tsat_max_C,95.0);
end

function summary = localWeatherSummary(cacheFile,epwFile)
summary = struct();
if isfile(cacheFile)
    S = load(cacheFile);
    if isfield(S,'weather')
        W = S.weather;
    elseif isfield(S,'WeatherData')
        W = S.WeatherData;
    else
        W = [];
    end
    if ~isempty(W)
        summary.Tdb_min_C = min(W.T_amb_C(:),[],'omitnan');
        summary.Tdb_max_C = max(W.T_amb_C(:),[],'omitnan');
        summary.Twb_min_C = min(W.T_wb_C(:),[],'omitnan');
        summary.Twb_max_C = max(W.T_wb_C(:),[],'omitnan');
        summary.RH_min_pct = min(W.RH_pct(:),[],'omitnan');
        summary.RH_max_pct = max(W.RH_pct(:),[],'omitnan');
        summary.P_min_Pa = min(W.Patm_Pa(:),[],'omitnan');
        summary.P_max_Pa = max(W.Patm_Pa(:),[],'omitnan');
        summary.nRows = numel(W.T_amb_C);
        summary.source = 'weather_cache';
        return
    end
end

if isfile(epwFile)
    [Tdb,RH,P] = localReadEpwRanges(epwFile);
    summary.Tdb_min_C = min(Tdb,[],'omitnan');
    summary.Tdb_max_C = max(Tdb,[],'omitnan');
    summary.RH_min_pct = min(RH,[],'omitnan');
    summary.RH_max_pct = max(RH,[],'omitnan');
    summary.Twb_min_C = wetbulb_stull(summary.Tdb_min_C,summary.RH_min_pct);
    summary.Twb_max_C = wetbulb_stull(summary.Tdb_max_C,summary.RH_max_pct);
    summary.P_min_Pa = min(P,[],'omitnan');
    summary.P_max_Pa = max(P,[],'omitnan');
    summary.nRows = numel(Tdb);
    summary.source = 'epw';
    return
end

summary = [];
end

function [Tdb,RH,P] = localReadEpwRanges(epwFile)
fid = fopen(epwFile,'r','n','UTF-8');
if fid == -1
    error('humid_air_grid_generator_V1:EpwOpen','Could not open EPW file.');
end
for i = 1:8
    fgetl(fid);
end
C = textscan(fid,'%f%f%f%f%f%s%f%f%f%f%*[^\n]', ...
    'Delimiter',',','ReturnOnError',false);
fclose(fid);
Tdb = C{7}(:);
RH = C{9}(:);
P = C{10}(:);
end

function dbwb = localBuildDbWb(Tdb_C,Twb_C,P_Pa,opts)
nT = numel(Tdb_C); nW = numel(Twb_C); nP = numel(P_Pa);
dbwb = struct();
dbwb.Tdb_C = Tdb_C;
dbwb.Twb_C = Twb_C;
dbwb.P_Pa = P_Pa;
dbwb.omega = nan(nT,nW,nP);
dbwb.h_Jkgda = nan(nT,nW,nP);
dbwb.RH = nan(nT,nW,nP);
dbwb.v_m3kgda = nan(nT,nW,nP);
dbwb.rho_da_kgm3 = nan(nT,nW,nP);
dbwb.rho_ma_kgm3 = nan(nT,nW,nP);

for ip = 1:nP
    P = P_Pa(ip);
    for it = 1:nT
        Tdb = Tdb_C(it);
        valid = Twb_C <= Tdb;
        if any(valid)
            W = localHA('W','T',Tdb+273.15,'P',P,'Twb',Twb_C(valid)+273.15);
            H = localHA('H','T',Tdb+273.15,'P',P,'Twb',Twb_C(valid)+273.15);
            R = localHA('R','T',Tdb+273.15,'P',P,'W',W);
            v = localMoistAirVolume(Tdb,W,P);
            dbwb.omega(it,valid,ip) = W;
            dbwb.h_Jkgda(it,valid,ip) = H;
            dbwb.RH(it,valid,ip) = R;
            dbwb.v_m3kgda(it,valid,ip) = v;
            dbwb.rho_da_kgm3(it,valid,ip) = 1./v;
            dbwb.rho_ma_kgm3(it,valid,ip) = (1+W)./v;
        end
    end
    localProgress(opts,'dbwb P slice',ip,nP);
end
end

function dbwb = localBlankDbWb(Tdb_C,Twb_C,P_Pa)
nT = numel(Tdb_C); nW = numel(Twb_C); nP = numel(P_Pa);
dbwb = struct();
dbwb.Tdb_C = Tdb_C;
dbwb.Twb_C = Twb_C;
dbwb.P_Pa = P_Pa;
dbwb.omega = nan(nT,nW,nP);
dbwb.h_Jkgda = nan(nT,nW,nP);
dbwb.RH = nan(nT,nW,nP);
dbwb.v_m3kgda = nan(nT,nW,nP);
dbwb.rho_da_kgm3 = nan(nT,nW,nP);
dbwb.rho_ma_kgm3 = nan(nT,nW,nP);
dbwb.note = 'Disabled by default; use Tdb-RH-P table for project weather.';
end

function dbrh = localBuildDbRh(Tdb_C,RH,P_Pa,opts)
nT = numel(Tdb_C); nR = numel(RH); nP = numel(P_Pa);
dbrh = struct();
dbrh.Tdb_C = Tdb_C;
dbrh.RH = RH;
dbrh.P_Pa = P_Pa;
dbrh.omega = nan(nT,nR,nP);
dbrh.h_Jkgda = nan(nT,nR,nP);
dbrh.Twb_C = nan(nT,nR,nP);
dbrh.v_m3kgda = nan(nT,nR,nP);
dbrh.rho_da_kgm3 = nan(nT,nR,nP);
dbrh.rho_ma_kgm3 = nan(nT,nR,nP);

for ip = 1:nP
    P = P_Pa(ip);
    for it = 1:nT
        Tdb = Tdb_C(it);
        W = localHA('W','T',Tdb+273.15,'P',P,'R',RH);
        H = localHA('H','T',Tdb+273.15,'P',P,'R',RH);
        Twb = localHA('Twb','T',Tdb+273.15,'P',P,'R',RH) - 273.15;
        v = localMoistAirVolume(Tdb,W,P);
        dbrh.omega(it,:,ip) = W;
        dbrh.h_Jkgda(it,:,ip) = H;
        dbrh.Twb_C(it,:,ip) = Twb;
        dbrh.v_m3kgda(it,:,ip) = v;
        dbrh.rho_da_kgm3(it,:,ip) = 1./v;
        dbrh.rho_ma_kgm3(it,:,ip) = (1+W)./v;
    end
    localProgress(opts,'dbrh P slice',ip,nP);
end
end

function sat = localBuildSat(Tsat_C,P_Pa,opts)
nT = numel(Tsat_C); nP = numel(P_Pa);
sat = struct();
sat.T_C = Tsat_C;
sat.P_Pa = P_Pa;
sat.omega_sat = nan(nT,nP);
sat.h_sat_Jkgda = nan(nT,nP);
sat.p_ws_Pa = nan(nT,nP);
sat.v_m3kgda = nan(nT,nP);
sat.rho_da_kgm3 = nan(nT,nP);
sat.rho_ma_kgm3 = nan(nT,nP);

for ip = 1:nP
    P = P_Pa(ip);
    W = localHA('W','T',Tsat_C+273.15,'P',P,'R',1.0);
    H = localHA('H','T',Tsat_C+273.15,'P',P,'R',1.0);
    v = localMoistAirVolume(Tsat_C,W,P);
    sat.omega_sat(:,ip) = W(:);
    sat.h_sat_Jkgda(:,ip) = H(:);
    sat.p_ws_Pa(:,ip) = W(:).*P./(0.62198+W(:));
    sat.v_m3kgda(:,ip) = v(:);
    sat.rho_da_kgm3(:,ip) = 1./v(:);
    sat.rho_ma_kgm3(:,ip) = (1+W(:))./v(:);
    localProgress(opts,'sat P slice',ip,nP);
end
end

function y = localHA(outKey,key1,val1,key2,val2,key3,val3)
persistent humidAirModule numpyModule
if isempty(humidAirModule)
    humidAirModule = py.importlib.import_module('CoolProp.HumidAirProp');
    numpyModule = py.importlib.import_module('numpy');
end

n = max([numel(val1),numel(val2),numel(val3)]);
val1 = localExpand(val1,n);
val2 = localExpand(val2,n);
val3 = localExpand(val3,n);

try
    result = humidAirModule.HAPropsSI(outKey, ...
        key1,numpyModule.array(val1), ...
        key2,numpyModule.array(val2), ...
        key3,numpyModule.array(val3));
    y = localPyNumericToVector(result);
    y = y(:).';
catch
    y = nan(1,n);
    for i = 1:n
        try
            result = humidAirModule.HAPropsSI(outKey,key1,val1(i),key2,val2(i),key3,val3(i));
            y(i) = double(result);
        catch
            y(i) = NaN;
        end
    end
end
end

function x = localExpand(x,n)
if isscalar(x)
    x = repmat(double(x),1,n);
else
    x = double(x(:)).';
end
end

function values = localPyNumericToVector(pyValue)
if isnumeric(pyValue)
    values = double(pyValue);
    return
end
if isa(pyValue,'py.numpy.ndarray')
    pyValue = pyValue.ravel().tolist();
end
if isa(pyValue,'py.list') || isa(pyValue,'py.tuple')
    c = cell(pyValue);
    values = [];
    for k = 1:numel(c)
        values = [values localPyNumericToVector(c{k})]; %#ok<AGROW>
    end
else
    values = double(pyValue);
end
end

function v = localMoistAirVolume(T_C,omega,P)
R_da = 287.055;
v = R_da.*(T_C(:).'+273.15)./P.*(1+1.607858.*omega);
end

function localProgress(opts,labelText,i,n)
if ~opts.showProgress
    return
end
if i == 1 || i == n || mod(i,opts.progressEvery) == 0
    fprintf('%s: %d/%d (%.1f%%)\n',labelText,i,n,100*i/n);
end
end

function name = localOutputName(opts)
suffix = char(string(opts.fileSuffix));
if isempty(suffix)
    name = 'humidAirDB_Mersin.mat';
else
    name = sprintf('humidAirDB_Mersin_%s.mat',suffix);
end
end

function localPrintFiniteSummary(db)
fprintf('\nFinite-value summary:\n');
localPrintBlock('dbwb',db.dbwb);
localPrintBlock('dbrh',db.dbrh);
localPrintBlock('sat',db.sat);
end

function localPrintBlock(prefix,st)
fields = fieldnames(st);
for i = 1:numel(fields)
    val = st.(fields{i});
    if isnumeric(val) && numel(val) > 1
        fprintf('  %-6s %-14s %.4f\n',prefix,fields{i},nnz(isfinite(val))/numel(val));
    end
end
end

function Twb_C = wetbulb_stull(T_C,RH_pct)
RH = RH_pct;
Twb_C = T_C.*atan(0.151977.*sqrt(RH+8.313659)) + atan(T_C+RH) ...
    - atan(RH-1.676331) + 0.00391838.*(RH.^(3/2)).*atan(0.023101.*RH) - 4.686035;
end
