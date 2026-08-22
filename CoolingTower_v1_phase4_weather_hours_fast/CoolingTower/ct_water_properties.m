function props = ct_water_properties(T_C,CTConfig)
% CT_WATER_PROPERTIES Return liquid-water properties from thermoDB_Water_V5.

if nargin < 2 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

T_K = T_C + 273.15;
P_Pa = localGetNested(CTConfig,'water','P_Pa',2e5);
backend = char(string(localGetNested(CTConfig,'water','property_backend','fluidgrid')));

if ~strcmpi(backend,'fluidgrid')
    props = struct();
    props.T_C = T_C;
    props.T_K = T_K;
    props.P_Pa = P_Pa;
    props.cp_JkgK = localGetNested(CTConfig,'water','cp_JkgK',4180);
    props.rho_kgm3 = localGetNested(CTConfig,'water','rho_kgm3',997);
    props.mu_Pas = localGetNested(CTConfig,'water','mu_Pas',NaN);
    props.k_WmK = localGetNested(CTConfig,'water','k_WmK',NaN);
    props.h_Jkg = NaN;
    props.source = 'CTConfig.water constants';
    return
end

db = localLoadWaterGrid(CTConfig);

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

function db = localLoadWaterGrid(CTConfig)
persistent cachedFile cachedDB

gridFile = localResolveGridFile(CTConfig);
if isempty(cachedDB) || ~strcmp(cachedFile,gridFile)
    if exist(gridFile,'file') ~= 2
        error('ct_water_properties:GridFileMissing', ...
            'Water grid file was not found: %s',gridFile);
    end
    S = load(gridFile,'thermoDB');
    if ~isfield(S,'thermoDB')
        error('ct_water_properties:MissingVariable', ...
            'Water grid file does not contain thermoDB: %s',gridFile);
    end
    dbTry = S.thermoDB;
    localValidateWaterGrid(dbTry,gridFile);
    cachedFile = gridFile;
    cachedDB = dbTry;
end
db = cachedDB;
end

function gridFile = localResolveGridFile(CTConfig)
ctDir = fileparts(mfilename('fullpath'));
gridFile = localGetNested(CTConfig,'water','gridFile','thermoDB_Water_V5.mat');
gridFile = char(string(gridFile));
if exist(gridFile,'file') ~= 2
    candidate = fullfile(ctDir,gridFile);
    if exist(candidate,'file') == 2
        gridFile = candidate;
    end
end
end

function localValidateWaterGrid(db,gridFile)
if ~isstruct(db) || ~isfield(db,'schema') || ~strcmp(char(string(db.schema)),'thermoDB_v5')
    error('ct_water_properties:Schema', ...
        'Water grid file is not thermoDB_v5: %s',gridFile);
end
if ~isfield(db,'fluid') || ~strcmpi(char(string(db.fluid)),'Water')
    error('ct_water_properties:FluidMismatch', ...
        'Water grid file fluid is not Water: %s',gridFile);
end
if ~isfield(db,'PT') || ~all(isfield(db.PT,{'P','T','H','rho','cp','mu','k'}))
    error('ct_water_properties:Schema', ...
        'Water grid file is missing required PT fields: %s',gridFile);
end
end

function value = localInterpPT(db,fieldName,P,T)
field = db.PT.(fieldName);
value = interpn(db.PT.P(:),db.PT.T(:),field,P,T,'linear',NaN);
if any(~isfinite(value(:)))
    error('ct_water_properties:OutOfRange', ...
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
