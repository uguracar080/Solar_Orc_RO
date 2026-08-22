function props = preheater_water_properties_v1(T_C,PHConfig)
% PREHEATER_WATER_PROPERTIES_V1 Return loop-water properties from V5 grid.

if nargin < 2 || isempty(PHConfig)
    PHConfig = struct();
end

T_K = T_C + 273.15;
P_Pa = localGetNested(PHConfig,'hot','P_Pa',2e5);
db = localLoadWaterGrid(PHConfig);

props = struct();
props.T_C = T_C;
props.T_K = T_K;
props.P_Pa = P_Pa;
props.cp_JkgK = localInterpPT(db,'cp',P_Pa,T_K);
props.rho_kgm3 = localInterpPT(db,'rho',P_Pa,T_K);
props.mu_Pas = localInterpPT(db,'mu',P_Pa,T_K);
props.k_WmK = localInterpPT(db,'k',P_Pa,T_K);
props.h_Jkg = localInterpPT(db,'H',P_Pa,T_K);
props.source = 'thermoDB_Water_V5';
end

function db = localLoadWaterGrid(PHConfig)
persistent cachedFile cachedDB

gridFile = localResolveGridFile(PHConfig);
if isempty(cachedDB) || ~strcmp(cachedFile,gridFile)
    if exist(gridFile,'file') ~= 2
        error('preheater_water_properties_v1:GridFileMissing', ...
            'Water grid file was not found: %s',gridFile);
    end
    S = load(gridFile,'thermoDB');
    if ~isfield(S,'thermoDB')
        error('preheater_water_properties_v1:MissingVariable', ...
            'Water grid file does not contain thermoDB: %s',gridFile);
    end
    dbTry = S.thermoDB;
    localValidateWaterGrid(dbTry,gridFile);
    cachedFile = gridFile;
    cachedDB = dbTry;
end
db = cachedDB;
end

function gridFile = localResolveGridFile(PHConfig)
hxDir = fileparts(mfilename('fullpath'));
gridFile = localGetNested(PHConfig,'hot','gridFile','thermoDB_Water_V5.mat');
gridFile = char(string(gridFile));
if exist(gridFile,'file') ~= 2
    candidate = fullfile(hxDir,gridFile);
    if exist(candidate,'file') == 2
        gridFile = candidate;
    end
end
end

function localValidateWaterGrid(db,gridFile)
if ~isstruct(db) || ~isfield(db,'schema') || ~strcmp(char(string(db.schema)),'thermoDB_v5')
    error('preheater_water_properties_v1:Schema', ...
        'Water grid file is not thermoDB_v5: %s',gridFile);
end
if ~isfield(db,'fluid') || ~strcmpi(char(string(db.fluid)),'Water')
    error('preheater_water_properties_v1:FluidMismatch', ...
        'Water grid file fluid is not Water: %s',gridFile);
end
if ~isfield(db,'PT') || ~all(isfield(db.PT,{'P','T','H','rho','cp','mu','k'}))
    error('preheater_water_properties_v1:Schema', ...
        'Water grid file is missing required PT fields: %s',gridFile);
end
end

function value = localInterpPT(db,fieldName,P,T)
field = db.PT.(fieldName);
value = interpn(db.PT.P(:),db.PT.T(:),field,P,T,'linear',NaN);
if any(~isfinite(value(:)))
    error('preheater_water_properties_v1:OutOfRange', ...
        'Water grid interpolation failed for P=%.6g Pa, T=%.6g K.',P,T);
end
end

function value = localGetNested(S,block,fieldName,defaultValue)
if isfield(S,block) && isstruct(S.(block)) && ...
        isfield(S.(block),fieldName) && ~isempty(S.(block).(fieldName))
    value = S.(block).(fieldName);
else
    value = defaultValue;
end
end
