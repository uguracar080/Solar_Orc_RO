function orcValue = orc_properties(config,varargin)
% ORC_PROPERTIES Central property interface for all ORC working-fluid files.
%
% CoolProp usage mirrors PropsSI:
%   h  = orc_properties(config,'H','P',P,'Q',0,fluid);
%   Pc = orc_properties(config,'PCRIT',fluid);
%
% R1233zd(E) thermal conductivity is supplied by the NIST correlation when
% CoolProp has no conductivity model for the installed fluid backend.

% =========================================================================
% INPUT CHECK
% =========================================================================
if nargin < 2
    error('orc_properties:NotEnoughInputs','Property request is missing.');
end

if ~isfield(config,'orc_property_backend')
    config = orc_default_config(config);
else
    config = orc_default_config(config);
end

% =========================================================================
% PROPERTY CACHE AND DIAGNOSTIC COMMANDS
% =========================================================================
persistent orcPropertyCache orcPropertyStats
if isempty(orcPropertyCache)
    orcPropertyCache = containers.Map('KeyType','char','ValueType','any');
end
if isempty(orcPropertyStats)
    orcPropertyStats = localBlankCacheStats();
end

% Utility commands used by quickstart/test suites.  They are intentionally
% handled here so the cache remains private to this property interface.
if numel(varargin) >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
    orcCacheCommand = upper(string(varargin{1}));       % [-]
    if orcCacheCommand == "CACHESTATS"
        orcValue = localGetCacheStats(orcPropertyCache,orcPropertyStats); % [-]
        return
    elseif orcCacheCommand == "CACHERESET"
        orcPropertyCache = containers.Map('KeyType','char','ValueType','any');
        orcPropertyStats = localBlankCacheStats();
        orcValue = true;                               % reset acknowledged [-]
        return
    end
end

orcUseCache = isfield(config,'orc_property_cache_enabled') && ...
    logical(config.orc_property_cache_enabled);        % [-]
orcUseStats = isfield(config,'orc_property_cache_stats_enabled') && ...
    logical(config.orc_property_cache_stats_enabled);  % [-]
orcCacheKey = '';                                      % [-]

if orcUseStats
    orcPropertyStats.nRequests = orcPropertyStats.nRequests + 1; % [-]
end

if orcUseCache
    orcCacheKey = localBuildCacheKey(config,varargin{:}); % [-]
    if isKey(orcPropertyCache,orcCacheKey)
        if orcUseStats
            orcPropertyStats.nHits = orcPropertyStats.nHits + 1; % [-]
        end
        orcValue = orcPropertyCache(orcCacheKey);      % cached value [-]
        return
    else
        if orcUseStats
            orcPropertyStats.nMisses = orcPropertyStats.nMisses + 1; % [-]
        end
    end
else
    if orcUseStats
        orcPropertyStats.nBypass = orcPropertyStats.nBypass + 1; % [-]
    end
end

% =========================================================================
% PROPERTY BACKEND
% =========================================================================
orcBackend = lower(string(config.orc_property_backend));

switch orcBackend
    case "coolprop"
        orcValue = localCoolPropProperty(config,varargin{:});

    case "fluidgrid"
        if isfield(config,'orc_useFluidGrid') && ~logical(config.orc_useFluidGrid)
            orcValue = localCoolPropProperty(config,varargin{:});
        elseif localIsFluidGridRequest(varargin{:})
            orcValue = localFluidGridProperty(config,varargin{:});
        else
            orcValue = localCoolPropProperty(config,varargin{:});
        end

    otherwise
        error('orc_properties:UnknownBackend', ...
            'Unknown ORC property backend: %s',char(orcBackend));
end

% =========================================================================
% OUTPUT CHECK
% =========================================================================
if isnumeric(orcValue) && any(~isfinite(orcValue(:)))
    error('orc_properties:NonFiniteProperty', ...
        'The property backend returned a non-finite value.');
end

% =========================================================================
% CACHE STORE
% =========================================================================
if orcUseCache
    if isfield(config,'orc_property_cache_maxEntries') && ...
            orcPropertyCache.Count > config.orc_property_cache_maxEntries
        orcPropertyCache = containers.Map('KeyType','char','ValueType','any');
        if orcUseStats
            orcPropertyStats.nResets = orcPropertyStats.nResets + 1; % [-]
        end
    end
    orcPropertyCache(orcCacheKey) = orcValue;          % store value [-]
    if orcUseStats
        orcPropertyStats.nStores = orcPropertyStats.nStores + 1; % [-]
    end
end

end

% =========================================================================
% LOCAL HELPER: CACHE KEY
% =========================================================================
function key = localBuildCacheKey(config,varargin)
% Build a compact cache key from a PropsSI-style request.
backend = 'backend=';
gridFile = 'grid=';
useGrid = 'useGrid=';
if isfield(config,'orc_property_backend')
    backend = ['backend=' char(string(config.orc_property_backend))];
end
if isfield(config,'orc_useFluidGrid')
    useGrid = ['useGrid=' char(string(logical(config.orc_useFluidGrid)))];
end
if isfield(config,'orc_fluidGridFile') && ~isempty(config.orc_fluidGridFile)
    gridFile = ['grid=' char(string(config.orc_fluidGridFile))];
end
waterGridFile = 'waterGrid=';
if isfield(config,'orc_waterFluidGridFile') && ~isempty(config.orc_waterFluidGridFile)
    waterGridFile = ['waterGrid=' char(string(config.orc_waterFluidGridFile))];
end
parts = cell(1,numel(varargin) + 4);
parts{1} = backend;
parts{2} = useGrid;
parts{3} = gridFile;
parts{4} = waterGridFile;
for i = 1:numel(varargin)
    v = varargin{i};
    if isnumeric(v)
        parts{i + 4} = sprintf('%.12g,',v(:));         % numeric key [-]
    elseif isstring(v) || ischar(v)
        parts{i + 4} = char(v);                        % text key [-]
    else
        parts{i + 4} = class(v);                       % fallback key [-]
    end
end
key = strjoin(parts,'|');                              % [-]
end

% =========================================================================
% LOCAL HELPER: CACHE STATS
% =========================================================================
function st = localBlankCacheStats()
% Initialize property-cache diagnostic counters.
st = struct();
st.nRequests = 0;                                      % property requests [-]
st.nHits = 0;                                          % cache hits [-]
st.nMisses = 0;                                        % cache misses [-]
st.nStores = 0;                                        % stored values [-]
st.nBypass = 0;                                        % uncached requests [-]
st.nResets = 0;                                        % automatic cache clears [-]
end

function st = localGetCacheStats(cache,rawStats)
% Return counters plus derived cache metrics.
st = rawStats;                                        % copy counters [-]
st.nEntries = cache.Count;                            % current cache entries [-]
if st.nRequests > 0
    st.hitRate = st.nHits/st.nRequests;                % [-]
else
    st.hitRate = NaN;                                  % [-]
end
if (st.nHits + st.nMisses) > 0
    st.activeHitRate = st.nHits/(st.nHits + st.nMisses); % cache-only hit rate [-]
else
    st.activeHitRate = NaN;                            % [-]
end
end

% =========================================================================
% LOCAL HELPER: COOLPROP BACKEND
% =========================================================================
function orcValue = localCoolPropProperty(config,varargin)
% Evaluate a PropsSI-style request with the legacy CoolProp backend.
if exist('PropsSI','file') ~= 2
    error('orc_properties:PropsSIMissing', ...
        ['PropsSI.m is not on the MATLAB path. Add the supplied ', ...
         'PropsSI wrapper and configure Python CoolProp first.']);
end

% Use source-based k model before CoolProp for R1233zd(E). [W/m/K]
if localIsR1233zdEConductivityRequest(config,varargin{:})
    orcValue = localR1233zdEConductivityFromState(config,varargin{:});
else
    try
        orcValue = PropsSI(varargin{:});
    catch orcME
        if localCanFallbackToR1233zdEConductivity(config,varargin{:})
            orcValue = localR1233zdEConductivityFromState(config,varargin{:});
        else
            rethrow(orcME);
        end
    end
end
end

% =========================================================================
% LOCAL HELPER: FLUID-GRID REQUEST TYPE
% =========================================================================
function tf = localIsFluidGridRequest(varargin)
% Route supported pure fluids to colocated V5 thermoDB files.
tf = false;
if numel(varargin) < 2
    return
end
orcFluid = varargin{end};
if ischar(orcFluid) || isstring(orcFluid)
    tf = localIsR1233zdEFluid(orcFluid) || localIsWaterFluid(orcFluid);
end
end

% =========================================================================
% LOCAL HELPER: FLUID-GRID BACKEND
% =========================================================================
function orcValue = localFluidGridProperty(config,varargin)
% Evaluate supported PropsSI-style pure-fluid requests from thermoDB_v5.
if numel(varargin) ~= 2 && numel(varargin) ~= 6
    error('orc_properties:FluidGridInputCount', ...
        'Fluid-grid backend supports only 2- and 6-input PropsSI-style requests.');
end

orcFluid = varargin{end};
db = localLoadFluidGrid(config,orcFluid);
outKey = localCanonicalPropertyKey(varargin{1});

if numel(varargin) == 2
    orcValue = localFluidGridMeta(db,outKey);
    return
end

key1 = localCanonicalStateKey(varargin{2});
val1 = varargin{3};
key2 = localCanonicalStateKey(varargin{4});
val2 = varargin{5};

if key1 == "P"
    P = val1;
    stateKey = key2;
    stateVal = val2;
elseif key2 == "P"
    P = val2;
    stateKey = key1;
    stateVal = val1;
else
    error('orc_properties:FluidGridStatePair', ...
        'Fluid-grid backend requires pressure as one state input.');
end

switch stateKey
    case "Q"
        orcValue = localFluidGridSat(db,outKey,P,stateVal);
    case "H"
        orcValue = localFluidGridPH(db,outKey,P,stateVal);
    case "S"
        orcValue = localFluidGridPS(db,outKey,P,stateVal);
    case "T"
        orcValue = localFluidGridPT(db,outKey,P,stateVal);
    otherwise
        error('orc_properties:FluidGridStatePair', ...
            'Unsupported fluid-grid state pair: P,%s',char(stateKey));
end
end

function db = localLoadFluidGrid(config,orcFluid)
% Load and validate thermoDB_v5 once per file path.
persistent cachedDBByFile

if isempty(cachedDBByFile)
    cachedDBByFile = containers.Map('KeyType','char','ValueType','any');
end

gridFile = localResolveFluidGridFile(config,orcFluid);
gridKey = char(java.io.File(gridFile).getCanonicalPath());
if ~isKey(cachedDBByFile,gridKey)
    if exist(gridFile,'file') ~= 2
        error('orc_properties:FluidGridFileMissing', ...
            'Fluid-grid file was not found: %s',gridFile);
    end
    S = load(gridFile,'thermoDB');
    if ~isfield(S,'thermoDB')
        error('orc_properties:FluidGridMissingVariable', ...
            'Fluid-grid file does not contain variable thermoDB: %s',gridFile);
    end
    dbTry = S.thermoDB;
    localValidateFluidGrid(dbTry,orcFluid,gridFile);
    cachedDBByFile(gridKey) = dbTry;
end
db = cachedDBByFile(gridKey);
end

function gridFile = localResolveFluidGridFile(config,orcFluid)
% Resolve explicit or colocated thermoDB file paths.
orcDir = fileparts(mfilename('fullpath'));
if localIsWaterFluid(orcFluid) && isfield(config,'orc_waterFluidGridFile') && ...
        ~isempty(config.orc_waterFluidGridFile)
    gridFile = char(string(config.orc_waterFluidGridFile));
elseif ~localIsWaterFluid(orcFluid) && isfield(config,'orc_fluidGridFile') && ...
        ~isempty(config.orc_fluidGridFile)
    gridFile = char(string(config.orc_fluidGridFile));
else
    gridFile = fullfile(orcDir,sprintf('thermoDB_%s_V5.mat',char(strtrim(string(orcFluid)))));
end
if exist(gridFile,'file') ~= 2
    candidate = fullfile(orcDir,gridFile);
    if exist(candidate,'file') == 2
        gridFile = candidate;
    end
end
end

function localValidateFluidGrid(db,orcFluid,gridFile)
% Confirm the loaded file has the expected V5 schema and fluid identity.
if ~isstruct(db) || ~isfield(db,'schema') || ~strcmp(char(string(db.schema)),'thermoDB_v5')
    error('orc_properties:FluidGridSchema', ...
        'Fluid-grid file is not thermoDB_v5: %s',gridFile);
end
if ~isfield(db,'fluid') || ~localSameFluidName(db.fluid,orcFluid)
    error('orc_properties:FluidGridFluidMismatch', ...
        'Fluid-grid file fluid "%s" does not match requested fluid "%s".', ...
        char(string(db.fluid)),char(string(orcFluid)));
end
requiredBlocks = {'meta','sat','Ps','Ph','PT'};
for i = 1:numel(requiredBlocks)
    if ~isfield(db,requiredBlocks{i})
        error('orc_properties:FluidGridSchema', ...
            'Fluid-grid file is missing thermoDB.%s.',requiredBlocks{i});
    end
end
end

function tf = localSameFluidName(a,b)
% Compare fluid names with punctuation/case ignored.
ac = lower(regexprep(char(string(a)),'[^a-zA-Z0-9]',''));
bc = lower(regexprep(char(string(b)),'[^a-zA-Z0-9]',''));
tf = strcmp(ac,bc);
end

function key = localCanonicalPropertyKey(rawKey)
% Normalize common CoolProp output aliases used by ORC_v23.
k = upper(string(rawKey));
switch k
    case {"H","HMASS","ENTHALPY"}
        key = "H";
    case {"S","SMASS","ENTROPY"}
        key = "S";
    case {"T","TEMPERATURE"}
        key = "T";
    case {"D","DMASS","RHO","DENSITY"}
        key = "D";
    case {"C","CPMASS","CP","CP0MASS"}
        key = "C";
    case {"V","VISCOSITY","MU"}
        key = "V";
    case {"L","CONDUCTIVITY","THERMAL_CONDUCTIVITY"}
        key = "L";
    case {"Q","QUALITY"}
        key = "Q";
    case {"P","PRESSURE"}
        key = "P";
    case {"PCRIT","PCRITICAL","P_CRITICAL"}
        key = "PCRIT";
    case {"TCRIT","TCRITICAL","T_CRITICAL"}
        key = "TCRIT";
    case {"TMIN","T_MIN"}
        key = "TMIN";
    case {"TMAX","T_MAX"}
        key = "TMAX";
    case {"RHOCRIT","DCRIT","RHO_CRITICAL","RHOMASS_CRITICAL"}
        key = "RHOCRIT";
    otherwise
        key = k;
end
end

function key = localCanonicalStateKey(rawKey)
% Normalize state-input aliases used by PropsSI-style calls.
k = upper(string(rawKey));
switch k
    case {"P","PRESSURE"}
        key = "P";
    case {"H","HMASS","ENTHALPY"}
        key = "H";
    case {"S","SMASS","ENTROPY"}
        key = "S";
    case {"T","TEMPERATURE"}
        key = "T";
    case {"Q","QUALITY"}
        key = "Q";
    case {"D","DMASS","RHO","DENSITY"}
        key = "D";
    otherwise
        key = k;
end
end

function value = localFluidGridMeta(db,outKey)
% Return trivial properties from thermoDB metadata.
switch outKey
    case "PCRIT"
        value = db.meta.Pcrit;
    case "TCRIT"
        value = db.meta.Tcrit;
    case "TMIN"
        value = db.meta.Tmin;
    case "TMAX"
        value = db.meta.Tmax;
    case "RHOCRIT"
        value = db.meta.rhocrit;
    otherwise
        error('orc_properties:FluidGridMeta', ...
            'Unsupported fluid-grid metadata property: %s',char(outKey));
end
end

function value = localFluidGridSat(db,outKey,P,Q)
% Return saturation properties from the pressure-indexed table.
[P,Q] = localMatchQuerySize(P,Q);
switch outKey
    case "Q"
        value = Q;
    case "T"
        value = localInterpSat(db.sat.P,db.sat.T,P,outKey);
    case "H"
        hf = localInterpSat(db.sat.P,db.sat.hf,P,outKey);
        hg = localInterpSat(db.sat.P,db.sat.hg,P,outKey);
        value = hf + Q.*(hg - hf);
    case "S"
        sf = localInterpSat(db.sat.P,db.sat.sf,P,outKey);
        sg = localInterpSat(db.sat.P,db.sat.sg,P,outKey);
        value = sf + Q.*(sg - sf);
    case "D"
        rho_f = localInterpSat(db.sat.P,db.sat.rho_f,P,outKey);
        rho_g = localInterpSat(db.sat.P,db.sat.rho_g,P,outKey);
        value = 1./((1 - Q)./rho_f + Q./rho_g);
    case "C"
        value = localEndpointSatTransport(db.sat.P,db.sat.cp_f,db.sat.cp_g,P,Q,outKey);
    case "V"
        value = localEndpointSatTransport(db.sat.P,db.sat.mu_f,db.sat.mu_g,P,Q,outKey);
    case "L"
        value = localEndpointSatTransport(db.sat.P,db.sat.k_f,db.sat.k_g,P,Q,outKey);
    case "P"
        value = P;
    otherwise
        error('orc_properties:FluidGridSaturation', ...
            'Unsupported saturation output property: %s',char(outKey));
end
end

function value = localFluidGridPH(db,outKey,P,h)
% Return properties from the (P,h) table.
switch outKey
    case "P"
        value = P;
    case "H"
        value = h;
    case "T"
        value = localInterpGrid(db.Ph.P,db.Ph.h,db.Ph.T,P,h,outKey);
    case "S"
        value = localInterpGrid(db.Ph.P,db.Ph.h,db.Ph.s,P,h,outKey);
    case "D"
        value = localInterpGrid(db.Ph.P,db.Ph.h,db.Ph.rho,P,h,outKey);
    case "C"
        value = localInterpGrid(db.Ph.P,db.Ph.h,db.Ph.cp,P,h,outKey);
    case "V"
        value = localInterpGrid(db.Ph.P,db.Ph.h,db.Ph.mu,P,h,outKey);
    case "L"
        value = localInterpGrid(db.Ph.P,db.Ph.h,db.Ph.k,P,h,outKey);
    case "Q"
        value = localInterpGridAllowNaN(db.Ph.P,db.Ph.h,db.Ph.Q,P,h);
    otherwise
        error('orc_properties:FluidGridPH', ...
            'Unsupported P,H output property: %s',char(outKey));
end
end

function value = localFluidGridPS(db,outKey,P,s)
% Return properties from the (P,s) table.
switch outKey
    case "P"
        value = P;
    case "S"
        value = s;
    case "H"
        value = localInterpGrid(db.Ps.P,db.Ps.s,db.Ps.H,P,s,outKey);
    case "T"
        value = localInterpGrid(db.Ps.P,db.Ps.s,db.Ps.T,P,s,outKey);
    case "D"
        value = localInterpGrid(db.Ps.P,db.Ps.s,db.Ps.rho,P,s,outKey);
    case "C"
        value = localInterpGrid(db.Ps.P,db.Ps.s,db.Ps.cp,P,s,outKey);
    case "V"
        value = localInterpGrid(db.Ps.P,db.Ps.s,db.Ps.mu,P,s,outKey);
    case "L"
        value = localInterpGrid(db.Ps.P,db.Ps.s,db.Ps.k,P,s,outKey);
    case "Q"
        value = localInterpGridAllowNaN(db.Ps.P,db.Ps.s,db.Ps.Q,P,s);
    otherwise
        error('orc_properties:FluidGridPS', ...
            'Unsupported P,S output property: %s',char(outKey));
end
end

function value = localFluidGridPT(db,outKey,P,T)
% Return properties from the (P,T) table.
switch outKey
    case "P"
        value = P;
    case "T"
        value = T;
    case "H"
        value = localInterpGrid(db.PT.P,db.PT.T,db.PT.H,P,T,outKey);
    case "S"
        value = localInterpGrid(db.PT.P,db.PT.T,db.PT.s,P,T,outKey);
    case "D"
        value = localInterpGrid(db.PT.P,db.PT.T,db.PT.rho,P,T,outKey);
    case "C"
        value = localInterpGrid(db.PT.P,db.PT.T,db.PT.cp,P,T,outKey);
    case "V"
        value = localInterpGrid(db.PT.P,db.PT.T,db.PT.mu,P,T,outKey);
    case "L"
        value = localInterpGrid(db.PT.P,db.PT.T,db.PT.k,P,T,outKey);
    case "Q"
        value = localInterpGridAllowNaN(db.PT.P,db.PT.T,db.PT.Q,P,T);
    otherwise
        error('orc_properties:FluidGridPT', ...
            'Unsupported P,T output property: %s',char(outKey));
end
end

function value = localInterpSat(axis,field,P,outKey)
% Interpolate a saturation-table field without extrapolation.
value = interp1(axis(:),field(:),P,'linear',NaN);
localAssertFiniteGridValue(value,outKey);
end

function value = localEndpointSatTransport(Paxis,fieldF,fieldG,P,Q,outKey)
% Transport properties are used only at saturated endpoints in ORC_v23.
tol = 1e-10;
if any(Q(:) > tol & Q(:) < 1 - tol)
    error('orc_properties:FluidGridTwoPhaseTransport', ...
        'P,Q transport requests require Q=0 or Q=1 for fluid-grid backend.');
end
vf = localInterpSat(Paxis,fieldF,P,outKey);
vg = localInterpSat(Paxis,fieldG,P,outKey);
value = vf;
maskG = Q >= 0.5;
value(maskG) = vg(maskG);
end

function value = localInterpGrid(Paxis,Xaxis,field,P,X,outKey)
% Interpolate a V5 2-D property field without extrapolation.
value = localInterpGridAllowNaN(Paxis,Xaxis,field,P,X);
localAssertFiniteGridValue(value,outKey);
end

function value = localInterpGridAllowNaN(Paxis,Xaxis,field,P,X)
% Interpolate a V5 2-D property field; Q maps may return NaN for single phase.
value = interpn(Paxis(:),Xaxis(:),field,P,X,'linear',NaN);
end

function localAssertFiniteGridValue(value,outKey)
% Fail fast on out-of-range or empty grid cells.
if isnumeric(value) && any(~isfinite(value(:)))
    error('orc_properties:FluidGridNonFinite', ...
        'Fluid-grid interpolation returned non-finite value for %s.',char(outKey));
end
end

function [a,b] = localMatchQuerySize(a,b)
% Expand scalar/vector query inputs to compatible elementwise arrays.
if isscalar(a) && ~isscalar(b)
    a = a + zeros(size(b));
elseif isscalar(b) && ~isscalar(a)
    b = b + zeros(size(a));
elseif ~isequal(size(a),size(b))
    error('orc_properties:FluidGridQuerySize', ...
        'Fluid-grid query inputs must be scalar or the same size.');
end
end

% =========================================================================
% LOCAL HELPER: REQUEST TYPE
% =========================================================================
function tf = localIsR1233zdEConductivityRequest(config,varargin)
% Return true when NIST R1233zd(E) conductivity should be used.
tf = false;
if nargin < 2 || numel(varargin) < 2
    return
end
if ~isfield(config,'orc_r1233zde_k_useNist') || ~config.orc_r1233zde_k_useNist
    return
end
orcOutKey = upper(string(varargin{1}));
orcFluid = varargin{end};
if localIsConductivityKey(orcOutKey) && localIsR1233zdEFluid(orcFluid)
    tf = true;
end
end

% =========================================================================
% LOCAL HELPER: FALLBACK TYPE
% =========================================================================
function tf = localCanFallbackToR1233zdEConductivity(config,varargin)
% Return true when a failed CoolProp call can be replaced by NIST k.
tf = localIsR1233zdEConductivityRequest(config,varargin{:});
end

% =========================================================================
% LOCAL HELPER: CONDUCTIVITY KEY
% =========================================================================
function tf = localIsConductivityKey(orcOutKey)
% CoolProp commonly uses 'L' for thermal conductivity.
orcKey = upper(string(orcOutKey));
tf = any(orcKey == ["L","CONDUCTIVITY","THERMAL_CONDUCTIVITY"]);
end

% =========================================================================
% LOCAL HELPER: FLUID NAME
% =========================================================================
function tf = localIsR1233zdEFluid(orcFluid)
% Accept common R1233zd(E) string variants.
orcFluidClean = lower(regexprep(char(orcFluid),'[^a-zA-Z0-9]',''));
tf = contains(orcFluidClean,'r1233zde');
end

function tf = localIsWaterFluid(orcFluid)
% Accept common pure-water identifiers.
orcFluidClean = lower(regexprep(char(orcFluid),'[^a-zA-Z0-9]',''));
tf = any(strcmp(orcFluidClean,{'water','h2o'}));
end

% =========================================================================
% LOCAL HELPER: NIST CONDUCTIVITY FROM PROPSI-STYLE STATE
% =========================================================================
function orcK = localR1233zdEConductivityFromState(config,varargin)
% Convert a PropsSI-style state request to T and rho, then evaluate k.

orcFluid = varargin{end};
orcN = numel(varargin);

if orcN < 6
    error('orc_properties:R1233zdEStateMissing', ...
        'R1233zd(E) conductivity requires two independent state inputs.');
end

orcKey1 = upper(string(varargin{2}));
orcVal1 = varargin{3};
orcKey2 = upper(string(varargin{4}));
orcVal2 = varargin{5};

% -------------------------------------------------------------------------
% Direct state if already available.
% -------------------------------------------------------------------------
orcHasT = false;
orcHasD = false;

if orcKey1 == "T"
    orcT = orcVal1;                                  % [K]
    orcHasT = true;
elseif any(orcKey1 == ["D","DMASS"])
    orcRho = orcVal1;                                % [kg/m3]
    orcHasD = true;
end

if orcKey2 == "T"
    orcT = orcVal2;                                  % [K]
    orcHasT = true;
elseif any(orcKey2 == ["D","DMASS"])
    orcRho = orcVal2;                                % [kg/m3]
    orcHasD = true;
end

% -------------------------------------------------------------------------
% Ask CoolProp only for thermodynamic T/rho, not conductivity.
% -------------------------------------------------------------------------
if ~orcHasT
    orcT = orc_properties(config,'T',char(orcKey1),orcVal1,char(orcKey2),orcVal2,orcFluid); % [K]
end
if ~orcHasD
    orcRho = orc_properties(config,'D',char(orcKey1),orcVal1,char(orcKey2),orcVal2,orcFluid); % [kg/m3]
end

% -------------------------------------------------------------------------
% Evaluate the source-based thermal conductivity.
% -------------------------------------------------------------------------
orcK = orc_r1233zde_thermal_conductivity(config,orcT,orcRho); % [W/m/K]
end
